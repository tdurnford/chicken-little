--[[
	GameStateService
	Knit service that manages day/night cycle and global game state.
	
	Provides:
	- Day/night cycle management with lighting updates
	- Time synchronization to clients
	- Predator spawn multiplier based on time
	- Night cycle survival XP tracking
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))

-- LevelService is required lazily to avoid circular dependency
local LevelService

-- Create the service
local GameStateService = Knit.CreateService({
  Name = "GameStateService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to all clients
    TimeChanged = Knit.CreateSignal(), -- Fires (timeInfo: TimeInfo)
    PeriodChanged = Knit.CreateSignal(), -- Fires (newPeriod: string)
    NightStarted = Knit.CreateSignal(), -- Fires ()
    DayStarted = Knit.CreateSignal(), -- Fires ()
  },
})

-- Server-side signals (for other services to listen to)
GameStateService.TimeChangedSignal = GoodSignal.new() -- (timeInfo: TimeInfo)
GameStateService.PeriodChangedSignal = GoodSignal.new() -- (newPeriod: string, oldPeriod: string)
GameStateService.NightStartedSignal = GoodSignal.new() -- ()
GameStateService.NightEndedSignal = GoodSignal.new() -- ()
GameStateService.NightCycleCompleteSignal = GoodSignal.new() -- ()

-- Internal state
local dayNightState: DayNightCycle.DayNightState
local currentPeriod: string = "day"
local nightCycleNumber: number = 0
local playerNightCycleCount: { [number]: number } = {} -- Tracks last awarded night cycle per player
local updateConnection: RBXScriptConnection?

-- Type for time info sent to clients
export type TimeInfo = {
  gameTime: number,
  timeOfDay: string,
  isNight: boolean,
  predatorMultiplier: number,
}

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function GameStateService:KnitInit()
  -- Initialize day/night cycle
  dayNightState = DayNightCycle.init()
  currentPeriod = DayNightCycle.getTimeOfDay(dayNightState)

  print("[GameStateService] Initialized - Starting period:", currentPeriod)
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function GameStateService:KnitStart()
  -- Require LevelService here to avoid load-time circular dependency
  LevelService = Knit.GetService("LevelService")

  -- Start the update loop for lighting transitions
  updateConnection = RunService.Heartbeat:Connect(function()
    self:_updateCycle()
  end)

  -- Initialize player tracking
  Players.PlayerAdded:Connect(function(player)
    playerNightCycleCount[player.UserId] = nightCycleNumber
  end)

  Players.PlayerRemoving:Connect(function(player)
    playerNightCycleCount[player.UserId] = nil
  end)

  -- Initialize existing players
  for _, player in ipairs(Players:GetPlayers()) do
    playerNightCycleCount[player.UserId] = nightCycleNumber
  end

  print("[GameStateService] Started")
end

--[[
	Gets the current game time (0-24 hours).
	
	@param player Player - The player requesting data
	@return number - Current game time
]]
function GameStateService.Client:GetGameTime(player: Player): number
  return DayNightCycle.getGameTime(dayNightState)
end

--[[
	Gets the current time period (day/night/dawn/dusk).
	
	@param player Player - The player requesting data
	@return string - Current time period
]]
function GameStateService.Client:GetTimeOfDay(player: Player): string
  return DayNightCycle.getTimeOfDay(dayNightState)
end

--[[
	Gets whether it's currently night time.
	
	@param player Player - The player requesting data
	@return boolean - True if night
]]
function GameStateService.Client:IsNight(player: Player): boolean
  return DayNightCycle.isNight(dayNightState)
end

--[[
	Gets the current predator spawn multiplier.
	
	@param player Player - The player requesting data
	@return number - Spawn multiplier
]]
function GameStateService.Client:GetPredatorMultiplier(player: Player): number
  return DayNightCycle.getPredatorSpawnMultiplier(dayNightState)
end

--[[
	Gets full time info for UI display.
	
	@param player Player - The player requesting data
	@return TimeInfo - Complete time information
]]
function GameStateService.Client:GetTimeInfo(player: Player): TimeInfo
  return {
    gameTime = DayNightCycle.getGameTime(dayNightState),
    timeOfDay = DayNightCycle.getTimeOfDay(dayNightState),
    isNight = DayNightCycle.isNight(dayNightState),
    predatorMultiplier = DayNightCycle.getPredatorSpawnMultiplier(dayNightState),
  }
end

--[[
	SERVER-ONLY: Gets the current game time.
	
	@return number - Current game time (0-24)
]]
function GameStateService:GetGameTime(): number
  return DayNightCycle.getGameTime(dayNightState)
end

--[[
	SERVER-ONLY: Gets the current time of day.
	
	@return string - Current time period
]]
function GameStateService:GetTimeOfDay(): string
  return DayNightCycle.getTimeOfDay(dayNightState)
end

--[[
	SERVER-ONLY: Gets whether it's night.
	
	@return boolean - True if night
]]
function GameStateService:IsNight(): boolean
  return DayNightCycle.isNight(dayNightState)
end

--[[
	SERVER-ONLY: Gets whether it's dawn.
	
	@return boolean - True if dawn
]]
function GameStateService:IsDawn(): boolean
  return DayNightCycle.isDawn(dayNightState)
end

--[[
	SERVER-ONLY: Gets whether it's dusk.
	
	@return boolean - True if dusk
]]
function GameStateService:IsDusk(): boolean
  return DayNightCycle.isDusk(dayNightState)
end

--[[
	SERVER-ONLY: Gets whether it's day.
	
	@return boolean - True if day
]]
function GameStateService:IsDay(): boolean
  return DayNightCycle.isDay(dayNightState)
end

--[[
	SERVER-ONLY: Gets the predator spawn multiplier.
	
	@return number - Spawn multiplier (0.5 - 2.0)
]]
function GameStateService:GetPredatorSpawnMultiplier(): number
  return DayNightCycle.getPredatorSpawnMultiplier(dayNightState)
end

--[[
	SERVER-ONLY: Gets the full time info.
	
	@return TimeInfo - Complete time information
]]
function GameStateService:GetTimeInfo(): TimeInfo
  return {
    gameTime = DayNightCycle.getGameTime(dayNightState),
    timeOfDay = DayNightCycle.getTimeOfDay(dayNightState),
    isNight = DayNightCycle.isNight(dayNightState),
    predatorMultiplier = DayNightCycle.getPredatorSpawnMultiplier(dayNightState),
  }
end

--[[
	SERVER-ONLY: Gets the current night cycle number.
	
	@return number - Night cycle count since server start
]]
function GameStateService:GetNightCycleNumber(): number
  return nightCycleNumber
end

--[[
	SERVER-ONLY: Gets the day/night state for external use.
	
	@return DayNightCycle.DayNightState - Internal state
]]
function GameStateService:GetDayNightState(): DayNightCycle.DayNightState
  return dayNightState
end

--[[
	PRIVATE: Updates the day/night cycle and handles period transitions.
]]
function GameStateService:_updateCycle()
  -- Update lighting
  DayNightCycle.update(dayNightState)

  -- Check for period changes
  local newPeriod = DayNightCycle.getTimeOfDay(dayNightState)

  if newPeriod ~= currentPeriod then
    local oldPeriod = currentPeriod
    currentPeriod = newPeriod

    -- Fire period change signals
    self.PeriodChangedSignal:Fire(newPeriod, oldPeriod)

    -- Broadcast to all clients
    for _, player in ipairs(Players:GetPlayers()) do
      self.Client.PeriodChanged:Fire(player, newPeriod)
    end

    -- Handle night start
    if newPeriod == "night" then
      self.NightStartedSignal:Fire()
      for _, player in ipairs(Players:GetPlayers()) do
        self.Client.NightStarted:Fire(player)
      end
    end

    -- Handle night end (transition to dawn means night is over)
    if oldPeriod == "night" and newPeriod == "dawn" then
      nightCycleNumber += 1
      self.NightEndedSignal:Fire()
      self.NightCycleCompleteSignal:Fire()

      -- Award XP to all players who survived the night
      self:_awardNightSurvivalXP()
    end

    -- Handle day start
    if newPeriod == "day" then
      for _, player in ipairs(Players:GetPlayers()) do
        self.Client.DayStarted:Fire(player)
      end
    end
  end
end

--[[
	PRIVATE: Awards XP to players who survived the night cycle.
]]
function GameStateService:_awardNightSurvivalXP()
  for _, player in ipairs(Players:GetPlayers()) do
    local userId = player.UserId
    local lastAwarded = playerNightCycleCount[userId] or 0

    -- Only award if they haven't been awarded for this cycle
    if lastAwarded < nightCycleNumber then
      playerNightCycleCount[userId] = nightCycleNumber
      LevelService:AwardDayNightCycleXP(userId)
    end
  end
end

--[[
	SERVER-ONLY: Force updates and broadcasts time to all clients.
	Useful after significant time skip or for periodic sync.
]]
function GameStateService:SyncTimeToClients()
  local timeInfo = self:GetTimeInfo()
  self.TimeChangedSignal:Fire(timeInfo)

  for _, player in ipairs(Players:GetPlayers()) do
    self.Client.TimeChanged:Fire(player, timeInfo)
  end
end

--[[
	SERVER-ONLY: Cleanup when service is destroyed.
]]
function GameStateService:Destroy()
  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end
end

return GameStateService
