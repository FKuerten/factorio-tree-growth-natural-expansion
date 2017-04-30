require "stdlib/area/chunk"
require "stdlib/area/area"

local MAX_RELEVANCE = 2

local initialize = function()
  global.indexToPos = global.indexToPos or {}
  global.chunksToScan = global.chunksToScan or {}
  global.chunkRelevance = global.chunkRelevance or {}
end

local maxn = function(a,b)
  if not a then return b end
  if not b then return a end
  return math.max(a,b)
end

local onTick = function(tick)
  local surface = game.surfaces["nauvis"]
  if not global.chunksToScan or not next(global.chunksToScan) then
    for chunkPos in surface.get_chunks() do
      global.chunksToScan[Chunk.get_index(surface, chunkPos)] = chunkPos
    end
    return
  end
  
  local index, chunkPos = next(global.chunksToScan)
  -- do a scan
  global.chunksToScan[index] = nil
  local area = Chunk.to_area(chunkPos)

  local populated = false
  for _, force in pairs(game.forces) do
    if force.valid and #force.connected_players > 0 then
      local count = surface.count_entities_filtered({area=area, force=force})
      if count > 0 then
        populated = true
      end
    end
  end
  
  global.indexToPos[index] = chunkPos
  if populated then
    global.chunkRelevance[index] = MAX_RELEVANCE
  else
    local top    = {x=chunkPos.x  , y=chunkPos.y-1}
    local bottom = {x=chunkPos.x  , y=chunkPos.y+1}
    local left   = {x=chunkPos.x-1, y=chunkPos.y  }
    local right  = {x=chunkPos.x+1, y=chunkPos.y  }
    local relevance = nil
    for _, pos in ipairs({top,bottom,left,right}) do
      if surface.is_chunk_generated(pos) then
        local neighborRelevance = global.chunkRelevance[Chunk.get_index(surface, pos)]
        relevance = maxn(relevance, neighborRelevance)
        --if neighborRelevance then
        --  surface.print("at " .. _ .. " x=" .. pos.x .. " y=" .. pos.y .. " " .. tostring(neighborRelevance) .. " -> " .. tostring(relevance))
        --end
      end
    end
    if relevance and relevance > 0 then
      global.chunkRelevance[index] = relevance - 1
    else
      global.chunkRelevance[index] = nil
    end
  end
  --if global.chunkRelevance[index] then
  --  surface.print(tostring(index) .. " x=" .. chunkPos.x .. " y=" .. chunkPos.y .. " " .. tostring(global.chunkRelevance[index]))
  --end
end

mod.isChunkRelevant = function(surface, chunkPos)
  local index = Chunk.get_index(surface, chunkPos)
  local relevance = global.chunkRelevance[index]
  return relevance and relevance > 0
end

mod.relevantChunkIterator = function(surface)
  local filteredNext = function(t, k)
    local index, pos = next(t, k)
    while index do
      if mod.isChunkRelevant(surface, pos) then
        return index, pos
      end
      index, pos = next(t, index)
    end
  end
  return filteredNext, global.indexToPos, nil
end

table.insert(mod.onTick, onTick)
table.insert(mod.onInit, initialize)