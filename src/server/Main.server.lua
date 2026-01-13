local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Util = require(Shared:WaitForChild("Util"))
local RemoteSetup = require(Server:WaitForChild("RemoteSetup"))
local DataPersistence = require(Server:WaitForChild("DataPersistence"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Initialize all RemoteEvents and RemoteFunctions
local remotes = RemoteSetup.initialize()

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
end)

-- Handle player section reservation on leave
Players.PlayerRemoving:Connect(function(player)
  local playerId = tostring(player.UserId)
  local reservedSection = MapGeneration.handlePlayerLeave(mapState, playerId)

  if reservedSection then
    print(string.format("[Main.server] Reserved section %d for %s", reservedSection, player.Name))
  end
end)

print("Server started. Clamp demo:", Util.clamp(10, 0, 5))
print("[Main.server] " .. RemoteSetup.getSummary())
print("[Main.server] " .. MapGeneration.getSummary(mapState))
