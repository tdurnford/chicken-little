--[[
	CombatHealth Module
	Manages player combat health, damage from predators, knockback,
	and health regeneration when out of combat.
]]

local CombatHealth = {}

-- Import dependencies
local PredatorConfig = require(script.Parent.PredatorConfig)

-- Constants
local MAX_COMBAT_HEALTH = 100
local HEALTH_REGEN_PER_SECOND = 10 -- Health regenerated per second when out of combat
local OUT_OF_COMBAT_DELAY = 3 -- Seconds after last damage before regen starts
local KNOCKBACK_DURATION = 1.5 -- Seconds player is stunned after health depletes
local COMBAT_RANGE_STUDS = 15 -- Distance from predator to be considered "in combat"

-- Type definitions
export type CombatState = {
  health: number,
  maxHealth: number,
  lastDamageTime: number,
  isKnockedBack: boolean,
  knockbackEndTime: number,
  inCombat: boolean,
}

export type DamageResult = {
  success: boolean,
  damageDealt: number,
  newHealth: number,
  wasKnockedBack: boolean,
  message: string,
}

export type RegenResult = {
  healthRestored: number,
  newHealth: number,
  isFullHealth: boolean,
}

-- Create initial combat state for a player
function CombatHealth.createState(): CombatState
  return {
    health = MAX_COMBAT_HEALTH,
    maxHealth = MAX_COMBAT_HEALTH,
    lastDamageTime = 0,
    isKnockedBack = false,
    knockbackEndTime = 0,
    inCombat = false,
  }
end

-- Get current health as a percentage (0-1)
function CombatHealth.getHealthPercent(state: CombatState): number
  return state.health / state.maxHealth
end

-- Check if player is at full health
function CombatHealth.isFullHealth(state: CombatState): boolean
  return state.health >= state.maxHealth
end

-- Check if player is knocked back (stunned)
function CombatHealth.isKnockedBack(state: CombatState, currentTime: number): boolean
  if not state.isKnockedBack then
    return false
  end
  -- Check if knockback has expired
  if currentTime >= state.knockbackEndTime then
    state.isKnockedBack = false
    return false
  end
  return true
end

-- Check if player can regenerate health (out of combat)
function CombatHealth.canRegenerate(state: CombatState, currentTime: number): boolean
  if CombatHealth.isFullHealth(state) then
    return false
  end
  if CombatHealth.isKnockedBack(state, currentTime) then
    return false
  end
  local timeSinceDamage = currentTime - state.lastDamageTime
  return timeSinceDamage >= OUT_OF_COMBAT_DELAY
end

-- Check if player is in combat (recently took damage)
function CombatHealth.isInCombat(state: CombatState, currentTime: number): boolean
  local timeSinceDamage = currentTime - state.lastDamageTime
  return timeSinceDamage < OUT_OF_COMBAT_DELAY
end

-- Apply damage to player from a predator
function CombatHealth.applyDamage(
  state: CombatState,
  predatorType: string,
  deltaTime: number,
  currentTime: number
): DamageResult
  -- Check if player is already knocked back
  if CombatHealth.isKnockedBack(state, currentTime) then
    return {
      success = false,
      damageDealt = 0,
      newHealth = state.health,
      wasKnockedBack = false,
      message = "Player is already knocked back",
    }
  end

  -- Get damage per second from predator config
  local damagePerSecond = PredatorConfig.getDamage(predatorType)
  local damage = damagePerSecond * deltaTime

  -- Apply damage
  local previousHealth = state.health
  state.health = math.max(0, state.health - damage)
  state.lastDamageTime = currentTime
  state.inCombat = true

  local wasKnockedBack = false
  local message = string.format("Took %.1f damage from %s", damage, predatorType)

  -- Check if health depleted (knockback)
  if state.health <= 0 then
    state.health = 0
    state.isKnockedBack = true
    state.knockbackEndTime = currentTime + KNOCKBACK_DURATION
    wasKnockedBack = true
    message = string.format("Knocked back by %s!", predatorType)
  end

  return {
    success = true,
    damageDealt = previousHealth - state.health,
    newHealth = state.health,
    wasKnockedBack = wasKnockedBack,
    message = message,
  }
end

-- Apply fixed damage amount (for testing or special attacks)
function CombatHealth.applyFixedDamage(
  state: CombatState,
  damage: number,
  currentTime: number,
  source: string?
): DamageResult
  if CombatHealth.isKnockedBack(state, currentTime) then
    return {
      success = false,
      damageDealt = 0,
      newHealth = state.health,
      wasKnockedBack = false,
      message = "Player is already knocked back",
    }
  end

  local previousHealth = state.health
  state.health = math.max(0, state.health - damage)
  state.lastDamageTime = currentTime
  state.inCombat = true

  local wasKnockedBack = false
  local message = string.format("Took %d damage", damage)
  if source then
    message = string.format("Took %d damage from %s", damage, source)
  end

  if state.health <= 0 then
    state.health = 0
    state.isKnockedBack = true
    state.knockbackEndTime = currentTime + KNOCKBACK_DURATION
    wasKnockedBack = true
    message = "Knocked back!"
  end

  return {
    success = true,
    damageDealt = previousHealth - state.health,
    newHealth = state.health,
    wasKnockedBack = wasKnockedBack,
    message = message,
  }
end

-- Regenerate health when out of combat
function CombatHealth.regenerate(
  state: CombatState,
  deltaTime: number,
  currentTime: number
): RegenResult
  if not CombatHealth.canRegenerate(state, currentTime) then
    return {
      healthRestored = 0,
      newHealth = state.health,
      isFullHealth = CombatHealth.isFullHealth(state),
    }
  end

  local regenAmount = HEALTH_REGEN_PER_SECOND * deltaTime
  local previousHealth = state.health
  state.health = math.min(state.maxHealth, state.health + regenAmount)

  -- Clear combat state when reaching full health
  if state.health >= state.maxHealth then
    state.inCombat = false
  end

  return {
    healthRestored = state.health - previousHealth,
    newHealth = state.health,
    isFullHealth = CombatHealth.isFullHealth(state),
  }
end

-- Update combat state (handles knockback expiry and regeneration)
function CombatHealth.update(
  state: CombatState,
  deltaTime: number,
  currentTime: number
): {
  healthChanged: boolean,
  knockbackEnded: boolean,
  regenResult: RegenResult?,
}
  local healthChanged = false
  local knockbackEnded = false
  local regenResult: RegenResult? = nil

  -- Check if knockback ended
  if state.isKnockedBack and currentTime >= state.knockbackEndTime then
    state.isKnockedBack = false
    knockbackEnded = true
    -- Restore some health after knockback ends
    state.health = state.maxHealth * 0.25 -- Restore to 25% health
    healthChanged = true
  end

  -- Try to regenerate if possible
  if CombatHealth.canRegenerate(state, currentTime) then
    regenResult = CombatHealth.regenerate(state, deltaTime, currentTime)
    if regenResult.healthRestored > 0 then
      healthChanged = true
    end
  end

  -- Update combat state
  state.inCombat = CombatHealth.isInCombat(state, currentTime)

  return {
    healthChanged = healthChanged,
    knockbackEnded = knockbackEnded,
    regenResult = regenResult,
  }
end

-- Reset combat state (for respawn or new game)
function CombatHealth.reset(state: CombatState): ()
  state.health = state.maxHealth
  state.lastDamageTime = 0
  state.isKnockedBack = false
  state.knockbackEndTime = 0
  state.inCombat = false
end

-- Set health to a specific value (for testing)
function CombatHealth.setHealth(state: CombatState, health: number): ()
  state.health = math.clamp(health, 0, state.maxHealth)
end

-- Get display info for UI
function CombatHealth.getDisplayInfo(
  state: CombatState,
  currentTime: number
): {
  health: number,
  maxHealth: number,
  percent: number,
  inCombat: boolean,
  isKnockedBack: boolean,
  knockbackRemaining: number,
  canRegen: boolean,
  regenDelay: number,
}
  local knockbackRemaining = 0
  if state.isKnockedBack then
    knockbackRemaining = math.max(0, state.knockbackEndTime - currentTime)
  end

  local regenDelay = 0
  if
    not CombatHealth.canRegenerate(state, currentTime) and not CombatHealth.isFullHealth(state)
  then
    regenDelay = math.max(0, OUT_OF_COMBAT_DELAY - (currentTime - state.lastDamageTime))
  end

  return {
    health = state.health,
    maxHealth = state.maxHealth,
    percent = CombatHealth.getHealthPercent(state),
    inCombat = CombatHealth.isInCombat(state, currentTime),
    isKnockedBack = CombatHealth.isKnockedBack(state, currentTime),
    knockbackRemaining = knockbackRemaining,
    canRegen = CombatHealth.canRegenerate(state, currentTime),
    regenDelay = regenDelay,
  }
end

-- Get constants for configuration
function CombatHealth.getConstants(): {
  maxHealth: number,
  regenPerSecond: number,
  outOfCombatDelay: number,
  knockbackDuration: number,
  combatRangeStuds: number,
}
  return {
    maxHealth = MAX_COMBAT_HEALTH,
    regenPerSecond = HEALTH_REGEN_PER_SECOND,
    outOfCombatDelay = OUT_OF_COMBAT_DELAY,
    knockbackDuration = KNOCKBACK_DURATION,
    combatRangeStuds = COMBAT_RANGE_STUDS,
  }
end

-- Helper to clamp value (in case math.clamp is not available)
local function mathClamp(value: number, min: number, max: number): number
  return math.max(min, math.min(max, value))
end

-- Override setHealth with proper clamp
function CombatHealth.setHealth(state: CombatState, health: number): ()
  state.health = mathClamp(health, 0, state.maxHealth)
end

return CombatHealth
