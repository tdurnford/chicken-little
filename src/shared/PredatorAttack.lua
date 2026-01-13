--[[
	PredatorAttack Module
	Handles predator attack behavior including coop detection,
	chicken stealing/killing, escape logic, and player alerts.
]]

local PredatorAttack = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local PredatorConfig = require(script.Parent.PredatorConfig)
local PredatorSpawning = require(script.Parent.PredatorSpawning)
local ChickenPlacement = require(script.Parent.ChickenPlacement)
local ChickenConfig = require(script.Parent.ChickenConfig)

-- Type definitions
export type AttackResult = {
  success: boolean,
  message: string,
  chickensLost: number,
  chickenIds: { string },
  predatorEscaped: boolean,
  totalValueLost: number,
}

export type AlertInfo = {
  alertType: "approaching" | "attacking" | "escaped" | "defeated" | "caught",
  predatorType: string,
  predatorDisplayName: string,
  threatLevel: PredatorConfig.ThreatLevel,
  message: string,
  urgent: boolean,
}

export type DefenseCheckResult = {
  canDefend: boolean,
  trapReady: boolean,
  batAvailable: boolean,
  predatorResistance: number,
  message: string,
}

-- Constants
local APPROACH_TIME_SECONDS = 5 -- Time for predator to reach coop after spawning
local ESCAPE_DELAY_SECONDS = 3 -- Time for predator to escape after attacking

-- Check if a predator has reached the coop (transition from approaching to attacking)
function PredatorAttack.hasReachedCoop(
  predator: PredatorSpawning.PredatorInstance,
  currentTime: number
): boolean
  if predator.state ~= "approaching" and predator.state ~= "spawning" then
    return false
  end
  local timeSinceSpawn = currentTime - predator.spawnTime
  return timeSinceSpawn >= APPROACH_TIME_SECONDS
end

-- Transition predator to attacking state
function PredatorAttack.startAttacking(
  spawnState: PredatorSpawning.SpawnState,
  predatorId: string
): boolean
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return false
  end
  if predator.state ~= "spawning" and predator.state ~= "approaching" then
    return false
  end
  return PredatorSpawning.updatePredatorState(spawnState, predatorId, "attacking")
end

-- Select random chickens from coop for attack
local function selectChickensForAttack(
  playerData: PlayerData.PlayerDataSchema,
  count: number
): { PlayerData.ChickenData }
  local placedChickens = playerData.placedChickens
  if #placedChickens == 0 then
    return {}
  end

  local selected = {}
  local indices = {}

  -- Create list of indices to select from
  for i = 1, #placedChickens do
    table.insert(indices, i)
  end

  -- Randomly select chickens up to count or available chickens
  local toSelect = math.min(count, #placedChickens)
  for _ = 1, toSelect do
    if #indices == 0 then
      break
    end
    local randomIndex = math.random(1, #indices)
    local chickenIndex = indices[randomIndex]
    table.insert(selected, placedChickens[chickenIndex])
    table.remove(indices, randomIndex)
  end

  return selected
end

-- Calculate value of lost chickens
local function calculateChickenValue(chicken: PlayerData.ChickenData): number
  local config = ChickenConfig.get(chicken.chickenType)
  if not config then
    return 0
  end
  -- Value based on money per second * 60 (one minute of production) + accumulated money
  return (config.moneyPerSecond * 60) + chicken.accumulatedMoney
end

-- Execute a predator attack on a player's coop
function PredatorAttack.executeAttack(
  playerData: PlayerData.PlayerDataSchema,
  spawnState: PredatorSpawning.SpawnState,
  predatorId: string
): AttackResult
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return {
      success = false,
      message = "Predator not found",
      chickensLost = 0,
      chickenIds = {},
      predatorEscaped = false,
      totalValueLost = 0,
    }
  end

  -- Check predator is in attacking state
  if predator.state ~= "attacking" then
    return {
      success = false,
      message = "Predator is not attacking",
      chickensLost = 0,
      chickenIds = {},
      predatorEscaped = false,
      totalValueLost = 0,
    }
  end

  -- Check if coop has chickens
  if #playerData.placedChickens == 0 then
    return {
      success = false,
      message = "No chickens in coop to attack",
      chickensLost = 0,
      chickenIds = {},
      predatorEscaped = false,
      totalValueLost = 0,
    }
  end

  -- Get predator config for attack damage
  local config = PredatorConfig.get(predator.predatorType)
  if not config then
    return {
      success = false,
      message = "Invalid predator type",
      chickensLost = 0,
      chickenIds = {},
      predatorEscaped = false,
      totalValueLost = 0,
    }
  end

  -- Apply predator resistance from upgrades
  local resistance = playerData.upgrades.predatorResistance or 0
  local resistanceRoll = math.random()

  -- Resistance can block the attack
  if resistanceRoll < resistance then
    return {
      success = true,
      message = "Attack blocked by coop defenses!",
      chickensLost = 0,
      chickenIds = {},
      predatorEscaped = false,
      totalValueLost = 0,
    }
  end

  -- Select chickens to attack
  local chickensToAttack = selectChickensForAttack(playerData, config.chickensPerAttack)
  local chickenIds = {}
  local totalValueLost = 0

  -- Remove chickens from coop
  for _, chicken in ipairs(chickensToAttack) do
    table.insert(chickenIds, chicken.id)
    totalValueLost = totalValueLost + calculateChickenValue(chicken)

    -- Find and remove the chicken from placed chickens
    for i, placedChicken in ipairs(playerData.placedChickens) do
      if placedChicken.id == chicken.id then
        table.remove(playerData.placedChickens, i)
        break
      end
    end
  end

  -- Decrease predator's remaining attacks
  local attackResult = PredatorSpawning.decreaseAttacks(spawnState, predatorId)
  local predatorEscaped = attackResult.shouldEscape

  local displayName = config.displayName or predator.predatorType
  local message
  if #chickenIds == 1 then
    message = displayName .. " stole a chicken!"
  else
    message = displayName .. " stole " .. #chickenIds .. " chickens!"
  end

  if predatorEscaped then
    message = message .. " The " .. displayName .. " escaped!"
  end

  return {
    success = true,
    message = message,
    chickensLost = #chickenIds,
    chickenIds = chickenIds,
    predatorEscaped = predatorEscaped,
    totalValueLost = totalValueLost,
  }
end

-- Update predator states based on time (spawning -> approaching -> attacking)
function PredatorAttack.updatePredatorStates(
  spawnState: PredatorSpawning.SpawnState,
  currentTime: number
): { string } -- Returns list of predator IDs that started attacking
  local nowAttacking = {}

  for _, predator in ipairs(spawnState.activePredators) do
    if predator.state == "spawning" then
      -- Transition to approaching immediately
      PredatorSpawning.updatePredatorState(spawnState, predator.id, "approaching")
    elseif predator.state == "approaching" then
      -- Check if reached coop
      if PredatorAttack.hasReachedCoop(predator, currentTime) then
        PredatorSpawning.updatePredatorState(spawnState, predator.id, "attacking")
        table.insert(nowAttacking, predator.id)
      end
    end
  end

  return nowAttacking
end

-- Get attack info for a predator
function PredatorAttack.getAttackInfo(predator: PredatorSpawning.PredatorInstance): {
  predatorType: string,
  displayName: string,
  threatLevel: PredatorConfig.ThreatLevel,
  chickensPerAttack: number,
  attacksRemaining: number,
  isAttacking: boolean,
  canBeTrapped: boolean,
  canBeBatted: boolean,
}
  local config = PredatorConfig.get(predator.predatorType)
  local displayName = config and config.displayName or predator.predatorType
  local threatLevel = config and config.threatLevel or "Minor"
  local chickensPerAttack = config and config.chickensPerAttack or 1

  local isActive = predator.state ~= "caught"
    and predator.state ~= "escaped"
    and predator.state ~= "defeated"

  return {
    predatorType = predator.predatorType,
    displayName = displayName,
    threatLevel = threatLevel,
    chickensPerAttack = chickensPerAttack,
    attacksRemaining = predator.attacksRemaining,
    isAttacking = predator.state == "attacking",
    canBeTrapped = isActive and predator.state ~= "defeated",
    canBeBatted = isActive,
  }
end

-- Generate an alert for a predator event
function PredatorAttack.generateAlert(
  predator: PredatorSpawning.PredatorInstance,
  alertType: "approaching" | "attacking" | "escaped" | "defeated" | "caught"
): AlertInfo
  local config = PredatorConfig.get(predator.predatorType)
  local displayName = config and config.displayName or predator.predatorType
  local threatLevel = config and config.threatLevel or "Minor"

  local messages = {
    approaching = displayName .. " is approaching your coop!",
    attacking = displayName .. " is attacking your chickens!",
    escaped = displayName .. " escaped with your chickens!",
    defeated = "You defeated the " .. displayName .. "!",
    caught = displayName .. " was caught in a trap!",
  }

  local urgentTypes = {
    approaching = true,
    attacking = true,
    escaped = false,
    defeated = false,
    caught = false,
  }

  -- Higher threat levels are always urgent
  local highThreatLevels = {
    Severe = true,
    Deadly = true,
    Catastrophic = true,
  }

  return {
    alertType = alertType,
    predatorType = predator.predatorType,
    predatorDisplayName = displayName,
    threatLevel = threatLevel,
    message = messages[alertType] or "A predator event occurred!",
    urgent = urgentTypes[alertType] or highThreatLevels[threatLevel] or false,
  }
end

-- Check player's defense capabilities
function PredatorAttack.checkDefenses(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): DefenseCheckResult
  -- Check for ready traps
  local trapReady = false
  for _, trap in ipairs(playerData.traps) do
    if not trap.cooldownEndTime or currentTime >= trap.cooldownEndTime then
      if not trap.caughtPredator then
        trapReady = true
        break
      end
    end
  end

  -- Bat is always available (no cooldown in base game)
  local batAvailable = true

  local resistance = playerData.upgrades.predatorResistance or 0
  local canDefend = trapReady or batAvailable

  local message
  if not canDefend then
    message = "No defenses available!"
  elseif trapReady and batAvailable then
    message = "Traps and bat ready"
  elseif trapReady then
    message = "Traps ready"
  else
    message = "Bat ready"
  end

  return {
    canDefend = canDefend,
    trapReady = trapReady,
    batAvailable = batAvailable,
    predatorResistance = resistance,
    message = message,
  }
end

-- Get time until a predator will attack
function PredatorAttack.getTimeUntilAttack(
  predator: PredatorSpawning.PredatorInstance,
  currentTime: number
): number
  if predator.state == "attacking" then
    return 0
  end
  if predator.state ~= "spawning" and predator.state ~= "approaching" then
    return -1 -- Not going to attack
  end
  local timeSinceSpawn = currentTime - predator.spawnTime
  return math.max(0, APPROACH_TIME_SECONDS - timeSinceSpawn)
end

-- Check if any predators are threatening a player's coop
function PredatorAttack.getThreateningPredators(
  spawnState: PredatorSpawning.SpawnState,
  targetPlayerId: string
): { PredatorSpawning.PredatorInstance }
  local threats = {}
  for _, predator in ipairs(spawnState.activePredators) do
    if predator.targetPlayerId == targetPlayerId then
      if
        predator.state == "spawning"
        or predator.state == "approaching"
        or predator.state == "attacking"
      then
        table.insert(threats, predator)
      end
    end
  end
  return threats
end

-- Get summary of current threats
function PredatorAttack.getThreatSummary(
  spawnState: PredatorSpawning.SpawnState,
  targetPlayerId: string,
  currentTime: number
): {
  totalThreats: number,
  approachingCount: number,
  attackingCount: number,
  mostDangerousThreat: string?,
  timeUntilNextAttack: number?,
}
  local threats = PredatorAttack.getThreateningPredators(spawnState, targetPlayerId)

  local approachingCount = 0
  local attackingCount = 0
  local mostDangerousThreat: string? = nil
  local highestDifficulty = 0
  local timeUntilNextAttack: number? = nil

  for _, predator in ipairs(threats) do
    if predator.state == "approaching" or predator.state == "spawning" then
      approachingCount = approachingCount + 1
      local timeUntil = PredatorAttack.getTimeUntilAttack(predator, currentTime)
      if timeUntilNextAttack == nil or timeUntil < timeUntilNextAttack then
        timeUntilNextAttack = timeUntil
      end
    elseif predator.state == "attacking" then
      attackingCount = attackingCount + 1
      timeUntilNextAttack = 0
    end

    local config = PredatorConfig.get(predator.predatorType)
    if config and config.catchDifficulty > highestDifficulty then
      highestDifficulty = config.catchDifficulty
      mostDangerousThreat = config.displayName or predator.predatorType
    end
  end

  return {
    totalThreats = #threats,
    approachingCount = approachingCount,
    attackingCount = attackingCount,
    mostDangerousThreat = mostDangerousThreat,
    timeUntilNextAttack = timeUntilNextAttack,
  }
end

-- Calculate total potential damage from all active threats
function PredatorAttack.calculatePotentialDamage(
  spawnState: PredatorSpawning.SpawnState,
  targetPlayerId: string
): number
  local threats = PredatorAttack.getThreateningPredators(spawnState, targetPlayerId)
  local totalDamage = 0

  for _, predator in ipairs(threats) do
    local config = PredatorConfig.get(predator.predatorType)
    if config then
      totalDamage = totalDamage + (config.chickensPerAttack * predator.attacksRemaining)
    end
  end

  return totalDamage
end

-- Check if a predator should be forced to escape (e.g., no more chickens to steal)
function PredatorAttack.shouldForceEscape(
  playerData: PlayerData.PlayerDataSchema,
  predator: PredatorSpawning.PredatorInstance
): boolean
  -- Escape if no chickens left
  if #playerData.placedChickens == 0 then
    return true
  end
  -- Escape if no attacks remaining
  if predator.attacksRemaining <= 0 then
    return true
  end
  return false
end

-- Force a predator to escape
function PredatorAttack.forceEscape(
  spawnState: PredatorSpawning.SpawnState,
  predatorId: string
): boolean
  return PredatorSpawning.markEscaped(spawnState, predatorId)
end

-- Get constants for external configuration
function PredatorAttack.getConstants(): {
  approachTimeSeconds: number,
  escapeDelaySeconds: number,
}
  return {
    approachTimeSeconds = APPROACH_TIME_SECONDS,
    escapeDelaySeconds = ESCAPE_DELAY_SECONDS,
  }
end

return PredatorAttack
