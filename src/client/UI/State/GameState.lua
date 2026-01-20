--[[
	GameState Module
	Fusion reactive state for game-wide state (day/night cycle, time, etc).
	Wraps GameStateController signals into Fusion Value objects for UI consumption.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

-- Create a persistent scope for state values
local scope = Fusion.scoped(Fusion)

-- Type exports for consumers
export type TimeInfo = {
  gameTime: number,
  timeOfDay: string,
  isNight: boolean,
  predatorMultiplier: number,
}

export type GameStateType = {
  -- Time state
  GameTime: Fusion.Value<number>,
  TimeOfDay: Fusion.Value<string>,
  IsNight: Fusion.Value<boolean>,
  PredatorMultiplier: Fusion.Value<number>,

  -- Computed values
  IsDangerousTime: Fusion.Computed<boolean>,
  IsSafeTime: Fusion.Computed<boolean>,
  TimeDisplayString: Fusion.Computed<string>,
  PeriodIcon: Fusion.Computed<string>,

  -- Connection management
  Connections: { RBXScriptConnection | { Disconnect: () -> () } },
}

local GameState = {} :: GameStateType

-- Time state values
GameState.GameTime = scope:Value(12) -- Default to noon
GameState.TimeOfDay = scope:Value("day")
GameState.IsNight = scope:Value(false)
GameState.PredatorMultiplier = scope:Value(1)

-- Computed: Is it a dangerous time (night or dusk)?
GameState.IsDangerousTime = scope:Computed(function(use)
  local period = use(GameState.TimeOfDay)
  return period == "night" or period == "dusk"
end)

-- Computed: Is it a safe time (day or dawn)?
GameState.IsSafeTime = scope:Computed(function(use)
  local period = use(GameState.TimeOfDay)
  return period == "day" or period == "dawn"
end)

-- Computed: User-friendly time display string
GameState.TimeDisplayString = scope:Computed(function(use)
  local period = use(GameState.TimeOfDay)
  local periodNames = {
    day = "Day",
    night = "Night",
    dawn = "Dawn",
    dusk = "Dusk",
  }
  return periodNames[period] or "Day"
end)

-- Computed: Period icon/emoji for UI
GameState.PeriodIcon = scope:Computed(function(use)
  local period = use(GameState.TimeOfDay)
  local periodIcons = {
    day = "☀️",
    night = "🌙",
    dawn = "🌅",
    dusk = "🌆",
  }
  return periodIcons[period] or "☀️"
end)

-- Store connections for cleanup
GameState.Connections = {}

--[[
	Initialize the state from TimeInfo.

	@param timeInfo TimeInfo - The time info from server
]]
function GameState.initFromTimeInfo(timeInfo: TimeInfo)
  GameState.GameTime:set(timeInfo.gameTime or 12)
  GameState.TimeOfDay:set(timeInfo.timeOfDay or "day")
  GameState.IsNight:set(timeInfo.isNight or false)
  GameState.PredatorMultiplier:set(timeInfo.predatorMultiplier or 1)
end

--[[
	Update from TimeInfo.

	@param timeInfo TimeInfo - The new time info
]]
function GameState.setTimeInfo(timeInfo: TimeInfo)
  GameState.GameTime:set(timeInfo.gameTime)
  GameState.TimeOfDay:set(timeInfo.timeOfDay)
  GameState.IsNight:set(timeInfo.isNight)
  GameState.PredatorMultiplier:set(timeInfo.predatorMultiplier)
end

--[[
	Set the time of day period.

	@param period string - "day", "night", "dawn", or "dusk"
]]
function GameState.setPeriod(period: string)
  GameState.TimeOfDay:set(period)
  GameState.IsNight:set(period == "night")
end

--[[
	Set night started state.
]]
function GameState.setNightStarted()
  GameState.IsNight:set(true)
  GameState.TimeOfDay:set("night")
end

--[[
	Set day started state.
]]
function GameState.setDayStarted()
  GameState.IsNight:set(false)
  GameState.TimeOfDay:set("day")
end

--[[
	Get current game time value.

	@return number - Game time (0-24)
]]
function GameState.getGameTime(): number
  return GameState.GameTime:get()
end

--[[
	Check if it's currently night.

	@return boolean
]]
function GameState.isCurrentlyNight(): boolean
  return GameState.IsNight:get()
end

--[[
	Cleanup all connections.
]]
function GameState.cleanup()
  for _, connection in ipairs(GameState.Connections) do
    if typeof(connection) == "RBXScriptConnection" then
      connection:Disconnect()
    elseif type(connection) == "table" and connection.Disconnect then
      connection:Disconnect()
    end
  end
  table.clear(GameState.Connections)
end

return GameState
