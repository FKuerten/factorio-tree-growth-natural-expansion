require "stdlib/area/chunk"
require "stdlib/area/area"
require "stdlib/area/position"
require "stdlib/area/tile"

-- TODO get mature group from tree-growth
local tree_growth = { groups = { mature = "tree-growth-mature" } }

local initialize = function()
  global.lastTreeInChunk = global.lastTreeInChunk or {}
  global.offspringData = global.offspringData or {}
end

local onConfigurationChanged = function()
  global.offspringData = nil
  initialize()
end

local getTreeData = function(name)
  assert(name, "name not given")
  return remote.call("tree-growth-core", "getTreeData", name)
end

local getOffspring = function(name)
  if not global.offspringData[name] then
    local data = getTreeData(name)
    if data then
      global.offspringData[name] = data.saplings
    end
  end
  return global.offspringData[name]
end


local pickRandomTree = function(nextTrees)
  local sum = 0
  local lastEntry
  for _, entry in ipairs(nextTrees) do
    sum = sum + entry.probability
    lastEntry = entry
  end
  local r = math.random() * sum
  local offset = 0
  for _, entry in ipairs(nextTrees) do
    offset = offset + entry.probability
    if r < offset then
      return entry
    end
  end
  -- should not happen.
  return lastEntry
end

local tryToSpawnTreeNearTree = function(oldTree, saplingName)
  local surface = oldTree.surface
  local oldPosition = oldTree.position
  --surface.print("span tree of type " .. oldTree.name .. " near x=" .. oldPosition.x .. " y=" .. oldPosition.y)
  -- TODO: use something with a larger collision box to make sure trees are not too close
  --local newPosition = surface.find_non_colliding_position(saplingName, oldPosition, spawnRadius, 1)
  local distanceToTrees = settings.global['tgne-distance-trees'].value
  local spawnRadius = distanceToTrees + 3
  local newPosition = oldPosition
  
  -- random offset
  local randomX = math.random(-spawnRadius, spawnRadius)
  local randomY = math.random(-spawnRadius, spawnRadius)
  local newPosition = Position.offset(newPosition, randomX, randomY)
  
  -- wind 
  local windRadius = surface.wind_speed * settings.global['tgne-wind-factor'].value
  -- surface.wind_orientation == 0 => north
  -- surface.wind_orientation == 0.25 => east
  local windOrientation = surface.wind_orientation * 2 * math.pi
  local windX = math.sin(windOrientation) * windRadius
  local windY = -math.cos(windOrientation) * windRadius
  newPosition = Position.offset(newPosition, windX, windY)
  --surface.print(surface.wind_orientation .. " " .. windX .. " " .. windY)
  
  if distanceToTrees > 0 then
    local treeArea = Position.expand_to_area(newPosition, 2 * distanceToTrees)  
    if surface.count_entities_filtered({area=treeArea, type="tree"}) > 0 then
      return false
    end
  end
  
  local playerCenter = Position.offset(newPosition, 0, -0.5)
  local playerArea = Position.expand_to_area(playerCenter, 2 * settings.global['tgne-distance-players'].value)
  if surface.count_entities_filtered({area=playerArea}) - surface.count_entities_filtered({area=playerArea, force="neutral"}) > 0 then
    return false
  end
  local tile = surface.get_tile(Tile.from_position(newPosition))
  local speed = tile.prototype.walking_speed_modifier
  --surface.print("tile: " .. tile.name .. " speed: " .. speed)
  if speed > 1 then
    return false
  end
  
  local newTreeArg = {name=saplingName, position=newPosition, force=oldTree.force}
  if surface.can_place_entity(newTreeArg) then        
    --surface.print("span tree of type " .. saplingName .. " near x=" .. newPosition.x .. " y=" .. newPosition.y)  
    local newTree = surface.create_entity(newTreeArg)
    --remote.call("tree-growth", "onTreePlaced", newTree)
    script.raise_event(defines.events.on_built_entity, {name = "on_created_entity", tick=game.tick, created_entity = newTree})
    return true
  end
  return false
end

local spawnTreeNearTree = function(oldTree, saplingName)
  for i = 0, 10 do
    local success = tryToSpawnTreeNearTree(oldTree, saplingName)
    if success then 
      return 
    end
  end
end

local spawnTreesInChunk = function(surface, chunkPos)
  local spawnProbability = settings.global['tgne-expansion-probability'].value
  -- find existing trees
  -- surface.print("looking at chunk x=" .. chunkPos.x .. " y=" .. chunkPos.y)
  local area = Chunk.to_area(chunkPos)
  local trees = surface.find_entities_filtered{area = area, type = "tree"}
  for k, tree in pairs(trees) do
    local treeName = tree.name
    local saplingEntries = getOffspring(treeName)
    if saplingEntries and #saplingEntries > 0 then
        local saplingEntry = pickRandomTree(saplingEntries)
      if saplingEntry then
        if math.random() < spawnProbability then
          spawnTreeNearTree(tree, saplingEntry.name)
        end
      end
    end
  end
end

local onTick = function()
  local processChunkEveryTick = settings.global['tgne-process-every-tick'].value
  local surface = game.surfaces["nauvis"]
  for chunkIndex, chunkPos in mod.relevantChunkIterator(surface) do
    if (not global.lastTreeInChunk[chunkIndex]) or (global.lastTreeInChunk[chunkIndex] + processChunkEveryTick < game.tick) then
      spawnTreesInChunk(surface, chunkPos)
      global.lastTreeInChunk[chunkIndex] = game.tick
      return
    end
  end
end

script.on_configuration_changed(onConfigurationChanged)
table.insert(mod.onTick, onTick)
table.insert(mod.onInit, initialize)