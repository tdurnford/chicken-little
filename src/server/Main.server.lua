local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Util = require(Shared:WaitForChild("Util"))
local RemoteSetup = require(Server:WaitForChild("RemoteSetup"))
local DataPersistence = require(Server:WaitForChild("DataPersistence"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Player Data Sync Configuration
local DATA_SYNC_THROTTLE_INTERVAL = 0.1 -- Minimum seconds between data updates per player
local lastDataSyncTime: { [number]: number } = {} -- Tracks last sync time per player

-- Initialize all RemoteEvents and RemoteFunctions
local remotes = RemoteSetup.initialize()

--[[
  Fires PlayerDataChanged event to a specific player with throttling.
  Throttles frequent updates to prevent network spam.
  @param player Player - The player to send data to
  @param data table? - Optional data to send (defaults to cached data)
  @param forceSync boolean? - Optional flag to bypass throttle
]]
local function syncPlayerData(player: Player, data: { [string]: any }?, forceSync: boolean?)
  local userId = player.UserId
  local currentTime = os.clock()
  local lastSync = lastDataSyncTime[userId] or 0

  -- Throttle check (skip if forceSync is true)
  if not forceSync and (currentTime - lastSync) < DATA_SYNC_THROTTLE_INTERVAL then
    return
  end

  -- Get data from cache if not provided
  local syncData = data or DataPersistence.getData(userId)
  if not syncData then
    return
  end

  -- Fire the event to the client
  local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
  if playerDataChangedEvent then
    playerDataChangedEvent:FireClient(player, syncData)
    lastDataSyncTime[userId] = currentTime
  end
end

-- Setup GetPlayerData RemoteFunction handler
local getPlayerDataFunc = RemoteSetup.getFunction("GetPlayerData")
if getPlayerDataFunc then
  getPlayerDataFunc.OnServerInvoke = function(player: Player)
    local userId = player.UserId
    local data = DataPersistence.getData(userId)
    return data
  end
end

-- Initialize DataPersistence system (handles player data saving/loading)
local dataPersistenceStarted = DataPersistence.start()
if dataPersistenceStarted then
  print("[Main.server] DataPersistence initialized successfully")
else
  warn("[Main.server] DataPersistence failed to initialize DataStore - running in offline mode")
end

-- Initialize Map Generation system
local mapState = MapGeneration.createMapState()
local sectionCount = #mapState.sections
print(string.format("[Main.server] MapGeneration initialized: %d sections created", sectionCount))

-- Handle player section assignment on join
Players.PlayerAdded:Connect(function(player)
  local currentTime = os.time()
  local playerId = tostring(player.UserId)
  local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)

  if sectionIndex then
    print(string.format("[Main.server] Assigned section %d to %s", sectionIndex, player.Name))
    local spawnPoint = MapGeneration.getPlayerSpawnPoint(mapState, playerId)
    if spawnPoint then
      print(
        string.format(
          "[Main.server] Spawn point for %s: (%.1f, %.1f, %.1f)",
          player.Name,
          spawnPoint.x,
          spawnPoint.y,
          spawnPoint.z
        )
      )
    end
  else
    warn(
      string.format("[Main.server] Failed to assign section to %s - map may be full", player.Name)
    )
  end

  -- Sync player data to client after DataPersistence has loaded it
  -- Use task.defer to ensure DataPersistence.PlayerAdded completes first
  task.defer(function()
    local data = DataPersistence.getData(player.UserId)
    if data then
      syncPlayerData(player, data, true) -- Force sync on join
      print(string.format("[Main.server] Synced player data to %s", player.Name))
    end
  end)
end)

-- Handle player section reservation on leave
Players.PlayerRemoving:Connect(function(player)
  local playerId = tostring(player.UserId)
  local reservedSection = MapGeneration.handlePlayerLeave(mapState, playerId)

  if reservedSection then
    print(string.format("[Main.server] Reserved section %d for %s", reservedSection, player.Name))
  end

  -- Clean up sync tracking for this player
  lastDataSyncTime[player.UserId] = nil
end)

print("Server started. Clamp demo:", Util.clamp(10, 0, 5))
print("[Main.server] " .. RemoteSetup.getSummary())
print("[Main.server] " .. MapGeneration.getSummary(mapState))
