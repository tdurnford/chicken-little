--[[
	MoneyScaling Module
	Handles exponential money scaling, number formatting for large values (K, M, B, T, Qa, Qi),
	and multiplier calculations for upgrades and prestige.
]]

local MoneyScaling = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local ChickenConfig = require(script.Parent.ChickenConfig)

-- Type definitions
export type FormattedMoney = {
  value: number,
  suffix: string,
  formatted: string,
  raw: number,
}

export type MultiplierBreakdown = {
  base: number,
  upgradeMultiplier: number,
  prestigeMultiplier: number,
  totalMultiplier: number,
  final: number,
}

-- Number formatting suffixes and thresholds
-- Supports up to Qi (quintillion = 10^18)
local SUFFIXES = {
  { threshold = 1e18, suffix = "Qi" }, -- Quintillion
  { threshold = 1e15, suffix = "Qa" }, -- Quadrillion
  { threshold = 1e12, suffix = "T" }, -- Trillion
  { threshold = 1e9, suffix = "B" }, -- Billion
  { threshold = 1e6, suffix = "M" }, -- Million
  { threshold = 1e3, suffix = "K" }, -- Thousand
}

-- Upgrade multiplier tiers (cage tier -> money multiplier)
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

-- Prestige multiplier (number of prestiges -> multiplier)
-- Each prestige gives 10% additional bonus, compounding
local PRESTIGE_BASE_BONUS = 0.10

-- Format a number with appropriate suffix (K, M, B, T, Qa, Qi)
function MoneyScaling.format(amount: number, decimalPlaces: number?): FormattedMoney
  local decimals = decimalPlaces or 2
  local raw = amount

  -- Handle negative numbers
  local sign = amount < 0 and "-" or ""
  amount = math.abs(amount)

  -- Find appropriate suffix
  for _, data in ipairs(SUFFIXES) do
    if amount >= data.threshold then
      local value = amount / data.threshold
      local formatted = sign .. string.format("%." .. decimals .. "f", value) .. data.suffix
      return {
        value = value,
        suffix = data.suffix,
        formatted = formatted,
        raw = raw,
      }
    end
  end

  -- No suffix needed for small numbers
  local formatted
  if amount == math.floor(amount) then
    formatted = sign .. tostring(math.floor(amount))
  else
    formatted = sign .. string.format("%." .. decimals .. "f", amount)
  end

  return {
    value = amount,
    suffix = "",
    formatted = formatted,
    raw = raw,
  }
end

-- Format with currency symbol prefix
function MoneyScaling.formatCurrency(amount: number, decimalPlaces: number?): string
  local result = MoneyScaling.format(amount, decimalPlaces)
  return "$" .. result.formatted
end

-- Helper to strip trailing zeros from a formatted number string
local function stripTrailingZeros(str: string): string
  -- Match number portion and suffix (if any)
  local numPart, suffix = str:match("^([%d%.%-]+)(.*)$")
  if not numPart then
    return str
  end
  -- Only strip if there's a decimal point
  if numPart:find("%.") then
    -- Remove trailing zeros after decimal
    numPart = numPart:gsub("%.?0+$", "")
  end
  return numPart .. suffix
end

-- Format currency cleanly, removing unnecessary decimal places
-- Use this for store prices where "$100" is preferred over "$100.00"
function MoneyScaling.formatCleanCurrency(amount: number): string
  local sign = amount < 0 and "-" or ""
  amount = math.abs(amount)

  -- Find appropriate suffix
  for _, data in ipairs(SUFFIXES) do
    if amount >= data.threshold then
      local value = amount / data.threshold
      -- Format with 2 decimal places, then strip trailing zeros
      local formatted = string.format("%.2f", value)
      formatted = stripTrailingZeros(formatted)
      return "$" .. sign .. formatted .. data.suffix
    end
  end

  -- No suffix needed for small numbers
  if amount == math.floor(amount) then
    return "$" .. sign .. tostring(math.floor(amount))
  else
    -- Format with 2 decimal places and strip trailing zeros
    local formatted = string.format("%.2f", amount)
    formatted = stripTrailingZeros(formatted)
    return "$" .. sign .. formatted
  end
end

-- Compact format for UI (1 decimal place, always abbreviated if possible)
function MoneyScaling.formatCompact(amount: number): string
  return MoneyScaling.format(amount, 1).formatted
end

-- Get the upgrade multiplier for a given cage tier
function MoneyScaling.getUpgradeMultiplier(cageTier: number): number
  if cageTier < 1 then
    return 1.0
  end
  if cageTier > 10 then
    cageTier = 10 -- Cap at max tier
  end
  return UPGRADE_MULTIPLIERS[cageTier] or 1.0
end

-- Get the prestige multiplier for a given number of prestiges
function MoneyScaling.getPrestigeMultiplier(prestigeCount: number): number
  if prestigeCount < 0 then
    return 1.0
  end
  -- Each prestige gives 10% bonus, compounding: (1 + 0.10)^prestigeCount
  return math.pow(1 + PRESTIGE_BASE_BONUS, prestigeCount)
end

-- Calculate total multiplier from all sources for a player
function MoneyScaling.calculateTotalMultiplier(
  playerData: PlayerData.PlayerDataSchema,
  prestigeCount: number?
): MultiplierBreakdown
  local prestige = prestigeCount or 0
  local cageTier = playerData.upgrades.cageTier or 1

  local upgradeMultiplier = MoneyScaling.getUpgradeMultiplier(cageTier)
  local prestigeMultiplier = MoneyScaling.getPrestigeMultiplier(prestige)
  local totalMultiplier = upgradeMultiplier * prestigeMultiplier

  return {
    base = 1.0,
    upgradeMultiplier = upgradeMultiplier,
    prestigeMultiplier = prestigeMultiplier,
    totalMultiplier = totalMultiplier,
    final = totalMultiplier,
  }
end

-- Apply multipliers to a base amount
function MoneyScaling.applyMultipliers(
  baseAmount: number,
  playerData: PlayerData.PlayerDataSchema,
  prestigeCount: number?
): number
  local breakdown = MoneyScaling.calculateTotalMultiplier(playerData, prestigeCount)
  return baseAmount * breakdown.totalMultiplier
end

-- Calculate money per second for all placed chickens with multipliers applied
function MoneyScaling.getScaledMoneyPerSecond(
  playerData: PlayerData.PlayerDataSchema,
  prestigeCount: number?
): number
  local baseMPS = 0

  for _, chicken in ipairs(playerData.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      baseMPS = baseMPS + config.moneyPerSecond
    end
  end

  return MoneyScaling.applyMultipliers(baseMPS, playerData, prestigeCount)
end

return MoneyScaling
