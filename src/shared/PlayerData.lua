--[[
	PlayerData Module
	Defines the data structure for storing player information including
	inventory, money, chickens, eggs, traps, and upgrades.
]]

local PlayerData = {}

-- Type definitions for player data structure
export type ChickenData = {
  id: string,
  chickenType: string,
  rarity: string,
  accumulatedMoney: number,
  lastEggTime: number,
  spotIndex: number?, -- nil if in inventory
  placedTime: number?, -- os.time() when placed in coop (for protection period)
}

export type EggData = {
  id: string,
  eggType: string,
  rarity: string,
}

export type TrapData = {
  id: string,
  trapType: string,
  tier: number,
  spotIndex: number,
  cooldownEndTime: number?,
  caughtPredator: string?,
}

export type UpgradeData = {
  cageTier: number,
  lockDurationMultiplier: number,
  predatorResistance: number,
}

export type ActivePowerUp = {
  powerUpId: string,
  activatedTime: number,
  expiresAt: number,
}

export type InventoryData = {
  eggs: { EggData },
  chickens: { ChickenData }, -- Chickens not placed in coop
}

export type PlayerDataSchema = {
  money: number,
  inventory: InventoryData,
  placedChickens: { ChickenData }, -- Chickens placed in coop spots
  traps: { TrapData },
  upgrades: UpgradeData,
  activePowerUps: { ActivePowerUp }?, -- Currently active power-ups
  sectionIndex: number?,
  lastLogoutTime: number?,
  totalPlayTime: number,
  tutorialComplete: boolean?,
}

-- Rarity tiers for validation
local VALID_RARITIES = {
  Common = true,
  Uncommon = true,
  Rare = true,
  Epic = true,
  Legendary = true,
  Mythic = true,
}

-- Bankruptcy protection constants
local CHEAPEST_ITEM_PRICE = 100 -- Common egg costs $100
local BANKRUPTCY_STARTER_MONEY = 100 -- Amount given to bankrupt players

-- Creates default player data with starting money (enough to buy a common egg)
function PlayerData.createDefault(): PlayerDataSchema
  return {
    money = 100, -- Exactly enough to buy a Common Egg from the store
    inventory = {
      eggs = {},
      chickens = {},
    },
    placedChickens = {},
    traps = {},
    upgrades = {
      cageTier = 1,
      lockDurationMultiplier = 1,
      predatorResistance = 0,
    },
    activePowerUps = {},
    sectionIndex = nil,
    lastLogoutTime = nil,
    totalPlayTime = 0,
    tutorialComplete = false,
  }
end

-- Generates a unique ID for items
function PlayerData.generateId(): string
  return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

-- Validates that a value is a number and optionally within range
local function validateNumber(value: any, minVal: number?, maxVal: number?): boolean
  if type(value) ~= "number" then
    return false
  end
  if minVal and value < minVal then
    return false
  end
  if maxVal and value > maxVal then
    return false
  end
  return true
end

-- Validates a rarity string
local function validateRarity(rarity: any): boolean
  return type(rarity) == "string" and VALID_RARITIES[rarity] == true
end

-- Validates an egg data structure
function PlayerData.validateEgg(egg: any): boolean
  if type(egg) ~= "table" then
    return false
  end
  if type(egg.id) ~= "string" or egg.id == "" then
    return false
  end
  if type(egg.eggType) ~= "string" or egg.eggType == "" then
    return false
  end
  if not validateRarity(egg.rarity) then
    return false
  end
  return true
end

-- Validates a chicken data structure
function PlayerData.validateChicken(chicken: any): boolean
  if type(chicken) ~= "table" then
    return false
  end
  if type(chicken.id) ~= "string" or chicken.id == "" then
    return false
  end
  if type(chicken.chickenType) ~= "string" or chicken.chickenType == "" then
    return false
  end
  if not validateRarity(chicken.rarity) then
    return false
  end
  if not validateNumber(chicken.accumulatedMoney, 0) then
    return false
  end
  if not validateNumber(chicken.lastEggTime, 0) then
    return false
  end
  -- spotIndex is optional (nil if in inventory)
  if chicken.spotIndex ~= nil and not validateNumber(chicken.spotIndex, 1, 12) then
    return false
  end
  return true
end

-- Validates a trap data structure
function PlayerData.validateTrap(trap: any): boolean
  if type(trap) ~= "table" then
    return false
  end
  if type(trap.id) ~= "string" or trap.id == "" then
    return false
  end
  if type(trap.trapType) ~= "string" or trap.trapType == "" then
    return false
  end
  if not validateNumber(trap.tier, 1) then
    return false
  end
  if not validateNumber(trap.spotIndex, 1) then
    return false
  end
  -- Optional fields
  if trap.cooldownEndTime ~= nil and not validateNumber(trap.cooldownEndTime, 0) then
    return false
  end
  if trap.caughtPredator ~= nil and type(trap.caughtPredator) ~= "string" then
    return false
  end
  return true
end

-- Validates upgrade data structure
function PlayerData.validateUpgrades(upgrades: any): boolean
  if type(upgrades) ~= "table" then
    return false
  end
  if not validateNumber(upgrades.cageTier, 1) then
    return false
  end
  if not validateNumber(upgrades.lockDurationMultiplier, 1) then
    return false
  end
  if not validateNumber(upgrades.predatorResistance, 0, 1) then
    return false
  end
  return true
end

-- Validates a single active power-up structure
function PlayerData.validateActivePowerUp(powerUp: any): boolean
  if type(powerUp) ~= "table" then
    return false
  end
  if type(powerUp.powerUpId) ~= "string" or powerUp.powerUpId == "" then
    return false
  end
  if not validateNumber(powerUp.activatedTime, 0) then
    return false
  end
  if not validateNumber(powerUp.expiresAt, 0) then
    return false
  end
  return true
end

-- Validates inventory data structure
function PlayerData.validateInventory(inventory: any): boolean
  if type(inventory) ~= "table" then
    return false
  end
  if type(inventory.eggs) ~= "table" then
    return false
  end
  if type(inventory.chickens) ~= "table" then
    return false
  end
  for _, egg in ipairs(inventory.eggs) do
    if not PlayerData.validateEgg(egg) then
      return false
    end
  end
  for _, chicken in ipairs(inventory.chickens) do
    if not PlayerData.validateChicken(chicken) then
      return false
    end
  end
  return true
end

-- Validates complete player data structure
function PlayerData.validate(data: any): boolean
  if type(data) ~= "table" then
    return false
  end

  -- Validate money
  if not validateNumber(data.money, 0) then
    return false
  end

  -- Validate inventory
  if not PlayerData.validateInventory(data.inventory) then
    return false
  end

  -- Validate placed chickens
  if type(data.placedChickens) ~= "table" then
    return false
  end
  for _, chicken in ipairs(data.placedChickens) do
    if not PlayerData.validateChicken(chicken) then
      return false
    end
  end

  -- Validate traps
  if type(data.traps) ~= "table" then
    return false
  end
  for _, trap in ipairs(data.traps) do
    if not PlayerData.validateTrap(trap) then
      return false
    end
  end

  -- Validate upgrades
  if not PlayerData.validateUpgrades(data.upgrades) then
    return false
  end

  -- Validate activePowerUps (optional field)
  if data.activePowerUps ~= nil then
    if type(data.activePowerUps) ~= "table" then
      return false
    end
    for _, powerUp in ipairs(data.activePowerUps) do
      if not PlayerData.validateActivePowerUp(powerUp) then
        return false
      end
    end
  end

  -- Validate optional fields
  if data.sectionIndex ~= nil and not validateNumber(data.sectionIndex, 1, 12) then
    return false
  end
  if data.lastLogoutTime ~= nil and not validateNumber(data.lastLogoutTime, 0) then
    return false
  end
  if not validateNumber(data.totalPlayTime, 0) then
    return false
  end
  -- tutorialComplete is optional boolean
  if data.tutorialComplete ~= nil and type(data.tutorialComplete) ~= "boolean" then
    return false
  end

  return true
end

-- Deep clone player data to prevent reference issues
function PlayerData.clone(data: PlayerDataSchema): PlayerDataSchema
  local function deepClone(tbl: any): any
    if type(tbl) ~= "table" then
      return tbl
    end
    local copy = {}
    for key, value in pairs(tbl) do
      copy[key] = deepClone(value)
    end
    return copy
  end
  return deepClone(data)
end

-- Check if a player is bankrupt (cannot afford anything and has no assets)
function PlayerData.isBankrupt(data: PlayerDataSchema): boolean
  -- Has money to buy cheapest item? Not bankrupt
  if data.money >= CHEAPEST_ITEM_PRICE then
    return false
  end

  -- Has any eggs in inventory? Not bankrupt (can hatch them)
  if data.inventory and data.inventory.eggs and #data.inventory.eggs > 0 then
    return false
  end

  -- Has any chickens in inventory? Not bankrupt (can sell or place them)
  if data.inventory and data.inventory.chickens and #data.inventory.chickens > 0 then
    return false
  end

  -- Has any placed chickens? Not bankrupt (can collect money)
  if data.placedChickens and #data.placedChickens > 0 then
    return false
  end

  -- No assets and not enough money - player is bankrupt
  return true
end

-- Get the starter money amount for bankruptcy assistance
function PlayerData.getBankruptcyStarterMoney(): number
  return BANKRUPTCY_STARTER_MONEY
end

-- Check if a player has an active power-up of a specific type
function PlayerData.hasActivePowerUp(data: PlayerDataSchema, powerUpType: string): boolean
  if not data.activePowerUps then
    return false
  end
  local currentTime = os.time()
  for _, powerUp in ipairs(data.activePowerUps) do
    -- Check if power-up matches type and is not expired
    if string.find(powerUp.powerUpId, powerUpType) and currentTime < powerUp.expiresAt then
      return true
    end
  end
  return false
end

-- Get the active power-up of a specific type (returns nil if none or expired)
function PlayerData.getActivePowerUp(data: PlayerDataSchema, powerUpType: string): ActivePowerUp?
  if not data.activePowerUps then
    return nil
  end
  local currentTime = os.time()
  for _, powerUp in ipairs(data.activePowerUps) do
    if string.find(powerUp.powerUpId, powerUpType) and currentTime < powerUp.expiresAt then
      return powerUp
    end
  end
  return nil
end

-- Add or extend a power-up for a player
function PlayerData.addPowerUp(data: PlayerDataSchema, powerUpId: string, durationSeconds: number)
  -- Initialize if nil
  if not data.activePowerUps then
    data.activePowerUps = {}
  end

  local currentTime = os.time()

  -- Find matching power-up type prefix (e.g., "HatchLuck" or "EggQuality")
  local powerUpType = nil
  if string.find(powerUpId, "HatchLuck") then
    powerUpType = "HatchLuck"
  elseif string.find(powerUpId, "EggQuality") then
    powerUpType = "EggQuality"
  end

  -- Look for existing power-up of same type to extend
  for i, existingPowerUp in ipairs(data.activePowerUps) do
    if powerUpType and string.find(existingPowerUp.powerUpId, powerUpType) then
      -- Extend from current expiry time (or current time if expired)
      local baseTime = math.max(currentTime, existingPowerUp.expiresAt)
      data.activePowerUps[i] = {
        powerUpId = powerUpId,
        activatedTime = existingPowerUp.activatedTime,
        expiresAt = baseTime + durationSeconds,
      }
      return
    end
  end

  -- No existing power-up of this type, add new one
  table.insert(data.activePowerUps, {
    powerUpId = powerUpId,
    activatedTime = currentTime,
    expiresAt = currentTime + durationSeconds,
  })
end

-- Remove expired power-ups from player data
function PlayerData.cleanupExpiredPowerUps(data: PlayerDataSchema)
  if not data.activePowerUps then
    return
  end

  local currentTime = os.time()
  local activePowerUps = {}

  for _, powerUp in ipairs(data.activePowerUps) do
    if currentTime < powerUp.expiresAt then
      table.insert(activePowerUps, powerUp)
    end
  end

  data.activePowerUps = activePowerUps
end

return PlayerData
