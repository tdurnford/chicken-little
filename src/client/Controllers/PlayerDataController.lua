--[[
	PlayerDataController
	Client-side Knit controller for managing player data.
	
	Provides:
	- Local data caching for immediate UI access
	- GoodSignal events for reactive UI updates
	- Connection to PlayerDataService via Knit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))

-- Create the controller
local PlayerDataController = Knit.CreateController({
  Name = "PlayerDataController",
})

-- Local cache of player data
local cachedData: PlayerData.PlayerDataSchema? = nil
local isDataLoaded = false

-- GoodSignal events for reactive UI
PlayerDataController.DataLoaded = GoodSignal.new() -- Fires (data: PlayerDataSchema) when data is first loaded
PlayerDataController.DataChanged = GoodSignal.new() -- Fires (data: PlayerDataSchema) on any change
PlayerDataController.MoneyChanged = GoodSignal.new() -- Fires (newMoney: number)
PlayerDataController.InventoryChanged = GoodSignal.new() -- Fires (inventory: InventoryData)
PlayerDataController.LevelChanged = GoodSignal.new() -- Fires (level: number, xp: number)

-- Reference to the server service
local playerDataService = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function PlayerDataController:KnitInit()
  print("[PlayerDataController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function PlayerDataController:KnitStart()
  -- Get reference to server service
  playerDataService = Knit.GetService("PlayerDataService")

  -- Connect to server signals
  playerDataService.DataChanged:Connect(function(data: PlayerData.PlayerDataSchema)
    local previousData = cachedData
    cachedData = data

    -- Fire DataLoaded on first load
    if not isDataLoaded then
      isDataLoaded = true
      self.DataLoaded:Fire(data)
      print("[PlayerDataController] Data loaded")
    end

    -- Always fire DataChanged
    self.DataChanged:Fire(data)

    -- Fire specific change signals if relevant fields changed
    if previousData then
      if previousData.money ~= data.money then
        self.MoneyChanged:Fire(data.money)
      end

      -- Inventory changed (reference check - service sends new table on change)
      if previousData.inventory ~= data.inventory then
        self.InventoryChanged:Fire(data.inventory)
      end
    else
      -- First load - fire all specific signals
      self.MoneyChanged:Fire(data.money)
      self.InventoryChanged:Fire(data.inventory)

      local level = PlayerData.getLevel(data)
      local xp = PlayerData.getXP(data)
      self.LevelChanged:Fire(level, xp)
    end
  end)

  playerDataService.MoneyChanged:Connect(function(newMoney: number)
    if cachedData then
      cachedData.money = newMoney
    end
    self.MoneyChanged:Fire(newMoney)
  end)

  playerDataService.InventoryChanged:Connect(function(inventory: PlayerData.InventoryData)
    if cachedData then
      cachedData.inventory = inventory
    end
    self.InventoryChanged:Fire(inventory)
  end)

  playerDataService.LevelChanged:Connect(function(level: number, xp: number)
    if cachedData then
      cachedData.level = level
      cachedData.xp = xp
    end
    self.LevelChanged:Fire(level, xp)
  end)

  -- Request initial data from server
  playerDataService:GetData()
    :andThen(function(data)
      if data and not isDataLoaded then
        cachedData = data
        isDataLoaded = true
        self.DataLoaded:Fire(data)
        self.DataChanged:Fire(data)
        self.MoneyChanged:Fire(data.money)
        self.InventoryChanged:Fire(data.inventory)

        local level = PlayerData.getLevel(data)
        local xp = PlayerData.getXP(data)
        self.LevelChanged:Fire(level, xp)

        print("[PlayerDataController] Initial data loaded from request")
      end
    end)
    :catch(function(err)
      warn("[PlayerDataController] Failed to load initial data:", err)
    end)

  print("[PlayerDataController] Started")
end

--[[
	Gets the cached player data.
	Returns nil if data has not been loaded yet.
	
	@return PlayerDataSchema? - The cached data or nil
]]
function PlayerDataController:GetData(): PlayerData.PlayerDataSchema?
  return cachedData
end

--[[
	Gets the player's current money from cache.
	
	@return number - The cached money (0 if no data)
]]
function PlayerDataController:GetMoney(): number
  if cachedData then
    return cachedData.money
  end
  return 0
end

--[[
	Gets the player's inventory from cache.
	
	@return InventoryData? - The cached inventory or nil
]]
function PlayerDataController:GetInventory(): PlayerData.InventoryData?
  if cachedData then
    return cachedData.inventory
  end
  return nil
end

--[[
	Gets the player's placed chickens from cache.
	
	@return {ChickenData} - Array of placed chickens
]]
function PlayerDataController:GetPlacedChickens(): { PlayerData.ChickenData }
  if cachedData then
    return cachedData.placedChickens
  end
  return {}
end

--[[
	Gets the player's level from cache.
	
	@return number - The player's level (1 if no data)
]]
function PlayerDataController:GetLevel(): number
  if cachedData then
    return PlayerData.getLevel(cachedData)
  end
  return 1
end

--[[
	Gets the player's XP from cache.
	
	@return number - The player's XP (0 if no data)
]]
function PlayerDataController:GetXP(): number
  if cachedData then
    return PlayerData.getXP(cachedData)
  end
  return 0
end

--[[
	Returns whether player data has been loaded.
	
	@return boolean - True if data is loaded
]]
function PlayerDataController:IsDataLoaded(): boolean
  return isDataLoaded
end

--[[
	Checks if a player has an active power-up of a specific type.
	
	@param powerUpType string - The power-up type to check
	@return boolean - Whether the power-up is active
]]
function PlayerDataController:HasActivePowerUp(powerUpType: string): boolean
  if cachedData then
    return PlayerData.hasActivePowerUp(cachedData, powerUpType)
  end
  return false
end

--[[
	Gets the currently equipped weapon.
	
	@return string - The equipped weapon type
]]
function PlayerDataController:GetEquippedWeapon(): string
  if cachedData then
    return PlayerData.getEquippedWeapon(cachedData)
  end
  return "BaseballBat"
end

--[[
	Gets all owned weapons.
	
	@return {string} - Array of owned weapon types
]]
function PlayerDataController:GetOwnedWeapons(): { string }
  if cachedData then
    return PlayerData.getOwnedWeapons(cachedData)
  end
  return { "BaseballBat" }
end

--[[
	Checks if a player owns a specific weapon.
	
	@param weaponType string - The weapon type to check
	@return boolean - Whether the weapon is owned
]]
function PlayerDataController:OwnsWeapon(weaponType: string): boolean
  if cachedData then
    return PlayerData.ownsWeapon(cachedData, weaponType)
  end
  return weaponType == "BaseballBat" -- Everyone has baseball bat
end

--[[
	Gets the shield state from cache.
	
	@return ShieldState? - The shield state or nil
]]
function PlayerDataController:GetShieldState(): PlayerData.ShieldState?
  if cachedData then
    return cachedData.shieldState
  end
  return nil
end

--[[
	Checks if the player's shield is currently active.
	
	@return boolean - Whether shield is active
]]
function PlayerDataController:IsShieldActive(): boolean
  if cachedData and cachedData.shieldState then
    local shieldState = cachedData.shieldState
    if shieldState.isActive and shieldState.expiresAt then
      return os.time() < shieldState.expiresAt
    end
  end
  return false
end

--[[
	Gets remaining shield duration in seconds.
	
	@return number - Seconds remaining (0 if not active)
]]
function PlayerDataController:GetShieldRemainingTime(): number
  if cachedData and cachedData.shieldState then
    local shieldState = cachedData.shieldState
    if shieldState.isActive and shieldState.expiresAt then
      local remaining = shieldState.expiresAt - os.time()
      return math.max(0, remaining)
    end
  end
  return 0
end

--[[
	Marks the tutorial as completed on the server.
	Called when player completes or skips the tutorial.
	
	@return Promise<boolean> - Promise resolving to whether the update succeeded
]]
function PlayerDataController:CompleteTutorial()
  if cachedData then
    cachedData.tutorialComplete = true
  end
  return playerDataService:CompleteTutorial()
    :andThen(function(success)
      return success
    end)
    :catch(function(err)
      warn("[PlayerDataController] CompleteTutorial failed:", err)
      return false
    end)
end

return PlayerDataController
