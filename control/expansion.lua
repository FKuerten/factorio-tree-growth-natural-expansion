require "stdlib/area/chunk"
require "stdlib/area/area"
require "stdlib/area/position"
require "stdlib/area/tile"

-- TODO get mature group from tree-growth
local tree_growth = { groups = { mature = "tree-growth-mature" } }

local treePlantedEvent
local initialize = function()
  global.lastUpdateForChunk = global.lastUpdateForChunk or {}
  global.chunkSlowdownFactor = global.chunkSlowdownFactor or {}
  global.offspringData = global.offspringData or {}
  if not global.groups then
    global.groups = remote.call("tree-growth-core", "getGroups")
  end
end

local onLoad = function()
  if treePlantedEvent then
    script.on_event(treePlantedEvent, nil)
  end
  if not treePlantedEvent then
    treePlantedEvent = remote.call("tree-growth-core", "getEvents")['on_tree_planted']
    script.on_event(treePlantedEvent, onEntityPlaced)
  end
end

local onConfigurationChanged = function()
  global.offspringData = nil
  global.groups = nil
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

-- local spawnTreeNearTree = function(oldTree, saplingEntries)
  -- for i = 0, 10 do
    -- local success = tryToSpawnTreeNearTree(oldTree, saplingEntries)
    -- if success then
      -- return
    -- end
  -- end
-- end

local maybeDeconstructTree = function(treeEntity)
  local matureDistance = settings.global['tgne-distance-deconstruct-mature-players'].value
  local growingDistance = settings.global['tgne-distance-deconstruct-growing-players'].value
  local prototype = treeEntity.prototype
  local relevantDistance
  --local treeData = getTreeData(treeEntity.name)
  if prototype.subgroup.name == global.groups.sapling or
     prototype.subgroup.name == global.groups.intermediate then
    relevantDistance = growingDistance
  elseif prototype.subgroup.name == global.groups.mature then
    relevantDistance = matureDistance
  else
    return
  end
    
  -- if there is something near the tree, deconstruct the tree
  local treeCenter = treeEntity.position
  local adjustedPosition = Position.offset(treeCenter, 0, -0.5)
  local area = Position.expand_to_area(adjustedPosition, 2 * relevantDistance)
  local surface = treeEntity.surface
  local types = {
    "accumulator",
    "ammo-turret",
    "artillery-turret",
    "assembling-machine",
    "beacon",
    "boiler",
    "container",
    "curved-rail",
    "decider-combinator",
    "electric-pole",
    "electric-turret",
    "fluid-turret",
    "furnace",
    "gate",
    "generator",
    "heat-pipe",
    "infinity-container",
    "inserter",
    -- "item-entity", -- debatable
    "lab",
    "lamp",
    "land-mine", -- debatable
    "loader",
    "logistic-container",
    "market",
    "mining-drill",
    "offshore-pump",
    "pipe",
    "pipe-to-ground",
    "power-switch",
    "programmable-speaker",
    "pump",
    "radar",
    "rail-chain-signal",
    "rail-signal",
    "reactor",
    "roboport",
    "rocket-silo",
    "solar-panel",
    "splitter",
    "storage-tank",
    "straight-rail",
    "train-stop",
    "transport-belt",
    "turret", -- these are alien turrets by default
    "underground-belt",
    "unit-spawner",
    "wall",
  }
  for _, force in pairs(game.forces) do
    if #(force.players) > 0 then
      if surface.count_entities_filtered({area=area, force=force, type=types}) > 0 then
        -- deconstruct
        treeEntity.order_deconstruction(force)
      end
    end
  end
end

local randomElementFromArray = function(array)
  local count = #array
  local index = math.random(count)
  return index, array[index]
end

-- Allows trees in a given chunk to reproduce and spawn new trees, not necessarily in the same chunk.
-- Whether trees are really spawned depends on the spawnProbaility and whether there is space.
-- @param surface the surface of the chunk
-- @param chunkPos the position of the chunk
-- @param timeSinceLastProcessing number of ticks since last update
local processTreesInChunk = function(surface, chunkPos, timeSinceLastProcessing)
  local meanTimeForTreeToExpand = settings.global['tgne-expansion-mean-time'].value
  local area = Chunk.to_area(chunkPos)
  local trees = surface.find_entities_filtered{area = area, type = "tree"}

  local changed = false
  -- Before spawning, remove all trees that are too close to a player structure
  for _, treeEntity in ipairs(trees) do
    local deconstructed = maybeDeconstructTree(treeEntity)
    if deconstructed then
      changed = true
    end
  end

   -- Compute how many trees should spawn
  local numberOfSpawns = #trees * timeSinceLastProcessing / meanTimeForTreeToExpand

  local failures = 0
  while (numberOfSpawns > 0) and (#trees > 0) and (failures < 5) do
    -- pick random tree
    local i, oldTree = randomElementFromArray(trees)
    
    -- check if tree can reproduce
    local saplingEntries = getOffspring(oldTree.name)
    if not saplingEntries or #saplingEntries <= 0 then
      table.remove(trees, i)
    else
      -- try to spawn
      local success = tryToSpawnTreeNearTree(oldTree, saplingEntries)
      if success then
        numberOfSpawns = numberOfSpawns - 1
        failures = 0
        changed = true
      else
        failures = failures + 1
      end
    end
  end

  return changed
end

local onTick = function()
  local processChunkEveryTick = settings.global['tgne-process-every-tick'].value
  local surface = game.surfaces["nauvis"]
  for chunkIndex, chunkPos in mod.relevantChunkIterator(surface) do
    if not global.lastUpdateForChunk[chunkIndex] then
      global.lastUpdateForChunk[chunkIndex] = game.tick
    elseif not global.chunkSlowdownFactor[chunkIndex] then
      global.chunkSlowdownFactor[chunkIndex] = 1
    else
      local timeSinceLastProcessing = game.tick - global.lastUpdateForChunk[chunkIndex]
      local adjustedTimeSinceLastProcessing = timeSinceLastProcessing * global.chunkSlowdownFactor[chunkIndex]
      if adjustedTimeSinceLastProcessing > processChunkEveryTick then
        local changed = processTreesInChunk(surface, chunkPos, adjustedTimeSinceLastProcessing)
        global.lastUpdateForChunk[chunkIndex] = game.tick
        if changed then
          global.chunkSlowdownFactor[chunkIndex] = 1
        else
          global.chunkSlowdownFactor[chunkIndex] = 0.5
        end
      end
    end
  end
end

script.on_configuration_changed(onConfigurationChanged)
table.insert(mod.onTick, onTick)
table.insert(mod.onInit, initialize)
table.insert(mod.onLoad, onLoad)