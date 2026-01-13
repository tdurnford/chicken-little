--[[
	MapGeneration Module
	Handles generation of the game map with 12 player sections.
	Sections are arranged in a 4x3 grid layout.
	Manages player section assignment and rejoining.
]]

local PlayerSection = require(script.Parent.PlayerSection)

local MapGeneration = {}

-- Constants for map layout
local MAX_PLAYERS = 12
local GRID_COLUMNS = 4
local GRID_ROWS = 3
local SECTION_GAP = 4 -- studs between sections

-- Type definitions
export type SectionAssignment = {
  sectionIndex: number,
  playerId: string,
  assignedAt: number,
}

export type MapState = {
  sections: { PlayerSection.SectionTemplate },
  assignments: { [number]: SectionAssignment? },
  playerToSection: { [string]: number },
  reservations: { [string]: number }, -- playerId -> sectionIndex for rejoining
}

export type MapConfig = {
  maxPlayers: number,
  gridColumns: number,
  gridRows: number,
  sectionGap: number,
  originPosition: PlayerSection.Vector3,
}

-- Get the default map configuration
function MapGeneration.getConfig(): MapConfig
  return {
    maxPlayers = MAX_PLAYERS,
    gridColumns = GRID_COLUMNS,
    gridRows = GRID_ROWS,
    sectionGap = SECTION_GAP,
    originPosition = { x = 0, y = 0, z = 0 },
  }
end

-- Get the total number of sections
function MapGeneration.getMaxSections(): number
  return MAX_PLAYERS
end

-- Calculate the center position for a section based on its index (1-12)
function MapGeneration.getSectionPosition(
  sectionIndex: number,
  config: MapConfig?
): PlayerSection.Vector3?
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return nil
  end

  local cfg = config or MapGeneration.getConfig()
  local sectionSize = PlayerSection.getSectionSize()

  -- Convert to 0-based for math
  local index0 = sectionIndex - 1
  local row = math.floor(index0 / cfg.gridColumns) -- 0, 1, 2
  local column = index0 % cfg.gridColumns -- 0, 1, 2, 3

  -- Calculate total grid size
  local totalWidth = cfg.gridColumns * sectionSize.x + (cfg.gridColumns - 1) * cfg.sectionGap
  local totalDepth = cfg.gridRows * sectionSize.z + (cfg.gridRows - 1) * cfg.sectionGap

  -- Calculate offset from center of grid to place section
  local offsetX = (column - (cfg.gridColumns - 1) / 2) * (sectionSize.x + cfg.sectionGap)
  local offsetZ = (row - (cfg.gridRows - 1) / 2) * (sectionSize.z + cfg.sectionGap)

  return {
    x = cfg.originPosition.x + offsetX,
    y = cfg.originPosition.y,
    z = cfg.originPosition.z + offsetZ,
  }
end

-- Generate all 12 section templates
function MapGeneration.generateSections(config: MapConfig?): { PlayerSection.SectionTemplate }
  local cfg = config or MapGeneration.getConfig()
  local sections = {}

  for i = 1, MAX_PLAYERS do
    local position = MapGeneration.getSectionPosition(i, cfg)
    if position then
      local template = PlayerSection.createTemplate(i, position)
      table.insert(sections, template)
    end
  end

  return sections
end

-- Create initial map state with all sections generated
function MapGeneration.createMapState(config: MapConfig?): MapState
  local sections = MapGeneration.generateSections(config)
  local assignments: { [number]: SectionAssignment? } = {}

  -- Initialize all assignments as nil
  for i = 1, MAX_PLAYERS do
    assignments[i] = nil
  end

  return {
    sections = sections,
    assignments = assignments,
    playerToSection = {},
    reservations = {},
  }
end

-- Find the first available (unassigned) section
function MapGeneration.findAvailableSection(mapState: MapState): number?
  for i = 1, MAX_PLAYERS do
    if mapState.assignments[i] == nil then
      return i
    end
  end
  return nil
end

-- Check if a section is available for assignment
function MapGeneration.isSectionAvailable(mapState: MapState, sectionIndex: number): boolean
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return false
  end
  return mapState.assignments[sectionIndex] == nil
end

-- Check if a player has a section assigned
function MapGeneration.hasPlayerSection(mapState: MapState, playerId: string): boolean
  return mapState.playerToSection[playerId] ~= nil
end

-- Get the section index assigned to a player
function MapGeneration.getPlayerSection(mapState: MapState, playerId: string): number?
  return mapState.playerToSection[playerId]
end

-- Get the section template for a player
function MapGeneration.getPlayerSectionTemplate(
  mapState: MapState,
  playerId: string
): PlayerSection.SectionTemplate?
  local sectionIndex = mapState.playerToSection[playerId]
  if sectionIndex and mapState.sections[sectionIndex] then
    return mapState.sections[sectionIndex]
  end
  return nil
end

-- Assign a player to a specific section
function MapGeneration.assignSection(
  mapState: MapState,
  playerId: string,
  sectionIndex: number,
  currentTime: number
): boolean
  -- Validate section index
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return false
  end

  -- Check if section is already assigned
  if mapState.assignments[sectionIndex] ~= nil then
    return false
  end

  -- Check if player already has a section
  if mapState.playerToSection[playerId] ~= nil then
    return false
  end

  -- Create assignment
  local assignment: SectionAssignment = {
    sectionIndex = sectionIndex,
    playerId = playerId,
    assignedAt = currentTime,
  }

  mapState.assignments[sectionIndex] = assignment
  mapState.playerToSection[playerId] = sectionIndex

  -- Clear any reservation for this player
  mapState.reservations[playerId] = nil

  return true
end

-- Assign a player to the next available section
function MapGeneration.assignNextAvailableSection(
  mapState: MapState,
  playerId: string,
  currentTime: number
): number?
  -- Check if player already has a section
  if mapState.playerToSection[playerId] then
    return mapState.playerToSection[playerId]
  end

  -- Check if player has a reservation
  local reservedSection = mapState.reservations[playerId]
  if reservedSection and MapGeneration.isSectionAvailable(mapState, reservedSection) then
    if MapGeneration.assignSection(mapState, playerId, reservedSection, currentTime) then
      return reservedSection
    end
  end

  -- Find next available section
  local availableSection = MapGeneration.findAvailableSection(mapState)
  if availableSection then
    if MapGeneration.assignSection(mapState, playerId, availableSection, currentTime) then
      return availableSection
    end
  end

  return nil
end

-- Unassign a player from their section (for leaving)
function MapGeneration.unassignSection(mapState: MapState, playerId: string): boolean
  local sectionIndex = mapState.playerToSection[playerId]
  if sectionIndex == nil then
    return false
  end

  mapState.assignments[sectionIndex] = nil
  mapState.playerToSection[playerId] = nil

  return true
end

-- Reserve a section for a player who left (for rejoining)
function MapGeneration.reserveSection(
  mapState: MapState,
  playerId: string,
  sectionIndex: number
): boolean
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return false
  end

  mapState.reservations[playerId] = sectionIndex
  return true
end

-- Handle player leaving - unassign and reserve their section
function MapGeneration.handlePlayerLeave(mapState: MapState, playerId: string): number?
  local sectionIndex = mapState.playerToSection[playerId]
  if sectionIndex == nil then
    return nil
  end

  -- Unassign the section
  MapGeneration.unassignSection(mapState, playerId)

  -- Reserve it for rejoining
  MapGeneration.reserveSection(mapState, playerId, sectionIndex)

  return sectionIndex
end

-- Handle player joining - assign to reserved or next available section
function MapGeneration.handlePlayerJoin(
  mapState: MapState,
  playerId: string,
  currentTime: number
): number?
  return MapGeneration.assignNextAvailableSection(mapState, playerId, currentTime)
end

-- Clear a reservation (e.g., after timeout or server cleanup)
function MapGeneration.clearReservation(mapState: MapState, playerId: string): boolean
  if mapState.reservations[playerId] then
    mapState.reservations[playerId] = nil
    return true
  end
  return false
end

-- Get all active assignments
function MapGeneration.getActiveAssignments(mapState: MapState): { SectionAssignment }
  local active = {}
  for i = 1, MAX_PLAYERS do
    local assignment = mapState.assignments[i]
    if assignment then
      table.insert(active, assignment)
    end
  end
  return active
end

-- Get count of assigned sections
function MapGeneration.getAssignedCount(mapState: MapState): number
  local count = 0
  for i = 1, MAX_PLAYERS do
    if mapState.assignments[i] ~= nil then
      count = count + 1
    end
  end
  return count
end

-- Get count of available sections
function MapGeneration.getAvailableCount(mapState: MapState): number
  return MAX_PLAYERS - MapGeneration.getAssignedCount(mapState)
end

-- Check if the map is full (all sections assigned)
function MapGeneration.isMapFull(mapState: MapState): boolean
  return MapGeneration.getAssignedCount(mapState) >= MAX_PLAYERS
end

-- Get section template by index
function MapGeneration.getSectionByIndex(
  mapState: MapState,
  sectionIndex: number
): PlayerSection.SectionTemplate?
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return nil
  end
  return mapState.sections[sectionIndex]
end

-- Find which section a position is in
function MapGeneration.findSectionAtPosition(
  mapState: MapState,
  position: PlayerSection.Vector3
): number?
  for i, section in ipairs(mapState.sections) do
    if PlayerSection.isPositionInSection(position, section.centerPosition) then
      return i
    end
  end
  return nil
end

-- Get spawn point for a player
function MapGeneration.getPlayerSpawnPoint(
  mapState: MapState,
  playerId: string
): PlayerSection.Vector3?
  local template = MapGeneration.getPlayerSectionTemplate(mapState, playerId)
  if template then
    return template.spawnPoint
  end
  return nil
end

-- Get store location for a player
function MapGeneration.getPlayerStoreLocation(
  mapState: MapState,
  playerId: string
): PlayerSection.Vector3?
  local template = MapGeneration.getPlayerSectionTemplate(mapState, playerId)
  if template then
    return template.storeLocation
  end
  return nil
end

-- Validate map state integrity
function MapGeneration.validateMapState(mapState: MapState): boolean
  if type(mapState) ~= "table" then
    return false
  end

  -- Check sections
  if type(mapState.sections) ~= "table" or #mapState.sections ~= MAX_PLAYERS then
    return false
  end

  for i, section in ipairs(mapState.sections) do
    if not PlayerSection.validateTemplate(section) then
      return false
    end
    if section.sectionIndex ~= i then
      return false
    end
  end

  -- Check assignments table exists
  if type(mapState.assignments) ~= "table" then
    return false
  end

  -- Check playerToSection table exists
  if type(mapState.playerToSection) ~= "table" then
    return false
  end

  -- Check reservations table exists
  if type(mapState.reservations) ~= "table" then
    return false
  end

  -- Validate assignment consistency
  for sectionIndex, assignment in pairs(mapState.assignments) do
    if assignment then
      if type(assignment) ~= "table" then
        return false
      end
      if assignment.sectionIndex ~= sectionIndex then
        return false
      end
      if mapState.playerToSection[assignment.playerId] ~= sectionIndex then
        return false
      end
    end
  end

  return true
end

-- Get map dimensions (total width and depth of all sections)
function MapGeneration.getMapSize(config: MapConfig?): PlayerSection.Vector3
  local cfg = config or MapGeneration.getConfig()
  local sectionSize = PlayerSection.getSectionSize()

  local totalWidth = cfg.gridColumns * sectionSize.x + (cfg.gridColumns - 1) * cfg.sectionGap
  local totalDepth = cfg.gridRows * sectionSize.z + (cfg.gridRows - 1) * cfg.sectionGap

  return {
    x = totalWidth,
    y = sectionSize.y,
    z = totalDepth,
  }
end

-- Get section neighbors (adjacent sections for a given section)
function MapGeneration.getSectionNeighbors(sectionIndex: number): { number }
  if sectionIndex < 1 or sectionIndex > MAX_PLAYERS then
    return {}
  end

  local neighbors = {}
  local index0 = sectionIndex - 1
  local row = math.floor(index0 / GRID_COLUMNS)
  local column = index0 % GRID_COLUMNS

  -- Check left neighbor
  if column > 0 then
    table.insert(neighbors, sectionIndex - 1)
  end

  -- Check right neighbor
  if column < GRID_COLUMNS - 1 then
    table.insert(neighbors, sectionIndex + 1)
  end

  -- Check top neighbor
  if row > 0 then
    table.insert(neighbors, sectionIndex - GRID_COLUMNS)
  end

  -- Check bottom neighbor
  if row < GRID_ROWS - 1 then
    table.insert(neighbors, sectionIndex + GRID_COLUMNS)
  end

  return neighbors
end

-- Get summary of map state for debugging
function MapGeneration.getSummary(mapState: MapState): string
  local assigned = MapGeneration.getAssignedCount(mapState)
  local available = MapGeneration.getAvailableCount(mapState)
  local reservations = 0
  for _ in pairs(mapState.reservations) do
    reservations = reservations + 1
  end

  return string.format(
    "Map: %d/%d sections assigned, %d available, %d reservations",
    assigned,
    MAX_PLAYERS,
    available,
    reservations
  )
end

return MapGeneration
