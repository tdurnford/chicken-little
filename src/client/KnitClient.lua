--[[
	KnitClient.lua
	Client-side Knit bootstrap module.
	
	Initializes Knit and loads all controllers from the Controllers directory.
	This module should be required and started from Main.client.lua.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local KnitClient = {}

-- Track if Knit has been started
local started = false
local startedPromise = nil

--[[
	Loads all controller modules from the Controllers directory.
	Controllers must follow the Knit controller pattern with CreateController.
]]
local function loadControllers()
  local controllersFolder = script.Parent:FindFirstChild("Controllers")
  if not controllersFolder then
    warn("[KnitClient] Controllers folder not found")
    return
  end

  local controllerCount = 0
  for _, child in ipairs(controllersFolder:GetChildren()) do
    if child:IsA("ModuleScript") and not child.Name:match("%.spec$") then
      local success, err = pcall(function()
        require(child)
      end)
      if success then
        controllerCount = controllerCount + 1
        print("[KnitClient] Loaded controller:", child.Name)
      else
        warn("[KnitClient] Failed to load controller", child.Name, "-", err)
      end
    end
  end

  print("[KnitClient] Loaded", controllerCount, "controllers")
end

--[[
	Initializes and starts the Knit client.
	Should be called once from Main.client.lua.
	
	@return Promise that resolves when Knit has started
]]
function KnitClient.start()
  if started then
    warn("[KnitClient] Already started")
    return startedPromise
  end

  print("[KnitClient] Loading controllers...")
  loadControllers()

  print("[KnitClient] Starting Knit...")
  startedPromise = Knit.Start()
    :andThen(function()
      started = true
      print("[KnitClient] Knit started successfully")
    end)
    :catch(function(err)
      warn("[KnitClient] Failed to start Knit:", err)
    end)

  return startedPromise
end

--[[
	Returns whether Knit has been started.
	@return boolean
]]
function KnitClient.isStarted(): boolean
  return started
end

--[[
	Returns the Knit module for creating controllers.
	@return Knit module
]]
function KnitClient.getKnit()
  return Knit
end

--[[
	Gets a service from the server by name.
	Must be called after Knit.Start() has resolved.
	@param serviceName The name of the service to get
	@return The service or nil if not found
]]
function KnitClient.getService(serviceName: string)
  if not started then
    warn("[KnitClient] Cannot get service before Knit has started")
    return nil
  end
  return Knit.GetService(serviceName)
end

return KnitClient
