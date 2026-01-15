--[[
	PredatorSpawning Module
	Handles predator spawn timing, wave management, difficulty scaling,
	and predator state tracking for the chicken coop defense system.
]]

local PredatorSpawning = {}

-- Import dependencies
local PredatorConfig = require(script.Parent.PredatorConfig)

-- Type definitions
export type PredatorInstance = {
  id: string,
  predatorType: string,
  spawnTime: number,
  targetPlayerId: string?,
  targetChickenId: string?, -- The chicken this predator is targeting
  state: "spawning" | "approaching" | "attacking" | "caught" | "escaped" | "defeated",
  attacksRemaining: number,
  health: number, -- bat hits to defeat
}

export type SpawnState = {
  lastSpawnTime: number,
  waveNumber: number,
  predatorsSpawned: number,
  activePredators: { PredatorInstance },
  difficultyMultiplier: number,
}

export type SpawnResult = {
  success: boolean,
  message: string,
  predator: PredatorInstance?,
  nextSpawnTime: number?,
}

export type WaveInfo = {
  waveNumber: number,
  predatorCount: number,
  threatLevel: PredatorConfig.ThreatLevel,
  spawnInterval: number,
  difficultyMultiplier: number,
}

-- Configuration constants
local BASE_SPAWN_INTERVAL = 60 -- Base seconds between spawns
local MIN_SPAWN_INTERVAL = 15 -- Minimum spawn interval at high difficulty
local WAVE_SIZE_BASE = 1 -- Predators per wave at start
local WAVE_SIZE_INCREMENT = 0.5 -- Additional predators per wave number
local MAX_ACTIVE_PREDATORS = 5 -- Maximum predators active at once
local DIFFICULTY_SCALE_RATE = 0.05 -- Difficulty increase per wave

-- Generate unique ID for predators
local function generateId(): string
  return string.format("pred_%d_%d", os.time(), math.random(100000, 999999))
end

-- Create initial spawn state
function PredatorSpawning.createSpawnState(): SpawnState
  return {
    lastSpawnTime = 0,
    waveNumber = 0,
    predatorsSpawned = 0,
    activePredators = {},
    difficultyMultiplier = 1.0,
  }
end

-- Calculate spawn interval based on wave number, difficulty, and time of day
function PredatorSpawning.calculateSpawnInterval(
  waveNumber: number,
  difficultyMultiplier: number,
  timeOfDayMultiplier: number?
): number
  -- Interval decreases as waves progress
  local waveReduction = math.min(waveNumber * 2, 30) -- Max 30 second reduction
  local interval = BASE_SPAWN_INTERVAL - waveReduction
  interval = interval / difficultyMultiplier

  -- Apply time-of-day multiplier (higher multiplier = shorter interval = more spawns)
  -- Night (2.0) = spawns twice as often, Day (0.5) = spawns half as often
  local timeMultiplier = timeOfDayMultiplier or 1.0
  interval = interval / timeMultiplier

  return math.max(interval, MIN_SPAWN_INTERVAL)
end

-- Get info about the current wave
function PredatorSpawning.getWaveInfo(
  spawnState: SpawnState,
  timeOfDayMultiplier: number?
): WaveInfo
  local waveNumber = spawnState.waveNumber
  local predatorCount = math.floor(WAVE_SIZE_BASE + (waveNumber - 1) * WAVE_SIZE_INCREMENT)
  predatorCount = math.min(predatorCount, MAX_ACTIVE_PREDATORS)

  -- Threat level increases with wave number
  local threatLevels = PredatorConfig.getThreatLevels()
  local threatIndex = math.min(math.ceil(waveNumber / 5), #threatLevels)
  local dominantThreat = threatLevels[threatIndex]

  return {
    waveNumber = waveNumber,
    predatorCount = predatorCount,
    threatLevel = dominantThreat,
    spawnInterval = PredatorSpawning.calculateSpawnInterval(
      waveNumber,
      spawnState.difficultyMultiplier,
      timeOfDayMultiplier
    ),
    difficultyMultiplier = spawnState.difficultyMultiplier,
  }
end

-- Select predator type based on wave difficulty
function PredatorSpawning.selectPredatorForWave(waveNumber: number): string
  -- Early waves favor lower threat predators
  -- Later waves can include higher threats
  local threatLevels = PredatorConfig.getThreatLevels()
  local maxThreatIndex = math.min(math.ceil(waveNumber / 3), #threatLevels)

  -- Weight towards higher threats as waves progress
  local totalWeight = 0
  local weightedTypes = {}

  for _, predatorType in ipairs(PredatorConfig.getAllTypes()) do
    local config = PredatorConfig.get(predatorType)
    if config then
      -- Find threat level index
      local threatIndex = 1
      for i, level in ipairs(threatLevels) do
        if level == config.threatLevel then
          threatIndex = i
          break
        end
      end

      -- Only include predators up to max threat for this wave
      if threatIndex <= maxThreatIndex then
        -- Apply spawn weight from config
        table.insert(weightedTypes, {
          predatorType = predatorType,
          weight = config.spawnWeight,
        })
        totalWeight = totalWeight + config.spawnWeight
      end
    end
  end

  -- Select based on weighted random
  if totalWeight == 0 then
    return "Rat" -- Fallback
  end

  local roll = math.random() * totalWeight
  local cumulativeWeight = 0

  for _, entry in ipairs(weightedTypes) do
    cumulativeWeight = cumulativeWeight + entry.weight
    if roll <= cumulativeWeight then
      return entry.predatorType
    end
  end

  return "Rat" -- Fallback
end

-- Create a new predator instance
function PredatorSpawning.createPredator(
  predatorType: string,
  currentTime: number,
  targetPlayerId: string?,
  targetChickenId: string?
): PredatorInstance?
  local config = PredatorConfig.get(predatorType)
  if not config then
    return nil
  end

  return {
    id = generateId(),
    predatorType = predatorType,
    spawnTime = currentTime,
    targetPlayerId = targetPlayerId,
    targetChickenId = targetChickenId,
    state = "spawning",
    attacksRemaining = config.chickensPerAttack,
    health = PredatorConfig.getBatHitsRequired(predatorType),
  }
end

-- Check if a spawn should occur
function PredatorSpawning.shouldSpawn(
  spawnState: SpawnState,
  currentTime: number,
  timeOfDayMultiplier: number?
): boolean
  -- Check max active predators
  local activePredatorCount = PredatorSpawning.getActivePredatorCount(spawnState)
  if activePredatorCount >= MAX_ACTIVE_PREDATORS then
    return false
  end

  -- Check spawn interval
  local waveInfo = PredatorSpawning.getWaveInfo(spawnState, timeOfDayMultiplier)
  local timeSinceLastSpawn = currentTime - spawnState.lastSpawnTime

  return timeSinceLastSpawn >= waveInfo.spawnInterval
end

-- Get next spawn time
function PredatorSpawning.getNextSpawnTime(
  spawnState: SpawnState,
  timeOfDayMultiplier: number?
): number
  local waveInfo = PredatorSpawning.getWaveInfo(spawnState, timeOfDayMultiplier)
  return spawnState.lastSpawnTime + waveInfo.spawnInterval
end

-- Spawn a new predator
function PredatorSpawning.spawn(
  spawnState: SpawnState,
  currentTime: number,
  targetPlayerId: string?,
  timeOfDayMultiplier: number?
): SpawnResult
  -- Check if spawn should occur
  if not PredatorSpawning.shouldSpawn(spawnState, currentTime, timeOfDayMultiplier) then
    local nextSpawn = PredatorSpawning.getNextSpawnTime(spawnState, timeOfDayMultiplier)
    local reason = PredatorSpawning.getActivePredatorCount(spawnState) >= MAX_ACTIVE_PREDATORS
        and "Max active predators reached"
      or "Spawn interval not elapsed"

    return {
      success = false,
      message = reason,
      predator = nil,
      nextSpawnTime = nextSpawn,
    }
  end

  -- Increment wave if this is first spawn or wave is complete
  if spawnState.waveNumber == 0 then
    spawnState.waveNumber = 1
  end

  -- Select and create predator
  local predatorType = PredatorSpawning.selectPredatorForWave(spawnState.waveNumber)
  local predator = PredatorSpawning.createPredator(predatorType, currentTime, targetPlayerId)

  if not predator then
    return {
      success = false,
      message = "Failed to create predator of type: " .. predatorType,
      predator = nil,
      nextSpawnTime = PredatorSpawning.getNextSpawnTime(spawnState, timeOfDayMultiplier),
    }
  end

  -- Add to active predators
  table.insert(spawnState.activePredators, predator)

  -- Update spawn state
  spawnState.lastSpawnTime = currentTime
  spawnState.predatorsSpawned = spawnState.predatorsSpawned + 1

  -- Check if wave should advance (every 5 spawns)
  if spawnState.predatorsSpawned % 5 == 0 then
    spawnState.waveNumber = spawnState.waveNumber + 1
    spawnState.difficultyMultiplier = 1 + (spawnState.waveNumber - 1) * DIFFICULTY_SCALE_RATE
  end

  local config = PredatorConfig.get(predatorType)
  local displayName = config and config.displayName or predatorType

  return {
    success = true,
    message = displayName .. " has appeared!",
    predator = predator,
    nextSpawnTime = PredatorSpawning.getNextSpawnTime(spawnState, timeOfDayMultiplier),
  }
end

-- Force spawn a specific predator type (for events/testing)
function PredatorSpawning.forceSpawn(
  spawnState: SpawnState,
  predatorType: string,
  currentTime: number,
  targetPlayerId: string?
): SpawnResult
  -- Validate predator type
  if not PredatorConfig.isValidType(predatorType) then
    return {
      success = false,
      message = "Invalid predator type: " .. predatorType,
      predator = nil,
      nextSpawnTime = nil,
    }
  end

  -- Check max active predators
  if PredatorSpawning.getActivePredatorCount(spawnState) >= MAX_ACTIVE_PREDATORS then
    return {
      success = false,
      message = "Max active predators reached",
      predator = nil,
      nextSpawnTime = nil,
    }
  end

  -- Create predator
  local predator = PredatorSpawning.createPredator(predatorType, currentTime, targetPlayerId)
  if not predator then
    return {
      success = false,
      message = "Failed to create predator",
      predator = nil,
      nextSpawnTime = nil,
    }
  end

  -- Add to active predators
  table.insert(spawnState.activePredators, predator)
  spawnState.predatorsSpawned = spawnState.predatorsSpawned + 1

  local config = PredatorConfig.get(predatorType)
  local displayName = config and config.displayName or predatorType

  return {
    success = true,
    message = displayName .. " has appeared!",
    predator = predator,
    nextSpawnTime = PredatorSpawning.getNextSpawnTime(spawnState),
  }
end

-- Get count of active predators
function PredatorSpawning.getActivePredatorCount(spawnState: SpawnState): number
  local count = 0
  for _, predator in ipairs(spawnState.activePredators) do
    if
      predator.state ~= "caught"
      and predator.state ~= "escaped"
      and predator.state ~= "defeated"
    then
      count = count + 1
    end
  end
  return count
end

-- Get all active predators
function PredatorSpawning.getActivePredators(spawnState: SpawnState): { PredatorInstance }
  local active = {}
  for _, predator in ipairs(spawnState.activePredators) do
    if
      predator.state ~= "caught"
      and predator.state ~= "escaped"
      and predator.state ~= "defeated"
    then
      table.insert(active, predator)
    end
  end
  return active
end

-- Find a predator by ID
function PredatorSpawning.findPredator(
  spawnState: SpawnState,
  predatorId: string
): PredatorInstance?
  for _, predator in ipairs(spawnState.activePredators) do
    if predator.id == predatorId then
      return predator
    end
  end
  return nil
end

-- Update predator state
function PredatorSpawning.updatePredatorState(
  spawnState: SpawnState,
  predatorId: string,
  newState: "spawning" | "approaching" | "attacking" | "caught" | "escaped" | "defeated"
): boolean
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return false
  end

  predator.state = newState
  return true
end

-- Apply bat hit to predator
function PredatorSpawning.applyBatHit(
  spawnState: SpawnState,
  predatorId: string
): {
  success: boolean,
  message: string,
  defeated: boolean,
  remainingHealth: number,
}
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return {
      success = false,
      message = "Predator not found",
      defeated = false,
      remainingHealth = 0,
    }
  end

  -- Can only hit active predators
  if predator.state == "caught" or predator.state == "escaped" or predator.state == "defeated" then
    return {
      success = false,
      message = "Predator is no longer active",
      defeated = false,
      remainingHealth = predator.health,
    }
  end

  -- Apply damage
  predator.health = predator.health - 1

  if predator.health <= 0 then
    predator.state = "defeated"
    local config = PredatorConfig.get(predator.predatorType)
    local displayName = config and config.displayName or predator.predatorType

    return {
      success = true,
      message = displayName .. " defeated!",
      defeated = true,
      remainingHealth = 0,
    }
  end

  return {
    success = true,
    message = "Hit! " .. predator.health .. " hits remaining",
    defeated = false,
    remainingHealth = predator.health,
  }
end

-- Mark predator as caught by trap
function PredatorSpawning.markCaught(spawnState: SpawnState, predatorId: string): boolean
  return PredatorSpawning.updatePredatorState(spawnState, predatorId, "caught")
end

-- Mark predator as escaped
function PredatorSpawning.markEscaped(spawnState: SpawnState, predatorId: string): boolean
  return PredatorSpawning.updatePredatorState(spawnState, predatorId, "escaped")
end

-- Update target chicken for a predator (for re-targeting when chicken dies/picked up)
function PredatorSpawning.updateTargetChicken(
  spawnState: SpawnState,
  predatorId: string,
  newTargetChickenId: string?
): boolean
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return false
  end
  predator.targetChickenId = newTargetChickenId
  return true
end

-- Get target chicken ID for a predator
function PredatorSpawning.getTargetChickenId(spawnState: SpawnState, predatorId: string): string?
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return nil
  end
  return predator.targetChickenId
end

-- Clean up inactive predators (removes caught, escaped, defeated)
function PredatorSpawning.cleanup(spawnState: SpawnState): number
  local removed = 0
  local newActive = {}

  for _, predator in ipairs(spawnState.activePredators) do
    if
      predator.state ~= "caught"
      and predator.state ~= "escaped"
      and predator.state ~= "defeated"
    then
      table.insert(newActive, predator)
    else
      removed = removed + 1
    end
  end

  spawnState.activePredators = newActive
  return removed
end

-- Get time until next spawn
function PredatorSpawning.getTimeUntilNextSpawn(
  spawnState: SpawnState,
  currentTime: number,
  timeOfDayMultiplier: number?
): number
  local nextSpawn = PredatorSpawning.getNextSpawnTime(spawnState, timeOfDayMultiplier)
  return math.max(0, nextSpawn - currentTime)
end

-- Get spawn state summary for UI
function PredatorSpawning.getSummary(
  spawnState: SpawnState,
  currentTime: number,
  timeOfDayMultiplier: number?
): {
  waveNumber: number,
  activePredators: number,
  maxPredators: number,
  predatorsSpawned: number,
  timeUntilNextSpawn: number,
  difficultyMultiplier: number,
  dominantThreat: PredatorConfig.ThreatLevel,
  timeOfDayMultiplier: number,
}
  local waveInfo = PredatorSpawning.getWaveInfo(spawnState, timeOfDayMultiplier)
  local timeMultiplier = timeOfDayMultiplier or 1.0

  return {
    waveNumber = spawnState.waveNumber,
    activePredators = PredatorSpawning.getActivePredatorCount(spawnState),
    maxPredators = MAX_ACTIVE_PREDATORS,
    predatorsSpawned = spawnState.predatorsSpawned,
    timeUntilNextSpawn = PredatorSpawning.getTimeUntilNextSpawn(
      spawnState,
      currentTime,
      timeOfDayMultiplier
    ),
    difficultyMultiplier = spawnState.difficultyMultiplier,
    dominantThreat = waveInfo.threatLevel,
    timeOfDayMultiplier = timeMultiplier,
  }
end

-- Get predator info for display
function PredatorSpawning.getPredatorInfo(predator: PredatorInstance): {
  id: string,
  displayName: string,
  threatLevel: PredatorConfig.ThreatLevel,
  state: string,
  health: number,
  maxHealth: number,
  attacksRemaining: number,
}
  local config = PredatorConfig.get(predator.predatorType)
  local displayName = config and config.displayName or predator.predatorType
  local threatLevel = config and config.threatLevel or "Minor"
  local maxHealth = PredatorConfig.getBatHitsRequired(predator.predatorType)

  return {
    id = predator.id,
    displayName = displayName,
    threatLevel = threatLevel,
    state = predator.state,
    health = predator.health,
    maxHealth = maxHealth,
    attacksRemaining = predator.attacksRemaining,
  }
end

-- Decrease attacks remaining when predator attacks
function PredatorSpawning.decreaseAttacks(
  spawnState: SpawnState,
  predatorId: string
): {
  success: boolean,
  attacksRemaining: number,
  shouldEscape: boolean,
}
  local predator = PredatorSpawning.findPredator(spawnState, predatorId)
  if not predator then
    return {
      success = false,
      attacksRemaining = 0,
      shouldEscape = false,
    }
  end

  predator.attacksRemaining = predator.attacksRemaining - 1
  local shouldEscape = predator.attacksRemaining <= 0

  if shouldEscape then
    predator.state = "escaped"
  end

  return {
    success = true,
    attacksRemaining = predator.attacksRemaining,
    shouldEscape = shouldEscape,
  }
end

-- Reset spawn state (for new game or testing)
function PredatorSpawning.reset(spawnState: SpawnState): ()
  spawnState.lastSpawnTime = 0
  spawnState.waveNumber = 0
  spawnState.predatorsSpawned = 0
  spawnState.activePredators = {}
  spawnState.difficultyMultiplier = 1.0
end

-- Get constants for external configuration
function PredatorSpawning.getConstants(): {
  baseSpawnInterval: number,
  minSpawnInterval: number,
  maxActivePredators: number,
  waveSizeBase: number,
  waveSizeIncrement: number,
  difficultyScaleRate: number,
}
  return {
    baseSpawnInterval = BASE_SPAWN_INTERVAL,
    minSpawnInterval = MIN_SPAWN_INTERVAL,
    maxActivePredators = MAX_ACTIVE_PREDATORS,
    waveSizeBase = WAVE_SIZE_BASE,
    waveSizeIncrement = WAVE_SIZE_INCREMENT,
    difficultyScaleRate = DIFFICULTY_SCALE_RATE,
  }
end

-- Validate spawn state
function PredatorSpawning.validateState(
  spawnState: SpawnState
): { success: boolean, errors: { string } }
  local errors = {}

  if spawnState.waveNumber < 0 then
    table.insert(errors, "Wave number cannot be negative")
  end

  if spawnState.difficultyMultiplier < 1 then
    table.insert(errors, "Difficulty multiplier cannot be less than 1")
  end

  if spawnState.predatorsSpawned < 0 then
    table.insert(errors, "Predators spawned cannot be negative")
  end

  -- Validate each active predator
  for i, predator in ipairs(spawnState.activePredators) do
    if not PredatorConfig.isValidType(predator.predatorType) then
      table.insert(
        errors,
        string.format("Predator %d has invalid type: %s", i, predator.predatorType)
      )
    end

    if predator.health < 0 then
      table.insert(errors, string.format("Predator %d has negative health", i))
    end

    local validStates = {
      spawning = true,
      approaching = true,
      attacking = true,
      caught = true,
      escaped = true,
      defeated = true,
    }
    if not validStates[predator.state] then
      table.insert(errors, string.format("Predator %d has invalid state: %s", i, predator.state))
    end
  end

  return {
    success = #errors == 0,
    errors = errors,
  }
end

return PredatorSpawning
