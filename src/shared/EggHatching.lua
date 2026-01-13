--[[
	EggHatching Module
	Handles the egg hatching system including weighted random selection,
	egg consumption, and chicken spawning.
]]

local EggHatching = {}

-- Import dependencies
local EggConfig = require(script.Parent.EggConfig)
local ChickenConfig = require(script.Parent.ChickenConfig)
local PlayerData = require(script.Parent.PlayerData)

-- Type definitions
export type HatchResult = {
  success: boolean,
  message: string,
  chickenType: string?,
  chickenRarity: string?,
  chickenId: string?,
  isRareHatch: boolean,
  celebrationTier: number, -- 0=none, 1=uncommon, 2=rare, 3=epic, 4=legendary, 5=mythic
}

-- Rarity to celebration tier mapping
local CELEBRATION_TIERS: { [string]: number } = {
  Common = 0,
  Uncommon = 1,
  Rare = 2,
  Epic = 3,
  Legendary = 4,
  Mythic = 5,
}

-- Find an egg in the player's inventory by ID
local function findEggById(
  playerData: PlayerData.PlayerDataSchema,
  eggId: string
): (number?, PlayerData.EggData?)
  for index, egg in ipairs(playerData.inventory.eggs) do
    if egg.id == eggId then
      return index, egg
    end
  end
  return nil, nil
end

-- Find an egg in the player's inventory by type (returns first match)
local function findEggByType(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string
): (number?, PlayerData.EggData?)
  for index, egg in ipairs(playerData.inventory.eggs) do
    if egg.eggType == eggType then
      return index, egg
    end
  end
  return nil, nil
end

-- Remove an egg from inventory by index
local function removeEggAtIndex(playerData: PlayerData.PlayerDataSchema, index: number): boolean
  if index < 1 or index > #playerData.inventory.eggs then
    return false
  end
  table.remove(playerData.inventory.eggs, index)
  return true
end

-- Add a chicken to inventory
local function addChickenToInventory(
  playerData: PlayerData.PlayerDataSchema,
  chickenType: string
): PlayerData.ChickenData?
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return nil
  end

  local currentTime = os.time()
  local chickenData: PlayerData.ChickenData = {
    id = PlayerData.generateId(),
    chickenType = chickenType,
    rarity = chickenConfig.rarity,
    accumulatedMoney = 0,
    lastEggTime = currentTime,
    spotIndex = nil, -- In inventory, not placed
  }

  table.insert(playerData.inventory.chickens, chickenData)
  return chickenData
end

-- Get celebration tier for a rarity
function EggHatching.getCelebrationTier(rarity: string): number
  return CELEBRATION_TIERS[rarity] or 0
end

-- Check if a rarity should trigger celebration effects
function EggHatching.isRareHatch(rarity: string): boolean
  local tier = CELEBRATION_TIERS[rarity] or 0
  return tier >= 2 -- Rare or higher
end

-- Get hatch outcomes preview for an egg type (for UI display)
function EggHatching.getHatchPreview(eggType: string): { EggConfig.HatchOutcome }?
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return nil
  end
  return eggConfig.hatchOutcomes
end

-- Validate that a hatch can occur
function EggHatching.canHatch(
  playerData: PlayerData.PlayerDataSchema,
  eggId: string
): (boolean, string)
  -- Validate player data
  if not playerData or not playerData.inventory then
    return false, "Invalid player data"
  end

  -- Find the egg
  local eggIndex, egg = findEggById(playerData, eggId)
  if not eggIndex or not egg then
    return false, "Egg not found in inventory"
  end

  -- Validate egg type exists in config
  if not EggConfig.isValidType(egg.eggType) then
    return false, "Invalid egg type"
  end

  return true, "Ready to hatch"
end

-- Perform the hatch operation
-- This modifies the playerData in place: removes egg, adds chicken
function EggHatching.hatch(playerData: PlayerData.PlayerDataSchema, eggId: string): HatchResult
  -- Validate can hatch
  local canHatch, message = EggHatching.canHatch(playerData, eggId)
  if not canHatch then
    return {
      success = false,
      message = message,
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  -- Find the egg
  local eggIndex, egg = findEggById(playerData, eggId)
  if not eggIndex or not egg then
    return {
      success = false,
      message = "Egg not found",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  -- Select chicken using weighted random selection
  local selectedChickenType = EggConfig.selectHatchOutcome(egg.eggType)
  if not selectedChickenType then
    return {
      success = false,
      message = "Failed to select hatch outcome",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  -- Remove egg from inventory
  if not removeEggAtIndex(playerData, eggIndex) then
    return {
      success = false,
      message = "Failed to remove egg from inventory",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  -- Add chicken to inventory
  local newChicken = addChickenToInventory(playerData, selectedChickenType)
  if not newChicken then
    -- Rollback: add egg back (this shouldn't happen)
    table.insert(playerData.inventory.eggs, eggIndex, egg)
    return {
      success = false,
      message = "Failed to create chicken",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  local chickenRarity = newChicken.rarity
  local celebrationTier = EggHatching.getCelebrationTier(chickenRarity)
  local isRare = EggHatching.isRareHatch(chickenRarity)

  return {
    success = true,
    message = "Hatched successfully!",
    chickenType = selectedChickenType,
    chickenRarity = chickenRarity,
    chickenId = newChicken.id,
    isRareHatch = isRare,
    celebrationTier = celebrationTier,
  }
end

-- Hatch an egg by type (uses first matching egg in inventory)
function EggHatching.hatchByType(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string
): HatchResult
  -- Find an egg of this type
  local _, egg = findEggByType(playerData, eggType)
  if not egg then
    return {
      success = false,
      message = "No egg of type " .. eggType .. " found in inventory",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  return EggHatching.hatch(playerData, egg.id)
end

-- Get the count of eggs of a specific type in inventory
function EggHatching.getEggCount(playerData: PlayerData.PlayerDataSchema, eggType: string): number
  local count = 0
  for _, egg in ipairs(playerData.inventory.eggs) do
    if egg.eggType == eggType then
      count = count + 1
    end
  end
  return count
end

-- Get total egg count in inventory
function EggHatching.getTotalEggCount(playerData: PlayerData.PlayerDataSchema): number
  return #playerData.inventory.eggs
end

-- Simulate many hatches to verify probability distribution (for testing)
function EggHatching.simulateHatches(eggType: string, numHatches: number): { [string]: number }
  local results: { [string]: number } = {}

  for _ = 1, numHatches do
    local chickenType = EggConfig.selectHatchOutcome(eggType)
    if chickenType then
      results[chickenType] = (results[chickenType] or 0) + 1
    end
  end

  return results
end

-- Get celebration effect data for a rarity tier
function EggHatching.getCelebrationEffects(celebrationTier: number): {
  particleCount: number,
  soundName: string,
  screenFlash: boolean,
  announceToServer: boolean,
}
  if celebrationTier <= 0 then
    return {
      particleCount = 0,
      soundName = "hatch_common",
      screenFlash = false,
      announceToServer = false,
    }
  elseif celebrationTier == 1 then
    return {
      particleCount = 10,
      soundName = "hatch_uncommon",
      screenFlash = false,
      announceToServer = false,
    }
  elseif celebrationTier == 2 then
    return {
      particleCount = 25,
      soundName = "hatch_rare",
      screenFlash = true,
      announceToServer = false,
    }
  elseif celebrationTier == 3 then
    return {
      particleCount = 50,
      soundName = "hatch_epic",
      screenFlash = true,
      announceToServer = false,
    }
  elseif celebrationTier == 4 then
    return {
      particleCount = 100,
      soundName = "hatch_legendary",
      screenFlash = true,
      announceToServer = true,
    }
  else -- 5 (Mythic)
    return {
      particleCount = 200,
      soundName = "hatch_mythic",
      screenFlash = true,
      announceToServer = true,
    }
  end
end

return EggHatching
