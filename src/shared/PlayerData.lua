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
  lastCollectTime: number?, -- os.time() when money was last collected
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

export type ShieldState = {
  isActive: boolean,
  activatedTime: number?,
  expiresAt: number?,
  cooldownEndTime: number?,
}

export type GameRecord = {
  totalWins: number, -- Total predators defeated
  totalLosses: number, -- Total chickens lost to predators
  totalSteals: number, -- Total chickens stolen from other players
}

export type PlayerDataSchema = {
  money: number,
  inventory: InventoryData,
  placedChickens: { ChickenData }, -- Chickens placed in coop spots
  traps: { TrapData },
  upgrades: UpgradeData,
  activePowerUps: { ActivePowerUp }?, -- Currently active power-ups
  ownedWeapons: { string }?, -- List of weapon types the player owns
  equippedWeapon: string?, -- Currently equipped weapon type
  shieldState: ShieldState?, -- Area shield protection state
  sectionIndex: number?,
  lastLogoutTime: number?,
  totalPlayTime: number,
  tutorialComplete: boolean?,
  level: number?, -- Player's current level (calculated from XP)
  xp: number?, -- Total experience points earned
  gameRecord: GameRecord?, -- Player's game record (wins, losses, steals)
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

-- Creates default player data with starting money and starter items
function PlayerData.createDefault(): PlayerDataSchema
  local currentTime = os.time()
  return {
    money = 100, -- Exactly enough to buy a Common Egg from the store
    inventory = {
      eggs = {}, -- Empty - starter egg is spawned in world on join
      chickens = {},
    },
    -- New players start with one Basic Chick already placed in their area
    placedChickens = {
      {
        id = tostring(currentTime) .. "_starter_chicken",
        chickenType = "BasicChick",
        rarity = "Common",
        accumulatedMoney = 0,
        lastEggTime = currentTime,
        lastCollectTime = currentTime,
        spotIndex = 1,
        placedTime = currentTime,
      },
    },
    traps = {},
    upgrades = {
      cageTier = 1,
      lockDurationMultiplier = 1,
      predatorResistance = 0,
    },
    activePowerUps = {},
    ownedWeapons = { "BaseballBat" }, -- Everyone starts with a baseball bat
    equippedWeapon = "BaseballBat", -- Bat is equipped by default
    shieldState = {
      isActive = false,
      activatedTime = nil,
      expiresAt = nil,
      cooldownEndTime = nil,
    },
    sectionIndex = nil,
    lastLogoutTime = nil,
    totalPlayTime = 0,
    tutorialComplete = false,
    level = 1,
    xp = 0,
    gameRecord = {
      totalWins = 0,
      totalLosses = 0,
      totalSteals = 0,
    },
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

-- Validates game record structure
function PlayerData.validateGameRecord(gameRecord: any): boolean
  if type(gameRecord) ~= "table" then
    return false
  end
  if not validateNumber(gameRecord.totalWins, 0) then
    return false
  end
  if not validateNumber(gameRecord.totalLosses, 0) then
    return false
  end
  if not validateNumber(gameRecord.totalSteals, 0) then
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

  -- Validate ownedWeapons (optional field)
  if data.ownedWeapons ~= nil then
    if type(data.ownedWeapons) ~= "table" then
      return false
    end
    for _, weapon in ipairs(data.ownedWeapons) do
      if type(weapon) ~= "string" or weapon == "" then
        return false
      end
    end
  end

  -- Validate equippedWeapon (optional string)
  if data.equippedWeapon ~= nil and type(data.equippedWeapon) ~= "string" then
    return false
  end

  -- Validate shieldState (optional field)
  if data.shieldState ~= nil then
    if type(data.shieldState) ~= "table" then
      return false
    end
    if type(data.shieldState.isActive) ~= "boolean" then
      return false
    end
    if
      data.shieldState.activatedTime ~= nil
      and not validateNumber(data.shieldState.activatedTime, 0)
    then
      return false
    end
    if data.shieldState.expiresAt ~= nil and not validateNumber(data.shieldState.expiresAt, 0) then
      return false
    end
    if
      data.shieldState.cooldownEndTime ~= nil
      and not validateNumber(data.shieldState.cooldownEndTime, 0)
    then
      return false
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
  -- level is optional number (1+)
  if data.level ~= nil and not validateNumber(data.level, 1) then
    return false
  end
  -- xp is optional number (0+)
  if data.xp ~= nil and not validateNumber(data.xp, 0) then
    return false
  end
  -- gameRecord is optional, but if present must be valid
  if data.gameRecord ~= nil and not PlayerData.validateGameRecord(data.gameRecord) then
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

-- Check if a player owns a specific weapon
function PlayerData.ownsWeapon(data: PlayerDataSchema, weaponType: string): boolean
  if not data.ownedWeapons then
    return false
  end
  for _, weapon in ipairs(data.ownedWeapons) do
    if weapon == weaponType then
      return true
    end
  end
  return false
end

-- Add a weapon to player's owned weapons
function PlayerData.addWeapon(data: PlayerDataSchema, weaponType: string): boolean
  -- Initialize if nil
  if not data.ownedWeapons then
    data.ownedWeapons = {}
  end

  -- Check if already owned
  if PlayerData.ownsWeapon(data, weaponType) then
    return false -- Already owns this weapon
  end

  table.insert(data.ownedWeapons, weaponType)
  return true
end

-- Equip a weapon (must own it first)
function PlayerData.equipWeapon(data: PlayerDataSchema, weaponType: string): boolean
  if not PlayerData.ownsWeapon(data, weaponType) then
    return false -- Can't equip what you don't own
  end
  data.equippedWeapon = weaponType
  return true
end

-- Get the currently equipped weapon (defaults to BaseballBat)
function PlayerData.getEquippedWeapon(data: PlayerDataSchema): string
  return data.equippedWeapon or "BaseballBat"
end

-- Get all owned weapons
function PlayerData.getOwnedWeapons(data: PlayerDataSchema): { string }
  return data.ownedWeapons or { "BaseballBat" }
end

-- Get player's current level
function PlayerData.getLevel(data: PlayerDataSchema): number
  return data.level or 1
end

-- Get player's current XP
function PlayerData.getXP(data: PlayerDataSchema): number
  return data.xp or 0
end

-- Add XP to player (returns new level if leveled up, nil otherwise)
function PlayerData.addXP(data: PlayerDataSchema, amount: number): number?
  if amount <= 0 then
    return nil
  end

  local oldXP = data.xp or 0
  local newXP = oldXP + math.floor(amount)
  data.xp = newXP

  -- Calculate levels from XP (lazy load LevelConfig to avoid circular deps)
  local LevelConfig = require(script.Parent.LevelConfig)
  local oldLevel = LevelConfig.getLevelFromXP(oldXP)
  local newLevel = LevelConfig.getLevelFromXP(newXP)

  -- Update stored level
  data.level = newLevel

  -- Return new level if leveled up
  if newLevel > oldLevel then
    return newLevel
  end
  return nil
end

-- Set player's level and XP directly (for admin/testing)
function PlayerData.setLevelAndXP(data: PlayerDataSchema, level: number, xp: number): boolean
  if level < 1 or xp < 0 then
    return false
  end

  data.level = math.floor(level)
  data.xp = math.floor(xp)
  return true
end

-- Get player's game record (returns default if not set)
function PlayerData.getGameRecord(data: PlayerDataSchema): GameRecord
  if data.gameRecord then
    return data.gameRecord
  end
  return {
    totalWins = 0,
    totalLosses = 0,
    totalSteals = 0,
  }
end

-- Initialize game record if not present
local function ensureGameRecord(data: PlayerDataSchema)
  if not data.gameRecord then
    data.gameRecord = {
      totalWins = 0,
      totalLosses = 0,
      totalSteals = 0,
    }
  end
end

-- Increment total wins (predators defeated)
function PlayerData.incrementWins(data: PlayerDataSchema, amount: number?): number
  ensureGameRecord(data)
  local increment = math.floor(amount or 1)
  if increment > 0 then
    data.gameRecord.totalWins = data.gameRecord.totalWins + increment
  end
  return data.gameRecord.totalWins
end

-- Increment total losses (chickens lost to predators)
function PlayerData.incrementLosses(data: PlayerDataSchema, amount: number?): number
  ensureGameRecord(data)
  local increment = math.floor(amount or 1)
  if increment > 0 then
    data.gameRecord.totalLosses = data.gameRecord.totalLosses + increment
  end
  return data.gameRecord.totalLosses
end

-- Increment total steals (chickens stolen from other players)
function PlayerData.incrementSteals(data: PlayerDataSchema, amount: number?): number
  ensureGameRecord(data)
  local increment = math.floor(amount or 1)
  if increment > 0 then
    data.gameRecord.totalSteals = data.gameRecord.totalSteals + increment
  end
  return data.gameRecord.totalSteals
end

-- Get game record summary string
function PlayerData.getGameRecordSummary(data: PlayerDataSchema): string
  local record = PlayerData.getGameRecord(data)
  return string.format(
    "Wins: %d | Losses: %d | Steals: %d",
    record.totalWins,
    record.totalLosses,
    record.totalSteals
  )
end

return PlayerData
