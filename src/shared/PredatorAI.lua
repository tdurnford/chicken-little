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

-- Predator behavior states
export type PredatorBehaviorState = "roaming" | "stalking" | "approaching" | "attacking"

-- Type definitions
export type PredatorPosition = {
  id: string,
  predatorType: string,
  currentPosition: Vector3,
  targetPosition: Vector3,
  spawnPosition: Vector3,
  walkSpeed: number,
  hasReachedTarget: boolean,
  facingDirection: Vector3,
  -- Roaming behavior fields
  behaviorState: PredatorBehaviorState,
  roamTarget: Vector3?,
  roamEndTime: number?,
  targetSectionIndex: number?,
  detectionRange: number,
  isStalking: boolean,
}

export type PredatorAIState = {
  positions: { [string]: PredatorPosition },
  neutralZoneCenter: Vector3,
  neutralZoneSize: number,
}

-- Constants
local DEFAULT_WALK_SPEED = 8 -- studs per second
local ARRIVAL_THRESHOLD = 2 -- studs - how close to count as "arrived"

-- Roaming behavior constants
local ROAM_SPEED_MULTIPLIER = 0.6 -- slower while roaming
local ROAM_DURATION_MIN = 10 -- minimum seconds to roam
local ROAM_DURATION_MAX = 30 -- maximum seconds to roam
local DETECTION_RANGE_BASE = 40 -- base detection range for finding sections
local ROAM_TARGET_DISTANCE = 15 -- how far to roam to new target
local STALKING_DURATION = 5 -- seconds to stalk before approaching

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
function PredatorAI.createState(
  neutralZoneCenter: Vector3?,
  neutralZoneSize: number?
): PredatorAIState
  return {
    positions = {},
    neutralZoneCenter = neutralZoneCenter or Vector3.new(0, 0, 0),
    neutralZoneSize = neutralZoneSize or 80,
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

-- Register a new predator for AI tracking (direct approach - spawns at section edge)
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
    predatorType = predatorType,
    currentPosition = spawnPos,
    targetPosition = targetPos,
    spawnPosition = spawnPos,
    walkSpeed = walkSpeed,
    hasReachedTarget = false,
    facingDirection = direction,
    behaviorState = "approaching",
    roamTarget = nil,
    roamEndTime = nil,
    targetSectionIndex = nil,
    detectionRange = DETECTION_RANGE_BASE,
    isStalking = false,
  }

  aiState.positions[predatorId] = position
  return position
end

-- Generate a random position within the neutral zone for roaming
function PredatorAI.generateRoamPosition(
  aiState: PredatorAIState,
  currentPosition: Vector3
): Vector3
  local center = aiState.neutralZoneCenter
  local halfSize = aiState.neutralZoneSize / 2 - 5 -- margin from edge

  -- Generate random offset from current position
  local angle = math.random() * math.pi * 2
  local distance = math.random() * ROAM_TARGET_DISTANCE + 5

  local targetX = currentPosition.X + math.cos(angle) * distance
  local targetZ = currentPosition.Z + math.sin(angle) * distance

  -- Clamp to neutral zone bounds
  targetX = math.clamp(targetX, center.X - halfSize, center.X + halfSize)
  targetZ = math.clamp(targetZ, center.Z - halfSize, center.Z + halfSize)

  return Vector3.new(targetX, center.Y + 1, targetZ)
end

-- Register a roaming predator (spawns in neutral zone, roams before selecting target)
function PredatorAI.registerRoamingPredator(
  aiState: PredatorAIState,
  predatorId: string,
  predatorType: string,
  currentTime: number
): PredatorPosition
  local center = aiState.neutralZoneCenter
  local halfSize = aiState.neutralZoneSize / 2 - 10

  -- Spawn at random position in neutral zone
  local spawnX = center.X + (math.random() - 0.5) * halfSize * 2
  local spawnZ = center.Z + (math.random() - 0.5) * halfSize * 2
  local spawnPos = Vector3.new(spawnX, center.Y + 1, spawnZ)

  local walkSpeed = PredatorAI.getWalkSpeed(predatorType)
  local roamSpeed = walkSpeed * ROAM_SPEED_MULTIPLIER

  -- Generate initial roam target
  local roamTarget = PredatorAI.generateRoamPosition(aiState, spawnPos)
  local direction = (roamTarget - spawnPos).Unit

  -- Calculate roam duration
  local roamDuration = math.random() * (ROAM_DURATION_MAX - ROAM_DURATION_MIN) + ROAM_DURATION_MIN

  local config = PredatorConfig.get(predatorType)
  local detectionRange = DETECTION_RANGE_BASE
  if config then
    -- More dangerous predators have larger detection range
    local threatMultiplier = THREAT_SPEED_MULTIPLIER[config.threatLevel] or 1.0
    detectionRange = DETECTION_RANGE_BASE * threatMultiplier
  end

  local position: PredatorPosition = {
    id = predatorId,
    predatorType = predatorType,
    currentPosition = spawnPos,
    targetPosition = spawnPos, -- No coop target yet
    spawnPosition = spawnPos,
    walkSpeed = roamSpeed, -- Use slower roam speed initially
    hasReachedTarget = false,
    facingDirection = direction,
    behaviorState = "roaming",
    roamTarget = roamTarget,
    roamEndTime = currentTime + roamDuration,
    targetSectionIndex = nil,
    detectionRange = detectionRange,
    isStalking = false,
  }

  aiState.positions[predatorId] = position
  return position
end

-- Section info type for target selection
type SectionInfo = {
  sectionIndex: number,
  center: Vector3,
  chickenCount: number,
  distance: number,
}

-- Detect nearby player sections with chickens (returns sections in detection range)
function PredatorAI.detectNearbySections(
  aiState: PredatorAIState,
  predatorId: string,
  sectionInfoProvider: (
    sectionIndex: number
  ) -> { center: Vector3, chickenCount: number }?
): { SectionInfo }
  local position = aiState.positions[predatorId]
  if not position then
    return {}
  end

  local nearbySections: { SectionInfo } = {}

  -- Check all 12 potential sections
  for sectionIndex = 1, 12 do
    local info = sectionInfoProvider(sectionIndex)
    if info and info.chickenCount > 0 then
      local sectionCenter = info.center
      local distance = (position.currentPosition - sectionCenter).Magnitude

      if distance <= position.detectionRange then
        table.insert(nearbySections, {
          sectionIndex = sectionIndex,
          center = sectionCenter,
          chickenCount = info.chickenCount,
          distance = distance,
        })
      end
    end
  end

  -- Sort by opportunity score (closer sections with more chickens first)
  table.sort(nearbySections, function(a, b)
    -- Score = chickenCount / distance (higher is better)
    local scoreA = a.chickenCount / math.max(a.distance, 1)
    local scoreB = b.chickenCount / math.max(b.distance, 1)
    return scoreA > scoreB
  end)

  return nearbySections
end

-- Select a target section based on nearby sections
function PredatorAI.selectTarget(
  aiState: PredatorAIState,
  predatorId: string,
  nearbySections: { SectionInfo }
): SectionInfo?
  if #nearbySections == 0 then
    return nil
  end

  -- Weight random selection towards better targets
  -- 50% chance to pick best target, 30% second best, 20% random from rest
  local roll = math.random()
  if roll < 0.5 or #nearbySections == 1 then
    return nearbySections[1]
  elseif roll < 0.8 and #nearbySections >= 2 then
    return nearbySections[2]
  else
    return nearbySections[math.random(1, #nearbySections)]
  end
end

-- Transition predator to stalking state (visual indicator before approach)
function PredatorAI.startStalking(
  aiState: PredatorAIState,
  predatorId: string,
  targetSection: SectionInfo,
  currentTime: number
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  position.behaviorState = "stalking"
  position.isStalking = true
  position.targetSectionIndex = targetSection.sectionIndex
  position.roamEndTime = currentTime + STALKING_DURATION

  -- Face towards the target section
  local direction = (targetSection.center - position.currentPosition)
  if direction.Magnitude > 0 then
    position.facingDirection = direction.Unit
  end

  return true
end

-- Transition predator from stalking to approaching
function PredatorAI.startApproaching(
  aiState: PredatorAIState,
  predatorId: string,
  sectionCenter: Vector3
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  local targetPos = PredatorAI.calculateTargetPosition(sectionCenter)
  local fullSpeed = PredatorAI.getWalkSpeed(position.predatorType)

  position.behaviorState = "approaching"
  position.isStalking = false
  position.targetPosition = targetPos
  position.walkSpeed = fullSpeed
  position.roamTarget = nil
  position.roamEndTime = nil

  return true
end

-- Update roaming behavior for a predator
function PredatorAI.updateRoaming(
  aiState: PredatorAIState,
  predatorId: string,
  deltaTime: number,
  currentTime: number
): PredatorPosition?
  local position = aiState.positions[predatorId]
  if not position or position.behaviorState ~= "roaming" then
    return position
  end

  -- Check if roam target reached
  local roamTarget = position.roamTarget
  if roamTarget then
    local toTarget = roamTarget - position.currentPosition
    local distance = toTarget.Magnitude

    if distance <= ARRIVAL_THRESHOLD then
      -- Generate new roam target
      position.roamTarget = PredatorAI.generateRoamPosition(aiState, position.currentPosition)
    else
      -- Move towards roam target
      local direction = toTarget.Unit
      local moveDistance = position.walkSpeed * deltaTime

      if moveDistance >= distance then
        position.currentPosition = roamTarget
        position.roamTarget = PredatorAI.generateRoamPosition(aiState, position.currentPosition)
      else
        position.currentPosition = position.currentPosition + direction * moveDistance
      end
      position.facingDirection = direction
    end
  end

  return position
end

-- Check if roaming predator should look for targets
function PredatorAI.shouldSeekTarget(
  aiState: PredatorAIState,
  predatorId: string,
  currentTime: number
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- Only seek targets while roaming
  if position.behaviorState ~= "roaming" then
    return false
  end

  -- Check if roam time has expired
  if position.roamEndTime and currentTime >= position.roamEndTime then
    return true
  end

  return false
end

-- Check if stalking predator should start approaching
function PredatorAI.shouldStartApproaching(
  aiState: PredatorAIState,
  predatorId: string,
  currentTime: number
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  if position.behaviorState ~= "stalking" then
    return false
  end

  -- Check if stalking time has expired
  if position.roamEndTime and currentTime >= position.roamEndTime then
    return true
  end

  return false
end

-- Get predator's current behavior state
function PredatorAI.getBehaviorState(
  aiState: PredatorAIState,
  predatorId: string
): PredatorBehaviorState?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end
  return position.behaviorState
end

-- Check if predator is roaming
function PredatorAI.isRoaming(aiState: PredatorAIState, predatorId: string): boolean
  local state = PredatorAI.getBehaviorState(aiState, predatorId)
  return state == "roaming"
end

-- Check if predator is stalking
function PredatorAI.isStalking(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  return position ~= nil and position.isStalking
end

-- Get roaming predators
function PredatorAI.getRoamingPredators(aiState: PredatorAIState): { string }
  local roaming = {}
  for id, position in pairs(aiState.positions) do
    if position.behaviorState == "roaming" then
      table.insert(roaming, id)
    end
  end
  return roaming
end

-- Get stalking predators
function PredatorAI.getStalkingPredators(aiState: PredatorAIState): { string }
  local stalking = {}
  for id, position in pairs(aiState.positions) do
    if position.behaviorState == "stalking" then
      table.insert(stalking, id)
    end
  end
  return stalking
end

-- Update a predator's position based on deltaTime (handles approaching behavior)
function PredatorAI.updatePosition(
  aiState: PredatorAIState,
  predatorId: string,
  deltaTime: number
): PredatorPosition?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end

  -- Roaming predators are handled by updateRoaming
  if position.behaviorState == "roaming" then
    return position
  end

  -- Stalking predators don't move, just face target
  if position.behaviorState == "stalking" then
    return position
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
    position.behaviorState = "attacking"
    return position
  end

  -- Move towards target
  local direction = toTarget.Unit
  local moveDistance = position.walkSpeed * deltaTime

  -- Don't overshoot
  if moveDistance >= distance then
    position.currentPosition = position.targetPosition
    position.hasReachedTarget = true
    position.behaviorState = "attacking"
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
  roaming: number,
  stalking: number,
  approaching: number,
  atCoop: number,
}
  local roaming = 0
  local stalking = 0
  local approaching = 0
  local atCoop = 0

  for _, position in pairs(aiState.positions) do
    if position.behaviorState == "roaming" then
      roaming = roaming + 1
    elseif position.behaviorState == "stalking" then
      stalking = stalking + 1
    elseif position.hasReachedTarget then
      atCoop = atCoop + 1
    else
      approaching = approaching + 1
    end
  end

  return {
    totalActive = roaming + stalking + approaching + atCoop,
    roaming = roaming,
    stalking = stalking,
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
  behaviorState: PredatorBehaviorState,
  isStalking: boolean,
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
    behaviorState = position.behaviorState,
    isStalking = position.isStalking,
  }
end

-- Set neutral zone for roaming area
function PredatorAI.setNeutralZone(aiState: PredatorAIState, center: Vector3, size: number)
  aiState.neutralZoneCenter = center
  aiState.neutralZoneSize = size
end

-- Get neutral zone info
function PredatorAI.getNeutralZone(aiState: PredatorAIState): { center: Vector3, size: number }
  return {
    center = aiState.neutralZoneCenter,
    size = aiState.neutralZoneSize,
  }
end

return PredatorAI
