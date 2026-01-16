--[[
	PlayerSection Module
	Defines the template for a single player's section of the map.
	Each section contains a chicken coop with 12 placement spots,
	spawn point, store location, and boundaries.
]]

local PlayerSection = {}

-- Constants for section dimensions
local SECTION_WIDTH = 64 -- studs
local SECTION_DEPTH = 64 -- studs
local SECTION_HEIGHT = 16 -- studs (for boundary walls)
local BOUNDARY_THICKNESS = 2 -- studs

-- Coop configuration
local COOP_SPOTS = 12
local COOP_ROWS = 3
local COOP_COLUMNS = 4
local SPOT_SIZE = 6 -- studs per spot
local SPOT_SPACING = 2 -- studs between spots
local COOP_OFFSET_X = 0 -- centered in section
local COOP_OFFSET_Z = -10 -- towards back of section

-- Trap spot configuration (8 spots around the coop perimeter)
local TRAP_SPOTS = 8
local TRAP_SPOT_SIZE = 4 -- studs per trap spot
local TRAP_DISTANCE_FROM_COOP = 12 -- studs from coop center to trap spots

-- Type definitions
export type Vector3 = {
  x: number,
  y: number,
  z: number,
}

export type SpotData = {
  index: number,
  position: Vector3,
  size: number,
  row: number,
  column: number,
}

export type BoundaryData = {
  position: Vector3,
  size: Vector3,
  side: string, -- "north", "south", "east", "west"
}

export type TrapSpotData = {
  index: number,
  position: Vector3,
  size: number,
}

export type SectionConfig = {
  width: number,
  depth: number,
  height: number,
  boundaryThickness: number,
  coopSpots: number,
  coopRows: number,
  coopColumns: number,
  spotSize: number,
  spotSpacing: number,
}

export type SectionTemplate = {
  sectionIndex: number,
  centerPosition: Vector3,
  spawnPoint: Vector3,
  storeLocation: Vector3,
  coopCenter: Vector3,
  spots: { SpotData },
  boundaries: { BoundaryData },
  config: SectionConfig,
}

-- Get the default section configuration
function PlayerSection.getConfig(): SectionConfig
  return {
    width = SECTION_WIDTH,
    depth = SECTION_DEPTH,
    height = SECTION_HEIGHT,
    boundaryThickness = BOUNDARY_THICKNESS,
    coopSpots = COOP_SPOTS,
    coopRows = COOP_ROWS,
    coopColumns = COOP_COLUMNS,
    spotSize = SPOT_SIZE,
    spotSpacing = SPOT_SPACING,
  }
end

-- Get the maximum number of coop spots
function PlayerSection.getMaxSpots(): number
  return COOP_SPOTS
end

-- Get the maximum number of trap spots
function PlayerSection.getMaxTrapSpots(): number
  return TRAP_SPOTS
end

-- Calculate position for a specific trap spot index (1-8)
-- Trap spots are arranged in an octagon around the coop
function PlayerSection.getTrapSpotPosition(spotIndex: number, sectionCenter: Vector3): Vector3?
  if spotIndex < 1 or spotIndex > TRAP_SPOTS then
    return nil
  end

  -- Calculate angle for this spot (8 spots = 45 degrees apart)
  -- Start from front-right and go counter-clockwise
  local angleOffset = -math.pi / 8 -- Start slightly offset to center spots
  local angle = angleOffset + ((spotIndex - 1) * (2 * math.pi / TRAP_SPOTS))

  -- Calculate position using polar coordinates
  local offsetX = math.cos(angle) * TRAP_DISTANCE_FROM_COOP
  local offsetZ = math.sin(angle) * TRAP_DISTANCE_FROM_COOP

  return {
    x = sectionCenter.x + COOP_OFFSET_X + offsetX,
    y = sectionCenter.y,
    z = sectionCenter.z + COOP_OFFSET_Z + offsetZ,
  }
end

-- Get all trap spot data for a section
function PlayerSection.getAllTrapSpots(sectionCenter: Vector3): { TrapSpotData }
  local spots = {}
  for i = 1, TRAP_SPOTS do
    local position = PlayerSection.getTrapSpotPosition(i, sectionCenter)
    if position then
      table.insert(spots, {
        index = i,
        position = position,
        size = TRAP_SPOT_SIZE,
      })
    end
  end
  return spots
end

-- Find the nearest available trap spot to a position
function PlayerSection.findNearestTrapSpot(position: Vector3, sectionCenter: Vector3): TrapSpotData?
  local spots = PlayerSection.getAllTrapSpots(sectionCenter)
  local nearestSpot: TrapSpotData? = nil
  local nearestDistance = math.huge

  for _, spot in ipairs(spots) do
    local dx = position.x - spot.position.x
    local dz = position.z - spot.position.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance < nearestDistance then
      nearestDistance = distance
      nearestSpot = spot
    end
  end

  return nearestSpot
end

-- Check if trap spot index is valid
function PlayerSection.isValidTrapSpotIndex(spotIndex: number): boolean
  return type(spotIndex) == "number"
    and spotIndex >= 1
    and spotIndex <= TRAP_SPOTS
    and spotIndex == math.floor(spotIndex)
end

-- Get the section dimensions
function PlayerSection.getSectionSize(): Vector3
  return {
    x = SECTION_WIDTH,
    y = SECTION_HEIGHT,
    z = SECTION_DEPTH,
  }
end

-- Calculate the coop dimensions
function PlayerSection.getCoopSize(): Vector3
  local coopWidth = COOP_COLUMNS * SPOT_SIZE + (COOP_COLUMNS - 1) * SPOT_SPACING
  local coopDepth = COOP_ROWS * SPOT_SIZE + (COOP_ROWS - 1) * SPOT_SPACING
  return {
    x = coopWidth,
    y = 1, -- floor height
    z = coopDepth,
  }
end

-- Calculate position for a specific spot index (1-12)
-- Spots are arranged in a 4x3 grid (4 columns, 3 rows)
function PlayerSection.getSpotPosition(spotIndex: number, sectionCenter: Vector3): Vector3?
  if spotIndex < 1 or spotIndex > COOP_SPOTS then
    return nil
  end

  -- Convert to 0-based for math
  local index0 = spotIndex - 1
  local row = math.floor(index0 / COOP_COLUMNS) -- 0, 1, 2
  local column = index0 % COOP_COLUMNS -- 0, 1, 2, 3

  -- Calculate coop dimensions
  local coopWidth = COOP_COLUMNS * SPOT_SIZE + (COOP_COLUMNS - 1) * SPOT_SPACING
  local coopDepth = COOP_ROWS * SPOT_SIZE + (COOP_ROWS - 1) * SPOT_SPACING

  -- Calculate spot offset from coop center
  local spotOffsetX = (column - (COOP_COLUMNS - 1) / 2) * (SPOT_SIZE + SPOT_SPACING)
  local spotOffsetZ = (row - (COOP_ROWS - 1) / 2) * (SPOT_SIZE + SPOT_SPACING)

  return {
    x = sectionCenter.x + COOP_OFFSET_X + spotOffsetX,
    y = sectionCenter.y,
    z = sectionCenter.z + COOP_OFFSET_Z + spotOffsetZ,
  }
end

-- Get all spot data for a section
function PlayerSection.getAllSpots(sectionCenter: Vector3): { SpotData }
  local spots = {}
  for i = 1, COOP_SPOTS do
    local position = PlayerSection.getSpotPosition(i, sectionCenter)
    if position then
      local index0 = i - 1
      local row = math.floor(index0 / COOP_COLUMNS) + 1
      local column = (index0 % COOP_COLUMNS) + 1
      table.insert(spots, {
        index = i,
        position = position,
        size = SPOT_SIZE,
        row = row,
        column = column,
      })
    end
  end
  return spots
end

-- Calculate spawn point position (front-center of section)
function PlayerSection.getSpawnPoint(sectionCenter: Vector3): Vector3
  return {
    x = sectionCenter.x,
    y = sectionCenter.y + 3, -- slightly above ground
    z = sectionCenter.z + SECTION_DEPTH / 2 - 8, -- front of section
  }
end

-- Calculate store location (front-right corner of section)
function PlayerSection.getStoreLocation(sectionCenter: Vector3): Vector3
  return {
    x = sectionCenter.x + SECTION_WIDTH / 4,
    y = sectionCenter.y,
    z = sectionCenter.z + SECTION_DEPTH / 2 - 6,
  }
end

-- Calculate coop center position
function PlayerSection.getCoopCenter(sectionCenter: Vector3): Vector3
  return {
    x = sectionCenter.x + COOP_OFFSET_X,
    y = sectionCenter.y,
    z = sectionCenter.z + COOP_OFFSET_Z,
  }
end

-- Get boundary wall data for section
function PlayerSection.getBoundaries(sectionCenter: Vector3): { BoundaryData }
  local halfWidth = SECTION_WIDTH / 2
  local halfDepth = SECTION_DEPTH / 2
  local halfThickness = BOUNDARY_THICKNESS / 2

  return {
    -- North wall (back)
    {
      position = {
        x = sectionCenter.x,
        y = sectionCenter.y + SECTION_HEIGHT / 2,
        z = sectionCenter.z - halfDepth + halfThickness,
      },
      size = {
        x = SECTION_WIDTH,
        y = SECTION_HEIGHT,
        z = BOUNDARY_THICKNESS,
      },
      side = "north",
    },
    -- South wall (front)
    {
      position = {
        x = sectionCenter.x,
        y = sectionCenter.y + SECTION_HEIGHT / 2,
        z = sectionCenter.z + halfDepth - halfThickness,
      },
      size = {
        x = SECTION_WIDTH,
        y = SECTION_HEIGHT,
        z = BOUNDARY_THICKNESS,
      },
      side = "south",
    },
    -- East wall (right)
    {
      position = {
        x = sectionCenter.x + halfWidth - halfThickness,
        y = sectionCenter.y + SECTION_HEIGHT / 2,
        z = sectionCenter.z,
      },
      size = {
        x = BOUNDARY_THICKNESS,
        y = SECTION_HEIGHT,
        z = SECTION_DEPTH,
      },
      side = "east",
    },
    -- West wall (left)
    {
      position = {
        x = sectionCenter.x - halfWidth + halfThickness,
        y = sectionCenter.y + SECTION_HEIGHT / 2,
        z = sectionCenter.z,
      },
      size = {
        x = BOUNDARY_THICKNESS,
        y = SECTION_HEIGHT,
        z = SECTION_DEPTH,
      },
      side = "west",
    },
  }
end

-- Create a complete section template
function PlayerSection.createTemplate(
  sectionIndex: number,
  centerPosition: Vector3
): SectionTemplate
  return {
    sectionIndex = sectionIndex,
    centerPosition = centerPosition,
    spawnPoint = PlayerSection.getSpawnPoint(centerPosition),
    storeLocation = PlayerSection.getStoreLocation(centerPosition),
    coopCenter = PlayerSection.getCoopCenter(centerPosition),
    spots = PlayerSection.getAllSpots(centerPosition),
    boundaries = PlayerSection.getBoundaries(centerPosition),
    config = PlayerSection.getConfig(),
  }
end

-- Check if a position is within a section's boundaries
function PlayerSection.isPositionInSection(position: Vector3, sectionCenter: Vector3): boolean
  local halfWidth = SECTION_WIDTH / 2
  local halfDepth = SECTION_DEPTH / 2

  return position.x >= sectionCenter.x - halfWidth
    and position.x <= sectionCenter.x + halfWidth
    and position.z >= sectionCenter.z - halfDepth
    and position.z <= sectionCenter.z + halfDepth
end

-- Find the nearest spot to a position within the section
function PlayerSection.findNearestSpot(position: Vector3, sectionCenter: Vector3): SpotData?
  local spots = PlayerSection.getAllSpots(sectionCenter)
  local nearestSpot: SpotData? = nil
  local nearestDistance = math.huge

  for _, spot in ipairs(spots) do
    local dx = position.x - spot.position.x
    local dz = position.z - spot.position.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance < nearestDistance then
      nearestDistance = distance
      nearestSpot = spot
    end
  end

  return nearestSpot
end

-- Check if a position is within a spot's area
function PlayerSection.isPositionInSpot(position: Vector3, spot: SpotData): boolean
  local halfSize = spot.size / 2
  return math.abs(position.x - spot.position.x) <= halfSize
    and math.abs(position.z - spot.position.z) <= halfSize
end

-- Get the spot at a specific position (or nil if not on a spot)
function PlayerSection.getSpotAtPosition(position: Vector3, sectionCenter: Vector3): SpotData?
  local spots = PlayerSection.getAllSpots(sectionCenter)
  for _, spot in ipairs(spots) do
    if PlayerSection.isPositionInSpot(position, spot) then
      return spot
    end
  end
  return nil
end

-- Validate that a spot index is valid
function PlayerSection.isValidSpotIndex(spotIndex: number): boolean
  return type(spotIndex) == "number"
    and spotIndex >= 1
    and spotIndex <= COOP_SPOTS
    and spotIndex == math.floor(spotIndex)
end

-- Get spot by index from a section template
function PlayerSection.getSpotByIndex(
  sectionTemplate: SectionTemplate,
  spotIndex: number
): SpotData?
  if not PlayerSection.isValidSpotIndex(spotIndex) then
    return nil
  end
  return sectionTemplate.spots[spotIndex]
end

-- Validate a section template has all required data
function PlayerSection.validateTemplate(template: SectionTemplate): boolean
  if type(template) ~= "table" then
    return false
  end

  -- Check required fields
  if type(template.sectionIndex) ~= "number" or template.sectionIndex < 1 then
    return false
  end

  if type(template.centerPosition) ~= "table" then
    return false
  end

  if type(template.spawnPoint) ~= "table" then
    return false
  end

  if type(template.storeLocation) ~= "table" then
    return false
  end

  if type(template.spots) ~= "table" or #template.spots ~= COOP_SPOTS then
    return false
  end

  -- Validate each spot
  for i, spot in ipairs(template.spots) do
    if type(spot) ~= "table" then
      return false
    end
    if spot.index ~= i then
      return false
    end
    if type(spot.position) ~= "table" then
      return false
    end
  end

  if type(template.boundaries) ~= "table" or #template.boundaries ~= 4 then
    return false
  end

  return true
end

-- Get distance between a position and a spot center
function PlayerSection.getDistanceToSpot(position: Vector3, spot: SpotData): number
  local dx = position.x - spot.position.x
  local dy = position.y - spot.position.y
  local dz = position.z - spot.position.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Get all spots within a certain range of a position
function PlayerSection.getSpotsInRange(
  position: Vector3,
  sectionCenter: Vector3,
  range: number
): { SpotData }
  local spots = PlayerSection.getAllSpots(sectionCenter)
  local inRange = {}
  for _, spot in ipairs(spots) do
    if PlayerSection.getDistanceToSpot(position, spot) <= range then
      table.insert(inRange, spot)
    end
  end
  return inRange
end

-- Get a random position within the section's roaming area
-- Uses a margin from the boundaries to keep chickens inside
function PlayerSection.getRandomPositionInSection(sectionCenter: Vector3): Vector3
  local margin = 4 -- Keep chickens away from walls
  local halfWidth = SECTION_WIDTH / 2 - margin
  local halfDepth = SECTION_DEPTH / 2 - margin

  return {
    x = sectionCenter.x + (math.random() - 0.5) * halfWidth * 2,
    y = sectionCenter.y,
    z = sectionCenter.z + (math.random() - 0.5) * halfDepth * 2,
  }
end

-- Clamp a position to be within the section's boundaries (with margin)
-- Useful for spawning chickens near a target position while keeping them in bounds
function PlayerSection.clampPositionToSection(position: Vector3, sectionCenter: Vector3): Vector3
  local margin = 4 -- Same margin as getRandomPositionInSection
  local halfWidth = SECTION_WIDTH / 2 - margin
  local halfDepth = SECTION_DEPTH / 2 - margin

  return {
    x = math.clamp(position.x, sectionCenter.x - halfWidth, sectionCenter.x + halfWidth),
    y = sectionCenter.y, -- Always use ground level
    z = math.clamp(position.z, sectionCenter.z - halfDepth, sectionCenter.z + halfDepth),
  }
end

-- Get a position near a target position, with small random offset for natural spawning
-- Ensures the position stays within section bounds
function PlayerSection.getPositionNear(
  targetPosition: Vector3,
  sectionCenter: Vector3,
  spreadRadius: number?
): Vector3
  local spread = spreadRadius or 3 -- Default 3 stud spread
  local offset = {
    x = (math.random() - 0.5) * spread * 2,
    y = 0,
    z = (math.random() - 0.5) * spread * 2,
  }

  local nearPosition = {
    x = targetPosition.x + offset.x,
    y = targetPosition.y,
    z = targetPosition.z + offset.z,
  }

  -- Clamp to section bounds
  return PlayerSection.clampPositionToSection(nearPosition, sectionCenter)
end

-- Get a random position that's at least minDistance from a given position
-- Useful for spawning chickens with some spread
function PlayerSection.getRandomPositionWithSpread(
  sectionCenter: Vector3,
  avoidPositions: { Vector3 }?,
  minDistance: number?
): Vector3
  local minDist = minDistance or 5
  local margin = 4
  local halfWidth = SECTION_WIDTH / 2 - margin
  local halfDepth = SECTION_DEPTH / 2 - margin
  local maxAttempts = 10

  for _ = 1, maxAttempts do
    local position = {
      x = sectionCenter.x + (math.random() - 0.5) * halfWidth * 2,
      y = sectionCenter.y,
      z = sectionCenter.z + (math.random() - 0.5) * halfDepth * 2,
    }

    -- Check distance from all avoid positions
    local isFarEnough = true
    if avoidPositions then
      for _, avoidPos in ipairs(avoidPositions) do
        local dx = position.x - avoidPos.x
        local dz = position.z - avoidPos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < minDist then
          isFarEnough = false
          break
        end
      end
    end

    if isFarEnough then
      return position
    end
  end

  -- Fallback: just return a random position
  return {
    x = sectionCenter.x + (math.random() - 0.5) * halfWidth * 2,
    y = sectionCenter.y,
    z = sectionCenter.z + (math.random() - 0.5) * halfDepth * 2,
  }
end

return PlayerSection
