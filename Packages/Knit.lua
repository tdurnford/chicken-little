--[[
	Knit Framework - Stub Implementation
	
	This is a lightweight stub that mirrors the Knit API (sleitnick/knit@1.7.0).
	Replace this with the actual Knit package by running: wally install
	
	Knit provides:
	- Services (server-side singletons)
	- Controllers (client-side singletons)
	- Automatic remote event/function management
	
	Documentation: https://sleitnick.github.io/Knit/
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local IS_SERVER = RunService:IsServer()

-- Signal class for events
local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({
		_connections = {},
		_bindableEvent = Instance.new("BindableEvent"),
	}, Signal)
	return self
end

function Signal:Fire(...)
	self._bindableEvent:Fire(...)
end

function Signal:Connect(callback)
	local connection = self._bindableEvent.Event:Connect(callback)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Wait()
	return self._bindableEvent.Event:Wait()
end

function Signal:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._bindableEvent:Destroy()
end

-- RemoteSignal class for client-server events
local RemoteSignal = {}
RemoteSignal.__index = RemoteSignal

function RemoteSignal.new(remoteEvent: RemoteEvent)
	local self = setmetatable({
		_remoteEvent = remoteEvent,
		_connections = {},
	}, RemoteSignal)
	return self
end

function RemoteSignal:Fire(...)
	if IS_SERVER then
		error("Use :FireClient or :FireAll on server")
	else
		self._remoteEvent:FireServer(...)
	end
end

function RemoteSignal:FireClient(player: Player, ...)
	if not IS_SERVER then
		error("FireClient can only be called from server")
	end
	self._remoteEvent:FireClient(player, ...)
end

function RemoteSignal:FireAll(...)
	if not IS_SERVER then
		error("FireAll can only be called from server")
	end
	self._remoteEvent:FireAllClients(...)
end

function RemoteSignal:Connect(callback)
	local connection
	if IS_SERVER then
		connection = self._remoteEvent.OnServerEvent:Connect(callback)
	else
		connection = self._remoteEvent.OnClientEvent:Connect(callback)
	end
	table.insert(self._connections, connection)
	return connection
end

function RemoteSignal:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
end

-- RemoteProperty class for synced properties
local RemoteProperty = {}
RemoteProperty.__index = RemoteProperty

function RemoteProperty.new(initialValue: any)
	local self = setmetatable({
		_value = initialValue,
		_remoteEvent = nil,
		_changed = Signal.new(),
	}, RemoteProperty)
	return self
end

function RemoteProperty:Get()
	return self._value
end

function RemoteProperty:Set(value)
	if self._value ~= value then
		self._value = value
		self._changed:Fire(value)
		if self._remoteEvent then
			if IS_SERVER then
				self._remoteEvent:FireAllClients(value)
			end
		end
	end
end

function RemoteProperty:Observe(callback)
	callback(self._value)
	return self._changed:Connect(callback)
end

-- Knit main module
local Knit = {}
Knit.Util = {
	Signal = Signal,
	RemoteSignal = RemoteSignal,
	RemoteProperty = RemoteProperty,
}

-- Storage for services and controllers
local services = {}
local controllers = {}
local started = false
local onStartCallbacks = {}

-- Remote folder management
local remotesFolder = nil

local function getRemotesFolder()
	if remotesFolder then
		return remotesFolder
	end
	
	if IS_SERVER then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "KnitRemotes"
		remotesFolder.Parent = ReplicatedStorage
	else
		remotesFolder = ReplicatedStorage:WaitForChild("KnitRemotes", 10)
	end
	
	return remotesFolder
end

local function createServiceFolder(serviceName: string)
	local folder = Instance.new("Folder")
	folder.Name = serviceName
	folder.Parent = getRemotesFolder()
	return folder
end

local function setupServiceRemotes(service, serviceFolder)
	if not service.Client then
		return
	end
	
	-- Setup remote functions (methods)
	for methodName, method in pairs(service.Client) do
		if type(method) == "function" then
			local remoteFunction = Instance.new("RemoteFunction")
			remoteFunction.Name = methodName
			remoteFunction.Parent = serviceFolder
			
			remoteFunction.OnServerInvoke = function(player, ...)
				return method(service.Client, player, ...)
			end
		end
	end
end

--[[
	Creates a new Knit service.
	Services run on the server and can expose methods/events to clients.
	
	@param serviceDef table - Service definition with Name and optional Client table
	@return Service - The created service
]]
function Knit.CreateService(serviceDef: {
	Name: string,
	Client: {[string]: any}?,
	[string]: any,
})
	assert(IS_SERVER, "CreateService can only be called from the server")
	assert(serviceDef.Name, "Service must have a Name")
	assert(not services[serviceDef.Name], "Service already exists: " .. serviceDef.Name)
	
	local service = serviceDef
	
	-- Initialize Client table if not present
	if not service.Client then
		service.Client = {}
	end
	
	-- Set reference to server for Client methods
	service.Client.Server = service
	
	services[serviceDef.Name] = service
	return service
end

--[[
	Creates a new Knit controller.
	Controllers run on the client and can connect to services.
	
	@param controllerDef table - Controller definition with Name
	@return Controller - The created controller
]]
function Knit.CreateController(controllerDef: {
	Name: string,
	[string]: any,
})
	assert(not IS_SERVER, "CreateController can only be called from the client")
	assert(controllerDef.Name, "Controller must have a Name")
	assert(not controllers[controllerDef.Name], "Controller already exists: " .. controllerDef.Name)
	
	local controller = controllerDef
	controllers[controllerDef.Name] = controller
	return controller
end

--[[
	Gets a service by name.
	On server: returns the service directly
	On client: returns a service proxy with remote methods
	
	@param serviceName string - Name of the service
	@return Service - The service or service proxy
]]
function Knit.GetService(serviceName: string)
	if IS_SERVER then
		assert(services[serviceName], "Service not found: " .. serviceName)
		return services[serviceName]
	else
		-- Client: create proxy to access remotes
		local serviceFolder = getRemotesFolder():WaitForChild(serviceName, 10)
		if not serviceFolder then
			error("Service not found: " .. serviceName)
		end
		
		local proxy = {}
		local proxyMeta = {
			__index = function(_, methodName)
				local remote = serviceFolder:FindFirstChild(methodName)
				if remote then
					if remote:IsA("RemoteFunction") then
						return function(_, ...)
							return remote:InvokeServer(...)
						end
					elseif remote:IsA("RemoteEvent") then
						return RemoteSignal.new(remote)
					end
				end
				error("Method/Event not found on service: " .. methodName)
			end,
		}
		setmetatable(proxy, proxyMeta)
		return proxy
	end
end

--[[
	Gets a controller by name (client only).
	
	@param controllerName string - Name of the controller
	@return Controller - The controller
]]
function Knit.GetController(controllerName: string)
	assert(not IS_SERVER, "GetController can only be called from the client")
	assert(controllers[controllerName], "Controller not found: " .. controllerName)
	return controllers[controllerName]
end

--[[
	Adds all services/controllers from child ModuleScripts.
	
	@param parent Instance - Parent folder containing modules
	@return Promise-like - Resolves when all modules are loaded
]]
function Knit.AddServices(parent: Instance)
	assert(IS_SERVER, "AddServices can only be called from the server")
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") then
			local success, result = pcall(require, child)
			if not success then
				warn("[Knit] Failed to load service:", child.Name, result)
			end
		end
	end
end

function Knit.AddControllers(parent: Instance)
	assert(not IS_SERVER, "AddControllers can only be called from the client")
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") then
			local success, result = pcall(require, child)
			if not success then
				warn("[Knit] Failed to load controller:", child.Name, result)
			end
		end
	end
end

--[[
	Starts Knit and all registered services/controllers.
	Calls KnitInit on all services/controllers, then KnitStart.
	
	@return Promise-like - Resolves when started
]]
function Knit.Start()
	assert(not started, "Knit already started")
	started = true
	
	-- Create pseudo-promise return
	local promise = {
		_callbacks = {},
	}
	
	function promise:andThen(callback)
		table.insert(self._callbacks, callback)
		return self
	end
	
	function promise:catch(callback)
		-- Error handling stub
		return self
	end
	
	-- Run initialization
	task.spawn(function()
		local toInit = IS_SERVER and services or controllers
		local toStart = IS_SERVER and services or controllers
		
		-- Setup remotes for services
		if IS_SERVER then
			for serviceName, service in pairs(services) do
				local serviceFolder = createServiceFolder(serviceName)
				setupServiceRemotes(service, serviceFolder)
			end
		end
		
		-- Call KnitInit on all
		for name, obj in pairs(toInit) do
			if type(obj.KnitInit) == "function" then
				local success, err = pcall(obj.KnitInit, obj)
				if not success then
					warn("[Knit] KnitInit failed for", name, ":", err)
				end
			end
		end
		
		-- Call KnitStart on all
		for name, obj in pairs(toStart) do
			if type(obj.KnitStart) == "function" then
				task.spawn(function()
					local success, err = pcall(obj.KnitStart, obj)
					if not success then
						warn("[Knit] KnitStart failed for", name, ":", err)
					end
				end)
			end
		end
		
		-- Execute callbacks
		for _, callback in ipairs(promise._callbacks) do
			task.spawn(callback)
		end
		
		-- Execute onStart callbacks
		for _, callback in ipairs(onStartCallbacks) do
			task.spawn(callback)
		end
		
		print("[Knit] Started successfully")
	end)
	
	return promise
end

--[[
	Registers a callback to run after Knit.Start() completes.
	
	@param callback function - Callback to run
]]
function Knit.OnStart(callback: () -> ())
	if started then
		task.spawn(callback)
	else
		table.insert(onStartCallbacks, callback)
	end
end

-- Export utilities
Knit.Signal = Signal
Knit.RemoteSignal = RemoteSignal
Knit.RemoteProperty = RemoteProperty

return Knit
