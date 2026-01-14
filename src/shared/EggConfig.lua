--[[
	EggConfig Module
	Defines all egg types with their rarity, hatch probabilities for
	different chickens, and purchase prices.
]]

local EggConfig = {}

-- Import ChickenConfig types for validation
local ChickenConfig = require(script.Parent.ChickenConfig)

-- Create a properly seeded random generator using Roblox's Random class
-- This ensures different results each game session
local rng = Random.new()

-- Rarity tiers (same as ChickenConfig)
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- A single hatch outcome with chicken type and probability
export type HatchOutcome = {
  chickenType: string,
  probability: number, -- Percentage (0-100)
}

-- Egg configuration structure
export type EggTypeConfig = {
  name: string,
  displayName: string,
  rarity: Rarity,
  purchasePrice: number,
  sellPrice: number,
  hatchOutcomes: { HatchOutcome }, -- Exactly 3 outcomes summing to 100%
}

-- Base prices for eggs (exponential scaling)
local RARITY_PRICE_MULTIPLIERS: { [Rarity]: number } = {
  Common = 1,
  Uncommon = 10,
  Rare = 100,
  Epic = 1000,
  Legendary = 10000,
  Mythic = 100000,
}

-- Base purchase price (Common egg costs this)
local BASE_PURCHASE_PRICE = 100

-- Sell price is 50% of purchase price
local SELL_PRICE_RATIO = 0.5

-- All egg types in the game
-- Each egg has 3 possible chicken outcomes from its rarity tier
-- Probabilities: 70% common of tier, 25% mid-tier, 5% rare of tier
local EGG_TYPES: { [string]: EggTypeConfig } = {
  -- Common Egg: Hatches Common chickens
  CommonEgg = {
    name = "CommonEgg",
    displayName = "Common Egg",
    rarity = "Common",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Common,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Common * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "BasicChick", probability = 70 },
      { chickenType = "BrownHen", probability = 25 },
      { chickenType = "WhiteHen", probability = 5 },
    },
  },

  -- Uncommon Egg: Hatches Uncommon chickens
  UncommonEgg = {
    name = "UncommonEgg",
    displayName = "Uncommon Egg",
    rarity = "Uncommon",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Uncommon,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Uncommon * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "SpeckledHen", probability = 70 },
      { chickenType = "GoldenHen", probability = 25 },
      { chickenType = "SilverRooster", probability = 5 },
    },
  },

  -- Rare Egg: Hatches Rare chickens
  RareEgg = {
    name = "RareEgg",
    displayName = "Rare Egg",
    rarity = "Rare",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Rare,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Rare * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "RainbowChicken", probability = 70 },
      { chickenType = "CrystalHen", probability = 25 },
      { chickenType = "FlameRooster", probability = 5 },
    },
  },

  -- Epic Egg: Hatches Epic chickens
  EpicEgg = {
    name = "EpicEgg",
    displayName = "Epic Egg",
    rarity = "Epic",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Epic,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Epic * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "PhoenixChick", probability = 70 },
      { chickenType = "DiamondHen", probability = 25 },
      { chickenType = "ThunderRooster", probability = 5 },
    },
  },

  -- Legendary Egg: Hatches Legendary chickens
  LegendaryEgg = {
    name = "LegendaryEgg",
    displayName = "Legendary Egg",
    rarity = "Legendary",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Legendary,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Legendary * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "CosmicChicken", probability = 70 },
      { chickenType = "VoidHen", probability = 25 },
      { chickenType = "StarRooster", probability = 5 },
    },
  },

  -- Mythic Egg: Hatches Mythic chickens
  MythicEgg = {
    name = "MythicEgg",
    displayName = "Mythic Egg",
    rarity = "Mythic",
    purchasePrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Mythic,
    sellPrice = BASE_PURCHASE_PRICE * RARITY_PRICE_MULTIPLIERS.Mythic * SELL_PRICE_RATIO,
    hatchOutcomes = {
      { chickenType = "DragonChicken", probability = 70 },
      { chickenType = "CelestialHen", probability = 25 },
      { chickenType = "OmegaRooster", probability = 5 },
    },
  },
}

-- Get configuration for a specific egg type
function EggConfig.get(eggType: string): EggTypeConfig?
  return EGG_TYPES[eggType]
end

-- Get all egg types
function EggConfig.getAll(): { [string]: EggTypeConfig }
  return EGG_TYPES
end

-- Get all egg types of a specific rarity
function EggConfig.getByRarity(rarity: Rarity): { EggTypeConfig }
  local result = {}
  for _, config in pairs(EGG_TYPES) do
    if config.rarity == rarity then
      table.insert(result, config)
    end
  end
  return result
end

-- Get the price multiplier for a rarity
function EggConfig.getRarityPriceMultiplier(rarity: Rarity): number
  return RARITY_PRICE_MULTIPLIERS[rarity] or 1
end

-- Validate that an egg type exists
function EggConfig.isValidType(eggType: string): boolean
  return EGG_TYPES[eggType] ~= nil
end

-- Get all valid egg type names
function EggConfig.getAllTypes(): { string }
  local types = {}
  for typeName, _ in pairs(EGG_TYPES) do
    table.insert(types, typeName)
  end
  return types
end

-- Validate that all probabilities for an egg sum to 100%
function EggConfig.validateProbabilities(eggType: string): boolean
  local config = EGG_TYPES[eggType]
  if not config then
    return false
  end

  local totalProbability = 0
  for _, outcome in ipairs(config.hatchOutcomes) do
    totalProbability = totalProbability + outcome.probability
  end

  return totalProbability == 100
end

-- Validate all egg configurations
function EggConfig.validateAll(): { success: boolean, errors: { string } }
  local errors = {}

  for eggType, config in pairs(EGG_TYPES) do
    -- Check probability sum
    local totalProbability = 0
    for _, outcome in ipairs(config.hatchOutcomes) do
      totalProbability = totalProbability + outcome.probability

      -- Validate chicken type exists
      if not ChickenConfig.isValidType(outcome.chickenType) then
        table.insert(
          errors,
          string.format("%s: Invalid chicken type '%s'", eggType, outcome.chickenType)
        )
      end
    end

    if totalProbability ~= 100 then
      table.insert(
        errors,
        string.format("%s: Probabilities sum to %d%%, expected 100%%", eggType, totalProbability)
      )
    end

    -- Check has exactly 3 outcomes
    if #config.hatchOutcomes ~= 3 then
      table.insert(
        errors,
        string.format("%s: Has %d outcomes, expected exactly 3", eggType, #config.hatchOutcomes)
      )
    end

    -- Check prices are positive
    if config.purchasePrice <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid purchase price %d", eggType, config.purchasePrice)
      )
    end
    if config.sellPrice <= 0 then
      table.insert(errors, string.format("%s: Invalid sell price %d", eggType, config.sellPrice))
    end
  end

  return {
    success = #errors == 0,
    errors = errors,
  }
end

-- Select a random chicken from hatch outcomes based on weighted probability
function EggConfig.selectHatchOutcome(eggType: string): string?
  local config = EGG_TYPES[eggType]
  if not config then
    return nil
  end

  -- Use properly seeded Random instance for varied results
  local roll = rng:NextInteger(1, 100)
  local cumulativeProbability = 0

  for _, outcome in ipairs(config.hatchOutcomes) do
    cumulativeProbability = cumulativeProbability + outcome.probability
    if roll <= cumulativeProbability then
      return outcome.chickenType
    end
  end

  -- Fallback (should never reach here if probabilities sum to 100)
  return config.hatchOutcomes[1].chickenType
end

-- Get all rarities in order
function EggConfig.getRarities(): { Rarity }
  return { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
end

-- Get the starter egg type for new players
function EggConfig.getStarterEggType(): string
  return "CommonEgg"
end

return EggConfig
