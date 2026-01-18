--[[
	KnitServer - Server Bootstrap Script
	
	Initializes Knit framework and loads all server services.
	This replaces the monolithic Main.server.lua with a cleaner architecture.
	
	Services are loaded from src/server/Services/ and automatically:
	- Initialize via KnitInit
	- Start via KnitStart
	- Expose client-facing methods and events
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for packages to be available
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

-- Services folder location
local ServicesFolder = ServerScriptService:WaitForChild("Services")

-- Load all services
print("[KnitServer] Loading services...")
Knit.AddServices(ServicesFolder)

-- Start Knit
Knit.Start():andThen(function()
	print("[KnitServer] All services started successfully!")
end):catch(function(err)
	warn("[KnitServer] Failed to start:", err)
end)
