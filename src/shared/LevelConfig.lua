--[[
	LevelConfig Module
	Defines player level thresholds, XP requirements, and level-based
	difficulty scaling for predators and gameplay.
]]

local LevelConfig = {}

-- Type definitions
export type LevelData = {
  level: number,
  xpRequired: number, -- Total XP to reach this level
  maxSimultaneousPredators: number,
  predatorThreatMultiplier: number, -- 1.0 = normal, higher = more dangerous predators
  xpToNextLevel: number?, -- XP needed for next level (nil at max level)
}

-- Level progression constants
local MAX_LEVEL = 100
local BASE_XP_REQUIREMENT = 100 -- XP for level 2
local XP_SCALING_FACTOR = 1.15 -- Each level requires 15% more XP

-- Predator scaling constants
local BASE_MAX_PREDATORS = 1 -- Max predators at level 1
local PREDATORS_PER_5_LEVELS = 1 -- Add 1 max predator every 5 levels
local MAX_SIMULTANEOUS_PREDATORS = 8

-- Threat level scaling (controls which predator tiers can spawn)
local THREAT_UNLOCK_LEVELS = {
  Minor = 1, -- Available from start
  Moderate = 5, -- Unlocks at level 5
  Dangerous = 15, -- Unlocks at level 15
  Severe = 30, -- Unlocks at level 30
  Deadly = 50, -- Unlocks at level 50
  Catastrophic = 75, -- Unlocks at level 75
}

-- Pre-calculated level data cache
local levelDataCache: { [number]: LevelData } = {}

-- Calculate XP required for a specific level
function LevelConfig.getXPForLevel(level: number): number
  if level <= 1 then
    return 0
  end
  if level > MAX_LEVEL then
    level = MAX_LEVEL
  end

  -- XP formula: baseXP * (scalingFactor ^ (level - 2))
  -- Level 2 = 100, Level 3 = 115, Level 4 = 132, etc.
  local totalXP = 0
  for i = 2, level do
    totalXP = totalXP + math.floor(BASE_XP_REQUIREMENT * (XP_SCALING_FACTOR ^ (i - 2)))
  end
  return totalXP
end

-- Calculate level from total XP
function LevelConfig.getLevelFromXP(xp: number): number
  if xp < BASE_XP_REQUIREMENT then
    return 1
  end

  local level = 1
  local totalXPNeeded = 0

  while level < MAX_LEVEL do
    local xpForNextLevel = math.floor(BASE_XP_REQUIREMENT * (XP_SCALING_FACTOR ^ (level - 1)))
    if totalXPNeeded + xpForNextLevel > xp then
      break
    end
    totalXPNeeded = totalXPNeeded + xpForNextLevel
    level = level + 1
  end

  return level
end

-- Get XP progress within current level (0-1 range)
function LevelConfig.getLevelProgress(xp: number): number
  local level = LevelConfig.getLevelFromXP(xp)
  if level >= MAX_LEVEL then
    return 1
  end

  local currentLevelXP = LevelConfig.getXPForLevel(level)
  local nextLevelXP = LevelConfig.getXPForLevel(level + 1)
  local xpInLevel = xp - currentLevelXP
  local xpNeeded = nextLevelXP - currentLevelXP

  if xpNeeded <= 0 then
    return 1
  end

  return math.clamp(xpInLevel / xpNeeded, 0, 1)
end

-- Get XP needed to reach next level
function LevelConfig.getXPToNextLevel(xp: number): number?
  local level = LevelConfig.getLevelFromXP(xp)
  if level >= MAX_LEVEL then
    return nil -- Already at max level
  end

  local nextLevelXP = LevelConfig.getXPForLevel(level + 1)
  return nextLevelXP - xp
end

-- Get max simultaneous predators for a level
function LevelConfig.getMaxPredatorsForLevel(level: number): number
  local maxPredators = BASE_MAX_PREDATORS + math.floor((level - 1) / 5) * PREDATORS_PER_5_LEVELS
  return math.min(maxPredators, MAX_SIMULTANEOUS_PREDATORS)
end

-- Get predator threat multiplier for a level (affects spawn weights)
function LevelConfig.getThreatMultiplierForLevel(level: number): number
  -- Gradually increase threat from 1.0 to 2.0 across levels
  local progress = math.clamp((level - 1) / (MAX_LEVEL - 1), 0, 1)
  return 1.0 + progress
end

-- Get the highest threat level available at a player level
function LevelConfig.getMaxThreatLevel(level: number): string
  local maxThreat = "Minor"
  for threatLevel, requiredLevel in pairs(THREAT_UNLOCK_LEVELS) do
    if level >= requiredLevel then
      -- Only update if this threat is higher than current max
      if
        THREAT_UNLOCK_LEVELS[maxThreat] == nil
        or requiredLevel > THREAT_UNLOCK_LEVELS[maxThreat]
      then
        maxThreat = threatLevel
      end
    end
  end
  return maxThreat
end

-- Check if a threat level is unlocked for a player level
function LevelConfig.isThreatLevelUnlocked(level: number, threatLevel: string): boolean
  local requiredLevel = THREAT_UNLOCK_LEVELS[threatLevel]
  if requiredLevel == nil then
    return false
  end
  return level >= requiredLevel
end

-- Get complete level data for a specific level
function LevelConfig.getLevelData(level: number): LevelData
  if level < 1 then
    level = 1
  end
  if level > MAX_LEVEL then
    level = MAX_LEVEL
  end

  -- Check cache first
  if levelDataCache[level] then
    return levelDataCache[level]
  end

  local data: LevelData = {
    level = level,
    xpRequired = LevelConfig.getXPForLevel(level),
    maxSimultaneousPredators = LevelConfig.getMaxPredatorsForLevel(level),
    predatorThreatMultiplier = LevelConfig.getThreatMultiplierForLevel(level),
    xpToNextLevel = level < MAX_LEVEL
        and (LevelConfig.getXPForLevel(level + 1) - LevelConfig.getXPForLevel(level))
      or nil,
  }

  levelDataCache[level] = data
  return data
end

-- Get level data from XP value
function LevelConfig.getLevelDataFromXP(xp: number): LevelData
  local level = LevelConfig.getLevelFromXP(xp)
  return LevelConfig.getLevelData(level)
end

-- Get all threat unlock levels
function LevelConfig.getThreatUnlockLevels(): { [string]: number }
  -- Return a copy to prevent modification
  local copy = {}
  for k, v in pairs(THREAT_UNLOCK_LEVELS) do
    copy[k] = v
  end
  return copy
end

-- Get max level constant
function LevelConfig.getMaxLevel(): number
  return MAX_LEVEL
end

-- Get base XP requirement constant
function LevelConfig.getBaseXPRequirement(): number
  return BASE_XP_REQUIREMENT
end

-- Get XP scaling factor
function LevelConfig.getXPScalingFactor(): number
  return XP_SCALING_FACTOR
end

-- Validate level value
function LevelConfig.isValidLevel(level: number): boolean
  return type(level) == "number"
    and level >= 1
    and level <= MAX_LEVEL
    and level == math.floor(level)
end

-- Validate XP value
function LevelConfig.isValidXP(xp: number): boolean
  return type(xp) == "number" and xp >= 0 and xp == math.floor(xp)
end

-- Calculate XP award for reaching a new level (bonus XP)
function LevelConfig.getLevelUpBonusXP(newLevel: number): number
  -- Bonus XP increases with level milestones
  local bonus = 0
  if newLevel % 10 == 0 then
    bonus = 500 -- Major milestone every 10 levels
  elseif newLevel % 5 == 0 then
    bonus = 200 -- Medium milestone every 5 levels
  end
  return bonus
end

-- Get a summary of level progression for display
function LevelConfig.getSummary(): string
  local lines = {
    "=== Level Config Summary ===",
    "",
    "Level Range: 1 - " .. MAX_LEVEL,
    "Base XP: " .. BASE_XP_REQUIREMENT,
    "XP Scaling: " .. (XP_SCALING_FACTOR * 100) .. "% per level",
    "",
    "Predator Scaling:",
    "  Base Max Predators: " .. BASE_MAX_PREDATORS,
    "  Max Predators (cap): " .. MAX_SIMULTANEOUS_PREDATORS,
    "",
    "Threat Unlocks:",
  }

  for threatLevel, level in pairs(THREAT_UNLOCK_LEVELS) do
    table.insert(lines, "  " .. threatLevel .. ": Level " .. level)
  end

  return table.concat(lines, "\n")
end

-- Pre-populate cache for common levels (optimization)
local function initCache()
  for level = 1, 20 do
    LevelConfig.getLevelData(level)
  end
end
initCache()

return LevelConfig
