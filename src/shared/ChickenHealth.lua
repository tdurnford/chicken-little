--[[
	ChickenHealth Module
	Manages health state for chickens in the coop.
	Tracks damage from predator attacks and health regeneration when safe.
]]

local ChickenConfig = require(script.Parent.ChickenConfig)

local ChickenHealth = {}

-- Type definitions
export type ChickenHealthState = {
  chickenId: string,
  chickenType: string,
  currentHealth: number,
  maxHealth: number,
  lastDamageTime: number,
  regenRate: number,
  isDead: boolean,
}

export type ChickenHealthRegistry = {
  chickens: { [string]: ChickenHealthState },
}

-- Constants
local REGEN_DELAY_SECONDS = ChickenConfig.getHealthRegenDelay()

-- Create health registry for tracking all chickens
function ChickenHealth.createRegistry(): ChickenHealthRegistry
  return {
    chickens = {},
  }
end

-- Create health state for a chicken
function ChickenHealth.createState(chickenId: string, chickenType: string): ChickenHealthState
  local maxHealth = ChickenConfig.getMaxHealthForType(chickenType)
  local regenRate = ChickenConfig.getHealthRegenForType(chickenType)

  return {
    chickenId = chickenId,
    chickenType = chickenType,
    currentHealth = maxHealth,
    maxHealth = maxHealth,
    lastDamageTime = 0,
    regenRate = regenRate,
    isDead = false,
  }
end

-- Register a chicken in the health registry
function ChickenHealth.register(
  registry: ChickenHealthRegistry,
  chickenId: string,
  chickenType: string
): ChickenHealthState
  local state = ChickenHealth.createState(chickenId, chickenType)
  registry.chickens[chickenId] = state
  return state
end

-- Unregister a chicken from the health registry
function ChickenHealth.unregister(registry: ChickenHealthRegistry, chickenId: string): boolean
  if registry.chickens[chickenId] then
    registry.chickens[chickenId] = nil
    return true
  end
  return false
end

-- Get health state for a chicken
function ChickenHealth.get(registry: ChickenHealthRegistry, chickenId: string): ChickenHealthState?
  return registry.chickens[chickenId]
end

-- Apply damage to a chicken
function ChickenHealth.applyDamage(
  registry: ChickenHealthRegistry,
  chickenId: string,
  damage: number,
  currentTime: number
): {
  success: boolean,
  newHealth: number,
  died: boolean,
  damageDealt: number,
}
  local state = registry.chickens[chickenId]
  if not state then
    return { success = false, newHealth = 0, died = false, damageDealt = 0 }
  end

  if state.isDead then
    return { success = false, newHealth = 0, died = false, damageDealt = 0 }
  end

  local actualDamage = math.min(damage, state.currentHealth)
  state.currentHealth = state.currentHealth - actualDamage
  state.lastDamageTime = currentTime

  local died = false
  if state.currentHealth <= 0 then
    state.currentHealth = 0
    state.isDead = true
    died = true
  end

  return {
    success = true,
    newHealth = state.currentHealth,
    died = died,
    damageDealt = actualDamage,
  }
end

-- Update health regeneration for a chicken
function ChickenHealth.regenerate(
  registry: ChickenHealthRegistry,
  chickenId: string,
  deltaTime: number,
  currentTime: number
): { success: boolean, newHealth: number, amountHealed: number }
  local state = registry.chickens[chickenId]
  if not state then
    return { success = false, newHealth = 0, amountHealed = 0 }
  end

  if state.isDead then
    return { success = false, newHealth = 0, amountHealed = 0 }
  end

  -- Check if enough time has passed since last damage
  local timeSinceDamage = currentTime - state.lastDamageTime
  if timeSinceDamage < REGEN_DELAY_SECONDS then
    return { success = true, newHealth = state.currentHealth, amountHealed = 0 }
  end

  -- Already at full health
  if state.currentHealth >= state.maxHealth then
    return { success = true, newHealth = state.maxHealth, amountHealed = 0 }
  end

  -- Apply regeneration
  local regenAmount = state.regenRate * deltaTime
  local previousHealth = state.currentHealth
  state.currentHealth = math.min(state.maxHealth, state.currentHealth + regenAmount)

  return {
    success = true,
    newHealth = state.currentHealth,
    amountHealed = state.currentHealth - previousHealth,
  }
end

-- Update all chickens in registry (regeneration)
function ChickenHealth.updateAll(
  registry: ChickenHealthRegistry,
  deltaTime: number,
  currentTime: number
): { [string]: { newHealth: number, amountHealed: number } }
  local updates = {}

  for chickenId, state in pairs(registry.chickens) do
    if not state.isDead and state.currentHealth < state.maxHealth then
      local result = ChickenHealth.regenerate(registry, chickenId, deltaTime, currentTime)
      if result.success and result.amountHealed > 0 then
        updates[chickenId] = {
          newHealth = result.newHealth,
          amountHealed = result.amountHealed,
        }
      end
    end
  end

  return updates
end

-- Check if a chicken is at full health
function ChickenHealth.isFullHealth(registry: ChickenHealthRegistry, chickenId: string): boolean
  local state = registry.chickens[chickenId]
  if not state then
    return false
  end
  return state.currentHealth >= state.maxHealth
end

-- Check if a chicken is damaged (not at full health)
function ChickenHealth.isDamaged(registry: ChickenHealthRegistry, chickenId: string): boolean
  local state = registry.chickens[chickenId]
  if not state then
    return false
  end
  return state.currentHealth < state.maxHealth
end

-- Get health percentage for a chicken
function ChickenHealth.getHealthPercent(registry: ChickenHealthRegistry, chickenId: string): number
  local state = registry.chickens[chickenId]
  if not state or state.maxHealth <= 0 then
    return 0
  end
  return state.currentHealth / state.maxHealth
end

-- Get all damaged chickens (for UI display purposes)
function ChickenHealth.getDamagedChickens(registry: ChickenHealthRegistry): { ChickenHealthState }
  local damaged = {}
  for _, state in pairs(registry.chickens) do
    if state.currentHealth < state.maxHealth and not state.isDead then
      table.insert(damaged, state)
    end
  end
  return damaged
end

-- Get all dead chickens
function ChickenHealth.getDeadChickens(registry: ChickenHealthRegistry): { ChickenHealthState }
  local dead = {}
  for _, state in pairs(registry.chickens) do
    if state.isDead then
      table.insert(dead, state)
    end
  end
  return dead
end

-- Reset health for a chicken (for reviving or testing)
function ChickenHealth.resetHealth(registry: ChickenHealthRegistry, chickenId: string): boolean
  local state = registry.chickens[chickenId]
  if not state then
    return false
  end
  state.currentHealth = state.maxHealth
  state.isDead = false
  state.lastDamageTime = 0
  return true
end

-- Get count of registered chickens
function ChickenHealth.getCount(registry: ChickenHealthRegistry): number
  local count = 0
  for _ in pairs(registry.chickens) do
    count = count + 1
  end
  return count
end

-- Get summary for debugging
function ChickenHealth.getSummary(registry: ChickenHealthRegistry): {
  total: number,
  damaged: number,
  dead: number,
  fullHealth: number,
}
  local total = 0
  local damaged = 0
  local dead = 0
  local fullHealth = 0

  for _, state in pairs(registry.chickens) do
    total = total + 1
    if state.isDead then
      dead = dead + 1
    elseif state.currentHealth < state.maxHealth then
      damaged = damaged + 1
    else
      fullHealth = fullHealth + 1
    end
  end

  return {
    total = total,
    damaged = damaged,
    dead = dead,
    fullHealth = fullHealth,
  }
end

return ChickenHealth
