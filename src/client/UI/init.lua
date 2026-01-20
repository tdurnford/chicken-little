--[[
	UI Initialization Module
	Central entry point that mounts all Fusion UI components.
	Handles screen size changes and cleanup on player leave.

	Usage:
		local UI = require(script.Parent.UI)
		UI.initialize() -- Call once after Knit starts
		-- UI components are now ready to use
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

-- Components
local Components = script:WaitForChild("Components")
local MainHUD = require(Components:WaitForChild("MainHUD"))
local InventoryUI = require(Components:WaitForChild("InventoryUI"))
local StoreUI = require(Components:WaitForChild("StoreUI"))
local HatchPreviewUI = require(Components:WaitForChild("HatchPreviewUI"))
local TradeUI = require(Components:WaitForChild("TradeUI"))
local ShieldUI = require(Components:WaitForChild("ShieldUI"))
local DamageUI = require(Components:WaitForChild("DamageUI"))
local ChickenHealthBar = require(Components:WaitForChild("ChickenHealthBar"))
local PredatorHealthBar = require(Components:WaitForChild("PredatorHealthBar"))
local OfflineEarningsUI = require(Components:WaitForChild("OfflineEarningsUI"))
local Tutorial = require(Components:WaitForChild("Tutorial"))
local PredatorWarning = require(Components:WaitForChild("PredatorWarning"))

-- State management
local State = require(script:WaitForChild("State"))

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Module state
local UI = {}
local isInitialized = false
local connections: { RBXScriptConnection } = {}

-- Screen size tracking for responsive UI
local currentScreenSize: Vector2 = Vector2.new(0, 0)
local screenSizeCallbacks: { (Vector2) -> () } = {}

--[[
	Get the current screen size.

	@return Vector2 - Current screen dimensions
]]
function UI.getScreenSize(): Vector2
	return currentScreenSize
end

--[[
	Register a callback for screen size changes.
	Useful for responsive UI adjustments.

	@param callback - Function called with new screen size
	@return () -> () - Unsubscribe function
]]
function UI.onScreenSizeChanged(callback: (Vector2) -> ()): () -> ()
	table.insert(screenSizeCallbacks, callback)
	-- Call immediately with current size
	callback(currentScreenSize)

	return function()
		local index = table.find(screenSizeCallbacks, callback)
		if index then
			table.remove(screenSizeCallbacks, index)
		end
	end
end

--[[
	Internal: Update screen size and notify listeners.
]]
local function updateScreenSize()
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local screenGui = playerGui:FindFirstChild("UIScreenSize")
	if not screenGui then
		-- Create a temporary ScreenGui to measure
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "UIScreenSize"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.Parent = playerGui
	end

	local newSize = screenGui.AbsoluteSize
	if newSize ~= currentScreenSize then
		currentScreenSize = newSize
		for _, callback in ipairs(screenSizeCallbacks) do
			task.spawn(callback, newSize)
		end
	end
end

--[[
	Internal: Setup screen size monitoring.
]]
local function setupScreenSizeMonitoring()
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		localPlayer:GetPropertyChangedSignal("PlayerGui"):Wait()
		playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	end

	-- Create measurement ScreenGui
	local measureGui = Instance.new("ScreenGui")
	measureGui.Name = "UIScreenSize"
	measureGui.ResetOnSpawn = false
	measureGui.IgnoreGuiInset = true
	measureGui.Parent = playerGui

	-- Track size changes
	local sizeConnection = measureGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateScreenSize()
	end)
	table.insert(connections, sizeConnection)

	-- Initial size update
	updateScreenSize()
end

--[[
	Internal: Mount all UI components.
	Called during initialization.
]]
local function mountComponents(): boolean
	local success = true

	-- Mount MainHUD first (other components may reference its ScreenGui)
	if not MainHUD.create() then
		warn("[UI] Failed to create MainHUD")
		success = false
	end

	-- Mount Inventory UI
	if not InventoryUI.create() then
		warn("[UI] Failed to create InventoryUI")
		success = false
	end

	-- Mount Store UI
	if not StoreUI.create() then
		warn("[UI] Failed to create StoreUI")
		success = false
	end

	-- Mount Hatch Preview UI
	if not HatchPreviewUI.create() then
		warn("[UI] Failed to create HatchPreviewUI")
		success = false
	end

	-- Mount Trade UI
	if not TradeUI.create() then
		warn("[UI] Failed to create TradeUI")
		success = false
	end

	-- Mount Offline Earnings UI
	if not OfflineEarningsUI.create() then
		warn("[UI] Failed to create OfflineEarningsUI")
		success = false
	end

	-- Mount Tutorial UI
	if not Tutorial.create() then
		warn("[UI] Failed to create Tutorial")
		success = false
	end

	-- Initialize DamageUI (uses initialize pattern)
	DamageUI.initialize()

	-- Initialize PredatorWarning (uses initialize pattern)
	PredatorWarning.initialize()

	-- Mount ShieldUI
	if not ShieldUI.create() then
		warn("[UI] Failed to create ShieldUI")
		success = false
	end

	return success
end

--[[
	Internal: Cleanup all UI components.
	Called during shutdown.
]]
local function unmountComponents()
	-- Destroy all components in reverse order of creation
	ShieldUI.destroy()
	PredatorWarning.cleanup()
	DamageUI.cleanup()
	Tutorial.destroy()
	OfflineEarningsUI.destroy()
	TradeUI.destroy()
	HatchPreviewUI.destroy()
	StoreUI.destroy()
	InventoryUI.destroy()
	MainHUD.destroy()

	-- Cleanup health bars
	ChickenHealthBar.cleanup()
	PredatorHealthBar.cleanup()
end

--[[
	Initialize the UI system.
	Mounts all components and sets up event handlers.
	Must be called after Knit.Start() resolves.

	@return boolean - True if all components mounted successfully
]]
function UI.initialize(): boolean
	if isInitialized then
		warn("[UI] Already initialized")
		return true
	end

	print("[UI] Initializing UI system...")

	-- Initialize Fusion state first
	State.initialize()

	-- Setup screen size monitoring
	setupScreenSizeMonitoring()

	-- Mount all components
	local success = mountComponents()

	-- Setup player leaving cleanup
	local leavingConnection = localPlayer.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			UI.cleanup()
		end
	end)
	table.insert(connections, leavingConnection)

	isInitialized = true

	if success then
		print("[UI] UI system initialized successfully")
	else
		warn("[UI] UI system initialized with some component failures")
	end

	return success
end

--[[
	Check if the UI system is initialized.

	@return boolean
]]
function UI.isInitialized(): boolean
	return isInitialized
end

--[[
	Cleanup the UI system.
	Destroys all components and disconnects events.
]]
function UI.cleanup()
	if not isInitialized then
		return
	end

	print("[UI] Cleaning up UI system...")

	-- Disconnect all connections
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	-- Clear screen size callbacks
	screenSizeCallbacks = {}

	-- Unmount all components
	unmountComponents()

	-- Cleanup state
	State.cleanup()

	-- Remove measurement ScreenGui
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local measureGui = playerGui:FindFirstChild("UIScreenSize")
		if measureGui then
			measureGui:Destroy()
		end
	end

	isInitialized = false
	print("[UI] UI system cleaned up")
end

--[[
	Get a reference to a UI component module.
	Useful for accessing component APIs after initialization.

	@param name - Component name (e.g., "MainHUD", "InventoryUI")
	@return table? - Component module or nil if not found
]]
function UI.getComponent(name: string): any?
	local componentMap = {
		MainHUD = MainHUD,
		InventoryUI = InventoryUI,
		StoreUI = StoreUI,
		HatchPreviewUI = HatchPreviewUI,
		TradeUI = TradeUI,
		ShieldUI = ShieldUI,
		DamageUI = DamageUI,
		ChickenHealthBar = ChickenHealthBar,
		PredatorHealthBar = PredatorHealthBar,
		OfflineEarningsUI = OfflineEarningsUI,
		Tutorial = Tutorial,
		PredatorWarning = PredatorWarning,
	}
	return componentMap[name]
end

--[[
	Get the State module for reactive UI state.

	@return State module
]]
function UI.getState()
	return State
end

-- Export individual components for direct access
UI.Components = {
	MainHUD = MainHUD,
	InventoryUI = InventoryUI,
	StoreUI = StoreUI,
	HatchPreviewUI = HatchPreviewUI,
	TradeUI = TradeUI,
	ShieldUI = ShieldUI,
	DamageUI = DamageUI,
	ChickenHealthBar = ChickenHealthBar,
	PredatorHealthBar = PredatorHealthBar,
	OfflineEarningsUI = OfflineEarningsUI,
	Tutorial = Tutorial,
	PredatorWarning = PredatorWarning,
}

-- Export State for direct access
UI.State = State

return UI
