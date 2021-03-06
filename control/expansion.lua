require "stdlib/area/chunk"
require "stdlib/area/area"
require "stdlib/area/position"
require "stdlib/area/tile"

-- TODO get mature group from tree-growth
local tree_growth = { groups = { mature = "tree-growth-mature" } }

local treePlantedEvent
local initialize = function()
  global.lastUpdateForChunk = global.lastUpdateForChunk or {}
  global.offspringData = global.offspringData or {}
  if not treePlantedEvent then
    treePlantedEvent = remote.call("tree-growth-core", "getEvents")['on_tree_planted']
    script.on_event(treePlantedEvent, onEntityPlaced)
  end
end

local onConfigurationChanged = function()
  global.offspringData = nil
  if treePlantedEvent then
    script.on_event(treePlantedEvent, nil)
    treePlantedEvent = nil
  end
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

-- TOD0 currently dead code, need to add logic for filtering
local filterTrees = function(nextTrees, tileName)
  local result = {}
  for _, entry in ipairs(nextTrees) do
    local validTile = false
    if type(entry.tiles) == 'nil' or entry.tiles == true then
      validTile = true
    elseif type(entry.tiles) == 'table' then
      validTile = entry.tiles[tileName]
    end

    if validTile then
      table.insert(result, entry)
    end
  end
  return result
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

local tryToSpawnTreeNearTree = function(oldTree, saplingEntries)
  local surface = oldTree.surface
  local oldPosition = oldTree.position
  --surface.print("span tree of type " .. oldTree.name .. " near x=" .. oldPosition.x .. " y=" .. oldPosition.y)
  local distanceToTrees = settings.global['tgne-distance-trees'].value
  local spawnRadius = distanceToTrees + 5
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

  -- TODO tile filtering
  local filteredEntries = filterTrees(saplingEntries, tile.name)
  local saplingEntry = pickRandomTree(filteredEntries)
  if not saplingEntry then return false end


  local speed = tile.prototype.walking_speed_modifier
  --surface.print("tile: " .. tile.name .. " speed: " .. speed)
  if speed > 1 then
    return false
  end
  
  local saplingName = saplingEntry.name
  local newTreeArg = {name=saplingName, position=newPosition, force=oldTree.force}
  if surface.can_place_entity(newTreeArg) then        
    --surface.print("span tree of type " .. saplingName .. " near x=" .. newPosition.x .. " y=" .. newPosition.y)  
    local newTree = surface.create_entity(newTreeArg)
    --remote.call("tree-growth", "onTreePlaced", newTree)
    script.raise_event(treePlantedEvent, {created_entity = newTree})
    return true
  end
  return false
end

local spawnTreeNearTree = function(oldTree, saplingEntries)
  for i = 0, 10 do
    local success = tryToSpawnTreeNearTree(oldTree, saplingEntries)
    if success then 
      return 
    end
  end
end

-- Allows trees in a given chunk to reproduce an spawn new trees, not necessarily in the same chunk.
-- Whether trees are really spawned depends on the spawnProbaility and whether there is space.
-- @param surface the surface of the chunk
-- @param chunkPos the position of the chunk
local spawnTreesInChunk = function(surface, chunkPos)
  local spawnProbability = settings.global['tgne-expansion-probability'].value
  local area = Chunk.to_area(chunkPos)
  local trees = surface.find_entities_filtered{area = area, type = "tree"}
  for k, treeEntity in pairs(trees) do
    local treeName = treeEntity.name
    if math.random() < spawnProbability then
      local saplingEntries = getOffspring(treeName)
      -- Can this tree even reproduce?
      if saplingEntries and #saplingEntries > 0 then
        spawnTreeNearTree(treeEntity, saplingEntries)
      end
    end
  end
end

local onTick = function()
  local processChunkEveryTick = settings.global['tgne-process-every-tick'].value
  local surface = game.surfaces["nauvis"]
  for chunkIndex, chunkPos in mod.relevantChunkIterator(surface) do
    if (not global.lastUpdateForChunk[chunkIndex]) or (global.lastUpdateForChunk[chunkIndex] + processChunkEveryTick < game.tick) then
      spawnTreesInChunk(surface, chunkPos)
      global.lastUpdateForChunk[chunkIndex] = game.tick
      return
    end
  end
end

script.on_configuration_changed(onConfigurationChanged)
table.insert(mod.onTick, onTick)
table.insert(mod.onInit, initialize)