--[[
	KnitServer.lua
	Server-side Knit bootstrap module.
	
	Initializes Knit and loads all services from the Services directory.
	This module should be required and started from Main.server.lua.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local KnitServer = {}

-- Track if Knit has been started
local started = false

--[[
	Loads all service modules from the Services directory.
	Services must follow the Knit service pattern with CreateService.
]]
local function loadServices()
  local servicesFolder = ServerScriptService:FindFirstChild("Services")
  if not servicesFolder then
    warn("[KnitServer] Services folder not found")
    return
  end

  local serviceCount = 0
  for _, child in ipairs(servicesFolder:GetChildren()) do
    if child:IsA("ModuleScript") and not child.Name:match("%.spec$") then
      local success, err = pcall(function()
        require(child)
      end)
      if success then
        serviceCount = serviceCount + 1
        print("[KnitServer] Loaded service:", child.Name)
      else
        warn("[KnitServer] Failed to load service", child.Name, "-", err)
      end
    end
  end

  print("[KnitServer] Loaded", serviceCount, "services")
end

--[[
	Initializes and starts the Knit server.
	Should be called once from Main.server.lua.
	
	@return Promise that resolves when Knit has started
]]
function KnitServer.start()
  if started then
    warn("[KnitServer] Already started")
    return
  end

  print("[KnitServer] Loading services...")
  loadServices()

  print("[KnitServer] Starting Knit...")
  Knit.Start()
    :andThen(function()
      started = true
      print("[KnitServer] Knit started successfully")
    end)
    :catch(function(err)
      warn("[KnitServer] Failed to start Knit:", err)
    end)
end

--[[
	Returns whether Knit has been started.
	@return boolean
]]
function KnitServer.isStarted(): boolean
  return started
end

--[[
	Returns the Knit module for creating services.
	@return Knit module
]]
function KnitServer.getKnit()
  return Knit
end

return KnitServer
