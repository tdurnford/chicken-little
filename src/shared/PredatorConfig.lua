--[[
	PredatorConfig Module
	Defines all predator types with their threat levels, spawn rates,
	damage values, and rewards when caught.
]]

local PredatorConfig = {}

-- Threat tiers ordered from lowest to highest
export type ThreatLevel = "Minor" | "Moderate" | "Dangerous" | "Severe" | "Deadly" | "Catastrophic"

-- Predator configuration structure
export type PredatorTypeConfig = {
  name: string,
  displayName: string,
  threatLevel: ThreatLevel,
  spawnWeight: number, -- Higher = more common (relative to other predators)
  attackIntervalSeconds: number, -- How often predator attempts to attack
  chickensPerAttack: number, -- Number of chickens killed/stolen per attack
  catchDifficulty: number, -- 1-10 scale, affects trap success and bat hits needed
  rewardMoney: number, -- Money earned when caught
  damage: number, -- Damage per second dealt to players in combat
  description: string,
}

-- Threat level multipliers for rewards (higher threat = higher reward)
local THREAT_REWARD_MULTIPLIERS: { [ThreatLevel]: number } = {
  Minor = 1,
  Moderate = 5,
  Dangerous = 25,
  Severe = 100,
  Deadly = 500,
  Catastrophic = 2500,
}

-- Base reward for catching a predator
local BASE_CATCH_REWARD = 50

-- Spawn weights by threat level (lower threat = more common)
local THREAT_SPAWN_WEIGHTS: { [ThreatLevel]: number } = {
  Minor = 100,
  Moderate = 60,
  Dangerous = 30,
  Severe = 15,
  Deadly = 5,
  Catastrophic = 1,
}

-- Attack intervals by threat level (stronger predators attack less frequently but harder)
local THREAT_ATTACK_INTERVALS: { [ThreatLevel]: number } = {
  Minor = 30, -- 30 seconds
  Moderate = 45, -- 45 seconds
  Dangerous = 60, -- 1 minute
  Severe = 90, -- 1.5 minutes
  Deadly = 120, -- 2 minutes
  Catastrophic = 180, -- 3 minutes
}

-- Damage per second dealt to players by threat level
local THREAT_DAMAGE: { [ThreatLevel]: number } = {
  Minor = 5,
  Moderate = 10,
  Dangerous = 15,
  Severe = 25,
  Deadly = 40,
  Catastrophic = 60,
}

-- Chickens killed per attack by threat level
local THREAT_CHICKENS_PER_ATTACK: { [ThreatLevel]: number } = {
  Minor = 1,
  Moderate = 1,
  Dangerous = 2,
  Severe = 2,
  Deadly = 3,
  Catastrophic = 4,
}

-- All predator types in the game
local PREDATOR_TYPES: { [string]: PredatorTypeConfig } = {
  -- Minor Threats
  Rat = {
    name = "Rat",
    displayName = "Rat",
    threatLevel = "Minor",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Minor,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Minor,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Minor,
    catchDifficulty = 1,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Minor,
    damage = THREAT_DAMAGE.Minor,
    description = "A sneaky rodent that steals eggs",
  },
  Crow = {
    name = "Crow",
    displayName = "Crow",
    threatLevel = "Minor",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Minor * 0.8,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Minor,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Minor,
    catchDifficulty = 2,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Minor * 1.2,
    damage = THREAT_DAMAGE.Minor,
    description = "A clever bird that pecks at chicks",
  },

  -- Moderate Threats
  Weasel = {
    name = "Weasel",
    displayName = "Weasel",
    threatLevel = "Moderate",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Moderate,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Moderate,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Moderate,
    catchDifficulty = 3,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Moderate,
    damage = THREAT_DAMAGE.Moderate,
    description = "A quick predator that targets small chickens",
  },
  Raccoon = {
    name = "Raccoon",
    displayName = "Raccoon",
    threatLevel = "Moderate",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Moderate * 0.8,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Moderate,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Moderate,
    catchDifficulty = 4,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Moderate * 1.3,
    damage = THREAT_DAMAGE.Moderate,
    description = "A crafty scavenger that raids coops at night",
  },

  -- Dangerous Threats
  Fox = {
    name = "Fox",
    displayName = "Fox",
    threatLevel = "Dangerous",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Dangerous,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Dangerous,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Dangerous,
    catchDifficulty = 5,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Dangerous,
    damage = THREAT_DAMAGE.Dangerous,
    description = "A cunning hunter that preys on chickens",
  },
  Snake = {
    name = "Snake",
    displayName = "Snake",
    threatLevel = "Dangerous",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Dangerous * 0.7,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Dangerous,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Dangerous,
    catchDifficulty = 6,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Dangerous * 1.4,
    damage = THREAT_DAMAGE.Dangerous,
    description = "A silent predator that swallows eggs whole",
  },

  -- Severe Threats
  Coyote = {
    name = "Coyote",
    displayName = "Coyote",
    threatLevel = "Severe",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Severe,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Severe,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Severe,
    catchDifficulty = 7,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Severe,
    damage = THREAT_DAMAGE.Severe,
    description = "A fierce pack hunter targeting your flock",
  },
  Hawk = {
    name = "Hawk",
    displayName = "Hawk",
    threatLevel = "Severe",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Severe * 0.8,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Severe,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Severe,
    catchDifficulty = 8,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Severe * 1.3,
    damage = THREAT_DAMAGE.Severe,
    description = "A swift aerial predator that swoops from above",
  },

  -- Deadly Threats
  Wolf = {
    name = "Wolf",
    displayName = "Wolf",
    threatLevel = "Deadly",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Deadly,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Deadly,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Deadly,
    catchDifficulty = 9,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Deadly,
    damage = THREAT_DAMAGE.Deadly,
    description = "A powerful apex predator that devastates coops",
  },
  Bobcat = {
    name = "Bobcat",
    displayName = "Bobcat",
    threatLevel = "Deadly",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Deadly * 0.6,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Deadly,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Deadly,
    catchDifficulty = 9,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Deadly * 1.2,
    damage = THREAT_DAMAGE.Deadly,
    description = "A stealthy feline that strikes without warning",
  },

  -- Catastrophic Threats
  Bear = {
    name = "Bear",
    displayName = "Bear",
    threatLevel = "Catastrophic",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Catastrophic,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Catastrophic,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Catastrophic,
    catchDifficulty = 10,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Catastrophic,
    damage = THREAT_DAMAGE.Catastrophic,
    description = "A massive beast that destroys entire coops",
  },
  Eagle = {
    name = "Eagle",
    displayName = "Golden Eagle",
    threatLevel = "Catastrophic",
    spawnWeight = THREAT_SPAWN_WEIGHTS.Catastrophic * 0.5,
    attackIntervalSeconds = THREAT_ATTACK_INTERVALS.Catastrophic,
    chickensPerAttack = THREAT_CHICKENS_PER_ATTACK.Catastrophic,
    catchDifficulty = 10,
    rewardMoney = BASE_CATCH_REWARD * THREAT_REWARD_MULTIPLIERS.Catastrophic * 1.5,
    damage = THREAT_DAMAGE.Catastrophic,
    description = "A legendary aerial hunter that terrorizes farms",
  },
}

-- Get configuration for a specific predator type
function PredatorConfig.get(predatorType: string): PredatorTypeConfig?
  return PREDATOR_TYPES[predatorType]
end

-- Get all predator types
function PredatorConfig.getAll(): { [string]: PredatorTypeConfig }
  return PREDATOR_TYPES
end

-- Get all predator types of a specific threat level
function PredatorConfig.getByThreatLevel(threatLevel: ThreatLevel): { PredatorTypeConfig }
  local result = {}
  for _, config in pairs(PREDATOR_TYPES) do
    if config.threatLevel == threatLevel then
      table.insert(result, config)
    end
  end
  return result
end

-- Get the reward multiplier for a threat level
function PredatorConfig.getThreatRewardMultiplier(threatLevel: ThreatLevel): number
  return THREAT_REWARD_MULTIPLIERS[threatLevel] or 1
end

-- Get the spawn weight for a threat level
function PredatorConfig.getThreatSpawnWeight(threatLevel: ThreatLevel): number
  return THREAT_SPAWN_WEIGHTS[threatLevel] or 1
end

-- Get the attack interval for a threat level
function PredatorConfig.getThreatAttackInterval(threatLevel: ThreatLevel): number
  return THREAT_ATTACK_INTERVALS[threatLevel] or 60
end

-- Get the damage per second for a threat level
function PredatorConfig.getThreatDamage(threatLevel: ThreatLevel): number
  return THREAT_DAMAGE[threatLevel] or 5
end

-- Get the damage per second for a specific predator type
function PredatorConfig.getDamage(predatorType: string): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 5 -- Default to Minor damage
  end
  return config.damage
end

-- Validate that a predator type exists
function PredatorConfig.isValidType(predatorType: string): boolean
  return PREDATOR_TYPES[predatorType] ~= nil
end

-- Get all valid predator type names
function PredatorConfig.getAllTypes(): { string }
  local types = {}
  for typeName, _ in pairs(PREDATOR_TYPES) do
    table.insert(types, typeName)
  end
  return types
end

-- Get all threat levels in order
function PredatorConfig.getThreatLevels(): { ThreatLevel }
  return { "Minor", "Moderate", "Dangerous", "Severe", "Deadly", "Catastrophic" }
end

-- Calculate total spawn weight for weighted random selection
function PredatorConfig.getTotalSpawnWeight(): number
  local total = 0
  for _, config in pairs(PREDATOR_TYPES) do
    total = total + config.spawnWeight
  end
  return total
end

-- Select a random predator type based on spawn weights
function PredatorConfig.selectRandomPredator(): string
  local totalWeight = PredatorConfig.getTotalSpawnWeight()
  local roll = math.random() * totalWeight
  local cumulativeWeight = 0

  for predatorType, config in pairs(PREDATOR_TYPES) do
    cumulativeWeight = cumulativeWeight + config.spawnWeight
    if roll <= cumulativeWeight then
      return predatorType
    end
  end

  -- Fallback (should never reach here)
  return "Rat"
end

-- Validate all predator configurations
function PredatorConfig.validateAll(): { success: boolean, errors: { string } }
  local errors = {}

  for predatorType, config in pairs(PREDATOR_TYPES) do
    -- Check catch difficulty is in valid range
    if config.catchDifficulty < 1 or config.catchDifficulty > 10 then
      table.insert(
        errors,
        string.format(
          "%s: Catch difficulty %d is out of range (1-10)",
          predatorType,
          config.catchDifficulty
        )
      )
    end

    -- Check spawn weight is positive
    if config.spawnWeight <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid spawn weight %f", predatorType, config.spawnWeight)
      )
    end

    -- Check reward is positive
    if config.rewardMoney <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid reward money %f", predatorType, config.rewardMoney)
      )
    end

    -- Check attack interval is positive
    if config.attackIntervalSeconds <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid attack interval %d", predatorType, config.attackIntervalSeconds)
      )
    end

    -- Check chickens per attack is positive
    if config.chickensPerAttack <= 0 then
      table.insert(
        errors,
        string.format("%s: Invalid chickens per attack %d", predatorType, config.chickensPerAttack)
      )
    end

    -- Check damage is positive
    if config.damage <= 0 then
      table.insert(errors, string.format("%s: Invalid damage %d", predatorType, config.damage))
    end

    -- Check threat level is valid
    local validThreatLevel = false
    for _, level in ipairs(PredatorConfig.getThreatLevels()) do
      if config.threatLevel == level then
        validThreatLevel = true
        break
      end
    end
    if not validThreatLevel then
      table.insert(
        errors,
        string.format("%s: Invalid threat level '%s'", predatorType, config.threatLevel)
      )
    end
  end

  return {
    success = #errors == 0,
    errors = errors,
  }
end

-- Get the number of bat hits required to defeat a predator
function PredatorConfig.getBatHitsRequired(predatorType: string): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 1
  end
  -- Bat hits scale with catch difficulty: 1-3 for minor, up to 8-10 for catastrophic
  return math.ceil(config.catchDifficulty * 0.8)
end

-- Get the trap effectiveness against a predator (percentage chance to catch)
function PredatorConfig.getTrapEffectiveness(predatorType: string, trapTier: number): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 0
  end
  -- Base trap effectiveness starts at 100% for difficulty 1, decreases for harder predators
  -- Trap tier increases effectiveness: each tier adds 10% base effectiveness
  local baseEffectiveness = 100 - (config.catchDifficulty - 1) * 10
  local tierBonus = (trapTier - 1) * 10
  return math.clamp(baseEffectiveness + tierBonus, 10, 100)
end

-- Helper function to clamp a value between min and max
local function mathClamp(value: number, min: number, max: number): number
  return math.max(min, math.min(max, value))
end

-- Override the internal clamp since Luau may not have math.clamp
function PredatorConfig.getTrapEffectiveness(predatorType: string, trapTier: number): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 0
  end
  local baseEffectiveness = 100 - (config.catchDifficulty - 1) * 10
  local tierBonus = (trapTier - 1) * 10
  return mathClamp(baseEffectiveness + tierBonus, 10, 100)
end

-- Calculate expected damage from a predator attack (number of chickens at risk)
function PredatorConfig.calculateAttackDamage(predatorType: string): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 0
  end
  return config.chickensPerAttack
end

-- Get spawn probability for a specific predator (as percentage)
function PredatorConfig.getSpawnProbability(predatorType: string): number
  local config = PREDATOR_TYPES[predatorType]
  if not config then
    return 0
  end
  local totalWeight = PredatorConfig.getTotalSpawnWeight()
  return (config.spawnWeight / totalWeight) * 100
end

return PredatorConfig
