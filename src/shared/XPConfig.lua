--[[
	XPConfig Module
	Defines XP rewards for various player actions in the game.
	XP contributes to the player's level progression.
]]

local XPConfig = {}

-- Import dependencies
local ChickenConfig = require(script.Parent.ChickenConfig)
local PredatorConfig = require(script.Parent.PredatorConfig)

-- Type definitions
export type XPRewardType =
  "predator_killed"
  | "chicken_hatched"
  | "random_chicken_caught"
  | "day_night_cycle_survived"
  | "egg_collected"
  | "trap_caught_predator"

export type XPReward = {
  baseAmount: number,
  description: string,
}

-- Base XP rewards for each action
local BASE_REWARDS: { [XPRewardType]: XPReward } = {
  predator_killed = {
    baseAmount = 25,
    description = "Defeat a predator with your weapon",
  },
  chicken_hatched = {
    baseAmount = 10,
    description = "Hatch a chicken from an egg",
  },
  random_chicken_caught = {
    baseAmount = 50,
    description = "Catch a random chicken spawn",
  },
  day_night_cycle_survived = {
    baseAmount = 15,
    description = "Survive a complete night cycle",
  },
  egg_collected = {
    baseAmount = 5,
    description = "Collect an egg laid by a chicken",
  },
  trap_caught_predator = {
    baseAmount = 35,
    description = "Catch a predator in a trap",
  },
}

-- Rarity multipliers for chicken-related XP
local RARITY_XP_MULTIPLIERS: { [string]: number } = {
  Common = 1,
  Uncommon = 2,
  Rare = 4,
  Epic = 8,
  Legendary = 16,
  Mythic = 32,
}

-- Threat level multipliers for predator-related XP
local THREAT_XP_MULTIPLIERS: { [string]: number } = {
  Minor = 1,
  Moderate = 2,
  Dangerous = 4,
  Severe = 8,
  Deadly = 16,
  Catastrophic = 32,
}

-- Get base XP reward for an action
function XPConfig.getBaseReward(rewardType: XPRewardType): number
  local reward = BASE_REWARDS[rewardType]
  if not reward then
    return 0
  end
  return reward.baseAmount
end

-- Get description for a reward type
function XPConfig.getDescription(rewardType: XPRewardType): string
  local reward = BASE_REWARDS[rewardType]
  if not reward then
    return "Unknown action"
  end
  return reward.description
end

-- Calculate XP for killing a predator (scales with threat level)
function XPConfig.calculatePredatorKillXP(predatorType: string): number
  local baseXP = BASE_REWARDS.predator_killed.baseAmount
  local config = PredatorConfig.get(predatorType)
  if not config then
    return baseXP
  end

  local multiplier = THREAT_XP_MULTIPLIERS[config.threatLevel] or 1
  return math.floor(baseXP * multiplier)
end

-- Calculate XP for hatching a chicken (scales with rarity)
function XPConfig.calculateChickenHatchXP(chickenRarity: string): number
  local baseXP = BASE_REWARDS.chicken_hatched.baseAmount
  local multiplier = RARITY_XP_MULTIPLIERS[chickenRarity] or 1
  return math.floor(baseXP * multiplier)
end

-- Calculate XP for catching a random chicken (scales with rarity)
function XPConfig.calculateRandomChickenXP(chickenRarity: string): number
  local baseXP = BASE_REWARDS.random_chicken_caught.baseAmount
  local multiplier = RARITY_XP_MULTIPLIERS[chickenRarity] or 1
  return math.floor(baseXP * multiplier)
end

-- Calculate XP for collecting an egg (scales with rarity)
function XPConfig.calculateEggCollectedXP(eggRarity: string): number
  local baseXP = BASE_REWARDS.egg_collected.baseAmount
  local multiplier = RARITY_XP_MULTIPLIERS[eggRarity] or 1
  return math.floor(baseXP * multiplier)
end

-- Calculate XP for trap catching a predator (scales with threat level)
function XPConfig.calculateTrapCatchXP(predatorType: string): number
  local baseXP = BASE_REWARDS.trap_caught_predator.baseAmount
  local config = PredatorConfig.get(predatorType)
  if not config then
    return baseXP
  end

  local multiplier = THREAT_XP_MULTIPLIERS[config.threatLevel] or 1
  return math.floor(baseXP * multiplier)
end

-- Calculate XP for surviving a day/night cycle (flat amount)
function XPConfig.calculateDayNightCycleXP(): number
  return BASE_REWARDS.day_night_cycle_survived.baseAmount
end

-- Get all reward types
function XPConfig.getAllRewardTypes(): { XPRewardType }
  return {
    "predator_killed",
    "chicken_hatched",
    "random_chicken_caught",
    "day_night_cycle_survived",
    "egg_collected",
    "trap_caught_predator",
  }
end

-- Get rarity multiplier
function XPConfig.getRarityMultiplier(rarity: string): number
  return RARITY_XP_MULTIPLIERS[rarity] or 1
end

-- Get threat multiplier
function XPConfig.getThreatMultiplier(threatLevel: string): number
  return THREAT_XP_MULTIPLIERS[threatLevel] or 1
end

-- Get summary of all XP rewards
function XPConfig.getSummary(): string
  local lines = {
    "=== XP Reward Summary ===",
    "",
  }

  for rewardType, reward in pairs(BASE_REWARDS) do
    table.insert(lines, string.format("%s: %d XP base", rewardType, reward.baseAmount))
    table.insert(lines, "  " .. reward.description)
  end

  table.insert(lines, "")
  table.insert(lines, "Rarity Multipliers:")
  for rarity, mult in pairs(RARITY_XP_MULTIPLIERS) do
    table.insert(lines, string.format("  %s: %dx", rarity, mult))
  end

  table.insert(lines, "")
  table.insert(lines, "Threat Multipliers:")
  for threat, mult in pairs(THREAT_XP_MULTIPLIERS) do
    table.insert(lines, string.format("  %s: %dx", threat, mult))
  end

  return table.concat(lines, "\n")
end

return XPConfig
