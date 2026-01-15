--[[
	ChickenConfig Module
	Defines all chicken types with their rarity, egg laying intervals,
	money generation rates, and egg types they produce.
]]

local ChickenConfig = {}

-- Rarity tiers ordered from lowest to highest
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- Chicken configuration structure
export type ChickenTypeConfig = {
  name: string,
  displayName: string,
  rarity: Rarity,
  moneyPerSecond: number,
  eggLayIntervalSeconds: number,
  eggsLaid: { string }, -- Egg types this chicken can lay
}

-- Rarity multipliers for exponential scaling
-- Each tier is roughly 10x the previous
local RARITY_MONEY_MULTIPLIERS: { [Rarity]: number } = {
  Common = 1,
  Uncommon = 10,
  Rare = 100,
  Epic = 1000,
  Legendary = 10000,
  Mythic = 100000,
}

-- Base money per second (Common chicken earns this)
local BASE_MONEY_PER_SECOND = 1

-- Egg laying intervals (rarer chickens lay less frequently but lay rarer eggs)
local RARITY_EGG_INTERVALS: { [Rarity]: number } = {
  Common = 60, -- 1 minute
  Uncommon = 90, -- 1.5 minutes
  Rare = 120, -- 2 minutes
  Epic = 180, -- 3 minutes
  Legendary = 300, -- 5 minutes
  Mythic = 600, -- 10 minutes
}

-- Chicken health by rarity (rarer chickens have more health)
local RARITY_MAX_HEALTH: { [Rarity]: number } = {
  Common = 50,
  Uncommon = 75,
  Rare = 100,
  Epic = 150,
  Legendary = 200,
  Mythic = 300,
}

-- Health regeneration per second when not under attack (rarer chickens regen faster)
local RARITY_HEALTH_REGEN: { [Rarity]: number } = {
  Common = 5,
  Uncommon = 8,
  Rare = 10,
  Epic = 15,
  Legendary = 20,
  Mythic = 30,
}

-- Time in seconds before health starts regenerating after taking damage
local HEALTH_REGEN_DELAY = 3

-- Maximum number of chickens allowed per player area
local MAX_CHICKENS_PER_AREA = 15

-- All chicken types in the game
local CHICKEN_TYPES: { [string]: ChickenTypeConfig } = {
  -- Common Chickens
  BasicChick = {
    name = "BasicChick",
    displayName = "Basic Chick",
    rarity = "Common",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Common,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Common,
    eggsLaid = { "CommonEgg" },
  },
  BrownHen = {
    name = "BrownHen",
    displayName = "Brown Hen",
    rarity = "Common",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Common * 1.2,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Common,
    eggsLaid = { "CommonEgg" },
  },
  WhiteHen = {
    name = "WhiteHen",
    displayName = "White Hen",
    rarity = "Common",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Common * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Common,
    eggsLaid = { "CommonEgg" },
  },

  -- Uncommon Chickens
  SpeckledHen = {
    name = "SpeckledHen",
    displayName = "Speckled Hen",
    rarity = "Uncommon",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Uncommon,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Uncommon,
    eggsLaid = { "CommonEgg", "UncommonEgg" },
  },
  GoldenHen = {
    name = "GoldenHen",
    displayName = "Golden Hen",
    rarity = "Uncommon",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Uncommon * 1.3,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Uncommon,
    eggsLaid = { "CommonEgg", "UncommonEgg" },
  },
  SilverRooster = {
    name = "SilverRooster",
    displayName = "Silver Rooster",
    rarity = "Uncommon",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Uncommon * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Uncommon,
    eggsLaid = { "UncommonEgg" },
  },

  -- Rare Chickens
  RainbowChicken = {
    name = "RainbowChicken",
    displayName = "Rainbow Chicken",
    rarity = "Rare",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Rare,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Rare,
    eggsLaid = { "UncommonEgg", "RareEgg" },
  },
  CrystalHen = {
    name = "CrystalHen",
    displayName = "Crystal Hen",
    rarity = "Rare",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Rare * 1.3,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Rare,
    eggsLaid = { "RareEgg" },
  },
  FlameRooster = {
    name = "FlameRooster",
    displayName = "Flame Rooster",
    rarity = "Rare",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Rare * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Rare,
    eggsLaid = { "RareEgg" },
  },

  -- Epic Chickens
  PhoenixChick = {
    name = "PhoenixChick",
    displayName = "Phoenix Chick",
    rarity = "Epic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Epic,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Epic,
    eggsLaid = { "RareEgg", "EpicEgg" },
  },
  DiamondHen = {
    name = "DiamondHen",
    displayName = "Diamond Hen",
    rarity = "Epic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Epic * 1.3,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Epic,
    eggsLaid = { "EpicEgg" },
  },
  ThunderRooster = {
    name = "ThunderRooster",
    displayName = "Thunder Rooster",
    rarity = "Epic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Epic * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Epic,
    eggsLaid = { "EpicEgg" },
  },

  -- Legendary Chickens
  CosmicChicken = {
    name = "CosmicChicken",
    displayName = "Cosmic Chicken",
    rarity = "Legendary",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Legendary,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Legendary,
    eggsLaid = { "EpicEgg", "LegendaryEgg" },
  },
  VoidHen = {
    name = "VoidHen",
    displayName = "Void Hen",
    rarity = "Legendary",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Legendary * 1.3,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Legendary,
    eggsLaid = { "LegendaryEgg" },
  },
  StarRooster = {
    name = "StarRooster",
    displayName = "Star Rooster",
    rarity = "Legendary",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Legendary * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Legendary,
    eggsLaid = { "LegendaryEgg" },
  },

  -- Mythic Chickens
  DragonChicken = {
    name = "DragonChicken",
    displayName = "Dragon Chicken",
    rarity = "Mythic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Mythic,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Mythic,
    eggsLaid = { "LegendaryEgg", "MythicEgg" },
  },
  CelestialHen = {
    name = "CelestialHen",
    displayName = "Celestial Hen",
    rarity = "Mythic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Mythic * 1.3,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Mythic,
    eggsLaid = { "MythicEgg" },
  },
  OmegaRooster = {
    name = "OmegaRooster",
    displayName = "Omega Rooster",
    rarity = "Mythic",
    moneyPerSecond = BASE_MONEY_PER_SECOND * RARITY_MONEY_MULTIPLIERS.Mythic * 1.5,
    eggLayIntervalSeconds = RARITY_EGG_INTERVALS.Mythic,
    eggsLaid = { "MythicEgg" },
  },
}

-- Get configuration for a specific chicken type
function ChickenConfig.get(chickenType: string): ChickenTypeConfig?
  return CHICKEN_TYPES[chickenType]
end

-- Get all chicken types
function ChickenConfig.getAll(): { [string]: ChickenTypeConfig }
  return CHICKEN_TYPES
end

-- Get all chicken types of a specific rarity
function ChickenConfig.getByRarity(rarity: Rarity): { ChickenTypeConfig }
  local result = {}
  for _, config in pairs(CHICKEN_TYPES) do
    if config.rarity == rarity then
      table.insert(result, config)
    end
  end
  return result
end

-- Get the money multiplier for a rarity
function ChickenConfig.getRarityMultiplier(rarity: Rarity): number
  return RARITY_MONEY_MULTIPLIERS[rarity] or 1
end

-- Get the egg laying interval for a rarity
function ChickenConfig.getRarityEggInterval(rarity: Rarity): number
  return RARITY_EGG_INTERVALS[rarity] or 60
end

-- Validate that a chicken type exists
function ChickenConfig.isValidType(chickenType: string): boolean
  return CHICKEN_TYPES[chickenType] ~= nil
end

-- Get all valid chicken type names
function ChickenConfig.getAllTypes(): { string }
  local types = {}
  for typeName, _ in pairs(CHICKEN_TYPES) do
    table.insert(types, typeName)
  end
  return types
end

-- Get all rarities in order
function ChickenConfig.getRarities(): { Rarity }
  return { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
end

-- Calculate money earned over a time period for a chicken type
function ChickenConfig.calculateEarnings(chickenType: string, seconds: number): number
  local config = CHICKEN_TYPES[chickenType]
  if not config then
    return 0
  end
  return config.moneyPerSecond * seconds
end

-- Get max health for a rarity
function ChickenConfig.getMaxHealth(rarity: Rarity): number
  return RARITY_MAX_HEALTH[rarity] or 50
end

-- Get health regen rate for a rarity (HP per second)
function ChickenConfig.getHealthRegen(rarity: Rarity): number
  return RARITY_HEALTH_REGEN[rarity] or 5
end

-- Get health regen delay (time before regen starts after taking damage)
function ChickenConfig.getHealthRegenDelay(): number
  return HEALTH_REGEN_DELAY
end

-- Get max health for a specific chicken type
function ChickenConfig.getMaxHealthForType(chickenType: string): number
  local config = CHICKEN_TYPES[chickenType]
  if not config then
    return 50
  end
  return RARITY_MAX_HEALTH[config.rarity] or 50
end

-- Get health regen for a specific chicken type
function ChickenConfig.getHealthRegenForType(chickenType: string): number
  local config = CHICKEN_TYPES[chickenType]
  if not config then
    return 5
  end
  return RARITY_HEALTH_REGEN[config.rarity] or 5
end

-- Get maximum chickens allowed per player area
function ChickenConfig.getMaxChickensPerArea(): number
  return MAX_CHICKENS_PER_AREA
end

return ChickenConfig
