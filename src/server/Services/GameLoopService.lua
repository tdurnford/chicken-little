--[[
	GameLoopService
	Knit service that coordinates the main game loop.
	
	Provides:
	- Central Heartbeat loop for game updates
	- Coordinates per-frame updates across services
	- Manages game state synchronization
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Services are required lazily to avoid circular dependencies
local GameStateService
local PredatorService
local ChickenService
local EggService
local PlayerDataService
local CombatService
local StoreService
local LevelService
local MapService

-- Create the service
local GameLoopService = Knit.CreateService({
  Name = "GameLoopService",

  -- Client-exposed methods and events
  Client = {
    -- Signal for frame updates (if clients need to know)
    FrameUpdated = Knit.CreateSignal(), -- Fires (deltaTime: number)
  },
})

-- Server-side signals (for other services to listen to)
GameLoopService.PreUpdate = GoodSignal.new() -- (deltaTime: number) - Before main updates
GameLoopService.PostUpdate = GoodSignal.new() -- (deltaTime: number) - After main updates

-- Internal state
local heartbeatConnection: RBXScriptConnection?
local isRunning: boolean = false
local lastUpdateTime: number = 0

-- Update interval tracking for store (don't need to check every frame)
local storeUpdateAccumulator: number = 0
local STORE_UPDATE_INTERVAL: number = 1.0 -- Check store every second

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function GameLoopService:KnitInit()
  lastUpdateTime = os.clock()
  print("[GameLoopService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function GameLoopService:KnitStart()
  -- Get references to all services we need to coordinate
  GameStateService = Knit.GetService("GameStateService")
  PlayerDataService = Knit.GetService("PlayerDataService")
  StoreService = Knit.GetService("StoreService")

  -- Optional services (may not exist yet)
  local success
  success, PredatorService = pcall(function()
    return Knit.GetService("PredatorService")
  end)
  if not success then
    PredatorService = nil
  end

  success, ChickenService = pcall(function()
    return Knit.GetService("ChickenService")
  end)
  if not success then
    ChickenService = nil
  end

  success, EggService = pcall(function()
    return Knit.GetService("EggService")
  end)
  if not success then
    EggService = nil
  end

  success, CombatService = pcall(function()
    return Knit.GetService("CombatService")
  end)
  if not success then
    CombatService = nil
  end

  success, LevelService = pcall(function()
    return Knit.GetService("LevelService")
  end)
  if not success then
    LevelService = nil
  end

  success, MapService = pcall(function()
    return Knit.GetService("MapService")
  end)
  if not success then
    MapService = nil
  end

  -- Start the main game loop
  self:StartLoop()

  print("[GameLoopService] Started")
end

--[[
	SERVER-ONLY: Starts the main game loop.
]]
function GameLoopService:StartLoop()
  if isRunning then
    return
  end

  isRunning = true
  lastUpdateTime = os.clock()

  heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
    self:_update(deltaTime)
  end)

  print("[GameLoopService] Game loop started")
end

--[[
	SERVER-ONLY: Stops the main game loop.
]]
function GameLoopService:StopLoop()
  if not isRunning then
    return
  end

  isRunning = false

  if heartbeatConnection then
    heartbeatConnection:Disconnect()
    heartbeatConnection = nil
  end

  print("[GameLoopService] Game loop stopped")
end

--[[
	SERVER-ONLY: Returns whether the game loop is running.
	
	@return boolean - True if loop is running
]]
function GameLoopService:IsRunning(): boolean
  return isRunning
end

--[[
	PRIVATE: Main update function called every frame.
	
	@param deltaTime number - Time since last frame
]]
function GameLoopService:_update(deltaTime: number)
  -- Fire pre-update signal for services that need to prepare
  self.PreUpdate:Fire(deltaTime)

  -- 1. GameStateService handles its own day/night cycle updates via its own Heartbeat
  -- (No need to call it here as it self-updates)

  -- 2. Update store replenishment (throttled)
  storeUpdateAccumulator = storeUpdateAccumulator + deltaTime
  if storeUpdateAccumulator >= STORE_UPDATE_INTERVAL then
    storeUpdateAccumulator = 0
    if StoreService and StoreService.UpdateStore then
      StoreService:UpdateStore()
    end
  end

  -- 3. Update predator service if it has an Update method
  if PredatorService and PredatorService.Update then
    PredatorService:Update(deltaTime)
  end

  -- 4. Update chicken service if it has an Update method
  if ChickenService and ChickenService.Update then
    ChickenService:Update(deltaTime)
  end

  -- 5. Update egg service if it has an Update method
  if EggService and EggService.Update then
    EggService:Update(deltaTime)
  end

  -- 6. Update combat service if it has an Update method
  if CombatService and CombatService.Update then
    CombatService:Update(deltaTime)
  end

  -- Fire post-update signal for services that need to react
  self.PostUpdate:Fire(deltaTime)
end

--[[
	SERVER-ONLY: Gets time since last update.
	
	@return number - Time in seconds
]]
function GameLoopService:GetTimeSinceLastUpdate(): number
  return os.clock() - lastUpdateTime
end

--[[
	SERVER-ONLY: Cleanup when service is destroyed.
]]
function GameLoopService:Destroy()
  self:StopLoop()
end

return GameLoopService
