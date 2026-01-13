--[[
	BalanceConfig Module
	Centralizes all tunable economy values for game balance.
	Provides progression analysis tools to validate early/mid/late game pacing.
]]

local BalanceConfig = {}

-- Import dependencies
local ChickenConfig = require(script.Parent.ChickenConfig)
local EggConfig = require(script.Parent.EggConfig)

-- ============================================================================
-- Core Economy Constants
-- ============================================================================

-- Base values that drive the economy
local ECONOMY = {
  -- Base money per second for Common chickens
  BASE_MONEY_PER_SECOND = 1,

  -- Rarity multiplier (10x per tier for exponential scaling)
  RARITY_SCALE_FACTOR = 10,

  -- Base egg purchase price (Common egg)
  BASE_EGG_PRICE = 100,

  -- Sell price ratio (50% of purchase price)
  SELL_PRICE_RATIO = 0.5,

  -- Chicken sell value per money-per-second
  CHICKEN_VALUE_PER_MPS = 60,

  -- Chicken sell multiplier (50% of calculated value)
  CHICKEN_SELL_MULTIPLIER = 0.5,
}

-- Progression targets (money amounts by game stage)
local PROGRESSION_TARGETS = {
  -- Early game (first 10-30 minutes)
  EARLY_START = 0,
  EARLY_END = 10000, -- 10K

  -- Mid game (30 minutes - 2 hours)
  MID_START = 10000,
  MID_END = 10000000, -- 10M

  -- Late game (2+ hours)
  LATE_START = 10000000,
  LATE_END = 1000000000000, -- 1T
}

-- Upgrade multipliers (cage tier -> money multiplier)
local UPGRADE_MULTIPLIERS = {
  [1] = 1.0, -- Base tier
  [2] = 1.5,
  [3] = 2.0,
  [4] = 3.0,
  [5] = 5.0,
  [6] = 8.0,
  [7] = 12.0,
  [8] = 18.0,
  [9] = 25.0,
  [10] = 35.0, -- Max tier
}

-- Upgrade costs (cage tier -> cost to upgrade to this tier)
local UPGRADE_COSTS = {
  [2] = 1000,
  [3] = 5000,
  [4] = 25000,
  [5] = 100000,
  [6] = 500000,
  [7] = 2500000,
  [8] = 12500000,
  [9] = 62500000,
  [10] = 312500000,
}

-- Prestige system
local PRESTIGE = {
  -- Bonus per prestige (10% = 0.10)
  BASE_BONUS = 0.10,

  -- Minimum money to prestige
  MINIMUM_MONEY = 1000000000, -- 1B

  -- Money retained after prestige (percentage)
  RETENTION_RATE = 0,
}

-- Offline earnings limits
local OFFLINE = {
  -- Maximum offline duration (hours)
  MAX_HOURS = 8,

  -- Offline earnings efficiency (percentage of normal rate)
  EFFICIENCY = 0.5,

  -- Maximum money earnable offline
  MAX_MONEY = 100000000, -- 100M
}

-- ============================================================================
-- Type Definitions
-- ============================================================================

export type ProgressionStage = "Early" | "Mid" | "Late" | "Endgame"

export type ProgressionAnalysis = {
  stage: ProgressionStage,
  moneyPerSecond: number,
  timeToNextStage: number?, -- seconds, nil if at endgame
  percentComplete: number,
  bottlenecks: { string },
}

export type BalanceReport = {
  earlyGameValid: boolean,
  midGameValid: boolean,
  lateGameValid: boolean,
  issues: { string },
  recommendations: { string },
}

-- ============================================================================
-- Accessors
-- ============================================================================

function BalanceConfig.getEconomy()
  return ECONOMY
end

function BalanceConfig.getProgressionTargets()
  return PROGRESSION_TARGETS
end

function BalanceConfig.getUpgradeMultiplier(tier: number): number
  if tier < 1 then
    return 1.0
  end
  if tier > 10 then
    tier = 10
  end
  return UPGRADE_MULTIPLIERS[tier] or 1.0
end

function BalanceConfig.getUpgradeCost(tier: number): number?
  return UPGRADE_COSTS[tier]
end

function BalanceConfig.getPrestigeConfig()
  return PRESTIGE
end

function BalanceConfig.getOfflineConfig()
  return OFFLINE
end

-- ============================================================================
-- Progression Analysis
-- ============================================================================

-- Get the current progression stage based on money
function BalanceConfig.getProgressionStage(money: number): ProgressionStage
  if money >= PROGRESSION_TARGETS.LATE_END then
    return "Endgame"
  elseif money >= PROGRESSION_TARGETS.LATE_START then
    return "Late"
  elseif money >= PROGRESSION_TARGETS.MID_START then
    return "Mid"
  else
    return "Early"
  end
end

-- Calculate money per second for a set of chicken types
function BalanceConfig.calculateMoneyPerSecond(
  chickenTypes: { string },
  upgradeTier: number?
): number
  local tier = upgradeTier or 1
  local multiplier = BalanceConfig.getUpgradeMultiplier(tier)
  local total = 0

  for _, chickenType in ipairs(chickenTypes) do
    local config = ChickenConfig.get(chickenType)
    if config then
      total = total + config.moneyPerSecond
    end
  end

  return total * multiplier
end

-- Estimate time to reach a money target
function BalanceConfig.estimateTimeToTarget(
  currentMoney: number,
  targetMoney: number,
  moneyPerSecond: number
): number?
  if moneyPerSecond <= 0 then
    return nil
  end
  if currentMoney >= targetMoney then
    return 0
  end
  return (targetMoney - currentMoney) / moneyPerSecond
end

-- Analyze progression for a player state
function BalanceConfig.analyzeProgression(
  money: number,
  chickenTypes: { string },
  upgradeTier: number?
): ProgressionAnalysis
  local stage = BalanceConfig.getProgressionStage(money)
  local mps = BalanceConfig.calculateMoneyPerSecond(chickenTypes, upgradeTier)
  local bottlenecks: { string } = {}

  -- Calculate percent complete within current stage
  local stageStart, stageEnd
  if stage == "Early" then
    stageStart = PROGRESSION_TARGETS.EARLY_START
    stageEnd = PROGRESSION_TARGETS.EARLY_END
  elseif stage == "Mid" then
    stageStart = PROGRESSION_TARGETS.MID_START
    stageEnd = PROGRESSION_TARGETS.MID_END
  elseif stage == "Late" then
    stageStart = PROGRESSION_TARGETS.LATE_START
    stageEnd = PROGRESSION_TARGETS.LATE_END
  else
    stageStart = PROGRESSION_TARGETS.LATE_END
    stageEnd = PROGRESSION_TARGETS.LATE_END * 10
  end

  local range = stageEnd - stageStart
  local progress = money - stageStart
  local percentComplete = range > 0 and math.min(100, (progress / range) * 100) or 100

  -- Calculate time to next stage
  local timeToNext: number? = nil
  if stage ~= "Endgame" then
    timeToNext = BalanceConfig.estimateTimeToTarget(money, stageEnd, mps)
  end

  -- Detect bottlenecks
  if mps == 0 then
    table.insert(bottlenecks, "No income - need to place chickens")
  elseif mps < 10 and stage == "Early" then
    table.insert(bottlenecks, "Low income - consider hatching more eggs")
  end

  if timeToNext and timeToNext > 3600 * 24 then -- More than a day
    table.insert(bottlenecks, "Progression too slow - need better chickens or upgrades")
  end

  return {
    stage = stage,
    moneyPerSecond = mps,
    timeToNextStage = timeToNext,
    percentComplete = percentComplete,
    bottlenecks = bottlenecks,
  }
end

-- ============================================================================
-- Balance Validation
-- ============================================================================

-- Validate that economy values create good progression
function BalanceConfig.validateBalance(): BalanceReport
  local issues: { string } = {}
  local recommendations: { string } = {}

  -- Test early game (3 Common chickens)
  local earlyChickens = { "BasicChick", "BasicChick", "BasicChick" }
  local earlyMPS = BalanceConfig.calculateMoneyPerSecond(earlyChickens, 1)
  local earlyTimeToMid =
    BalanceConfig.estimateTimeToTarget(0, PROGRESSION_TARGETS.MID_START, earlyMPS)
  local earlyGameValid = earlyTimeToMid ~= nil and earlyTimeToMid < 3600 -- Should reach mid in < 1 hour

  if not earlyGameValid then
    table.insert(
      issues,
      "Early game too slow: " .. tostring(earlyTimeToMid) .. "s to reach mid game"
    )
    table.insert(recommendations, "Increase Common chicken money rates or lower mid game threshold")
  end

  -- Test mid game (6 Rare chickens)
  local midChickens = {
    "RainbowChicken",
    "RainbowChicken",
    "CrystalHen",
    "CrystalHen",
    "FlameRooster",
    "FlameRooster",
  }
  local midMPS = BalanceConfig.calculateMoneyPerSecond(midChickens, 3) -- Tier 3 upgrade
  local midTimeToLate = BalanceConfig.estimateTimeToTarget(
    PROGRESSION_TARGETS.MID_START,
    PROGRESSION_TARGETS.LATE_START,
    midMPS
  )
  local midGameValid = midTimeToLate ~= nil and midTimeToLate < 3600 * 2 -- Should reach late in < 2 hours

  if not midGameValid then
    table.insert(issues, "Mid game too slow: " .. tostring(midTimeToLate) .. "s to reach late game")
    table.insert(recommendations, "Increase Rare chicken rates or lower late game threshold")
  end

  -- Test late game (12 Mythic chickens)
  local lateChickens = {}
  for _ = 1, 12 do
    table.insert(lateChickens, "OmegaRooster")
  end
  local lateMPS = BalanceConfig.calculateMoneyPerSecond(lateChickens, 10) -- Max tier
  local lateTimeToEnd = BalanceConfig.estimateTimeToTarget(
    PROGRESSION_TARGETS.LATE_START,
    PROGRESSION_TARGETS.LATE_END,
    lateMPS
  )
  local lateGameValid = lateTimeToEnd ~= nil and lateTimeToEnd < 3600 * 8 -- Should reach endgame in < 8 hours

  if not lateGameValid then
    table.insert(issues, "Late game too slow: " .. tostring(lateTimeToEnd) .. "s to reach endgame")
    table.insert(recommendations, "Increase Mythic chicken rates or adjust late game targets")
  end

  -- Validate rarity scaling
  local rarities = ChickenConfig.getRarities()
  local prevMult = 0
  for _, rarity in ipairs(rarities) do
    local mult = ChickenConfig.getRarityMultiplier(rarity)
    if mult <= prevMult then
      table.insert(issues, "Rarity " .. rarity .. " multiplier not increasing")
    end
    prevMult = mult
  end

  -- Validate egg prices scale with rarity
  local prevPrice = 0
  for _, rarity in ipairs(rarities) do
    local eggs = EggConfig.getByRarity(rarity)
    if #eggs > 0 then
      local price = eggs[1].purchasePrice
      if price <= prevPrice then
        table.insert(issues, "Egg price for " .. rarity .. " not increasing")
      end
      prevPrice = price
    end
  end

  -- Validate upgrade costs are achievable
  for tier = 2, 10 do
    local cost = UPGRADE_COSTS[tier]
    if cost then
      -- Check that previous tier income can achieve this cost in reasonable time
      local prevMultiplier = UPGRADE_MULTIPLIERS[tier - 1] or 1
      -- Assume player has 6 chickens of appropriate tier
      local baseIncome = ECONOMY.BASE_MONEY_PER_SECOND
        * (ECONOMY.RARITY_SCALE_FACTOR ^ math.floor((tier - 1) / 2))
        * 6
      local income = baseIncome * prevMultiplier
      local timeToAfford = cost / income
      if timeToAfford > 3600 then -- More than an hour
        table.insert(
          recommendations,
          string.format("Tier %d upgrade may take too long (%.0f min)", tier, timeToAfford / 60)
        )
      end
    end
  end

  return {
    earlyGameValid = earlyGameValid,
    midGameValid = midGameValid,
    lateGameValid = lateGameValid,
    issues = issues,
    recommendations = recommendations,
  }
end

-- ============================================================================
-- Simulation Tools
-- ============================================================================

-- Simulate progression over time
function BalanceConfig.simulateProgression(
  startMoney: number,
  chickenTypes: { string },
  upgradeTier: number,
  durationSeconds: number
): { money: number, stage: ProgressionStage }
  local mps = BalanceConfig.calculateMoneyPerSecond(chickenTypes, upgradeTier)
  local finalMoney = startMoney + (mps * durationSeconds)
  return {
    money = finalMoney,
    stage = BalanceConfig.getProgressionStage(finalMoney),
  }
end

-- Calculate expected earnings over a play session
function BalanceConfig.calculateSessionEarnings(
  chickenTypes: { string },
  upgradeTier: number,
  sessionMinutes: number
): number
  local mps = BalanceConfig.calculateMoneyPerSecond(chickenTypes, upgradeTier)
  return mps * sessionMinutes * 60
end

-- Get recommended next actions for progression
function BalanceConfig.getProgressionRecommendations(
  money: number,
  chickenTypes: { string },
  currentUpgradeTier: number
): { string }
  local recommendations: { string } = {}
  local analysis = BalanceConfig.analyzeProgression(money, chickenTypes, currentUpgradeTier)

  -- Check if upgrade is affordable and beneficial
  local nextTier = currentUpgradeTier + 1
  local upgradeCost = UPGRADE_COSTS[nextTier]
  if upgradeCost and money >= upgradeCost then
    table.insert(recommendations, "Upgrade cage to tier " .. nextTier)
  end

  -- Check if better eggs are affordable
  local rarities = EggConfig.getRarities()
  for i = #rarities, 1, -1 do
    local rarity = rarities[i]
    local eggs = EggConfig.getByRarity(rarity)
    if #eggs > 0 then
      local eggPrice = eggs[1].purchasePrice
      if money >= eggPrice * 3 then -- Can afford 3 eggs
        table.insert(recommendations, "Buy " .. rarity .. " eggs")
        break
      end
    end
  end

  -- Add bottleneck fixes
  for _, bottleneck in ipairs(analysis.bottlenecks) do
    table.insert(recommendations, "Fix: " .. bottleneck)
  end

  return recommendations
end

-- ============================================================================
-- Summary and Debug
-- ============================================================================

function BalanceConfig.getSummary(): string
  local lines = {
    "=== Balance Config Summary ===",
    "",
    "Economy:",
    string.format("  Base MPS: %d", ECONOMY.BASE_MONEY_PER_SECOND),
    string.format("  Rarity Scale: %dx per tier", ECONOMY.RARITY_SCALE_FACTOR),
    string.format("  Base Egg Price: $%d", ECONOMY.BASE_EGG_PRICE),
    "",
    "Progression Targets:",
    string.format("  Early: $0 - $%s", tostring(PROGRESSION_TARGETS.EARLY_END)),
    string.format(
      "  Mid: $%s - $%s",
      tostring(PROGRESSION_TARGETS.MID_START),
      tostring(PROGRESSION_TARGETS.MID_END)
    ),
    string.format(
      "  Late: $%s - $%s",
      tostring(PROGRESSION_TARGETS.LATE_START),
      tostring(PROGRESSION_TARGETS.LATE_END)
    ),
    "",
    "Upgrade Tiers: 1-10",
    string.format("  Max Multiplier: %.1fx", UPGRADE_MULTIPLIERS[10]),
  }
  return table.concat(lines, "\n")
end

return BalanceConfig
