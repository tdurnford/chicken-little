local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Util = require(Shared:WaitForChild("Util"))
local RemoteSetup = require(Server:WaitForChild("RemoteSetup"))

-- Initialize all RemoteEvents and RemoteFunctions
local remotes = RemoteSetup.initialize()

print("Server started. Clamp demo:", Util.clamp(10, 0, 5))
print("[Main.server] " .. RemoteSetup.getSummary())
