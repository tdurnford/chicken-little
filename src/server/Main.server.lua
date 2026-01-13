local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Util = require(Shared:WaitForChild("Util"))
local RemoteSetup = require(Server:WaitForChild("RemoteSetup"))
local DataPersistence = require(Server:WaitForChild("DataPersistence"))

-- Initialize all RemoteEvents and RemoteFunctions
local remotes = RemoteSetup.initialize()

-- Initialize DataPersistence system (handles player data saving/loading)
local dataPersistenceStarted = DataPersistence.start()
if dataPersistenceStarted then
  print("[Main.server] DataPersistence initialized successfully")
else
  warn("[Main.server] DataPersistence failed to initialize DataStore - running in offline mode")
end

print("Server started. Clamp demo:", Util.clamp(10, 0, 5))
print("[Main.server] " .. RemoteSetup.getSummary())
