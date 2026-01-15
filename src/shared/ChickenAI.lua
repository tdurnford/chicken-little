--[[
	ChickenAI Module
	Handles chicken wandering behavior for both:
	- Wild chickens in the neutral zone
	- Player-owned chickens free-roaming in their owner's section
	Chickens wander randomly, changing direction periodically,
	and staying within their designated boundaries.
]]

local ChickenAI = {}

-- Import dependencies
local ChickenConfig = require(script.Parent.ChickenConfig)
local PlayerSection = require(script.Parent.PlayerSection)

-- Type definitions
export type ChickenPosition = {
  id: string,
  chickenType: string,
  currentPosition: Vector3,
  targetPosition: Vector3,
  walkSpeed: number,
  facingDirection: Vector3,
  isIdle: boolean,
  idleEndTime: number,
  nextDirectionChangeTime: number,
  stateChanged: boolean, -- True when target/idle state changed (needs client sync)
}

export type ChickenAIState = {
  positions: { [string]: ChickenPosition },
  neutralZoneCenter: Vector3,
  neutralZoneSize: number,
  -- Section-based bounds (for player-owned chickens)
  sectionCenter: PlayerSection.Vector3?,
  isPlayerSection: boolean,
}

-- Constants
local DEFAULT_WALK_SPEED = 4 -- studs per second (slower than predators)
local MIN_IDLE_TIME = 1 -- minimum seconds to idle
local MAX_IDLE_TIME = 4 -- maximum seconds to idle
local MIN_WALK_TIME = 2 -- minimum seconds before changing direction
local MAX_WALK_TIME = 6 -- maximum seconds before changing direction
local BOUNDARY_MARGIN = 2 -- studs from edge to start turning back
local TARGET_REACH_THRESHOLD = 1 -- studs - how close to count as "reached"

-- Walk speed multipliers by rarity (rarer chickens are slightly faster)
local RARITY_SPEED_MULTIPLIER: { [ChickenConfig.Rarity]: number } = {
  Common = 0.8,
  Uncommon = 0.9,
  Rare = 1.0,
  Epic = 1.1,
  Legendary = 1.2,
  Mythic = 1.3,
}

-- Create initial AI state
function ChickenAI.createState(
  neutralZoneCenter: Vector3?,
  neutralZoneSize: number?
): ChickenAIState
  return {
    positions = {},
    neutralZoneCenter = neutralZoneCenter or Vector3.new(0, 0, 0),
    neutralZoneSize = neutralZoneSize or 32,
    sectionCenter = nil,
    isPlayerSection = false,
  }
end

-- Create AI state for a player's section (for owned chickens)
function ChickenAI.createSectionState(sectionCenter: PlayerSection.Vector3): ChickenAIState
  local sectionSize = PlayerSection.getSectionSize()
  return {
    positions = {},
    -- Use section bounds instead of neutral zone
    neutralZoneCenter = Vector3.new(sectionCenter.x, sectionCenter.y, sectionCenter.z),
    neutralZoneSize = math.min(sectionSize.x, sectionSize.z) - 4, -- Slight margin from walls
    sectionCenter = sectionCenter,
    isPlayerSection = true,
  }
end

-- Get walk speed for a chicken type based on rarity
function ChickenAI.getWalkSpeed(chickenType: string): number
  local config = ChickenConfig.get(chickenType)
  if not config then
    return DEFAULT_WALK_SPEED
  end

  local multiplier = RARITY_SPEED_MULTIPLIER[config.rarity] or 1.0
  return DEFAULT_WALK_SPEED * multiplier
end

-- Check if a position is within the neutral zone boundaries
function ChickenAI.isWithinBounds(aiState: ChickenAIState, position: Vector3): boolean
  local halfSize = aiState.neutralZoneSize / 2
  local center = aiState.neutralZoneCenter

  return position.X >= center.X - halfSize
    and position.X <= center.X + halfSize
    and position.Z >= center.Z - halfSize
    and position.Z <= center.Z + halfSize
end

-- Clamp a position to stay within neutral zone boundaries
function ChickenAI.clampToBounds(aiState: ChickenAIState, position: Vector3): Vector3
  local halfSize = aiState.neutralZoneSize / 2 - BOUNDARY_MARGIN
  local center = aiState.neutralZoneCenter

  return Vector3.new(
    math.clamp(position.X, center.X - halfSize, center.X + halfSize),
    position.Y,
    math.clamp(position.Z, center.Z - halfSize, center.Z + halfSize)
  )
end

-- Generate a random target position within the neutral zone
function ChickenAI.generateRandomTarget(aiState: ChickenAIState, currentPosition: Vector3): Vector3
  local halfSize = aiState.neutralZoneSize / 2 - BOUNDARY_MARGIN
  local center = aiState.neutralZoneCenter

  -- Generate random offset from current position (between 5-15 studs away)
  local distance = 5 + math.random() * 10
  local angle = math.random() * math.pi * 2

  local targetX = currentPosition.X + math.cos(angle) * distance
  local targetZ = currentPosition.Z + math.sin(angle) * distance

  -- Clamp to bounds
  targetX = math.clamp(targetX, center.X - halfSize, center.X + halfSize)
  targetZ = math.clamp(targetZ, center.Z - halfSize, center.Z + halfSize)

  return Vector3.new(targetX, currentPosition.Y, targetZ)
end

-- Generate a random idle duration
local function getRandomIdleDuration(): number
  return MIN_IDLE_TIME + math.random() * (MAX_IDLE_TIME - MIN_IDLE_TIME)
end

-- Generate a random walk duration
local function getRandomWalkDuration(): number
  return MIN_WALK_TIME + math.random() * (MAX_WALK_TIME - MIN_WALK_TIME)
end

-- Register a chicken for AI tracking
function ChickenAI.registerChicken(
  aiState: ChickenAIState,
  chickenId: string,
  chickenType: string,
  spawnPosition: Vector3,
  currentTime: number
): ChickenPosition
  local walkSpeed = ChickenAI.getWalkSpeed(chickenType)
  local targetPosition = ChickenAI.generateRandomTarget(aiState, spawnPosition)

  -- Calculate initial facing direction
  local direction = (targetPosition - spawnPosition)
  if direction.Magnitude > 0 then
    direction = direction.Unit
  else
    direction = Vector3.new(1, 0, 0)
  end

  local position: ChickenPosition = {
    id = chickenId,
    chickenType = chickenType,
    currentPosition = spawnPosition,
    targetPosition = targetPosition,
    walkSpeed = walkSpeed,
    facingDirection = direction,
    isIdle = false,
    idleEndTime = 0,
    nextDirectionChangeTime = currentTime + getRandomWalkDuration(),
    stateChanged = true, -- New chicken needs initial sync
  }

  aiState.positions[chickenId] = position
  return position
end

-- Update a chicken's position based on deltaTime
function ChickenAI.updatePosition(
  aiState: ChickenAIState,
  chickenId: string,
  deltaTime: number,
  currentTime: number
): ChickenPosition?
  local position = aiState.positions[chickenId]
  if not position then
    return nil
  end

  -- Handle idle state
  if position.isIdle then
    if currentTime >= position.idleEndTime then
      -- End idle, start walking again
      position.isIdle = false
      position.targetPosition = ChickenAI.generateRandomTarget(aiState, position.currentPosition)
      position.nextDirectionChangeTime = currentTime + getRandomWalkDuration()

      local direction = (position.targetPosition - position.currentPosition)
      if direction.Magnitude > 0 then
        position.facingDirection = direction.Unit
      end
      position.stateChanged = true -- Notify clients to start walking to new target
    end
    return position
  end

  -- Check if we should change direction
  if currentTime >= position.nextDirectionChangeTime then
    -- Random chance to idle or just change direction
    if math.random() < 0.4 then
      -- Start idling
      position.isIdle = true
      position.idleEndTime = currentTime + getRandomIdleDuration()
      position.stateChanged = true -- Notify clients to stop walking
      return position
    else
      -- Just change direction
      position.targetPosition = ChickenAI.generateRandomTarget(aiState, position.currentPosition)
      position.nextDirectionChangeTime = currentTime + getRandomWalkDuration()

      local direction = (position.targetPosition - position.currentPosition)
      if direction.Magnitude > 0 then
        position.facingDirection = direction.Unit
      end
      position.stateChanged = true -- Notify clients of new target
    end
  end

  -- Calculate movement toward target
  local toTarget = position.targetPosition - position.currentPosition
  local distance = toTarget.Magnitude

  -- Check if reached target
  if distance <= TARGET_REACH_THRESHOLD then
    -- Start idling at destination
    position.isIdle = true
    position.idleEndTime = currentTime + getRandomIdleDuration()
    position.stateChanged = true -- Notify clients chicken stopped
    return position
  end

  -- Move towards target
  local direction = toTarget.Unit
  local moveDistance = position.walkSpeed * deltaTime

  -- Don't overshoot
  if moveDistance >= distance then
    position.currentPosition = position.targetPosition
    position.isIdle = true
    position.idleEndTime = currentTime + getRandomIdleDuration()
    position.stateChanged = true -- Notify clients chicken stopped
  else
    position.currentPosition = position.currentPosition + direction * moveDistance
    -- Ensure we stay in bounds
    position.currentPosition = ChickenAI.clampToBounds(aiState, position.currentPosition)
  end

  position.facingDirection = direction

  return position
end

-- Update all chicken positions
function ChickenAI.updateAll(
  aiState: ChickenAIState,
  deltaTime: number,
  currentTime: number
): { [string]: ChickenPosition }
  local updated = {}

  for chickenId, _ in pairs(aiState.positions) do
    local position = ChickenAI.updatePosition(aiState, chickenId, deltaTime, currentTime)
    if position then
      updated[chickenId] = position
    end
  end

  return updated
end

-- Get chicken position
function ChickenAI.getPosition(aiState: ChickenAIState, chickenId: string): ChickenPosition?
  return aiState.positions[chickenId]
end

-- Check if a chicken is currently idle
function ChickenAI.isIdle(aiState: ChickenAIState, chickenId: string): boolean
  local position = aiState.positions[chickenId]
  if not position then
    return false
  end
  return position.isIdle
end

-- Unregister a chicken (when claimed, despawned, etc.)
function ChickenAI.unregisterChicken(aiState: ChickenAIState, chickenId: string): boolean
  if aiState.positions[chickenId] then
    aiState.positions[chickenId] = nil
    return true
  end
  return false
end

-- Get all active chicken IDs
function ChickenAI.getActiveChickenIds(aiState: ChickenAIState): { string }
  local ids = {}
  for id, _ in pairs(aiState.positions) do
    table.insert(ids, id)
  end
  return ids
end

-- Get count of active chickens being tracked
function ChickenAI.getActiveCount(aiState: ChickenAIState): number
  local count = 0
  for _ in pairs(aiState.positions) do
    count = count + 1
  end
  return count
end

-- Reset AI state
function ChickenAI.reset(aiState: ChickenAIState)
  aiState.positions = {}
end

-- Get all positions for syncing to clients
function ChickenAI.getAllPositions(aiState: ChickenAIState): { [string]: Vector3 }
  local positions = {}
  for id, position in pairs(aiState.positions) do
    positions[id] = position.currentPosition
  end
  return positions
end

-- Get position info for a single chicken (for client sync)
-- Now includes walkSpeed for client-side movement interpolation
function ChickenAI.getPositionInfo(
  aiState: ChickenAIState,
  chickenId: string
): {
  position: Vector3,
  target: Vector3,
  facingDirection: Vector3,
  isIdle: boolean,
  walkSpeed: number,
}?
  local position = aiState.positions[chickenId]
  if not position then
    return nil
  end

  return {
    position = position.currentPosition,
    target = position.targetPosition,
    facingDirection = position.facingDirection,
    isIdle = position.isIdle,
    walkSpeed = position.walkSpeed,
  }
end

-- Get all chickens that have changed state since last sync
-- Returns a list of chickens with their full state info and clears stateChanged flags
function ChickenAI.getChangedChickens(aiState: ChickenAIState): {
  {
    id: string,
    position: Vector3,
    target: Vector3,
    facingDirection: Vector3,
    isIdle: boolean,
    walkSpeed: number,
  }
}
  local changed = {}

  for id, position in pairs(aiState.positions) do
    if position.stateChanged then
      table.insert(changed, {
        id = id,
        position = position.currentPosition,
        target = position.targetPosition,
        facingDirection = position.facingDirection,
        isIdle = position.isIdle,
        walkSpeed = position.walkSpeed,
      })
      position.stateChanged = false -- Clear the flag after collecting
    end
  end

  return changed
end

-- Clear stateChanged flags for all chickens (used after bulk sync)
function ChickenAI.clearChangedFlags(aiState: ChickenAIState)
  for _, position in pairs(aiState.positions) do
    position.stateChanged = false
  end
end

-- Update the spawn position of a chicken (for when RandomChickenSpawn spawns it)
function ChickenAI.updateSpawnPosition(
  aiState: ChickenAIState,
  chickenId: string,
  newPosition: Vector3
): boolean
  local position = aiState.positions[chickenId]
  if not position then
    return false
  end

  position.currentPosition = newPosition
  position.targetPosition = ChickenAI.generateRandomTarget(aiState, newPosition)
  return true
end

-- Configure the neutral zone bounds
function ChickenAI.setNeutralZone(aiState: ChickenAIState, center: Vector3, size: number)
  aiState.neutralZoneCenter = center
  aiState.neutralZoneSize = size
end

-- Get summary for debugging
function ChickenAI.getSummary(aiState: ChickenAIState): {
  totalActive: number,
  walking: number,
  idle: number,
}
  local walking = 0
  local idle = 0

  for _, position in pairs(aiState.positions) do
    if position.isIdle then
      idle = idle + 1
    else
      walking = walking + 1
    end
  end

  return {
    totalActive = walking + idle,
    walking = walking,
    idle = idle,
  }
end

return ChickenAI
