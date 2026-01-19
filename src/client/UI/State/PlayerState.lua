--[[
	PlayerState Module
	Fusion reactive state for player data.
	Wraps PlayerDataController signals into Fusion Value objects for UI consumption.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))

-- Fusion constructors
local Value = Fusion.Value
local Computed = Fusion.Computed

-- Type exports for consumers
export type PlayerStateType = {
  -- Core data values
  Money: Fusion.Value<number>,
  Level: Fusion.Value<number>,
  XP: Fusion.Value<number>,
  IsDataLoaded: Fusion.Value<boolean>,

  -- Inventory state
  Eggs: Fusion.Value<{ PlayerData.EggData }>,
  InventoryChickens: Fusion.Value<{ PlayerData.ChickenData }>,
  PlacedChickens: Fusion.Value<{ PlayerData.ChickenData }>,

  -- Combat state
  EquippedWeapon: Fusion.Value<string>,
  OwnedWeapons: Fusion.Value<{ string }>,
  ShieldActive: Fusion.Value<boolean>,
  ShieldExpiresAt: Fusion.Value<number?>,
  ShieldCooldownEnd: Fusion.Value<number?>,

  -- Computed values
  TotalChickens: Fusion.Computed<number>,
  TotalEggs: Fusion.Computed<number>,
  CanActivateShield: Fusion.Computed<boolean>,

  -- Connection management
  Connections: { RBXScriptConnection | { Disconnect: () -> () } },
}

local PlayerState = {} :: PlayerStateType

-- Core data values
PlayerState.Money = Value(0)
PlayerState.Level = Value(1)
PlayerState.XP = Value(0)
PlayerState.IsDataLoaded = Value(false)

-- Inventory state
PlayerState.Eggs = Value({} :: { PlayerData.EggData })
PlayerState.InventoryChickens = Value({} :: { PlayerData.ChickenData })
PlayerState.PlacedChickens = Value({} :: { PlayerData.ChickenData })

-- Combat state
PlayerState.EquippedWeapon = Value("BaseballBat")
PlayerState.OwnedWeapons = Value({ "BaseballBat" } :: { string })
PlayerState.ShieldActive = Value(false)
PlayerState.ShieldExpiresAt = Value(nil :: number?)
PlayerState.ShieldCooldownEnd = Value(nil :: number?)

-- Computed values
PlayerState.TotalChickens = Computed(function(use)
  local inventoryCount = #use(PlayerState.InventoryChickens)
  local placedCount = #use(PlayerState.PlacedChickens)
  return inventoryCount + placedCount
end)

PlayerState.TotalEggs = Computed(function(use)
  return #use(PlayerState.Eggs)
end)

PlayerState.CanActivateShield = Computed(function(use)
  local isActive = use(PlayerState.ShieldActive)
  local cooldownEnd = use(PlayerState.ShieldCooldownEnd)

  if isActive then
    return false
  end

  if cooldownEnd and os.time() < cooldownEnd then
    return false
  end

  return true
end)

-- Store connections for cleanup
PlayerState.Connections = {}

--[[
	Initialize the state from a PlayerDataSchema.
	Called when data is first loaded.

	@param data PlayerData.PlayerDataSchema - The loaded player data
]]
function PlayerState.initFromData(data: PlayerData.PlayerDataSchema)
  PlayerState.Money:set(data.money or 0)
  PlayerState.Level:set(PlayerData.getLevel(data))
  PlayerState.XP:set(PlayerData.getXP(data))

  -- Inventory
  if data.inventory then
    PlayerState.Eggs:set(data.inventory.eggs or {})
    PlayerState.InventoryChickens:set(data.inventory.chickens or {})
  end
  PlayerState.PlacedChickens:set(data.placedChickens or {})

  -- Combat
  PlayerState.EquippedWeapon:set(PlayerData.getEquippedWeapon(data))
  PlayerState.OwnedWeapons:set(PlayerData.getOwnedWeapons(data))

  -- Shield
  if data.shieldState then
    PlayerState.ShieldActive:set(data.shieldState.isActive or false)
    PlayerState.ShieldExpiresAt:set(data.shieldState.expiresAt)
    PlayerState.ShieldCooldownEnd:set(data.shieldState.cooldownEndTime)
  end

  PlayerState.IsDataLoaded:set(true)
end

--[[
	Update money value.

	@param newMoney number - The new money amount
]]
function PlayerState.setMoney(newMoney: number)
  PlayerState.Money:set(newMoney)
end

--[[
	Update inventory from InventoryData.

	@param inventory PlayerData.InventoryData - The new inventory data
]]
function PlayerState.setInventory(inventory: PlayerData.InventoryData)
  PlayerState.Eggs:set(inventory.eggs or {})
  PlayerState.InventoryChickens:set(inventory.chickens or {})
end

--[[
	Update level and XP.

	@param level number - The new level
	@param xp number - The new XP
]]
function PlayerState.setLevel(level: number, xp: number)
  PlayerState.Level:set(level)
  PlayerState.XP:set(xp)
end

--[[
	Update placed chickens list.

	@param chickens {ChickenData} - Array of placed chickens
]]
function PlayerState.setPlacedChickens(chickens: { PlayerData.ChickenData })
  PlayerState.PlacedChickens:set(chickens)
end

--[[
	Update shield state.

	@param isActive boolean - Whether shield is active
	@param expiresAt number? - When shield expires (os.time)
	@param cooldownEnd number? - When cooldown ends (os.time)
]]
function PlayerState.setShieldState(isActive: boolean, expiresAt: number?, cooldownEnd: number?)
  PlayerState.ShieldActive:set(isActive)
  PlayerState.ShieldExpiresAt:set(expiresAt)
  PlayerState.ShieldCooldownEnd:set(cooldownEnd)
end

--[[
	Update equipped weapon.

	@param weaponType string - The weapon type
]]
function PlayerState.setEquippedWeapon(weaponType: string)
  PlayerState.EquippedWeapon:set(weaponType)
end

--[[
	Update owned weapons list.

	@param weapons {string} - Array of weapon types
]]
function PlayerState.setOwnedWeapons(weapons: { string })
  PlayerState.OwnedWeapons:set(weapons)
end

--[[
	Cleanup all connections.
	Call when player leaves or UI is destroyed.
]]
function PlayerState.cleanup()
  for _, connection in ipairs(PlayerState.Connections) do
    if typeof(connection) == "RBXScriptConnection" then
      connection:Disconnect()
    elseif type(connection) == "table" and connection.Disconnect then
      connection:Disconnect()
    end
  end
  table.clear(PlayerState.Connections)
end

return PlayerState
