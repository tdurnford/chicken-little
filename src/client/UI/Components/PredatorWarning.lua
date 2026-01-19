--[[
	PredatorWarning Component (Fusion)
	Displays warning notifications when predators spawn and attack chickens.
	Shows directional indicator, screen flash, and "Chicken Under Attack!" message.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring

-- Types
export type WarningState = {
	predatorId: string,
	predatorType: string,
	threatLevel: string,
	position: Vector3,
	startTime: number,
	isActive: boolean,
}

export type WarningSummary = {
	activeCount: number,
	hasUI: boolean,
	warnings: { { predatorId: string, predatorType: string, threatLevel: string } },
}

-- Module state
local PredatorWarning = {}
local screenGui: ScreenGui? = nil
local scope: Fusion.Scope? = nil
local updateConnection: RBXScriptConnection? = nil

-- Reactive state
local hasActiveWarning: Fusion.Value<boolean>? = nil
local currentThreatLevel: Fusion.Value<string>? = nil
local currentPredatorType: Fusion.Value<string>? = nil
local showMessage: Fusion.Value<boolean>? = nil
local showFlash: Fusion.Value<boolean>? = nil
local arrowRotation: Fusion.Value<number>? = nil
local arrowVisible: Fusion.Value<boolean>? = nil
local arrowPositionX: Fusion.Value<number>? = nil
local arrowPositionY: Fusion.Value<number>? = nil

-- Active warnings tracking
local activeWarnings: { [string]: WarningState } = {}

-- Threat level colors
local THREAT_COLORS: { [string]: Color3 } = {
	Minor = Color3.fromRGB(150, 150, 100),
	Moderate = Color3.fromRGB(200, 180, 80),
	Dangerous = Color3.fromRGB(255, 140, 50),
	Severe = Color3.fromRGB(255, 80, 80),
	Deadly = Color3.fromRGB(200, 50, 150),
	Catastrophic = Color3.fromRGB(150, 50, 200),
}

-- Warning display settings
local WARNING_MESSAGE_DURATION = 4
local EDGE_INDICATOR_THICKNESS = 8
local DIRECTION_ARROW_SIZE = 50

-- Get threat color
local function getThreatColor(threatLevel: string): Color3
	return THREAT_COLORS[threatLevel] or THREAT_COLORS.Minor
end

-- Create screen flash overlay
local function createFlashOverlay(fusionScope: Fusion.Scope)
	local flashColor = Computed(fusionScope, function(use)
		local threat = use(currentThreatLevel :: any)
		return getThreatColor(threat)
	end)

	local flashTransparency = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(showFlash :: any) then 0.6 else 1
	end), 30)

	return New(fusionScope, "Frame")({
		Name = "FlashOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = flashColor,
		BackgroundTransparency = flashTransparency,
		BorderSizePixel = 0,
		Visible = Computed(fusionScope, function(use)
			return use(flashTransparency) < 0.99
		end),
	})
end

-- Create edge indicators
local function createEdgeIndicators(fusionScope: Fusion.Scope)
	local edgeColor = Computed(fusionScope, function(use)
		local threat = use(currentThreatLevel :: any)
		return getThreatColor(threat)
	end)

	local edgeTransparency = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(hasActiveWarning :: any) then 0.5 else 1
	end), 15)

	local edgePositions = {
		{ position = UDim2.new(0, 0, 0, 0), size = UDim2.new(0, EDGE_INDICATOR_THICKNESS, 1, 0), name = "LeftEdge" },
		{ position = UDim2.new(1, -EDGE_INDICATOR_THICKNESS, 0, 0), size = UDim2.new(0, EDGE_INDICATOR_THICKNESS, 1, 0), name = "RightEdge" },
		{ position = UDim2.new(0, 0, 0, 0), size = UDim2.new(1, 0, 0, EDGE_INDICATOR_THICKNESS), name = "TopEdge" },
		{ position = UDim2.new(0, 0, 1, -EDGE_INDICATOR_THICKNESS), size = UDim2.new(1, 0, 0, EDGE_INDICATOR_THICKNESS), name = "BottomEdge" },
	}

	local edges = {}
	for _, edgeConfig in ipairs(edgePositions) do
		table.insert(edges, New(fusionScope, "Frame")({
			Name = edgeConfig.name,
			Position = edgeConfig.position,
			Size = edgeConfig.size,
			BackgroundColor3 = edgeColor,
			BackgroundTransparency = edgeTransparency,
			BorderSizePixel = 0,
		}))
	end

	return edges
end

-- Create warning message
local function createWarningMessage(fusionScope: Fusion.Scope)
	local messageColor = Computed(fusionScope, function(use)
		local threat = use(currentThreatLevel :: any)
		return getThreatColor(threat)
	end)

	local messageTransparency = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(showMessage :: any) then 0 else 1
	end), 20)

	local predatorTypeText = Computed(fusionScope, function(use)
		local predatorType = use(currentPredatorType :: any)
		local threatLevel = use(currentThreatLevel :: any)
		local config = PredatorConfig.get(predatorType)
		local displayName = config and config.displayName or predatorType
		return displayName .. " (" .. threatLevel .. " Threat)"
	end)

	return New(fusionScope, "Frame")({
		Name = "MessageContainer",
		Size = UDim2.new(0, 400, 0, 90),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,

		[Children] = {
			-- Main warning message
			New(fusionScope, "TextLabel")({
				Name = "WarningMessage",
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BackgroundTransparency = 0.3,
				Text = "⚠️ CHICKEN UNDER ATTACK! ⚠️",
				TextColor3 = messageColor,
				TextStrokeTransparency = 0,
				TextStrokeColor3 = Color3.fromRGB(100, 50, 0),
				Font = Enum.Font.GothamBold,
				TextSize = 24,
				TextTransparency = messageTransparency,

				[Children] = {
					New(fusionScope, "UICorner")({
						CornerRadius = UDim.new(0, 8),
					}),
				},
			}),

			-- Predator type label
			New(fusionScope, "TextLabel")({
				Name = "PredatorTypeLabel",
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 0, 55),
				BackgroundTransparency = 1,
				Text = predatorTypeText,
				TextColor3 = messageColor,
				TextStrokeTransparency = 0.5,
				Font = Enum.Font.Gotham,
				TextSize = 18,
				TextTransparency = messageTransparency,
			}),
		},
	})
end

-- Create direction arrow
local function createDirectionArrow(fusionScope: Fusion.Scope)
	local arrowColor = Computed(fusionScope, function(use)
		local threat = use(currentThreatLevel :: any)
		return getThreatColor(threat)
	end)

	local arrowPosition = Computed(fusionScope, function(use)
		local x = use(arrowPositionX :: any)
		local y = use(arrowPositionY :: any)
		return UDim2.new(0, x - DIRECTION_ARROW_SIZE / 2, 0, y - DIRECTION_ARROW_SIZE / 2)
	end)

	return New(fusionScope, "Frame")({
		Name = "DirectionArrow",
		Size = UDim2.new(0, DIRECTION_ARROW_SIZE, 0, DIRECTION_ARROW_SIZE),
		Position = arrowPosition,
		BackgroundTransparency = 1,
		Rotation = Computed(fusionScope, function(use)
			return use(arrowRotation :: any)
		end),
		Visible = Computed(fusionScope, function(use)
			return use(arrowVisible :: any)
		end),

		[Children] = {
			New(fusionScope, "TextLabel")({
				Name = "ArrowIcon",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = "▶",
				TextColor3 = arrowColor,
				TextStrokeTransparency = 0,
				TextStrokeColor3 = Color3.fromRGB(100, 0, 0),
				Font = Enum.Font.GothamBold,
				TextSize = 36,
			}),
		},
	})
end

-- Update direction arrow to point towards predator
local function updateDirectionArrow()
	if not arrowVisible or not arrowRotation then
		return
	end

	-- Find the first active warning
	local targetPosition: Vector3? = nil
	local threatLevel: string = "Minor"

	for _, warning in pairs(activeWarnings) do
		if warning.isActive then
			targetPosition = warning.position
			threatLevel = warning.threatLevel
			break
		end
	end

	if not targetPosition then
		(arrowVisible :: any):set(false)
		return
	end

	-- Get camera and calculate direction
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local localPlayer = Players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		return
	end

	-- Check if predator is on screen
	local screenPos, onScreen = camera:WorldToScreenPoint(targetPosition)

	if onScreen then
		(arrowVisible :: any):set(false)
		return
	end

	-- Calculate direction from player to predator
	local playerPos = humanoidRootPart.Position
	local direction = (targetPosition - playerPos).Unit

	-- Project direction to screen space
	local cameraForward = camera.CFrame.LookVector
	local cameraRight = camera.CFrame.RightVector

	local dotForward = direction:Dot(cameraForward)
	local dotRight = direction:Dot(cameraRight)

	-- Calculate angle for arrow rotation
	local angle = math.atan2(dotRight, dotForward)

	-- Position arrow at edge of screen in the direction of predator
	local screenSize = camera.ViewportSize
	local centerX = screenSize.X / 2
	local centerY = screenSize.Y / 2
	local edgeOffset = 100

	local arrowX = centerX + math.sin(angle) * (centerX - edgeOffset)
	local arrowY = centerY - math.cos(angle) * (centerY - edgeOffset)

	arrowX = math.clamp(arrowX, edgeOffset, screenSize.X - edgeOffset)
	arrowY = math.clamp(arrowY, edgeOffset, screenSize.Y - edgeOffset)

	-- Update arrow state
	(arrowPositionX :: any):set(arrowX)
	(arrowPositionY :: any):set(arrowY)
	(arrowRotation :: any):set(math.deg(angle))
	(arrowVisible :: any):set(true)
end

-- Start the update loop for direction arrow
local function startUpdateLoop()
	if updateConnection then
		return
	end

	updateConnection = RunService.Heartbeat:Connect(function()
		updateDirectionArrow()
	end)
end

-- Stop the update loop
local function stopUpdateLoop()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
end

-- Initialize the warning system
function PredatorWarning.initialize()
	local player = Players.LocalPlayer
	if not player then
		warn("PredatorWarning: No LocalPlayer found")
		return
	end

	-- Clean up existing
	PredatorWarning.cleanup()

	-- Create Fusion scope
	scope = Fusion.scoped({})

	-- Initialize reactive state
	hasActiveWarning = Value(scope, false)
	currentThreatLevel = Value(scope, "Minor")
	currentPredatorType = Value(scope, "")
	showMessage = Value(scope, false)
	showFlash = Value(scope, false)
	arrowRotation = Value(scope, 0)
	arrowVisible = Value(scope, false)
	arrowPositionX = Value(scope, 0)
	arrowPositionY = Value(scope, 0)

	-- Create edge indicators
	local edgeIndicators = createEdgeIndicators(scope)

	-- Create ScreenGui
	screenGui = New(scope, "ScreenGui")({
		Name = "PredatorWarningUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 150,
		Parent = player:WaitForChild("PlayerGui"),

		[Children] = {
			createFlashOverlay(scope),
			createWarningMessage(scope),
			createDirectionArrow(scope),
			table.unpack(edgeIndicators),
		},
	})

	print("[PredatorWarning] Initialized")
end

-- Show warning for a new predator
function PredatorWarning.show(
	predatorId: string,
	predatorType: string,
	threatLevel: string,
	position: Vector3
)
	-- Create warning state
	local warningState: WarningState = {
		predatorId = predatorId,
		predatorType = predatorType,
		threatLevel = threatLevel,
		position = position,
		startTime = os.clock(),
		isActive = true,
	}

	activeWarnings[predatorId] = warningState

	-- Create UI if not exists
	if not screenGui then
		PredatorWarning.initialize()
	end

	-- Update reactive state
	if hasActiveWarning then
		(hasActiveWarning :: any):set(true)
	end
	if currentThreatLevel then
		(currentThreatLevel :: any):set(threatLevel)
	end
	if currentPredatorType then
		(currentPredatorType :: any):set(predatorType)
	end

	-- Show flash
	if showFlash then
		(showFlash :: any):set(true)
		task.delay(0.5, function()
			if showFlash then
				(showFlash :: any):set(false)
			end
		end)
	end

	-- Show message
	if showMessage then
		(showMessage :: any):set(true)
		task.delay(WARNING_MESSAGE_DURATION, function()
			if showMessage then
				(showMessage :: any):set(false)
			end
		end)
	end

	-- Start update loop for direction arrow
	startUpdateLoop()

	print("[PredatorWarning] Warning shown for", predatorType, "at", position)
end

-- Update predator position (for tracking)
function PredatorWarning.updatePosition(predatorId: string, position: Vector3)
	local warning = activeWarnings[predatorId]
	if warning then
		warning.position = position
	end
end

-- Clear warning for a specific predator
function PredatorWarning.clear(predatorId: string)
	local warning = activeWarnings[predatorId]
	if not warning then
		return
	end

	warning.isActive = false
	activeWarnings[predatorId] = nil

	-- Check if any warnings are still active
	local hasActive = false
	for _, w in pairs(activeWarnings) do
		if w.isActive then
			hasActive = true
			break
		end
	end

	-- Update state
	if hasActiveWarning then
		(hasActiveWarning :: any):set(hasActive)
	end
	if arrowVisible and not hasActive then
		(arrowVisible :: any):set(false)
	end
	if not hasActive then
		stopUpdateLoop()
	end

	print("[PredatorWarning] Warning cleared for", predatorId)
end

-- Clear all warnings
function PredatorWarning.clearAll()
	for predatorId in pairs(activeWarnings) do
		PredatorWarning.clear(predatorId)
	end
end

-- Check if there are active warnings
function PredatorWarning.hasActiveWarnings(): boolean
	for _, warning in pairs(activeWarnings) do
		if warning.isActive then
			return true
		end
	end
	return false
end

-- Get count of active warnings
function PredatorWarning.getActiveCount(): number
	local count = 0
	for _, warning in pairs(activeWarnings) do
		if warning.isActive then
			count = count + 1
		end
	end
	return count
end

-- Get all active warnings
function PredatorWarning.getActiveWarnings(): { [string]: WarningState }
	return activeWarnings
end

-- Cleanup resources
function PredatorWarning.cleanup()
	stopUpdateLoop()

	if scope then
		Fusion.doCleanup(scope)
		scope = nil
	end

	screenGui = nil
	hasActiveWarning = nil
	currentThreatLevel = nil
	currentPredatorType = nil
	showMessage = nil
	showFlash = nil
	arrowRotation = nil
	arrowVisible = nil
	arrowPositionX = nil
	arrowPositionY = nil

	activeWarnings = {}
end

-- Get summary for debugging
function PredatorWarning.getSummary(): WarningSummary
	local warnings = {}
	for predatorId, warning in pairs(activeWarnings) do
		if warning.isActive then
			table.insert(warnings, {
				predatorId = predatorId,
				predatorType = warning.predatorType,
				threatLevel = warning.threatLevel,
			})
		end
	end

	return {
		activeCount = PredatorWarning.getActiveCount(),
		hasUI = screenGui ~= nil,
		warnings = warnings,
	}
end

return PredatorWarning
