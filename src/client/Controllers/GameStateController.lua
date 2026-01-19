--[[
	GameStateController
	Client-side Knit controller for managing day/night cycle and game state.
	
	Provides:
	- Time info queries via GameStateService
	- GoodSignal events for reactive UI updates
	- Local time state caching
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Type for time info
export type TimeInfo = {
  gameTime: number,
  timeOfDay: string,
  isNight: boolean,
  predatorMultiplier: number,
}

-- Create the controller
local GameStateController = Knit.CreateController({
  Name = "GameStateController",
})

-- GoodSignal events for reactive UI
GameStateController.TimeChanged = GoodSignal.new() -- Fires (timeInfo: TimeInfo)
GameStateController.PeriodChanged = GoodSignal.new() -- Fires (newPeriod: string)
GameStateController.NightStarted = GoodSignal.new() -- Fires ()
GameStateController.DayStarted = GoodSignal.new() -- Fires ()

-- Reference to the server service
local gameStateService = nil

-- Cached state for synchronous access
local cachedTimeInfo: TimeInfo? = nil
local cachedPeriod: string = "day"
local cachedIsNight: boolean = false

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function GameStateController:KnitInit()
  print("[GameStateController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function GameStateController:KnitStart()
  -- Get reference to server service
  gameStateService = Knit.GetService("GameStateService")

  -- Get initial time info
  local initialInfo = gameStateService:GetTimeInfo()
  if initialInfo then
    cachedTimeInfo = initialInfo
    cachedPeriod = initialInfo.timeOfDay
    cachedIsNight = initialInfo.isNight
  end

  -- Connect to server signals
  gameStateService.TimeChanged:Connect(function(timeInfo)
    cachedTimeInfo = timeInfo
    cachedPeriod = timeInfo.timeOfDay
    cachedIsNight = timeInfo.isNight
    self.TimeChanged:Fire(timeInfo)
  end)

  gameStateService.PeriodChanged:Connect(function(newPeriod)
    cachedPeriod = newPeriod
    cachedIsNight = newPeriod == "night"
    self.PeriodChanged:Fire(newPeriod)
  end)

  gameStateService.NightStarted:Connect(function()
    cachedIsNight = true
    cachedPeriod = "night"
    self.NightStarted:Fire()
  end)

  gameStateService.DayStarted:Connect(function()
    cachedIsNight = false
    cachedPeriod = "day"
    self.DayStarted:Fire()
  end)

  print("[GameStateController] Started")
end

-- ============================================================================
-- Cached State Methods (Synchronous)
-- ============================================================================

--[[
	Get cached time info (synchronous).
	
	@return TimeInfo?
]]
function GameStateController:GetCachedTimeInfo(): TimeInfo?
  return cachedTimeInfo
end

--[[
	Get cached time of day period (synchronous).
	
	@return string - "day", "night", "dawn", or "dusk"
]]
function GameStateController:GetCachedPeriod(): string
  return cachedPeriod
end

--[[
	Check if it's currently night (synchronous, from cache).
	
	@return boolean
]]
function GameStateController:IsCachedNight(): boolean
  return cachedIsNight
end

--[[
	Get cached game time (synchronous).
	
	@return number - Game time (0-24), or 12 if not cached
]]
function GameStateController:GetCachedGameTime(): number
  if cachedTimeInfo then
    return cachedTimeInfo.gameTime
  end
  return 12 -- Default to noon
end

--[[
	Get cached predator multiplier (synchronous).
	
	@return number - Predator spawn multiplier, or 1 if not cached
]]
function GameStateController:GetCachedPredatorMultiplier(): number
  if cachedTimeInfo then
    return cachedTimeInfo.predatorMultiplier
  end
  return 1 -- Default multiplier
end

-- ============================================================================
-- Server Query Methods
-- ============================================================================

--[[
	Get full time info from server.
	
	@return TimeInfo
]]
function GameStateController:GetTimeInfo(): TimeInfo
  if not gameStateService then
    return {
      gameTime = 12,
      timeOfDay = "day",
      isNight = false,
      predatorMultiplier = 1,
    }
  end

  local info = gameStateService:GetTimeInfo()
  if info then
    -- Update cache
    cachedTimeInfo = info
    cachedPeriod = info.timeOfDay
    cachedIsNight = info.isNight
  end

  return info
end

--[[
	Get current game time from server.
	
	@return number - Game time (0-24)
]]
function GameStateController:GetGameTime(): number
  if not gameStateService then
    return 12
  end
  return gameStateService:GetGameTime()
end

--[[
	Get current time of day from server.
	
	@return string - "day", "night", "dawn", or "dusk"
]]
function GameStateController:GetTimeOfDay(): string
  if not gameStateService then
    return "day"
  end
  return gameStateService:GetTimeOfDay()
end

--[[
	Check if it's currently night from server.
	
	@return boolean
]]
function GameStateController:IsNight(): boolean
  if not gameStateService then
    return false
  end
  return gameStateService:IsNight()
end

--[[
	Get predator spawn multiplier from server.
	
	@return number - Spawn multiplier (0.5 - 2.0)
]]
function GameStateController:GetPredatorMultiplier(): number
  if not gameStateService then
    return 1
  end
  return gameStateService:GetPredatorMultiplier()
end

-- ============================================================================
-- Utility Methods
-- ============================================================================

--[[
	Check if it's a dangerous time (night or dusk).
	
	@return boolean
]]
function GameStateController:IsDangerousTime(): boolean
  return cachedPeriod == "night" or cachedPeriod == "dusk"
end

--[[
	Check if it's a safe time (day or dawn).
	
	@return boolean
]]
function GameStateController:IsSafeTime(): boolean
  return cachedPeriod == "day" or cachedPeriod == "dawn"
end

--[[
	Get a user-friendly time string for display.
	
	@return string - e.g., "Day", "Night", "Dawn", "Dusk"
]]
function GameStateController:GetTimeDisplayString(): string
  local periodNames = {
    day = "Day",
    night = "Night",
    dawn = "Dawn",
    dusk = "Dusk",
  }
  return periodNames[cachedPeriod] or "Day"
end

--[[
	Get the period icon/emoji for UI display.
	
	@return string - Unicode emoji for period
]]
function GameStateController:GetPeriodIcon(): string
  local periodIcons = {
    day = "☀️",
    night = "🌙",
    dawn = "🌅",
    dusk = "🌆",
  }
  return periodIcons[cachedPeriod] or "☀️"
end

return GameStateController
