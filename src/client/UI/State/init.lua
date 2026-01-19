--[[
	State Module (init)
	Central entry point for Fusion UI state.
	Connects Knit controllers to Fusion state objects.

	Usage:
		local State = require(script.Parent.UI.State)
		State.initialize() -- Call once after Knit starts

		-- Access state in Fusion components:
		local money = State.Player.Money
		local isNight = State.Game.IsNight
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local PlayerState = require(script.PlayerState)
local GameState = require(script.GameState)

local State = {
  Player = PlayerState,
  Game = GameState,
}

local isInitialized = false

--[[
	Initialize the state module.
	Connects Knit controller signals to Fusion state.
	Must be called after Knit.Start() resolves.
]]
function State.initialize()
  if isInitialized then
    warn("[State] Already initialized")
    return
  end

  -- Get controllers
  local PlayerDataController = Knit.GetController("PlayerDataController")
  local GameStateController = Knit.GetController("GameStateController")

  -- Wire up PlayerDataController signals
  if PlayerDataController then
    -- Initial data load
    table.insert(
      PlayerState.Connections,
      PlayerDataController.DataLoaded:Connect(function(data)
        PlayerState.initFromData(data)
        print("[State] Player data initialized")
      end)
    )

    -- Data change (full update)
    table.insert(
      PlayerState.Connections,
      PlayerDataController.DataChanged:Connect(function(data)
        PlayerState.initFromData(data)
      end)
    )

    -- Money changes
    table.insert(
      PlayerState.Connections,
      PlayerDataController.MoneyChanged:Connect(function(newMoney)
        PlayerState.setMoney(newMoney)
      end)
    )

    -- Inventory changes
    table.insert(
      PlayerState.Connections,
      PlayerDataController.InventoryChanged:Connect(function(inventory)
        PlayerState.setInventory(inventory)
      end)
    )

    -- Level changes
    table.insert(
      PlayerState.Connections,
      PlayerDataController.LevelChanged:Connect(function(level, xp)
        PlayerState.setLevel(level, xp)
      end)
    )

    -- If data is already loaded, initialize immediately
    if PlayerDataController:IsDataLoaded() then
      local data = PlayerDataController:GetData()
      if data then
        PlayerState.initFromData(data)
        print("[State] Player data initialized from existing cache")
      end
    end
  else
    warn("[State] PlayerDataController not found")
  end

  -- Wire up GameStateController signals
  if GameStateController then
    -- Time changes
    table.insert(
      GameState.Connections,
      GameStateController.TimeChanged:Connect(function(timeInfo)
        GameState.setTimeInfo(timeInfo)
      end)
    )

    -- Period changes
    table.insert(
      GameState.Connections,
      GameStateController.PeriodChanged:Connect(function(newPeriod)
        GameState.setPeriod(newPeriod)
      end)
    )

    -- Night started
    table.insert(
      GameState.Connections,
      GameStateController.NightStarted:Connect(function()
        GameState.setNightStarted()
      end)
    )

    -- Day started
    table.insert(
      GameState.Connections,
      GameStateController.DayStarted:Connect(function()
        GameState.setDayStarted()
      end)
    )

    -- Initialize from cached state
    local cachedTimeInfo = GameStateController:GetCachedTimeInfo()
    if cachedTimeInfo then
      GameState.initFromTimeInfo(cachedTimeInfo)
      print("[State] Game state initialized from cache")
    end
  else
    warn("[State] GameStateController not found")
  end

  isInitialized = true
  print("[State] Initialized successfully")
end

--[[
	Check if state has been initialized.

	@return boolean
]]
function State.isInitialized(): boolean
  return isInitialized
end

--[[
	Cleanup all state connections.
	Call when the UI system is being destroyed.
]]
function State.cleanup()
  PlayerState.cleanup()
  GameState.cleanup()
  isInitialized = false
  print("[State] Cleaned up")
end

--[[
	Get the PlayerState module directly.

	@return PlayerState
]]
function State.getPlayerState()
  return PlayerState
end

--[[
	Get the GameState module directly.

	@return GameState
]]
function State.getGameState()
  return GameState
end

return State
