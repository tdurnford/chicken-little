--[[
	KnitClient - Client Bootstrap Script
	
	Initializes Knit framework and loads all client controllers.
	This replaces the monolithic Main.client.lua with a cleaner architecture.
	
	Controllers are loaded from src/client/Controllers/ and automatically:
	- Initialize via KnitInit
	- Start via KnitStart
	- Connect to server services
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for packages to be available
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

-- Controllers folder location
local ControllersFolder = script.Parent:WaitForChild("Controllers")

-- Load all controllers
print("[KnitClient] Loading controllers...")
Knit.AddControllers(ControllersFolder)

-- Start Knit
Knit.Start():andThen(function()
	print("[KnitClient] All controllers started successfully!")
end):catch(function(err)
	warn("[KnitClient] Failed to start:", err)
end)
