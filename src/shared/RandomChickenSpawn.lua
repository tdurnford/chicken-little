--[[
	RandomChickenSpawn Module
	Handles periodic spawning of rare chickens in a neutral area
	for players to compete over. First player to grab the chicken claims it.
	
	Pot/Streak behavior:
	- When a player "captures the pot" (claims a spawned chicken), their potStreak increases
	- When a player "steals the pot" (steals chicken from another player via ChickenStealing),
	  their potStreak stays the same (doesn't increase or reset)
]]

local ChickenConfig = require(script.Parent.ChickenConfig)
local PlayerData = require(script.Parent.PlayerData)

local RandomChickenSpawn = {}

-- Initialize random seed with high-precision time components to ensure
-- unique random sequences across server restarts
math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 1000000))
-- Warm up the RNG by discarding first few values (improves randomness)
for _ = 1, 3 do
  math.random()
end

-- Constants for spawn events
local DEFAULT_SPAWN_INTERVAL_MIN = 120 -- 2 minutes minimum between spawns
local DEFAULT_SPAWN_INTERVAL_MAX = 300 -- 5 minutes maximum between spawns
local DEFAULT_DESPAWN_TIME = 30 -- seconds before unclaimed chicken despawns
local NEUTRAL_ZONE_SIZE = 32 -- studs, size of neutral spawn area
local CLAIM_RANGE = 12 -- studs, how close player must be to claim (generous to account for movement)

-- Spawn zone type for multi-zone spawning (spawn across entire map)
export type SpawnZone = {
  center: Vector3,
  size: number,
}

-- Rarity weights for spawn selection (higher = more common in events)
local SPAWN_RARITY_WEIGHTS: { [ChickenConfig.Rarity]: number } = {
  Common = 0, -- Common chickens don't spawn in events
  Uncommon = 5,
  Rare = 30,
  Epic = 40,
  Legendary = 20,
  Mythic = 5,
}

-- Minimum total playtime (seconds) required to unlock each rarity tier in random spawns
-- This prevents new players from getting overpowered chickens too early
local RARITY_PLAYTIME_REQUIREMENTS: { [ChickenConfig.Rarity]: number } = {
  Common = 0, -- Always available
  Uncommon = 0, -- Always available
  Rare = 300, -- 5 minutes of playtime
  Epic = 900, -- 15 minutes of playtime
  Legendary = 1800, -- 30 minutes of playtime
  Mythic = 3600, -- 60 minutes of playtime
}

-- Ordered list of rarities from lowest to highest for comparison
local RARITY_ORDER: { ChickenConfig.Rarity } =
  { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- Get the numeric index for a rarity (higher = rarer)
local function getRarityIndex(rarity: ChickenConfig.Rarity): number
  for i, r in ipairs(RARITY_ORDER) do
    if r == rarity then
      return i
    end
  end
  return 1
end

-- Determine the maximum rarity a player can receive based on their total playtime
function RandomChickenSpawn.getMaxAllowedRarity(totalPlayTime: number): ChickenConfig.Rarity
  local maxRarity: ChickenConfig.Rarity = "Common"
  for _, rarity in ipairs(RARITY_ORDER) do
    local requirement = RARITY_PLAYTIME_REQUIREMENTS[rarity] or 0
    if totalPlayTime >= requirement then
      maxRarity = rarity
    else
      break
    end
  end
  return maxRarity
end

-- Get the minimum playtime required for a specific rarity
function RandomChickenSpawn.getPlaytimeRequirement(rarity: ChickenConfig.Rarity): number
  return RARITY_PLAYTIME_REQUIREMENTS[rarity] or 0
end

-- Type definitions
export type Vector3 = {
  x: number,
  y: number,
  z: number,
}

export type SpawnConfig = {
  spawnIntervalMin: number,
  spawnIntervalMax: number,
  despawnTime: number,
  neutralZoneCenter: Vector3,
  neutralZoneSize: number,
  claimRange: number,
  spawnZones: { SpawnZone }?, -- Multiple spawn zones across the map (if nil, uses neutralZoneCenter)
}

export type SpawnedChicken = {
  id: string,
  chickenType: string,
  rarity: ChickenConfig.Rarity,
  position: Vector3,
  spawnedAt: number,
  despawnAt: number,
  -- Spawn zone boundary for AI movement (map-wide spawning)
  spawnZone: SpawnZone?,
}

export type SpawnEventState = {
  config: SpawnConfig,
  currentChicken: SpawnedChicken?,
  nextSpawnTime: number,
  lastSpawnTime: number,
  lastSpawnPosition: Vector3?, -- Track last spawn position to ensure variety
  totalSpawns: number,
  totalClaims: number,
  isActive: boolean,
}

export type ClaimResult = {
  success: boolean,
  chicken: SpawnedChicken?,
  claimedBy: string?,
  reason: string?,
}

export type SpawnResult = {
  success: boolean,
  chicken: SpawnedChicken?,
  reason: string?,
}

export type UpdateResult = {
  spawned: SpawnedChicken?,
  despawned: SpawnedChicken?,
}

-- Get default spawn configuration
function RandomChickenSpawn.getDefaultConfig(): SpawnConfig
  return {
    spawnIntervalMin = DEFAULT_SPAWN_INTERVAL_MIN,
    spawnIntervalMax = DEFAULT_SPAWN_INTERVAL_MAX,
    despawnTime = DEFAULT_DESPAWN_TIME,
    neutralZoneCenter = { x = 0, y = 0, z = 0 },
    neutralZoneSize = NEUTRAL_ZONE_SIZE,
    claimRange = CLAIM_RANGE,
    spawnZones = nil, -- nil means use single neutralZoneCenter
  }
end

-- Create spawn zones from a map configuration
-- This generates spawn zones for each player section in the map grid
function RandomChickenSpawn.createSpawnZonesFromMap(mapConfig: {
  gridColumns: number,
  gridRows: number,
  sectionWidth: number,
  sectionDepth: number,
  sectionGap: number,
  originPosition: Vector3,
}): { SpawnZone }
  local zones: { SpawnZone } = {}
  local totalSections = mapConfig.gridColumns * mapConfig.gridRows

  for i = 1, totalSections do
    local index0 = i - 1
    local row = math.floor(index0 / mapConfig.gridColumns)
    local column = index0 % mapConfig.gridColumns

    -- Calculate offset from grid center
    local offsetX = (column - (mapConfig.gridColumns - 1) / 2)
      * (mapConfig.sectionWidth + mapConfig.sectionGap)
    local offsetZ = (row - (mapConfig.gridRows - 1) / 2)
      * (mapConfig.sectionDepth + mapConfig.sectionGap)

    -- Spawn zone is smaller than section to keep chickens away from walls
    local zoneSize = math.min(mapConfig.sectionWidth, mapConfig.sectionDepth) - 16

    table.insert(zones, {
      center = {
        x = mapConfig.originPosition.x + offsetX,
        y = mapConfig.originPosition.y,
        z = mapConfig.originPosition.z + offsetZ,
      },
      size = zoneSize,
    })
  end

  return zones
end

-- Generate a unique ID for spawned chickens
local function generateSpawnId(): string
  return "spawn_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

-- Calculate horizontal distance between two positions (XZ plane only)
-- Uses 2D distance to avoid Y-axis differences between player (standing height)
-- and chicken (ground level) causing false "too far" rejections
local function getDistance(pos1: Vector3, pos2: Vector3): number
  local dx = pos2.x - pos1.x
  local dz = pos2.z - pos1.z
  return math.sqrt(dx * dx + dz * dz)
end

-- Calculate next spawn time based on config
local function calculateNextSpawnTime(config: SpawnConfig, currentTime: number): number
  local interval = config.spawnIntervalMin
    + math.random() * (config.spawnIntervalMax - config.spawnIntervalMin)
  return currentTime + interval
end

-- Minimum distance between consecutive spawn positions to ensure visible variety
local MIN_SPAWN_DISTANCE = 8 -- studs

-- Internal type for spawn position with zone info
type SpawnPositionResult = {
  position: Vector3,
  zone: SpawnZone?,
}

-- Get random position within a spawn zone or across all zones (for map-wide spawning)
-- If spawnZones are configured, randomly picks a zone then a position within it
-- Returns both the position and the selected zone for AI boundary tracking
function RandomChickenSpawn.getRandomSpawnPositionWithZone(
  config: SpawnConfig,
  lastPosition: Vector3?
): SpawnPositionResult
  local maxAttempts = 10 -- Prevent infinite loops

  -- Determine spawn zone to use
  local zoneCenter: Vector3
  local zoneSize: number
  local selectedZone: SpawnZone? = nil

  if config.spawnZones and #config.spawnZones > 0 then
    -- Pick a random zone from the available spawn zones (map-wide spawning)
    local randomZoneIndex = math.random(1, #config.spawnZones)
    selectedZone = config.spawnZones[randomZoneIndex]
    zoneCenter = selectedZone.center
    zoneSize = selectedZone.size
  else
    -- Fall back to single neutral zone
    zoneCenter = config.neutralZoneCenter
    zoneSize = config.neutralZoneSize
  end

  local halfSize = zoneSize / 2

  for _ = 1, maxAttempts do
    local newPosition = {
      x = zoneCenter.x + (math.random() - 0.5) * halfSize * 2,
      y = zoneCenter.y,
      z = zoneCenter.z + (math.random() - 0.5) * halfSize * 2,
    }

    -- If no last position, or if new position is far enough away, use it
    if not lastPosition then
      return { position = newPosition, zone = selectedZone }
    end

    -- Calculate distance from last position
    local dx = newPosition.x - lastPosition.x
    local dz = newPosition.z - lastPosition.z
    local distance = math.sqrt(dx * dx + dz * dz)

    if distance >= MIN_SPAWN_DISTANCE then
      return { position = newPosition, zone = selectedZone }
    end
  end

  -- Fallback: return a position anyway after max attempts
  return {
    position = {
      x = zoneCenter.x + (math.random() - 0.5) * halfSize * 2,
      y = zoneCenter.y,
      z = zoneCenter.z + (math.random() - 0.5) * halfSize * 2,
    },
    zone = selectedZone,
  }
end

-- Get random position within neutral zone, ensuring minimum distance from last spawn
-- Legacy function for backward compatibility
function RandomChickenSpawn.getRandomSpawnPosition(
  config: SpawnConfig,
  lastPosition: Vector3?
): Vector3
  local result = RandomChickenSpawn.getRandomSpawnPositionWithZone(config, lastPosition)
  return result.position
end

-- Select a random chicken type based on rarity weights
-- maxAllowedRarity: Optional parameter to cap the maximum rarity that can be selected
-- (used to prevent new players from getting overpowered chickens)
function RandomChickenSpawn.selectRandomChickenType(
  maxAllowedRarity: ChickenConfig.Rarity?
): string?
  local maxRarityIndex = maxAllowedRarity and getRarityIndex(maxAllowedRarity) or #RARITY_ORDER

  -- Calculate total weight, excluding rarities above maxAllowedRarity
  local totalWeight = 0
  for rarity, weight in pairs(SPAWN_RARITY_WEIGHTS) do
    local rarityIndex = getRarityIndex(rarity :: ChickenConfig.Rarity)
    if rarityIndex <= maxRarityIndex then
      totalWeight = totalWeight + weight
    end
  end

  if totalWeight == 0 then
    return nil
  end

  -- Roll random value
  local roll = math.random() * totalWeight
  local currentWeight = 0

  -- Find which rarity was selected (only considering eligible rarities)
  local selectedRarity: ChickenConfig.Rarity?
  for rarity, weight in pairs(SPAWN_RARITY_WEIGHTS) do
    local rarityIndex = getRarityIndex(rarity :: ChickenConfig.Rarity)
    if rarityIndex <= maxRarityIndex and weight > 0 then
      currentWeight = currentWeight + weight
      if roll <= currentWeight then
        selectedRarity = rarity :: ChickenConfig.Rarity
        break
      end
    end
  end

  if not selectedRarity then
    return nil
  end

  -- Get all chicken types of that rarity
  local chickensOfRarity = ChickenConfig.getByRarity(selectedRarity)
  if #chickensOfRarity == 0 then
    return nil
  end

  -- Select random chicken from that rarity
  local randomIndex = math.random(1, #chickensOfRarity)
  return chickensOfRarity[randomIndex].name
end

-- Create initial spawn event state
function RandomChickenSpawn.createSpawnState(
  config: SpawnConfig?,
  currentTime: number
): SpawnEventState
  local cfg = config or RandomChickenSpawn.getDefaultConfig()
  return {
    config = cfg,
    currentChicken = nil,
    nextSpawnTime = calculateNextSpawnTime(cfg, currentTime),
    lastSpawnTime = 0,
    lastSpawnPosition = nil,
    totalSpawns = 0,
    totalClaims = 0,
    isActive = true,
  }
end

-- Spawn a new chicken in the neutral zone
-- maxAllowedRarity: Optional parameter to cap the maximum rarity that can spawn
-- (used to prevent new players from getting overpowered chickens)
function RandomChickenSpawn.spawnChicken(
  state: SpawnEventState,
  currentTime: number,
  maxAllowedRarity: ChickenConfig.Rarity?
): SpawnResult
  -- Check if there's already a chicken
  if state.currentChicken then
    return {
      success = false,
      chicken = nil,
      reason = "A chicken is already spawned",
    }
  end

  -- Select chicken type (respecting max rarity if provided)
  local chickenType = RandomChickenSpawn.selectRandomChickenType(maxAllowedRarity)
  if not chickenType then
    return {
      success = false,
      chicken = nil,
      reason = "Failed to select chicken type",
    }
  end

  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return {
      success = false,
      chicken = nil,
      reason = "Invalid chicken configuration",
    }
  end

  -- Create spawned chicken with spawn zone info for AI boundary
  local spawnResult =
    RandomChickenSpawn.getRandomSpawnPositionWithZone(state.config, state.lastSpawnPosition)
  local spawnedChicken: SpawnedChicken = {
    id = generateSpawnId(),
    chickenType = chickenType,
    rarity = chickenConfig.rarity,
    position = spawnResult.position,
    spawnedAt = currentTime,
    despawnAt = currentTime + state.config.despawnTime,
    spawnZone = spawnResult.zone,
  }

  -- Update state
  state.currentChicken = spawnedChicken
  state.lastSpawnTime = currentTime
  state.lastSpawnPosition = spawnResult.position
  state.totalSpawns = state.totalSpawns + 1
  state.nextSpawnTime = calculateNextSpawnTime(state.config, currentTime)

  return {
    success = true,
    chicken = spawnedChicken,
    reason = nil,
  }
end

-- Check if it's time to spawn a new chicken
function RandomChickenSpawn.shouldSpawn(state: SpawnEventState, currentTime: number): boolean
  if not state.isActive then
    return false
  end
  if state.currentChicken then
    return false
  end
  return currentTime >= state.nextSpawnTime
end

-- Check if current chicken should despawn
function RandomChickenSpawn.shouldDespawn(state: SpawnEventState, currentTime: number): boolean
  if not state.currentChicken then
    return false
  end
  return currentTime >= state.currentChicken.despawnAt
end

-- Despawn current chicken (timeout)
function RandomChickenSpawn.despawnChicken(state: SpawnEventState): SpawnedChicken?
  local chicken = state.currentChicken
  state.currentChicken = nil
  return chicken
end

-- Check if a player can claim the current chicken
function RandomChickenSpawn.canClaimChicken(
  state: SpawnEventState,
  playerPosition: Vector3,
  currentTime: number
): boolean
  if not state.currentChicken then
    return false
  end

  -- Check if chicken hasn't despawned
  if currentTime >= state.currentChicken.despawnAt then
    return false
  end

  -- Check distance
  local distance = getDistance(playerPosition, state.currentChicken.position)
  return distance <= state.config.claimRange
end

-- Attempt to claim the current chicken
function RandomChickenSpawn.claimChicken(
  state: SpawnEventState,
  playerId: string,
  playerPosition: Vector3,
  currentTime: number
): ClaimResult
  -- Validate chicken exists
  if not state.currentChicken then
    return {
      success = false,
      chicken = nil,
      claimedBy = nil,
      reason = "No chicken available to claim",
    }
  end

  -- Check if chicken has despawned
  if currentTime >= state.currentChicken.despawnAt then
    state.currentChicken = nil
    return {
      success = false,
      chicken = nil,
      claimedBy = nil,
      reason = "Chicken has despawned",
    }
  end

  -- Check distance
  local distance = getDistance(playerPosition, state.currentChicken.position)
  if distance > state.config.claimRange then
    return {
      success = false,
      chicken = nil,
      claimedBy = nil,
      reason = string.format(
        "Too far from chicken (%.1f studs, need %.1f)",
        distance,
        state.config.claimRange
      ),
    }
  end

  -- Claim successful
  local claimedChicken = state.currentChicken
  state.currentChicken = nil
  state.totalClaims = state.totalClaims + 1

  return {
    success = true,
    chicken = claimedChicken,
    claimedBy = playerId,
    reason = nil,
  }
end

-- Update spawn state (call each frame/tick)
-- Returns UpdateResult with spawned/despawned chicken info
-- maxAllowedRarity: Optional parameter to cap the maximum rarity that can spawn
-- (based on minimum playtime of active players)
function RandomChickenSpawn.update(
  state: SpawnEventState,
  currentTime: number,
  maxAllowedRarity: ChickenConfig.Rarity?
): UpdateResult
  local result: UpdateResult = {
    spawned = nil,
    despawned = nil,
  }

  if not state.isActive then
    return result
  end

  -- Check for despawn
  if RandomChickenSpawn.shouldDespawn(state, currentTime) then
    result.despawned = RandomChickenSpawn.despawnChicken(state)
    -- Schedule next spawn
    state.nextSpawnTime = calculateNextSpawnTime(state.config, currentTime)
  end

  -- Check for new spawn
  if RandomChickenSpawn.shouldSpawn(state, currentTime) then
    local spawnResult = RandomChickenSpawn.spawnChicken(state, currentTime, maxAllowedRarity)
    if spawnResult.success and spawnResult.chicken then
      result.spawned = spawnResult.chicken
    end
  end

  return result
end

-- Get current chicken if any
function RandomChickenSpawn.getCurrentChicken(state: SpawnEventState): SpawnedChicken?
  return state.currentChicken
end

-- Get time until next spawn
function RandomChickenSpawn.getTimeUntilNextSpawn(
  state: SpawnEventState,
  currentTime: number
): number
  if state.currentChicken then
    -- Include despawn time + next interval
    return math.max(0, state.currentChicken.despawnAt - currentTime)
  end
  return math.max(0, state.nextSpawnTime - currentTime)
end

-- Get remaining time for current chicken before despawn
function RandomChickenSpawn.getRemainingClaimTime(
  state: SpawnEventState,
  currentTime: number
): number?
  if not state.currentChicken then
    return nil
  end
  return math.max(0, state.currentChicken.despawnAt - currentTime)
end

-- Check if there's an active spawn event
function RandomChickenSpawn.hasActiveChicken(state: SpawnEventState): boolean
  return state.currentChicken ~= nil
end

-- Pause spawn events
function RandomChickenSpawn.pause(state: SpawnEventState): ()
  state.isActive = false
end

-- Resume spawn events
function RandomChickenSpawn.resume(state: SpawnEventState, currentTime: number): ()
  state.isActive = true
  -- Reschedule next spawn if needed
  if not state.currentChicken and state.nextSpawnTime < currentTime then
    state.nextSpawnTime = calculateNextSpawnTime(state.config, currentTime)
  end
end

-- Reset spawn state
function RandomChickenSpawn.reset(state: SpawnEventState, currentTime: number): ()
  state.currentChicken = nil
  state.nextSpawnTime = calculateNextSpawnTime(state.config, currentTime)
  state.lastSpawnPosition = nil
  state.totalSpawns = 0
  state.totalClaims = 0
  state.isActive = true
end

-- Get spawn statistics
function RandomChickenSpawn.getStats(
  state: SpawnEventState
): { totalSpawns: number, totalClaims: number, claimRate: number }
  local claimRate = 0
  if state.totalSpawns > 0 then
    claimRate = state.totalClaims / state.totalSpawns
  end
  return {
    totalSpawns = state.totalSpawns,
    totalClaims = state.totalClaims,
    claimRate = claimRate,
  }
end

-- Get announcement text for a spawn event
function RandomChickenSpawn.getAnnouncementText(chicken: SpawnedChicken): string
  local config = ChickenConfig.get(chicken.chickenType)
  local displayName = config and config.displayName or chicken.chickenType
  return string.format("A %s %s has appeared in the neutral zone!", chicken.rarity, displayName)
end

-- Get claim prompt text
function RandomChickenSpawn.getClaimPrompt(state: SpawnEventState, currentTime: number): string?
  if not state.currentChicken then
    return nil
  end
  local remaining = RandomChickenSpawn.getRemainingClaimTime(state, currentTime) or 0
  local config = ChickenConfig.get(state.currentChicken.chickenType)
  local displayName = config and config.displayName or state.currentChicken.chickenType
  return string.format("[E] Claim %s (%.0fs)", displayName, remaining)
end

-- Get neutral zone bounds for UI/rendering
function RandomChickenSpawn.getNeutralZoneBounds(
  config: SpawnConfig
): { min: Vector3, max: Vector3 }
  local halfSize = config.neutralZoneSize / 2
  return {
    min = {
      x = config.neutralZoneCenter.x - halfSize,
      y = config.neutralZoneCenter.y,
      z = config.neutralZoneCenter.z - halfSize,
    },
    max = {
      x = config.neutralZoneCenter.x + halfSize,
      y = config.neutralZoneCenter.y + 10, -- some height for visualization
      z = config.neutralZoneCenter.z + halfSize,
    },
  }
end

-- Validate spawn state
function RandomChickenSpawn.validateState(state: SpawnEventState): boolean
  if type(state) ~= "table" then
    return false
  end
  if type(state.config) ~= "table" then
    return false
  end
  if type(state.nextSpawnTime) ~= "number" then
    return false
  end
  if type(state.lastSpawnTime) ~= "number" then
    return false
  end
  if type(state.totalSpawns) ~= "number" then
    return false
  end
  if type(state.totalClaims) ~= "number" then
    return false
  end
  if type(state.isActive) ~= "boolean" then
    return false
  end
  return true
end

-- Get summary for debugging
function RandomChickenSpawn.getSummary(state: SpawnEventState, currentTime: number): string
  local chickenInfo = "none"
  if state.currentChicken then
    local remaining = RandomChickenSpawn.getRemainingClaimTime(state, currentTime) or 0
    chickenInfo = string.format("%s (%.0fs remaining)", state.currentChicken.chickenType, remaining)
  end
  local nextIn = RandomChickenSpawn.getTimeUntilNextSpawn(state, currentTime)
  return string.format(
    "RandomChickenSpawn: active=%s, chicken=%s, nextIn=%.0fs, spawns=%d, claims=%d",
    tostring(state.isActive),
    chickenInfo,
    nextIn,
    state.totalSpawns,
    state.totalClaims
  )
end

-- Update player's pot streak after successfully capturing a spawned chicken
-- This should be called after claimChicken returns success=true
-- Returns the new streak value
function RandomChickenSpawn.updatePotStreakOnCapture(
  playerData: PlayerData.PlayerDataSchema
): number
  return PlayerData.increasePotStreak(playerData)
end

return RandomChickenSpawn
