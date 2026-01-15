--[[
	TrapConfig Module
	Defines all trap types with their tiers, effectiveness against predators,
	purchase prices, and placement limits.
]]

local PredatorConfig = require(script.Parent.PredatorConfig)

local TrapConfig = {}

-- Trap tiers ordered from lowest to highest
export type TrapTier = "Basic" | "Improved" | "Advanced" | "Expert" | "Master" | "Ultimate"

-- Trap configuration structure
export type TrapTypeConfig = {
  name: string,
  displayName: string,
  icon: string, -- Emoji icon for display in store/UI
  tier: TrapTier,
  tierLevel: number, -- 1-6 numeric tier for calculations
  price: number,
  sellPrice: number,
  maxPlacement: number, -- Max traps of this type per coop
  cooldownSeconds: number, -- Time before trap can catch again
  durability: number, -- Number of catches before trap breaks (0 = infinite)
  effectivenessBonus: number, -- Added to base catch probability
  description: string,
}

-- Tier level mapping for calculations
local TIER_LEVELS: { [TrapTier]: number } = {
  Basic = 1,
  Improved = 2,
  Advanced = 3,
  Expert = 4,
  Master = 5,
  Ultimate = 6,
}

-- Price scaling by tier (exponential)
local TIER_PRICES: { [TrapTier]: number } = {
  Basic = 500,
  Improved = 2500,
  Advanced = 12500,
  Expert = 62500,
  Master = 312500,
  Ultimate = 1562500,
}

-- Sell price is 40% of purchase price
local SELL_MULTIPLIER = 0.4

-- Cooldown in seconds by tier (higher tier = shorter cooldown)
local TIER_COOLDOWNS: { [TrapTier]: number } = {
  Basic = 120, -- 2 minutes
  Improved = 100, -- 1:40
  Advanced = 80, -- 1:20
  Expert = 60, -- 1 minute
  Master = 45, -- 45 seconds
  Ultimate = 30, -- 30 seconds
}

-- Durability by tier (0 = infinite, higher tier = more durable)
local TIER_DURABILITY: { [TrapTier]: number } = {
  Basic = 5,
  Improved = 8,
  Advanced = 12,
  Expert = 20,
  Master = 50,
  Ultimate = 0, -- Infinite durability
}

-- Effectiveness bonus by tier (added to base catch chance)
local TIER_EFFECTIVENESS: { [TrapTier]: number } = {
  Basic = 0,
  Improved = 10,
  Advanced = 20,
  Expert = 35,
  Master = 50,
  Ultimate = 75,
}

-- Max placement per coop by tier
local TIER_MAX_PLACEMENT: { [TrapTier]: number } = {
  Basic = 4,
  Improved = 4,
  Advanced = 3,
  Expert = 2,
  Master = 2,
  Ultimate = 1,
}

-- All trap types in the game
local TRAP_TYPES: { [string]: TrapTypeConfig } = {
  -- Basic Tier
  WoodenSnare = {
    name = "WoodenSnare",
    displayName = "Wooden Snare",
    icon = "🪵",
    tier = "Basic",
    tierLevel = TIER_LEVELS.Basic,
    price = TIER_PRICES.Basic,
    sellPrice = math.floor(TIER_PRICES.Basic * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Basic,
    cooldownSeconds = TIER_COOLDOWNS.Basic,
    durability = TIER_DURABILITY.Basic,
    effectivenessBonus = TIER_EFFECTIVENESS.Basic,
    description = "A simple wooden trap for catching small predators",
  },
  RopeTrap = {
    name = "RopeTrap",
    displayName = "Rope Trap",
    icon = "🪢",
    tier = "Basic",
    tierLevel = TIER_LEVELS.Basic,
    price = math.floor(TIER_PRICES.Basic * 1.2),
    sellPrice = math.floor(TIER_PRICES.Basic * 1.2 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Basic,
    cooldownSeconds = TIER_COOLDOWNS.Basic,
    durability = TIER_DURABILITY.Basic + 2,
    effectivenessBonus = TIER_EFFECTIVENESS.Basic + 5,
    description = "A rope snare that tangles predators' legs",
  },

  -- Improved Tier
  MetalCage = {
    name = "MetalCage",
    displayName = "Metal Cage",
    icon = "🗑️",
    tier = "Improved",
    tierLevel = TIER_LEVELS.Improved,
    price = TIER_PRICES.Improved,
    sellPrice = math.floor(TIER_PRICES.Improved * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Improved,
    cooldownSeconds = TIER_COOLDOWNS.Improved,
    durability = TIER_DURABILITY.Improved,
    effectivenessBonus = TIER_EFFECTIVENESS.Improved,
    description = "A sturdy metal cage that snaps shut on predators",
  },
  SpringTrap = {
    name = "SpringTrap",
    displayName = "Spring Trap",
    icon = "🔩",
    tier = "Improved",
    tierLevel = TIER_LEVELS.Improved,
    price = math.floor(TIER_PRICES.Improved * 1.3),
    sellPrice = math.floor(TIER_PRICES.Improved * 1.3 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Improved,
    cooldownSeconds = math.floor(TIER_COOLDOWNS.Improved * 0.9),
    durability = TIER_DURABILITY.Improved,
    effectivenessBonus = TIER_EFFECTIVENESS.Improved + 5,
    description = "A spring-loaded trap with lightning-fast response",
  },

  -- Advanced Tier
  ElectricFence = {
    name = "ElectricFence",
    displayName = "Electric Fence",
    icon = "⚡",
    tier = "Advanced",
    tierLevel = TIER_LEVELS.Advanced,
    price = TIER_PRICES.Advanced,
    sellPrice = math.floor(TIER_PRICES.Advanced * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Advanced,
    cooldownSeconds = TIER_COOLDOWNS.Advanced,
    durability = TIER_DURABILITY.Advanced,
    effectivenessBonus = TIER_EFFECTIVENESS.Advanced,
    description = "An electrified barrier that stuns predators",
  },
  BearTrap = {
    name = "BearTrap",
    displayName = "Bear Trap",
    icon = "🐻",
    tier = "Advanced",
    tierLevel = TIER_LEVELS.Advanced,
    price = math.floor(TIER_PRICES.Advanced * 1.4),
    sellPrice = math.floor(TIER_PRICES.Advanced * 1.4 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Advanced,
    cooldownSeconds = TIER_COOLDOWNS.Advanced,
    durability = TIER_DURABILITY.Advanced + 5,
    effectivenessBonus = TIER_EFFECTIVENESS.Advanced + 10,
    description = "A powerful clamping trap for larger predators",
  },

  -- Expert Tier
  LaserGrid = {
    name = "LaserGrid",
    displayName = "Laser Grid",
    icon = "🔴",
    tier = "Expert",
    tierLevel = TIER_LEVELS.Expert,
    price = TIER_PRICES.Expert,
    sellPrice = math.floor(TIER_PRICES.Expert * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Expert,
    cooldownSeconds = TIER_COOLDOWNS.Expert,
    durability = TIER_DURABILITY.Expert,
    effectivenessBonus = TIER_EFFECTIVENESS.Expert,
    description = "A high-tech laser detection and containment system",
  },
  SonicEmitter = {
    name = "SonicEmitter",
    displayName = "Sonic Emitter",
    icon = "📢",
    tier = "Expert",
    tierLevel = TIER_LEVELS.Expert,
    price = math.floor(TIER_PRICES.Expert * 1.3),
    sellPrice = math.floor(TIER_PRICES.Expert * 1.3 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Expert,
    cooldownSeconds = math.floor(TIER_COOLDOWNS.Expert * 0.8),
    durability = TIER_DURABILITY.Expert,
    effectivenessBonus = TIER_EFFECTIVENESS.Expert + 10,
    description = "Emits disorienting sound waves to incapacitate predators",
  },

  -- Master Tier
  GravityWell = {
    name = "GravityWell",
    displayName = "Gravity Well",
    icon = "🌀",
    tier = "Master",
    tierLevel = TIER_LEVELS.Master,
    price = TIER_PRICES.Master,
    sellPrice = math.floor(TIER_PRICES.Master * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Master,
    cooldownSeconds = TIER_COOLDOWNS.Master,
    durability = TIER_DURABILITY.Master,
    effectivenessBonus = TIER_EFFECTIVENESS.Master,
    description = "Creates a localized gravity field that immobilizes predators",
  },
  CryoTrap = {
    name = "CryoTrap",
    displayName = "Cryo Trap",
    icon = "❄️",
    tier = "Master",
    tierLevel = TIER_LEVELS.Master,
    price = math.floor(TIER_PRICES.Master * 1.2),
    sellPrice = math.floor(TIER_PRICES.Master * 1.2 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Master,
    cooldownSeconds = math.floor(TIER_COOLDOWNS.Master * 0.9),
    durability = TIER_DURABILITY.Master,
    effectivenessBonus = TIER_EFFECTIVENESS.Master + 10,
    description = "Flash-freezes predators on contact",
  },

  -- Ultimate Tier
  QuantumContainment = {
    name = "QuantumContainment",
    displayName = "Quantum Containment",
    icon = "🔮",
    tier = "Ultimate",
    tierLevel = TIER_LEVELS.Ultimate,
    price = TIER_PRICES.Ultimate,
    sellPrice = math.floor(TIER_PRICES.Ultimate * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Ultimate,
    cooldownSeconds = TIER_COOLDOWNS.Ultimate,
    durability = TIER_DURABILITY.Ultimate,
    effectivenessBonus = TIER_EFFECTIVENESS.Ultimate,
    description = "The ultimate trap - phases predators into a pocket dimension",
  },
  VoidPrison = {
    name = "VoidPrison",
    displayName = "Void Prison",
    icon = "🕳️",
    tier = "Ultimate",
    tierLevel = TIER_LEVELS.Ultimate,
    price = math.floor(TIER_PRICES.Ultimate * 1.5),
    sellPrice = math.floor(TIER_PRICES.Ultimate * 1.5 * SELL_MULTIPLIER),
    maxPlacement = TIER_MAX_PLACEMENT.Ultimate,
    cooldownSeconds = math.floor(TIER_COOLDOWNS.Ultimate * 0.8),
    durability = TIER_DURABILITY.Ultimate,
    effectivenessBonus = TIER_EFFECTIVENESS.Ultimate + 15,
    description = "Traps predators in an inescapable void dimension",
  },
}

-- Get configuration for a specific trap type
function TrapConfig.get(trapType: string): TrapTypeConfig?
  return TRAP_TYPES[trapType]
end

-- Get all trap types
function TrapConfig.getAll(): { [string]: TrapTypeConfig }
  return TRAP_TYPES
end

-- Get all trap types of a specific tier
function TrapConfig.getByTier(tier: TrapTier): { TrapTypeConfig }
  local result = {}
  for _, config in pairs(TRAP_TYPES) do
    if config.tier == tier then
      table.insert(result, config)
    end
  end
  return result
end

-- Get the tier level (1-6) for a tier name
function TrapConfig.getTierLevel(tier: TrapTier): number
  return TIER_LEVELS[tier] or 1
end

-- Get base price for a tier
function TrapConfig.getTierPrice(tier: TrapTier): number
  return TIER_PRICES[tier] or 500
end

-- Validate that a trap type exists
function TrapConfig.isValidType(trapType: string): boolean
  return TRAP_TYPES[trapType] ~= nil
end

-- Get all valid trap type names
function TrapConfig.getAllTypes(): { string }
  local types = {}
  for typeName, _ in pairs(TRAP_TYPES) do
    table.insert(types, typeName)
  end
  return types
end

-- Get all tiers in order
function TrapConfig.getTiers(): { TrapTier }
  return { "Basic", "Improved", "Advanced", "Expert", "Master", "Ultimate" }
end

-- Helper function to clamp a value between min and max
local function clamp(value: number, min: number, max: number): number
  return math.max(min, math.min(max, value))
end

-- Calculate catch probability for a trap against a predator
function TrapConfig.calculateCatchProbability(trapType: string, predatorType: string): number
  local trapConfig = TRAP_TYPES[trapType]
  local predatorConfig = PredatorConfig.get(predatorType)

  if not trapConfig or not predatorConfig then
    return 0
  end

  -- Base probability starts at 100% and decreases with predator difficulty
  -- Each point of catch difficulty reduces base by 10%
  local baseProbability = 100 - (predatorConfig.catchDifficulty - 1) * 10

  -- Trap tier adds effectiveness
  -- Each tier level above 1 adds 15% to counter predator difficulty
  local tierBonus = (trapConfig.tierLevel - 1) * 15

  -- Add trap-specific effectiveness bonus
  local effectivenessBonus = trapConfig.effectivenessBonus

  -- Calculate final probability
  local finalProbability = baseProbability + tierBonus + effectivenessBonus

  return clamp(finalProbability, 5, 100)
end

-- Get effectiveness rating (0-5 stars) for trap against predator
function TrapConfig.getEffectivenessRating(trapType: string, predatorType: string): number
  local probability = TrapConfig.calculateCatchProbability(trapType, predatorType)

  if probability >= 90 then
    return 5
  elseif probability >= 70 then
    return 4
  elseif probability >= 50 then
    return 3
  elseif probability >= 30 then
    return 2
  elseif probability >= 15 then
    return 1
  else
    return 0
  end
end

-- Check if trap can effectively catch a predator (>= 50% chance)
function TrapConfig.canEffectivelyCatch(trapType: string, predatorType: string): boolean
  return TrapConfig.calculateCatchProbability(trapType, predatorType) >= 50
end

-- Get minimum trap tier needed to effectively catch a predator
function TrapConfig.getMinimumTierForPredator(predatorType: string): TrapTier?
  local predatorConfig = PredatorConfig.get(predatorType)
  if not predatorConfig then
    return nil
  end

  local tiers = TrapConfig.getTiers()

  for _, tier in ipairs(tiers) do
    local trapsInTier = TrapConfig.getByTier(tier)
    for _, trap in ipairs(trapsInTier) do
      if TrapConfig.canEffectivelyCatch(trap.name, predatorType) then
        return tier
      end
    end
  end

  return "Ultimate" -- Fallback to highest tier
end

-- Get all traps sorted by tier and price
function TrapConfig.getAllSorted(): { TrapTypeConfig }
  local result = {}
  for _, config in pairs(TRAP_TYPES) do
    table.insert(result, config)
  end

  table.sort(result, function(a, b)
    if a.tierLevel ~= b.tierLevel then
      return a.tierLevel < b.tierLevel
    end
    return a.price < b.price
  end)

  return result
end

-- Calculate total placement limit for a player (sum of all trap max placements they can afford)
function TrapConfig.getMaxTotalTraps(): number
  local total = 0
  for _, tier in ipairs(TrapConfig.getTiers()) do
    total = total + (TIER_MAX_PLACEMENT[tier] or 0)
  end
  return total
end

-- Get recommended traps for a player's budget
function TrapConfig.getAffordableTraps(money: number): { TrapTypeConfig }
  local result = {}
  for _, config in pairs(TRAP_TYPES) do
    if config.price <= money then
      table.insert(result, config)
    end
  end

  table.sort(result, function(a, b)
    return a.price < b.price
  end)

  return result
end

-- Validate all trap configurations
function TrapConfig.validateAll(): { success: boolean, errors: { string } }
  local errors = {}

  for trapType, config in pairs(TRAP_TYPES) do
    -- Check tier level is valid
    if config.tierLevel < 1 or config.tierLevel > 6 then
      table.insert(errors, string.format("%s: Invalid tier level %d", trapType, config.tierLevel))
    end

    -- Check price is positive
    if config.price <= 0 then
      table.insert(errors, string.format("%s: Invalid price %d", trapType, config.price))
    end

    -- Check sell price is less than purchase price
    if config.sellPrice >= config.price then
      table.insert(
        errors,
        string.format(
          "%s: Sell price %d >= purchase price %d",
          trapType,
          config.sellPrice,
          config.price
        )
      )
    end

    -- Check cooldown is positive
    if config.cooldownSeconds <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid cooldown %d", trapType, config.cooldownSeconds)
      )
    end

    -- Check durability is non-negative
    if config.durability < 0 then
      table.insert(errors, string.format("%s: Invalid durability %d", trapType, config.durability))
    end

    -- Check max placement is positive
    if config.maxPlacement <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid max placement %d", trapType, config.maxPlacement)
      )
    end

    -- Check effectiveness bonus is non-negative
    if config.effectivenessBonus < 0 then
      table.insert(
        errors,
        string.format("%s: Invalid effectiveness bonus %d", trapType, config.effectivenessBonus)
      )
    end

    -- Check tier is valid
    local validTier = false
    for _, tier in ipairs(TrapConfig.getTiers()) do
      if config.tier == tier then
        validTier = true
        break
      end
    end
    if not validTier then
      table.insert(errors, string.format("%s: Invalid tier '%s'", trapType, config.tier))
    end
  end

  return {
    success = #errors == 0,
    errors = errors,
  }
end

-- Get trap info formatted for store display
function TrapConfig.getStoreInfo(trapType: string): {
  name: string,
  displayName: string,
  tier: TrapTier,
  price: number,
  description: string,
  effectiveness: string,
}?
  local config = TRAP_TYPES[trapType]
  if not config then
    return nil
  end

  -- Calculate average effectiveness against predators
  local totalEffectiveness = 0
  local predatorCount = 0
  for _, predator in ipairs(PredatorConfig.getAllTypes()) do
    totalEffectiveness = totalEffectiveness
      + TrapConfig.calculateCatchProbability(trapType, predator)
    predatorCount = predatorCount + 1
  end

  local avgEffectiveness = predatorCount > 0 and math.floor(totalEffectiveness / predatorCount) or 0

  local effectivenessLabel
  if avgEffectiveness >= 80 then
    effectivenessLabel = "Excellent"
  elseif avgEffectiveness >= 60 then
    effectivenessLabel = "Good"
  elseif avgEffectiveness >= 40 then
    effectivenessLabel = "Fair"
  else
    effectivenessLabel = "Basic"
  end

  return {
    name = config.name,
    displayName = config.displayName,
    tier = config.tier,
    price = config.price,
    description = config.description,
    effectiveness = effectivenessLabel,
  }
end

return TrapConfig
