--[[
	BaseballBat Module
	Implements baseball bat combat system for defending against predators
	and knocking back other players.
]]

local BaseballBat = {}

-- Import dependencies
local PredatorConfig = require(script.Parent.PredatorConfig)
local PredatorSpawning = require(script.Parent.PredatorSpawning)

-- Type definitions
export type BatState = {
  isEquipped: boolean,
  lastSwingTime: number,
  swingsCount: number,
}

export type SwingResult = {
  success: boolean,
  message: string,
  hitType: "predator" | "player" | "miss" | nil,
  targetId: string?,
  damage: number,
  defeated: boolean,
  knockback: boolean,
  rewardMoney: number,
}

export type BatConfig = {
  swingCooldownSeconds: number,
  swingRangeStuds: number,
  predatorDamage: number,
  playerKnockbackForce: number,
  playerKnockbackDuration: number,
}

-- Configuration constants
local BAT_CONFIG: BatConfig = {
  swingCooldownSeconds = 0.5, -- Half second between swings
  swingRangeStuds = 8, -- Range of bat swing
  predatorDamage = 1, -- Damage per hit (1 health per hit)
  playerKnockbackForce = 50, -- Force applied to knocked back players
  playerKnockbackDuration = 0.5, -- Duration of knockback effect
}

-- Create initial bat state for a player
function BaseballBat.createBatState(): BatState
  return {
    isEquipped = false,
    lastSwingTime = 0,
    swingsCount = 0,
  }
end

-- Check if the bat is equipped
function BaseballBat.isEquipped(batState: BatState): boolean
  return batState.isEquipped
end

-- Equip the bat
function BaseballBat.equip(batState: BatState): boolean
  if batState.isEquipped then
    return false -- Already equipped
  end
  batState.isEquipped = true
  return true
end

-- Unequip the bat
function BaseballBat.unequip(batState: BatState): boolean
  if not batState.isEquipped then
    return false -- Already unequipped
  end
  batState.isEquipped = false
  return true
end

-- Toggle bat equip state
function BaseballBat.toggle(batState: BatState): boolean
  batState.isEquipped = not batState.isEquipped
  return batState.isEquipped
end

-- Check if the bat can swing (not on cooldown)
function BaseballBat.canSwing(batState: BatState, currentTime: number): boolean
  if not batState.isEquipped then
    return false
  end
  local timeSinceLastSwing = currentTime - batState.lastSwingTime
  return timeSinceLastSwing >= BAT_CONFIG.swingCooldownSeconds
end

-- Get time until next swing is available
function BaseballBat.getSwingCooldownRemaining(batState: BatState, currentTime: number): number
  if not batState.isEquipped then
    return 0
  end
  local timeSinceLastSwing = currentTime - batState.lastSwingTime
  local remaining = BAT_CONFIG.swingCooldownSeconds - timeSinceLastSwing
  return math.max(0, remaining)
end

-- Perform a swing (updates bat state)
function BaseballBat.performSwing(batState: BatState, currentTime: number): boolean
  if not BaseballBat.canSwing(batState, currentTime) then
    return false
  end
  batState.lastSwingTime = currentTime
  batState.swingsCount = batState.swingsCount + 1
  return true
end

-- Hit a predator with the bat
function BaseballBat.hitPredator(
  batState: BatState,
  spawnState: PredatorSpawning.SpawnState,
  predatorId: string,
  currentTime: number
): SwingResult
  -- Check if can swing
  if not BaseballBat.canSwing(batState, currentTime) then
    local remaining = BaseballBat.getSwingCooldownRemaining(batState, currentTime)
    return {
      success = false,
      message = string.format("Bat on cooldown (%.1fs)", remaining),
      hitType = nil,
      targetId = nil,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Find the predator
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return {
      success = false,
      message = "Predator not found",
      hitType = nil,
      targetId = nil,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Check predator is in a hittable state
  if predator.state == "caught" or predator.state == "escaped" or predator.state == "defeated" then
    return {
      success = false,
      message = "Predator is no longer active",
      hitType = nil,
      targetId = predatorId,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Perform the swing
  BaseballBat.performSwing(batState, currentTime)

  -- Apply damage to predator
  local hitResult = PredatorSpawning.applyBatHit(spawnState, predatorId)
  if not hitResult.success then
    return {
      success = false,
      message = hitResult.message,
      hitType = "miss",
      targetId = predatorId,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Calculate reward if defeated
  local rewardMoney = 0
  if hitResult.defeated then
    local config = PredatorConfig.get(predator.predatorType)
    if config then
      rewardMoney = config.rewardMoney
    end
  end

  local config = PredatorConfig.get(predator.predatorType)
  local displayName = config and config.displayName or predator.predatorType

  return {
    success = true,
    message = hitResult.message,
    hitType = "predator",
    targetId = predatorId,
    damage = BAT_CONFIG.predatorDamage,
    defeated = hitResult.defeated,
    knockback = false,
    rewardMoney = rewardMoney,
  }
end

-- Hit a player with the bat (returns knockback info)
function BaseballBat.hitPlayer(
  batState: BatState,
  targetPlayerId: string,
  currentTime: number
): SwingResult
  -- Check if can swing
  if not BaseballBat.canSwing(batState, currentTime) then
    local remaining = BaseballBat.getSwingCooldownRemaining(batState, currentTime)
    return {
      success = false,
      message = string.format("Bat on cooldown (%.1fs)", remaining),
      hitType = nil,
      targetId = nil,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Perform the swing
  BaseballBat.performSwing(batState, currentTime)

  return {
    success = true,
    message = "Knocked back player!",
    hitType = "player",
    targetId = targetPlayerId,
    damage = 0, -- Players don't take damage
    defeated = false,
    knockback = true,
    rewardMoney = 0,
  }
end

-- Swing at nothing (miss)
function BaseballBat.swingMiss(batState: BatState, currentTime: number): SwingResult
  -- Check if can swing
  if not BaseballBat.canSwing(batState, currentTime) then
    local remaining = BaseballBat.getSwingCooldownRemaining(batState, currentTime)
    return {
      success = false,
      message = string.format("Bat on cooldown (%.1fs)", remaining),
      hitType = nil,
      targetId = nil,
      damage = 0,
      defeated = false,
      knockback = false,
      rewardMoney = 0,
    }
  end

  -- Perform the swing
  BaseballBat.performSwing(batState, currentTime)

  return {
    success = true,
    message = "Swing missed!",
    hitType = "miss",
    targetId = nil,
    damage = 0,
    defeated = false,
    knockback = false,
    rewardMoney = 0,
  }
end

-- Check if a target is within bat range (distance in studs)
function BaseballBat.isInRange(distance: number): boolean
  return distance <= BAT_CONFIG.swingRangeStuds
end

-- Get knockback parameters for player hit
function BaseballBat.getKnockbackParams(): { force: number, duration: number }
  return {
    force = BAT_CONFIG.playerKnockbackForce,
    duration = BAT_CONFIG.playerKnockbackDuration,
  }
end

-- Get bat configuration
function BaseballBat.getConfig(): BatConfig
  return {
    swingCooldownSeconds = BAT_CONFIG.swingCooldownSeconds,
    swingRangeStuds = BAT_CONFIG.swingRangeStuds,
    predatorDamage = BAT_CONFIG.predatorDamage,
    playerKnockbackForce = BAT_CONFIG.playerKnockbackForce,
    playerKnockbackDuration = BAT_CONFIG.playerKnockbackDuration,
  }
end

-- Get swing statistics for a player
function BaseballBat.getStats(batState: BatState): {
  isEquipped: boolean,
  totalSwings: number,
  lastSwingTime: number,
}
  return {
    isEquipped = batState.isEquipped,
    totalSwings = batState.swingsCount,
    lastSwingTime = batState.lastSwingTime,
  }
end

-- Reset bat state (for testing or new game)
function BaseballBat.reset(batState: BatState): ()
  batState.isEquipped = false
  batState.lastSwingTime = 0
  batState.swingsCount = 0
end

-- Find best predator target within range (for auto-targeting)
function BaseballBat.findBestTarget(
  spawnState: PredatorSpawning.SpawnState,
  targetPlayerId: string
): PredatorSpawning.PredatorInstance?
  local activePredators = PredatorSpawning.getActivePredators(spawnState)
  local bestTarget: PredatorSpawning.PredatorInstance? = nil
  local lowestHealth = math.huge

  for _, predator in ipairs(activePredators) do
    -- Only consider predators targeting this player
    if predator.targetPlayerId == targetPlayerId then
      -- Prioritize predators with lowest health (closest to defeat)
      if predator.health < lowestHealth then
        lowestHealth = predator.health
        bestTarget = predator
      end
    end
  end

  return bestTarget
end

-- Get display info for UI
function BaseballBat.getDisplayInfo(
  batState: BatState,
  currentTime: number
): {
  isEquipped: boolean,
  canSwing: boolean,
  cooldownRemaining: number,
  cooldownPercent: number,
}
  local cooldownRemaining = BaseballBat.getSwingCooldownRemaining(batState, currentTime)
  local cooldownPercent = 0
  if cooldownRemaining > 0 then
    cooldownPercent = cooldownRemaining / BAT_CONFIG.swingCooldownSeconds
  end

  return {
    isEquipped = batState.isEquipped,
    canSwing = BaseballBat.canSwing(batState, currentTime),
    cooldownRemaining = cooldownRemaining,
    cooldownPercent = cooldownPercent,
  }
end

-- Calculate hits required to defeat a predator
function BaseballBat.getHitsToDefeat(predatorType: string): number
  return PredatorConfig.getBatHitsRequired(predatorType)
end

-- Get all hittable predators targeting a player
function BaseballBat.getHittablePredators(
  spawnState: PredatorSpawning.SpawnState,
  targetPlayerId: string
): { PredatorSpawning.PredatorInstance }
  local hittable = {}
  local activePredators = PredatorSpawning.getActivePredators(spawnState)

  for _, predator in ipairs(activePredators) do
    if predator.targetPlayerId == targetPlayerId then
      -- Check predator is in a hittable state
      if
        predator.state ~= "caught"
        and predator.state ~= "escaped"
        and predator.state ~= "defeated"
      then
        table.insert(hittable, predator)
      end
    end
  end

  return hittable
end

-- Simulate multiple swings (for testing)
function BaseballBat.simulateSwings(
  batState: BatState,
  spawnState: PredatorSpawning.SpawnState,
  predatorId: string,
  swingCount: number,
  startTime: number
): {
  totalSwings: number,
  hitsLanded: number,
  defeated: boolean,
  totalReward: number,
}
  local result = {
    totalSwings = 0,
    hitsLanded = 0,
    defeated = false,
    totalReward = 0,
  }

  local currentTime = startTime

  for _ = 1, swingCount do
    -- Advance time past cooldown
    currentTime = currentTime + BAT_CONFIG.swingCooldownSeconds

    local swingResult = BaseballBat.hitPredator(batState, spawnState, predatorId, currentTime)
    result.totalSwings = result.totalSwings + 1

    if swingResult.success and swingResult.hitType == "predator" then
      result.hitsLanded = result.hitsLanded + 1
      if swingResult.defeated then
        result.defeated = true
        result.totalReward = result.totalReward + swingResult.rewardMoney
        break
      end
    elseif not swingResult.success then
      -- Predator no longer active
      break
    end
  end

  return result
end

return BaseballBat
