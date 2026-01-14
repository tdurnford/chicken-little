--[[
	PredatorAI Module
	Handles predator NPC walking behavior including spawn positions at map edges,
	movement towards player coops, and position tracking.
	
	Predators now spawn at section boundaries and walk towards the coop,
	giving players time to intercept them before they reach their chickens.
]]

local PredatorAI = {}

-- Import dependencies
local PredatorConfig = require(script.Parent.PredatorConfig)
local PlayerSection = require(script.Parent.PlayerSection)

-- Type definitions
export type PredatorPosition = {
  id: string,
  currentPosition: Vector3,
  targetPosition: Vector3,
  spawnPosition: Vector3,
  walkSpeed: number,
  hasReachedTarget: boolean,
  facingDirection: Vector3,
}

export type PredatorAIState = {
  positions: { [string]: PredatorPosition },
}

-- Constants
local DEFAULT_WALK_SPEED = 8 -- studs per second
local ARRIVAL_THRESHOLD = 2 -- studs - how close to count as "arrived"

-- Walk speed multipliers by threat level (more dangerous = faster)
local THREAT_SPEED_MULTIPLIER: { [string]: number } = {
  Minor = 0.7,
  Moderate = 0.85,
  Dangerous = 1.0,
  Severe = 1.15,
  Deadly = 1.3,
  Catastrophic = 1.5,
}

-- Spawn edge options
local SPAWN_EDGES = { "north", "south", "east", "west" }

-- Create initial AI state
function PredatorAI.createState(): PredatorAIState
  return {
    positions = {},
  }
end

-- Get walk speed for a predator type based on threat level
function PredatorAI.getWalkSpeed(predatorType: string): number
  local config = PredatorConfig.get(predatorType)
  if not config then
    return DEFAULT_WALK_SPEED
  end

  local multiplier = THREAT_SPEED_MULTIPLIER[config.threatLevel] or 1.0
  return DEFAULT_WALK_SPEED * multiplier
end

-- Calculate spawn position at section edge
-- sectionCenter is the Vector3 center of the player's section
function PredatorAI.calculateSpawnPosition(sectionCenter: Vector3, preferredEdge: string?): Vector3
  local sectionConfig = PlayerSection.getConfig()
  local halfWidth = sectionConfig.width / 2
  local halfDepth = sectionConfig.depth / 2

  -- Choose random edge if not specified
  local edge = preferredEdge
  if not edge then
    edge = SPAWN_EDGES[math.random(1, #SPAWN_EDGES)]
  end

  -- Calculate spawn position at edge with some random offset along the edge
  local spawnPos: Vector3

  if edge == "north" then
    -- Back of section (negative Z)
    local randomX = (math.random() - 0.5) * sectionConfig.width * 0.6
    spawnPos = Vector3.new(
      sectionCenter.X + randomX,
      sectionCenter.Y + 1, -- slightly above ground
      sectionCenter.Z - halfDepth - 5 -- outside section boundary
    )
  elseif edge == "south" then
    -- Front of section (positive Z)
    local randomX = (math.random() - 0.5) * sectionConfig.width * 0.6
    spawnPos =
      Vector3.new(sectionCenter.X + randomX, sectionCenter.Y + 1, sectionCenter.Z + halfDepth + 5)
  elseif edge == "east" then
    -- Right side (positive X)
    local randomZ = (math.random() - 0.5) * sectionConfig.depth * 0.6
    spawnPos =
      Vector3.new(sectionCenter.X + halfWidth + 5, sectionCenter.Y + 1, sectionCenter.Z + randomZ)
  else -- west
    -- Left side (negative X)
    local randomZ = (math.random() - 0.5) * sectionConfig.depth * 0.6
    spawnPos =
      Vector3.new(sectionCenter.X - halfWidth - 5, sectionCenter.Y + 1, sectionCenter.Z + randomZ)
  end

  return spawnPos
end

-- Calculate target position (coop center)
function PredatorAI.calculateTargetPosition(sectionCenter: Vector3): Vector3
  local coopCenter = PlayerSection.getCoopCenter(sectionCenter)
  return Vector3.new(coopCenter.x, sectionCenter.Y + 1, coopCenter.z)
end

-- Register a new predator for AI tracking
function PredatorAI.registerPredator(
  aiState: PredatorAIState,
  predatorId: string,
  predatorType: string,
  sectionCenter: Vector3,
  preferredEdge: string?
): PredatorPosition
  local spawnPos = PredatorAI.calculateSpawnPosition(sectionCenter, preferredEdge)
  local targetPos = PredatorAI.calculateTargetPosition(sectionCenter)
  local walkSpeed = PredatorAI.getWalkSpeed(predatorType)

  -- Calculate initial facing direction
  local direction = (targetPos - spawnPos).Unit

  local position: PredatorPosition = {
    id = predatorId,
    currentPosition = spawnPos,
    targetPosition = targetPos,
    spawnPosition = spawnPos,
    walkSpeed = walkSpeed,
    hasReachedTarget = false,
    facingDirection = direction,
  }

  aiState.positions[predatorId] = position
  return position
end

-- Update a predator's position based on deltaTime
function PredatorAI.updatePosition(
  aiState: PredatorAIState,
  predatorId: string,
  deltaTime: number
): PredatorPosition?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end

  -- Already at target
  if position.hasReachedTarget then
    return position
  end

  -- Calculate movement
  local toTarget = position.targetPosition - position.currentPosition
  local distance = toTarget.Magnitude

  -- Check if arrived
  if distance <= ARRIVAL_THRESHOLD then
    position.hasReachedTarget = true
    position.currentPosition = position.targetPosition
    return position
  end

  -- Move towards target
  local direction = toTarget.Unit
  local moveDistance = position.walkSpeed * deltaTime

  -- Don't overshoot
  if moveDistance >= distance then
    position.currentPosition = position.targetPosition
    position.hasReachedTarget = true
  else
    position.currentPosition = position.currentPosition + direction * moveDistance
  end

  position.facingDirection = direction

  return position
end

-- Update all predator positions
function PredatorAI.updateAll(
  aiState: PredatorAIState,
  deltaTime: number
): { [string]: PredatorPosition }
  local updated = {}

  for predatorId, _ in pairs(aiState.positions) do
    local position = PredatorAI.updatePosition(aiState, predatorId, deltaTime)
    if position then
      updated[predatorId] = position
    end
  end

  return updated
end

-- Get predator position
function PredatorAI.getPosition(aiState: PredatorAIState, predatorId: string): PredatorPosition?
  return aiState.positions[predatorId]
end

-- Check if a predator has reached its target (coop)
function PredatorAI.hasReachedCoop(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end
  return position.hasReachedTarget
end

-- Get distance to coop
function PredatorAI.getDistanceToCoop(aiState: PredatorAIState, predatorId: string): number
  local position = aiState.positions[predatorId]
  if not position then
    return 0
  end
  return (position.targetPosition - position.currentPosition).Magnitude
end

-- Get estimated time to reach coop
function PredatorAI.getTimeToReachCoop(aiState: PredatorAIState, predatorId: string): number
  local position = aiState.positions[predatorId]
  if not position then
    return 0
  end

  if position.hasReachedTarget then
    return 0
  end

  local distance = (position.targetPosition - position.currentPosition).Magnitude
  return distance / position.walkSpeed
end

-- Get progress percentage (0-100)
function PredatorAI.getProgress(aiState: PredatorAIState, predatorId: string): number
  local position = aiState.positions[predatorId]
  if not position then
    return 0
  end

  if position.hasReachedTarget then
    return 100
  end

  local totalDistance = (position.targetPosition - position.spawnPosition).Magnitude
  local currentDistance = (position.targetPosition - position.currentPosition).Magnitude

  if totalDistance <= 0 then
    return 100
  end

  local progress = ((totalDistance - currentDistance) / totalDistance) * 100
  return math.clamp(progress, 0, 100)
end

-- Unregister a predator (when defeated, escaped, or caught)
function PredatorAI.unregisterPredator(aiState: PredatorAIState, predatorId: string): boolean
  if aiState.positions[predatorId] then
    aiState.positions[predatorId] = nil
    return true
  end
  return false
end

-- Get all active predator IDs
function PredatorAI.getActivePredatorIds(aiState: PredatorAIState): { string }
  local ids = {}
  for id, _ in pairs(aiState.positions) do
    table.insert(ids, id)
  end
  return ids
end

-- Get count of active predators
function PredatorAI.getActiveCount(aiState: PredatorAIState): number
  local count = 0
  for _ in pairs(aiState.positions) do
    count = count + 1
  end
  return count
end

-- Get predators that have reached their target
function PredatorAI.getPredatorsAtCoop(aiState: PredatorAIState): { string }
  local atCoop = {}
  for id, position in pairs(aiState.positions) do
    if position.hasReachedTarget then
      table.insert(atCoop, id)
    end
  end
  return atCoop
end

-- Get predators still approaching
function PredatorAI.getApproachingPredators(aiState: PredatorAIState): { string }
  local approaching = {}
  for id, position in pairs(aiState.positions) do
    if not position.hasReachedTarget then
      table.insert(approaching, id)
    end
  end
  return approaching
end

-- Reset AI state
function PredatorAI.reset(aiState: PredatorAIState)
  aiState.positions = {}
end

-- Get summary for debugging
function PredatorAI.getSummary(aiState: PredatorAIState): {
  totalActive: number,
  approaching: number,
  atCoop: number,
}
  local approaching = 0
  local atCoop = 0

  for _, position in pairs(aiState.positions) do
    if position.hasReachedTarget then
      atCoop = atCoop + 1
    else
      approaching = approaching + 1
    end
  end

  return {
    totalActive = approaching + atCoop,
    approaching = approaching,
    atCoop = atCoop,
  }
end

-- Get all positions for syncing to clients
function PredatorAI.getAllPositions(aiState: PredatorAIState): { [string]: Vector3 }
  local positions = {}
  for id, position in pairs(aiState.positions) do
    positions[id] = position.currentPosition
  end
  return positions
end

-- Get position info for a single predator (for client sync)
function PredatorAI.getPositionInfo(
  aiState: PredatorAIState,
  predatorId: string
): {
  position: Vector3,
  target: Vector3,
  progress: number,
  hasReached: boolean,
}?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end

  return {
    position = position.currentPosition,
    target = position.targetPosition,
    progress = PredatorAI.getProgress(aiState, predatorId),
    hasReached = position.hasReachedTarget,
  }
end

return PredatorAI
