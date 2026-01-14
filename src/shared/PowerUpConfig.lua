--[[
	PowerUpConfig Module
	Defines power-ups that players can purchase with Robux to boost their luck
	when hatching eggs and improve egg quality from chickens.
]]

local PowerUpConfig = {}

-- Power-up type definitions
export type PowerUpType = "HatchLuck" | "EggQuality"

export type PowerUpConfig = {
  id: string,
  name: string,
  displayName: string,
  description: string,
  icon: string,
  durationSeconds: number,
  robuxPrice: number,
  boostMultiplier: number, -- How much to boost (1.5 = 50% better, 2.0 = 100% better)
}

export type ActivePowerUp = {
  powerUpId: string,
  activatedTime: number, -- os.time() when activated
  expiresAt: number, -- os.time() when it expires
}

-- Power-up configurations
local POWER_UPS: { [string]: PowerUpConfig } = {
  -- Hatch Luck Boost: Increases rare hatch chance by shifting probabilities
  HatchLuck15 = {
    id = "HatchLuck15",
    name = "HatchLuck15",
    displayName = "Luck Boost (15 min)",
    description = "2x chance for rare hatches!",
    icon = "🍀",
    durationSeconds = 15 * 60, -- 15 minutes
    robuxPrice = 25,
    boostMultiplier = 2.0, -- Doubles rare outcome chances
  },
  HatchLuck60 = {
    id = "HatchLuck60",
    name = "HatchLuck60",
    displayName = "Luck Boost (1 hour)",
    description = "2x chance for rare hatches!",
    icon = "🍀",
    durationSeconds = 60 * 60, -- 1 hour
    robuxPrice = 75,
    boostMultiplier = 2.0,
  },
  HatchLuck240 = {
    id = "HatchLuck240",
    name = "HatchLuck240",
    displayName = "Luck Boost (4 hours)",
    description = "2x chance for rare hatches!",
    icon = "🍀",
    durationSeconds = 240 * 60, -- 4 hours
    robuxPrice = 200,
    boostMultiplier = 2.0,
  },

  -- Egg Quality Boost: Chickens produce better eggs
  EggQuality15 = {
    id = "EggQuality15",
    name = "EggQuality15",
    displayName = "Golden Eggs (15 min)",
    description = "Chickens lay eggs 1 tier higher!",
    icon = "✨",
    durationSeconds = 15 * 60,
    robuxPrice = 35,
    boostMultiplier = 1.0, -- 1 tier upgrade
  },
  EggQuality60 = {
    id = "EggQuality60",
    name = "EggQuality60",
    displayName = "Golden Eggs (1 hour)",
    description = "Chickens lay eggs 1 tier higher!",
    icon = "✨",
    durationSeconds = 60 * 60,
    robuxPrice = 100,
    boostMultiplier = 1.0,
  },
  EggQuality240 = {
    id = "EggQuality240",
    name = "EggQuality240",
    displayName = "Golden Eggs (4 hours)",
    description = "Chickens lay eggs 1 tier higher!",
    icon = "✨",
    durationSeconds = 240 * 60,
    robuxPrice = 275,
    boostMultiplier = 1.0,
  },
}

-- Power-up type groupings for UI display
local POWER_UP_TYPES: { [PowerUpType]: { string } } = {
  HatchLuck = { "HatchLuck15", "HatchLuck60", "HatchLuck240" },
  EggQuality = { "EggQuality15", "EggQuality60", "EggQuality240" },
}

-- Get a power-up configuration by ID
function PowerUpConfig.get(powerUpId: string): PowerUpConfig?
  return POWER_UPS[powerUpId]
end

-- Get all power-up configurations
function PowerUpConfig.getAll(): { [string]: PowerUpConfig }
  return POWER_UPS
end

-- Get all power-ups as a sorted list
function PowerUpConfig.getAllSorted(): { PowerUpConfig }
  local result = {}
  for _, config in pairs(POWER_UPS) do
    table.insert(result, config)
  end
  table.sort(result, function(a, b)
    return a.robuxPrice < b.robuxPrice
  end)
  return result
end

-- Get power-ups by type
function PowerUpConfig.getByType(powerUpType: PowerUpType): { PowerUpConfig }
  local ids = POWER_UP_TYPES[powerUpType]
  if not ids then
    return {}
  end

  local result = {}
  for _, id in ipairs(ids) do
    local config = POWER_UPS[id]
    if config then
      table.insert(result, config)
    end
  end
  return result
end

-- Check if a power-up ID is valid
function PowerUpConfig.isValid(powerUpId: string): boolean
  return POWER_UPS[powerUpId] ~= nil
end

-- Get the power-up type from a power-up ID
function PowerUpConfig.getPowerUpType(powerUpId: string): PowerUpType?
  if string.find(powerUpId, "HatchLuck") then
    return "HatchLuck"
  elseif string.find(powerUpId, "EggQuality") then
    return "EggQuality"
  end
  return nil
end

-- Check if a power-up is active (not expired)
function PowerUpConfig.isActive(activePowerUp: ActivePowerUp): boolean
  local currentTime = os.time()
  return currentTime < activePowerUp.expiresAt
end

-- Get remaining time in seconds for an active power-up
function PowerUpConfig.getRemainingTime(activePowerUp: ActivePowerUp): number
  local currentTime = os.time()
  return math.max(0, activePowerUp.expiresAt - currentTime)
end

-- Create an active power-up from a power-up ID
function PowerUpConfig.activate(powerUpId: string): ActivePowerUp?
  local config = POWER_UPS[powerUpId]
  if not config then
    return nil
  end

  local currentTime = os.time()
  return {
    powerUpId = powerUpId,
    activatedTime = currentTime,
    expiresAt = currentTime + config.durationSeconds,
  }
end

-- Extend an existing power-up's duration (if same type is purchased again)
function PowerUpConfig.extend(activePowerUp: ActivePowerUp, powerUpId: string): ActivePowerUp?
  local config = POWER_UPS[powerUpId]
  if not config then
    return nil
  end

  -- Only extend if same power-up type
  local existingType = PowerUpConfig.getPowerUpType(activePowerUp.powerUpId)
  local newType = PowerUpConfig.getPowerUpType(powerUpId)
  if existingType ~= newType then
    return nil
  end

  -- Extend from current expiry time (or current time if already expired)
  local currentTime = os.time()
  local baseTime = math.max(currentTime, activePowerUp.expiresAt)

  return {
    powerUpId = powerUpId,
    activatedTime = activePowerUp.activatedTime, -- Keep original activation time
    expiresAt = baseTime + config.durationSeconds,
  }
end

-- Format remaining time as a readable string
function PowerUpConfig.formatRemainingTime(seconds: number): string
  if seconds <= 0 then
    return "Expired"
  end

  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60

  if hours > 0 then
    return string.format("%dh %dm", hours, minutes)
  elseif minutes > 0 then
    return string.format("%dm %ds", minutes, secs)
  else
    return string.format("%ds", secs)
  end
end

return PowerUpConfig
