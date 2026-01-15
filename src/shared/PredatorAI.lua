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
local MapGeneration = require(script.Parent.MapGeneration)

-- Predator behavior states
export type PredatorBehaviorState =
  "roaming"
  | "stalking"
  | "approaching"
  | "attacking"
  | "fleeing"
  | "cautious"

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
  -- Patrol behavior fields (when attacking)
  patrolTarget: Vector3?,
  patrolCooldown: number?, -- Time until next patrol movement
  targetChickenSpot: number?, -- Spot index of chicken being targeted
  noChickensTime: number?, -- Time when no chickens was first detected
  coopCenter: Vector3?, -- Center of the coop for patrol bounds
  -- AI improvement fields
  currentHealth: number?, -- Current health (for flee logic)
  maxHealth: number?, -- Max health (for flee threshold)
  lastDamageTime: number?, -- When predator last took damage
  fleeTarget: Vector3?, -- Position to flee towards
  fleeEndTime: number?, -- When fleeing ends
  nearbyPlayerDistance: number?, -- Distance to nearest player
  playerHasWeapon: boolean?, -- Whether nearby player has weapon
  cautiousEndTime: number?, -- When cautious state ends
  shieldDetected: boolean?, -- Whether a shield is detected nearby
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

-- Patrol behavior constants (when attacking at coop)
local PATROL_RADIUS = 10 -- studs - how far predator wanders from coop center
local PATROL_COOLDOWN_MIN = 1.5 -- minimum seconds between patrol movements
local PATROL_COOLDOWN_MAX = 3.5 -- maximum seconds between patrol movements
local PATROL_SPEED_MULTIPLIER = 0.5 -- slower while patrolling
local CHICKEN_APPROACH_SPEED = 0.7 -- speed when approaching a specific chicken
local NO_CHICKENS_DESPAWN_TIME = 8 -- seconds to wait before despawning if no chickens

-- AI improvement constants
local FLEE_HEALTH_THRESHOLD = 0.3 -- Flee when health drops below 30%
local FLEE_DURATION = 4 -- Seconds to flee before reassessing
local FLEE_SPEED_MULTIPLIER = 1.4 -- Faster when fleeing
local FLEE_DISTANCE = 25 -- How far to flee
local PLAYER_DETECTION_RANGE = 20 -- Range to detect nearby players
local WEAPON_DETECTION_RANGE = 15 -- Range to detect player weapons
local CAUTIOUS_DURATION = 3 -- Seconds to remain cautious
local CAUTIOUS_SPEED_MULTIPLIER = 0.4 -- Much slower when cautious
local CIRCLING_RADIUS = 8 -- Radius for circling behavior
local CIRCLING_SPEED_MULTIPLIER = 0.6 -- Speed when circling
local DAMAGE_MEMORY_DURATION = 5 -- Seconds to remember being damaged

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
-- If targetChickenPosition is provided, predator will walk toward that chicken instead of coop center
function PredatorAI.registerPredator(
  aiState: PredatorAIState,
  predatorId: string,
  predatorType: string,
  sectionCenter: Vector3,
  preferredEdge: string?,
  targetChickenPosition: Vector3?
): PredatorPosition
  local spawnPos = PredatorAI.calculateSpawnPosition(sectionCenter, preferredEdge)
  -- Use target chicken position if provided, otherwise fall back to coop center
  local targetPos = targetChickenPosition or PredatorAI.calculateTargetPosition(sectionCenter)
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

-- Generate a random patrol position within the coop area
function PredatorAI.generatePatrolPosition(coopCenter: Vector3, currentPosition: Vector3): Vector3
  -- Generate random offset from coop center
  local angle = math.random() * math.pi * 2
  local distance = math.random() * PATROL_RADIUS

  local targetX = coopCenter.X + math.cos(angle) * distance
  local targetZ = coopCenter.Z + math.sin(angle) * distance

  return Vector3.new(targetX, coopCenter.Y + 1, targetZ)
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

-- Update player awareness for a predator
function PredatorAI.updatePlayerAwareness(
  aiState: PredatorAIState,
  predatorId: string,
  playerPosition: Vector3?,
  playerHasWeapon: boolean?,
  currentTime: number
): {
  detected: boolean,
  distance: number?,
  becameCautious: boolean,
}
  local position = aiState.positions[predatorId]
  if not position then
    return { detected = false, distance = nil, becameCautious = false }
  end

  -- No player nearby
  if not playerPosition then
    position.nearbyPlayerDistance = nil
    position.playerHasWeapon = nil
    return { detected = false, distance = nil, becameCautious = false }
  end

  local distance = (playerPosition - position.currentPosition).Magnitude
  position.nearbyPlayerDistance = distance
  position.playerHasWeapon = playerHasWeapon or false

  local detected = distance <= PLAYER_DETECTION_RANGE
  local becameCautious = false

  -- If player has weapon and is close, become cautious
  if
    detected
    and playerHasWeapon
    and distance <= WEAPON_DETECTION_RANGE
    and position.behaviorState ~= "fleeing"
    and position.behaviorState ~= "cautious"
  then
    position.behaviorState = "cautious"
    position.cautiousEndTime = currentTime + CAUTIOUS_DURATION
    position.walkSpeed = PredatorAI.getWalkSpeed(position.predatorType) * CAUTIOUS_SPEED_MULTIPLIER
    becameCautious = true
  end

  return { detected = detected, distance = distance, becameCautious = becameCautious }
end

-- Check if predator should flee (health below threshold)
function PredatorAI.shouldFlee(
  aiState: PredatorAIState,
  predatorId: string,
  currentHealth: number?,
  maxHealth: number?
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- Already fleeing
  if position.behaviorState == "fleeing" then
    return false
  end

  -- Update health tracking
  if currentHealth ~= nil then
    position.currentHealth = currentHealth
  end
  if maxHealth ~= nil then
    position.maxHealth = maxHealth
  end

  -- Check health threshold
  local health = position.currentHealth or 1
  local max = position.maxHealth or 1
  local healthPercent = health / max

  return healthPercent <= FLEE_HEALTH_THRESHOLD and health > 0
end

-- Start fleeing behavior
function PredatorAI.startFleeing(
  aiState: PredatorAIState,
  predatorId: string,
  currentTime: number,
  awayFromPosition: Vector3?
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  position.behaviorState = "fleeing"
  position.fleeEndTime = currentTime + FLEE_DURATION
  position.lastDamageTime = currentTime

  -- Calculate flee direction (away from damage source or random)
  local fleeDirection: Vector3
  if awayFromPosition then
    local towardsThreat = awayFromPosition - position.currentPosition
    if towardsThreat.Magnitude > 0 then
      fleeDirection = -towardsThreat.Unit
    else
      -- Random direction if at same position
      local angle = math.random() * math.pi * 2
      fleeDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
    end
  else
    -- Random flee direction
    local angle = math.random() * math.pi * 2
    fleeDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
  end

  position.fleeTarget = position.currentPosition + fleeDirection * FLEE_DISTANCE
  position.walkSpeed = PredatorAI.getWalkSpeed(position.predatorType) * FLEE_SPEED_MULTIPLIER
  position.facingDirection = fleeDirection

  return true
end

-- Update fleeing behavior
function PredatorAI.updateFleeing(
  aiState: PredatorAIState,
  predatorId: string,
  deltaTime: number,
  currentTime: number
): {
  stillFleeing: boolean,
  reachedFleeTarget: boolean,
}
  local position = aiState.positions[predatorId]
  if not position or position.behaviorState ~= "fleeing" then
    return { stillFleeing = false, reachedFleeTarget = false }
  end

  -- Check if flee time expired
  if position.fleeEndTime and currentTime >= position.fleeEndTime then
    -- Return to previous behavior (roaming is safe default)
    position.behaviorState = "roaming"
    position.walkSpeed = PredatorAI.getWalkSpeed(position.predatorType) * ROAM_SPEED_MULTIPLIER
    position.fleeTarget = nil
    position.fleeEndTime = nil
    -- Generate new roam target
    position.roamTarget = PredatorAI.generateRoamPosition(aiState, position.currentPosition)
    position.roamEndTime = currentTime + ROAM_DURATION_MIN
    return { stillFleeing = false, reachedFleeTarget = false }
  end

  -- Move towards flee target
  local fleeTarget = position.fleeTarget
  if fleeTarget then
    local toTarget = fleeTarget - position.currentPosition
    local distance = toTarget.Magnitude

    if distance <= ARRIVAL_THRESHOLD then
      -- Reached flee target, continue fleeing in same direction
      local continueDirection = position.facingDirection
      position.fleeTarget = position.currentPosition + continueDirection * FLEE_DISTANCE
      return { stillFleeing = true, reachedFleeTarget = true }
    else
      local direction = toTarget.Unit
      local moveDistance = position.walkSpeed * deltaTime

      if moveDistance >= distance then
        position.currentPosition = fleeTarget
      else
        position.currentPosition = position.currentPosition + direction * moveDistance
      end
      position.facingDirection = direction
    end
  end

  return { stillFleeing = true, reachedFleeTarget = false }
end

-- Update cautious behavior
function PredatorAI.updateCautious(
  aiState: PredatorAIState,
  predatorId: string,
  deltaTime: number,
  currentTime: number
): {
  stillCautious: boolean,
  circlingPosition: Vector3?,
}
  local position = aiState.positions[predatorId]
  if not position or position.behaviorState ~= "cautious" then
    return { stillCautious = false, circlingPosition = nil }
  end

  -- Check if cautious time expired
  if position.cautiousEndTime and currentTime >= position.cautiousEndTime then
    -- Return to approaching if has target, otherwise roaming
    if position.targetSectionIndex then
      position.behaviorState = "approaching"
      position.walkSpeed = PredatorAI.getWalkSpeed(position.predatorType)
    else
      position.behaviorState = "roaming"
      position.walkSpeed = PredatorAI.getWalkSpeed(position.predatorType) * ROAM_SPEED_MULTIPLIER
      position.roamTarget = PredatorAI.generateRoamPosition(aiState, position.currentPosition)
      position.roamEndTime = currentTime + ROAM_DURATION_MIN
    end
    position.cautiousEndTime = nil
    return { stillCautious = false, circlingPosition = nil }
  end

  -- Circling behavior - move in arc around target
  local targetPos = position.targetPosition
  local toTarget = targetPos - position.currentPosition
  local distanceToTarget = toTarget.Magnitude

  if distanceToTarget > 0 then
    -- Calculate perpendicular direction for circling
    local perpendicular = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
    -- Alternate direction based on predator ID hash
    local dirMod = (string.byte(position.id, 6) or 0) % 2 == 0 and 1 or -1
    local circleDirection = perpendicular * dirMod

    local moveDistance = position.walkSpeed * deltaTime
    local newPosition = position.currentPosition + circleDirection * moveDistance

    position.currentPosition = newPosition
    position.facingDirection = toTarget.Unit

    return { stillCautious = true, circlingPosition = newPosition }
  end

  return { stillCautious = true, circlingPosition = nil }
end

-- Handle damage to predator (triggers flee check)
function PredatorAI.onDamage(
  aiState: PredatorAIState,
  predatorId: string,
  currentHealth: number,
  maxHealth: number,
  damageSourcePosition: Vector3?,
  currentTime: number
): {
  startedFleeing: boolean,
  healthPercent: number,
}
  local position = aiState.positions[predatorId]
  if not position then
    return { startedFleeing = false, healthPercent = 0 }
  end

  position.currentHealth = currentHealth
  position.maxHealth = maxHealth
  position.lastDamageTime = currentTime

  local healthPercent = currentHealth / maxHealth

  -- Check if should start fleeing
  if PredatorAI.shouldFlee(aiState, predatorId, currentHealth, maxHealth) then
    PredatorAI.startFleeing(aiState, predatorId, currentTime, damageSourcePosition)
    return { startedFleeing = true, healthPercent = healthPercent }
  end

  return { startedFleeing = false, healthPercent = healthPercent }
end

-- Update shield awareness for predator
function PredatorAI.updateShieldAwareness(
  aiState: PredatorAIState,
  predatorId: string,
  shieldActive: boolean,
  shieldCenter: Vector3?,
  currentTime: number
): {
  retreating: boolean,
  blocked: boolean,
}
  local position = aiState.positions[predatorId]
  if not position then
    return { retreating = false, blocked = false }
  end

  position.shieldDetected = shieldActive

  if not shieldActive or not shieldCenter then
    return { retreating = false, blocked = false }
  end

  local distanceToShield = (shieldCenter - position.currentPosition).Magnitude

  -- If approaching a shielded section, retreat
  if position.behaviorState == "approaching" or position.behaviorState == "attacking" then
    -- Check if our target is within the shielded area
    local targetDistance = (shieldCenter - position.targetPosition).Magnitude
    if targetDistance < 30 then -- Shield covers a reasonable radius
      -- Start fleeing away from shield
      PredatorAI.startFleeing(aiState, predatorId, currentTime, shieldCenter)
      return { retreating = true, blocked = true }
    end
  end

  return { retreating = false, blocked = false }
end

-- Check if predator is fleeing
function PredatorAI.isFleeing(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  return position ~= nil and position.behaviorState == "fleeing"
end

-- Check if predator is cautious
function PredatorAI.isCautious(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  return position ~= nil and position.behaviorState == "cautious"
end

-- Get predator aggression level (higher threat = more aggressive)
function PredatorAI.getAggressionLevel(predatorType: string): number
  local config = PredatorConfig.get(predatorType)
  if not config then
    return 1
  end

  local aggressionByThreat = {
    Minor = 1,
    Moderate = 2,
    Dangerous = 3,
    Severe = 4,
    Deadly = 5,
    Catastrophic = 6,
  }

  return aggressionByThreat[config.threatLevel] or 1
end

-- Check if predator should ignore caution (high aggression)
function PredatorAI.shouldIgnoreCaution(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  local aggression = PredatorAI.getAggressionLevel(position.predatorType)
  -- Severe and above (4+) have 50% chance to ignore caution
  if aggression >= 4 then
    return math.random() < 0.5
  end
  -- Dangerous (3) has 25% chance
  if aggression >= 3 then
    return math.random() < 0.25
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
  deltaTime: number,
  currentTime: number?
): PredatorPosition?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end

  local time = currentTime or os.clock()

  -- Handle fleeing behavior first (highest priority)
  if position.behaviorState == "fleeing" then
    PredatorAI.updateFleeing(aiState, predatorId, deltaTime, time)
    return position
  end

  -- Handle cautious behavior
  if position.behaviorState == "cautious" then
    PredatorAI.updateCautious(aiState, predatorId, deltaTime, time)
    return position
  end

  -- Roaming predators are handled by updateRoaming
  if position.behaviorState == "roaming" then
    return position
  end

  -- Stalking predators don't move, just face target
  if position.behaviorState == "stalking" then
    return position
  end

  -- Handle attacking/patrol behavior
  if position.hasReachedTarget and position.behaviorState == "attacking" then
    -- Store coop center if not already stored
    if not position.coopCenter then
      position.coopCenter = position.targetPosition
    end

    -- Update patrol behavior
    local time = currentTime or os.clock()

    -- Check if we need to generate new patrol target
    if
      not position.patrolTarget or (position.patrolCooldown and time >= position.patrolCooldown)
    then
      position.patrolTarget =
        PredatorAI.generatePatrolPosition(position.coopCenter, position.currentPosition)
      -- Set next patrol cooldown
      local cooldownDuration = PATROL_COOLDOWN_MIN
        + math.random() * (PATROL_COOLDOWN_MAX - PATROL_COOLDOWN_MIN)
      position.patrolCooldown = time + cooldownDuration
    end

    -- Move towards patrol target (or targeted chicken spot)
    local moveTarget = position.patrolTarget
    if moveTarget then
      local toTarget = moveTarget - position.currentPosition
      local distance = toTarget.Magnitude

      if distance > ARRIVAL_THRESHOLD then
        local direction = toTarget.Unit
        local patrolSpeed = PredatorAI.getWalkSpeed(position.predatorType) * PATROL_SPEED_MULTIPLIER
        -- Use faster speed if approaching a chicken
        if position.targetChickenSpot then
          patrolSpeed = PredatorAI.getWalkSpeed(position.predatorType) * CHICKEN_APPROACH_SPEED
        end
        local moveDistance = patrolSpeed * deltaTime

        if moveDistance >= distance then
          position.currentPosition = moveTarget
          -- Reached patrol target, clear it to generate a new one next update
          position.patrolTarget = nil
        else
          position.currentPosition = position.currentPosition + direction * moveDistance
        end
        position.facingDirection = direction
      else
        -- Reached patrol target
        position.patrolTarget = nil
      end
    end

    return position
  end

  -- Calculate movement towards coop (approaching state)
  local toTarget = position.targetPosition - position.currentPosition
  local distance = toTarget.Magnitude

  -- Check if arrived
  if distance <= ARRIVAL_THRESHOLD then
    position.hasReachedTarget = true
    position.currentPosition = position.targetPosition
    position.behaviorState = "attacking"
    position.coopCenter = position.targetPosition
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
    position.coopCenter = position.targetPosition
  else
    position.currentPosition = position.currentPosition + direction * moveDistance
  end

  position.facingDirection = direction

  return position
end

-- Update all predator positions
function PredatorAI.updateAll(
  aiState: PredatorAIState,
  deltaTime: number,
  currentTime: number?
): { [string]: PredatorPosition }
  local updated = {}
  local time = currentTime or os.clock()

  for predatorId, _ in pairs(aiState.positions) do
    local position = PredatorAI.updatePosition(aiState, predatorId, deltaTime, time)
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

-- Check if a predator has entered the target section boundary
-- This triggers attacking state earlier than reaching the coop center
function PredatorAI.hasEnteredSection(aiState: PredatorAIState, predatorId: string): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- If already reached coop, definitely in section
  if position.hasReachedTarget then
    return true
  end

  -- Need target section index to check bounds
  local sectionIndex = position.targetSectionIndex
  if not sectionIndex then
    return false
  end

  -- Get section center position
  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    return false
  end

  -- Convert to Vector3 table format for PlayerSection.isPositionInSection
  local predatorPos = {
    x = position.currentPosition.X,
    y = position.currentPosition.Y,
    z = position.currentPosition.Z,
  }

  return PlayerSection.isPositionInSection(predatorPos, sectionCenter)
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
  fleeing: number,
  cautious: number,
}
  local roaming = 0
  local stalking = 0
  local approaching = 0
  local atCoop = 0
  local fleeing = 0
  local cautious = 0

  for _, position in pairs(aiState.positions) do
    if position.behaviorState == "roaming" then
      roaming = roaming + 1
    elseif position.behaviorState == "stalking" then
      stalking = stalking + 1
    elseif position.behaviorState == "fleeing" then
      fleeing = fleeing + 1
    elseif position.behaviorState == "cautious" then
      cautious = cautious + 1
    elseif position.hasReachedTarget then
      atCoop = atCoop + 1
    else
      approaching = approaching + 1
    end
  end

  return {
    totalActive = roaming + stalking + approaching + atCoop + fleeing + cautious,
    roaming = roaming,
    stalking = stalking,
    approaching = approaching,
    atCoop = atCoop,
    fleeing = fleeing,
    cautious = cautious,
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
  isFleeing: boolean,
  isCautious: boolean,
  healthPercent: number?,
}?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end

  local healthPercent: number? = nil
  if position.currentHealth and position.maxHealth and position.maxHealth > 0 then
    healthPercent = position.currentHealth / position.maxHealth
  end

  return {
    position = position.currentPosition,
    target = position.targetPosition,
    progress = PredatorAI.getProgress(aiState, predatorId),
    hasReached = position.hasReachedTarget,
    behaviorState = position.behaviorState,
    isStalking = position.isStalking,
    isFleeing = position.behaviorState == "fleeing",
    isCautious = position.behaviorState == "cautious",
    healthPercent = healthPercent,
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

-- Set a target chicken spot for the predator to approach
function PredatorAI.setTargetChicken(
  aiState: PredatorAIState,
  predatorId: string,
  spotIndex: number?,
  spotPosition: Vector3?
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  position.targetChickenSpot = spotIndex

  -- If a position is provided, set it as the patrol target for approach
  if spotPosition and spotIndex then
    position.patrolTarget = spotPosition
    position.patrolCooldown = nil -- Clear cooldown to allow immediate approach
  else
    position.patrolTarget = nil
  end

  return true
end

-- Get the target chicken spot for a predator
function PredatorAI.getTargetChicken(aiState: PredatorAIState, predatorId: string): number?
  local position = aiState.positions[predatorId]
  if not position then
    return nil
  end
  return position.targetChickenSpot
end

-- Update the approach target position for a predator (for re-targeting or following moving chickens)
function PredatorAI.updateApproachTarget(
  aiState: PredatorAIState,
  predatorId: string,
  newTargetPosition: Vector3
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- Only update if predator is still approaching (not yet at coop)
  if position.hasReachedTarget then
    return false
  end

  position.targetPosition = newTargetPosition
  -- Update facing direction
  local toTarget = newTargetPosition - position.currentPosition
  if toTarget.Magnitude > 0 then
    position.facingDirection = toTarget.Unit
  end

  return true
end

-- Update chicken presence for predator (call when attacking)
-- Returns true if predator should despawn due to no chickens for too long
-- isEngagingPlayer: if true, predator is actively attacking a player and should not despawn
function PredatorAI.updateChickenPresence(
  aiState: PredatorAIState,
  predatorId: string,
  hasChickens: boolean,
  currentTime: number,
  isEngagingPlayer: boolean?
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- Only track for predators that are attacking
  if position.behaviorState ~= "attacking" then
    position.noChickensTime = nil
    return false
  end

  -- If predator is engaging a player, don't despawn (treat same as having chickens)
  local engagingPlayer = isEngagingPlayer or false
  if hasChickens or engagingPlayer then
    -- Reset the no-chickens timer
    position.noChickensTime = nil
    return false
  else
    -- No chickens present and not engaging player
    if not position.noChickensTime then
      -- First time noticing no chickens
      position.noChickensTime = currentTime
      return false
    else
      -- Check if enough time has passed
      local elapsed = currentTime - position.noChickensTime
      return elapsed >= NO_CHICKENS_DESPAWN_TIME
    end
  end
end

-- Check if predator should despawn due to no chickens
function PredatorAI.shouldDespawn(
  aiState: PredatorAIState,
  predatorId: string,
  currentTime: number
): boolean
  local position = aiState.positions[predatorId]
  if not position then
    return false
  end

  -- Only consider despawning for attacking predators
  if position.behaviorState ~= "attacking" then
    return false
  end

  if not position.noChickensTime then
    return false
  end

  local elapsed = currentTime - position.noChickensTime
  return elapsed >= NO_CHICKENS_DESPAWN_TIME
end

-- Get despawn time remaining (for UI/debugging)
function PredatorAI.getDespawnTimeRemaining(
  aiState: PredatorAIState,
  predatorId: string,
  currentTime: number
): number?
  local position = aiState.positions[predatorId]
  if not position or not position.noChickensTime then
    return nil
  end

  local elapsed = currentTime - position.noChickensTime
  local remaining = NO_CHICKENS_DESPAWN_TIME - elapsed
  return math.max(0, remaining)
end

return PredatorAI
