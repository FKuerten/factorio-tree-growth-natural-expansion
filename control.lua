mod = {
  onTick = {},
  onInit = {}
}
require "control/chunks"
require "control/expansion"

local round = function(x) return math.floor(x+0.5) end

local initialize = function()
  for _, init in pairs(mod.onInit) do
    init()
  end
end

do
  -- at this point all handlers should be registered
  local n = #mod.onTick
  local onTick = function(event)
    local tick = game.tick    
    local t, index = math.floor(tick / n), (tick % n) + 1
    mod.onTick[index](t)
  end
  script.on_event(defines.events.on_tick, onTick)
end
script.on_init(initialize)
script.on_load(initialize)
script.on_event(defines.events.on_built_entity, onEntityPlaced)
script.on_event(defines.events.on_robot_built_entity, onEntityPlaced)
