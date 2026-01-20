--[[
	MapService
	Knit service that handles map state management, player section assignment,
	section labels, and new player protection tracking.
	
	Provides:
	- Map state management via MapGeneration module
	- Player section assignment on join/leave
	- Section label updates via SectionLabels module
	- Player spawning/respawning to their section
	- New player protection tracking
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- SectionLabels is in server folder
local SectionLabels = require(ServerScriptService:WaitForChild("SectionLabels"))

-- Services will be retrieved after Knit starts
local PlayerDataService

-- Constants
local NEW_PLAYER_PROTECTION_DURATION = 120 -- 2 minutes of protection for new players

-- Create the service
local MapService = Knit.CreateService({
  Name = "MapService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to specific clients
    SectionAssigned = Knit.CreateSignal(), -- Fires (sectionIndex: number)
    ProtectionStatusChanged = Knit.CreateSignal(), -- Fires (status: ProtectionStatus)
  },
})

-- Server-side signals (for other services to listen to)
MapService.PlayerSectionAssigned = GoodSignal.new() -- (userId: number, sectionIndex: number)
MapService.MapStateChanged = GoodSignal.new() -- (mapState: MapState)

-- Internal state
local mapState: MapGeneration.MapState
local playerJoinTimes: { [number]: number } = {} -- userId -> os.time()
local playerSpawnPoints: { [number]: { x: number, y: number, z: number } } = {} -- userId -> spawn point

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function MapService:KnitInit()
  -- Create the map state
  mapState = MapGeneration.createMapState()

  -- Initialize section labels
  SectionLabels.initialize(mapState)

  local sectionCount = #mapState.sections
  print(string.format("[MapService] Initialized: %d sections created", sectionCount))
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function MapService:KnitStart()
  -- Get reference to PlayerDataService for persisting sectionIndex
  PlayerDataService = Knit.GetService("PlayerDataService")

  -- Setup player connections
  Players.PlayerAdded:Connect(function(player)
    self:_handlePlayerJoin(player)
  end)

  Players.PlayerRemoving:Connect(function(player)
    self:_handlePlayerLeave(player)
  end)

  -- Handle players who joined before the service started
  for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
      self:_handlePlayerJoin(player)
    end)
  end

  print("[MapService] Started")
end

--[[
	Internal: Handle player joining.
	Assigns section, updates labels, sets up spawning, and tracks protection.
]]
function MapService:_handlePlayerJoin(player: Player)
  local currentTime = os.time()
  local playerId = tostring(player.UserId)

  -- Assign section to player
  local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)

  -- Track join time for new player protection
  playerJoinTimes[player.UserId] = currentTime

  -- Send initial protection status to client
  task.defer(function()
    self.Client.ProtectionStatusChanged:Fire(player, {
      isProtected = true,
      remainingSeconds = NEW_PLAYER_PROTECTION_DURATION,
      totalDuration = NEW_PLAYER_PROTECTION_DURATION,
    })
  end)

  if sectionIndex then
    print(string.format("[MapService] Assigned section %d to %s", sectionIndex, player.Name))

    -- Persist sectionIndex to player data so client can access it
    local playerData = PlayerDataService:GetData(player.UserId)
    if playerData then
      playerData.sectionIndex = sectionIndex
      PlayerDataService:UpdateData(player.UserId, playerData)
    end

    -- Update section label with player's name
    SectionLabels.onPlayerJoined(player, sectionIndex)

    -- Get spawn point and setup spawning
    local spawnPoint = MapGeneration.getPlayerSpawnPoint(mapState, playerId)
    if spawnPoint then
      self:_setupCharacterSpawning(player, spawnPoint)
      print(
        string.format(
          "[MapService] Spawn point for %s: (%.1f, %.1f, %.1f)",
          player.Name,
          spawnPoint.x,
          spawnPoint.y,
          spawnPoint.z
        )
      )
    end

    -- Fire signals
    self.Client.SectionAssigned:Fire(player, sectionIndex)
    self.PlayerSectionAssigned:Fire(player.UserId, sectionIndex)
    self.MapStateChanged:Fire(mapState)
  else
    warn(
      string.format("[MapService] Failed to assign section to %s - map may be full", player.Name)
    )
  end
end

--[[
	Internal: Handle player leaving.
	Reserves section, updates labels, and cleans up tracking.
]]
function MapService:_handlePlayerLeave(player: Player)
  local playerId = tostring(player.UserId)

  -- Get section index before handling leave (for label update)
  local sectionIndex = MapGeneration.getPlayerSection(mapState, playerId)

  -- Handle leave and reserve section
  local reservedSection = MapGeneration.handlePlayerLeave(mapState, playerId)

  if reservedSection then
    print(string.format("[MapService] Reserved section %d for %s", reservedSection, player.Name))
  end

  -- Update section label to unclaimed
  if sectionIndex then
    SectionLabels.onPlayerLeft(sectionIndex)
  end

  -- Clean up player tracking
  playerSpawnPoints[player.UserId] = nil
  playerJoinTimes[player.UserId] = nil

  -- Fire state changed signal
  self.MapStateChanged:Fire(mapState)
end

--[[
	Internal: Setup character spawning for a player.
	Handles initial spawn and respawns to their section.
]]
function MapService:_setupCharacterSpawning(
  player: Player,
  spawnPoint: { x: number, y: number, z: number }
)
  -- Store spawn point for this player
  playerSpawnPoints[player.UserId] = spawnPoint

  -- Handle character added (initial spawn and respawns)
  player.CharacterAdded:Connect(function(character)
    -- Wait for character to be fully loaded
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
    if humanoidRootPart and playerSpawnPoints[player.UserId] then
      local sp = playerSpawnPoints[player.UserId]
      humanoidRootPart.CFrame = CFrame.new(sp.x, sp.y, sp.z)
      print(
        string.format(
          "[MapService] Spawned %s at section (%.1f, %.1f, %.1f)",
          player.Name,
          sp.x,
          sp.y,
          sp.z
        )
      )
    end
  end)

  -- If character already exists, teleport immediately
  if player.Character then
    local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if humanoidRootPart then
      humanoidRootPart.CFrame = CFrame.new(spawnPoint.x, spawnPoint.y, spawnPoint.z)
    end
  end
end

--[[
	CLIENT: Gets the player's assigned section index.
	
	@param player Player - The player requesting their section
	@return number? - The section index or nil if not assigned
]]
function MapService.Client:GetPlayerSection(player: Player): number?
  local playerId = tostring(player.UserId)
  return MapGeneration.getPlayerSection(mapState, playerId)
end

--[[
	CLIENT: Gets the position of a section by index.
	
	@param player Player - The player requesting (required by Knit)
	@param sectionIndex number - The section index to look up
	@return Vector3Table? - The section center position
]]
function MapService.Client:GetSectionPosition(
  player: Player,
  sectionIndex: number
): { x: number, y: number, z: number }?
  return MapGeneration.getSectionPosition(sectionIndex)
end

--[[
	CLIENT: Checks if the player is currently protected.
	
	@param player Player - The player to check
	@return boolean - Whether the player has protection
]]
function MapService.Client:IsPlayerProtected(player: Player): boolean
  local joinTime = playerJoinTimes[player.UserId]
  if not joinTime then
    return false
  end

  local currentTime = os.time()
  return (currentTime - joinTime) < NEW_PLAYER_PROTECTION_DURATION
end

--[[
	CLIENT: Gets the full map state (read-only snapshot).
	
	@param player Player - The player requesting (required by Knit)
	@return table - Summary of map state
]]
function MapService.Client:GetMapState(player: Player): {
  assignedCount: number,
  availableCount: number,
  maxSections: number,
}
  return {
    assignedCount = MapGeneration.getAssignedCount(mapState),
    availableCount = MapGeneration.getAvailableCount(mapState),
    maxSections = MapGeneration.getMaxSections(),
  }
end

--[[
	SERVER-ONLY: Gets the section index for any player by userId.
	
	@param userId number - The user ID
	@return number? - The section index or nil
]]
function MapService:GetPlayerSection(userId: number): number?
  local playerId = tostring(userId)
  return MapGeneration.getPlayerSection(mapState, playerId)
end

--[[
	SERVER-ONLY: Gets the position of a section by index.
	
	@param sectionIndex number - The section index to look up
	@return Vector3Table? - The section center position
]]
function MapService:GetSectionPosition(sectionIndex: number): { x: number, y: number, z: number }?
  return MapGeneration.getSectionPosition(sectionIndex)
end

--[[
	SERVER-ONLY: Checks if a player is currently protected.
	
	@param userId number - The user ID to check
	@return boolean - Whether the player has protection
]]
function MapService:IsPlayerProtected(userId: number): boolean
  local joinTime = playerJoinTimes[userId]
  if not joinTime then
    return false
  end

  local currentTime = os.time()
  return (currentTime - joinTime) < NEW_PLAYER_PROTECTION_DURATION
end

--[[
	SERVER-ONLY: Gets the remaining protection time for a player.
	
	@param userId number - The user ID to check
	@return number - Remaining seconds of protection (0 if expired)
]]
function MapService:GetProtectionRemaining(userId: number): number
  local joinTime = playerJoinTimes[userId]
  if not joinTime then
    return 0
  end

  local currentTime = os.time()
  local elapsed = currentTime - joinTime
  local remaining = NEW_PLAYER_PROTECTION_DURATION - elapsed

  return math.max(0, remaining)
end

--[[
	SERVER-ONLY: Gets the full internal map state.
	Use with caution - prefer specific methods when possible.
	
	@return MapState - The internal map state
]]
function MapService:GetMapState(): MapGeneration.MapState
  return mapState
end

--[[
	SERVER-ONLY: Gets the spawn point for a player.
	
	@param userId number - The user ID
	@return Vector3Table? - The spawn point or nil
]]
function MapService:GetPlayerSpawnPoint(userId: number): { x: number, y: number, z: number }?
  local playerId = tostring(userId)
  return MapGeneration.getPlayerSpawnPoint(mapState, playerId)
end

--[[
	SERVER-ONLY: Updates a player's protection status and notifies client.
	Used by game loops to notify when protection expires.
	
	@param userId number - The user ID
]]
function MapService:UpdateProtectionStatus(userId: number)
  local player = Players:GetPlayerByUserId(userId)
  if not player then
    return
  end

  local isProtected = self:IsPlayerProtected(userId)
  local remaining = self:GetProtectionRemaining(userId)

  self.Client.ProtectionStatusChanged:Fire(player, {
    isProtected = isProtected,
    remainingSeconds = remaining,
    totalDuration = NEW_PLAYER_PROTECTION_DURATION,
  })

  -- Clean up join time if protection expired
  if not isProtected then
    playerJoinTimes[userId] = nil
  end
end

--[[
	SERVER-ONLY: Gets all player IDs with active protection.
	
	@return {number} - Array of user IDs with protection
]]
function MapService:GetProtectedPlayers(): { number }
  local protected = {}
  local currentTime = os.time()

  for userId, joinTime in pairs(playerJoinTimes) do
    if (currentTime - joinTime) < NEW_PLAYER_PROTECTION_DURATION then
      table.insert(protected, userId)
    end
  end

  return protected
end

--[[
	SERVER-ONLY: Gets the protection duration constant.
	
	@return number - Protection duration in seconds
]]
function MapService:GetProtectionDuration(): number
  return NEW_PLAYER_PROTECTION_DURATION
end

return MapService
