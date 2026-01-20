--[[
	Tutorial Component (Fusion)
	Guides new players through basic mechanics using visual arrows.
	Simplified to: Go to store -> Buy egg -> Place/hatch chicken -> Done
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Get client modules
local ClientModules = script.Parent.Parent.Parent
local SectionVisuals = require(ClientModules:WaitForChild("SectionVisuals"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local peek = Fusion.peek

-- Types
export type TutorialStep = {
	id: string,
	title: string,
	message: string,
	icon: string?,
	action: string?,
	waitForAction: boolean?,
	duration: number?,
	targetPosition: Vector3?,
}

export type TutorialConfig = {
	steps: { TutorialStep },
	skipEnabled: boolean,
	autoAdvanceDelay: number,
}

-- Module state
local Tutorial = {}
local screenGui: ScreenGui? = nil
local scope: Fusion.Scope? = nil
local arrowPart: Part? = nil
local arrowUpdateConnection: RBXScriptConnection? = nil
local advanceConnection: RBXScriptConnection? = nil

-- Reactive state
local currentStepIndex: Fusion.Value<number>? = nil
local isActive: Fusion.Value<boolean>? = nil
local isPaused: Fusion.Value<boolean>? = nil
local frameVisible: Fusion.Value<boolean>? = nil
local isSkipping: Fusion.Value<boolean>? = nil  -- Track skip state for faster fade animation

-- Callbacks
local onCompleteCallback: (() -> ())? = nil
local onSkipCallback: (() -> ())? = nil
local onStepCompleteCallback: ((stepId: string) -> ())? = nil

-- Colors
local COLORS = {
	background = Color3.fromRGB(25, 25, 35),
	stroke = Color3.fromRGB(100, 180, 255),
	text = Color3.fromRGB(255, 255, 255),
	textSecondary = Color3.fromRGB(200, 200, 220),
	action = Color3.fromRGB(100, 180, 255),
	skipButton = Color3.fromRGB(60, 60, 80),
	continueButton = Color3.fromRGB(80, 140, 200),
	dotActive = Color3.fromRGB(255, 255, 255),
	dotCompleted = Color3.fromRGB(100, 180, 255),
	dotPending = Color3.fromRGB(80, 80, 100),
}

-- Get store position from map config
local function getStorePosition(): Vector3
	local config = MapGeneration.getConfig()
	return Vector3.new(config.originPosition.x, config.originPosition.y + 3, config.originPosition.z)
end

-- Get player's coop center position from their assigned section
local function getPlayerCoopCenter(): Vector3?
	local sectionIndex = SectionVisuals.getCurrentSection()
	if not sectionIndex then
		return nil
	end

	local sectionPos = MapGeneration.getSectionPosition(sectionIndex)
	if not sectionPos then
		return nil
	end

	local coopOffsetX = 0
	local coopOffsetZ = -10

	return Vector3.new(sectionPos.x + coopOffsetX, sectionPos.y + 3, sectionPos.z + coopOffsetZ)
end

-- Tutorial steps
local TUTORIAL_STEPS: { TutorialStep } = {
	{
		id = "buy_egg",
		title = "Buy an Egg!",
		message = "Go to the store and buy your first egg.",
		icon = "🏪",
		action = "Press E at the store",
		waitForAction = true,
		targetPosition = getStorePosition(),
	},
	{
		id = "place_egg",
		title = "Place Your Egg!",
		message = "Walk to your coop and place the egg.",
		icon = "🥚",
		action = "Walk near a coop spot",
		waitForAction = true,
	},
	{
		id = "complete",
		title = "Great Job!",
		message = "Your chicken is hatching! Keep buying eggs and growing your farm.",
		icon = "🎉",
		duration = 4,
	},
}

-- Default configuration
local DEFAULT_CONFIG: TutorialConfig = {
	steps = TUTORIAL_STEPS,
	skipEnabled = true,
	autoAdvanceDelay = 4,
}

local currentConfig: TutorialConfig = DEFAULT_CONFIG

-- Create 3D arrow that points to objectives
local function createArrowIndicator()
	if arrowPart then
		arrowPart:Destroy()
	end

	local arrow = Instance.new("Part")
	arrow.Name = "TutorialArrow"
	arrow.Size = Vector3.new(2, 0.5, 3)
	arrow.Color = Color3.fromRGB(100, 180, 255)
	arrow.Material = Enum.Material.Neon
	arrow.Transparency = 0.3
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CastShadow = false
	arrow.Parent = workspace

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Wedge
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = arrow

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ArrowLabel"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = arrow

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "Go here!"
	label.Parent = billboard

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 8)
	labelCorner.Parent = label

	arrowPart = arrow
	return arrow
end

-- Update arrow position and rotation
local function updateArrowPosition(targetPos: Vector3?)
	if not arrowPart then
		return
	end
	if not targetPos then
		arrowPart.Transparency = 1
		return
	end

	local player = Players.LocalPlayer
	local character = player and player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not rootPart then
		arrowPart.Transparency = 1
		return
	end

	local playerPos = rootPart.Position
	local direction = (targetPos - playerPos).Unit
	local arrowPos = playerPos + Vector3.new(0, 5, 0) + direction * 3

	local lookAt = CFrame.lookAt(arrowPos, targetPos)
	arrowPart.CFrame = lookAt * CFrame.Angles(math.rad(90), 0, 0)
	arrowPart.Transparency = 0.3
end

-- Set arrow label text
local function setArrowLabel(text: string)
	if not arrowPart then
		return
	end
	local billboard = arrowPart:FindFirstChild("ArrowLabel") :: BillboardGui?
	if billboard then
		local label = billboard:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = text
		end
	end
end

-- Start arrow update loop
local function startArrowUpdates()
	if arrowUpdateConnection then
		arrowUpdateConnection:Disconnect()
	end

	arrowUpdateConnection = RunService.Heartbeat:Connect(function()
		if not isActive or not peek(isActive) then
			return
		end
		if isPaused and peek(isPaused) then
			return
		end

		local stepIndex = currentStepIndex and peek(currentStepIndex) or 0
		local step = currentConfig.steps[stepIndex]
		if step and step.targetPosition then
			updateArrowPosition(step.targetPosition)
		else
			updateArrowPosition(nil)
		end
	end)
end

-- Stop arrow updates and hide arrow
local function stopArrowUpdates()
	if arrowUpdateConnection then
		arrowUpdateConnection:Disconnect()
		arrowUpdateConnection = nil
	end

	if arrowPart then
		arrowPart:Destroy()
		arrowPart = nil
	end
end

-- Create progress dots
local function createProgressDots(fusionScope: Fusion.Scope, totalSteps: number, transparency: Fusion.Computed<number>?)
	local dots = {}

	for i = 1, totalSteps do
		local dotColor = Computed(fusionScope, function(use)
			local stepIndex = use(currentStepIndex :: any)
			if i < stepIndex then
				return COLORS.dotCompleted
			elseif i == stepIndex then
				return COLORS.dotActive
			else
				return COLORS.dotPending
			end
		end)

		-- Compute dot transparency from the passed transparency value
		local dotTransparency = transparency and Computed(fusionScope, function(use)
			return use(transparency)
		end) or nil

		table.insert(dots, New(fusionScope, "Frame")({
			Name = "Dot_" .. i,
			Size = UDim2.new(0, 8, 0, 8),
			BackgroundColor3 = dotColor,
			BackgroundTransparency = dotTransparency or 0,
			BorderSizePixel = 0,

			[Children] = {
				New(fusionScope, "UICorner")({
					CornerRadius = UDim.new(1, 0),
				}),
			},
		}))
	end

	return New(fusionScope, "Frame")({
		Name = "ProgressDots",
		Size = UDim2.new(0, totalSteps * 14, 0, 10),
		Position = UDim2.new(0.5, 0, 1, -15),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,

		[Children] = {
			New(fusionScope, "UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),

			table.unpack(dots),
		},
	})
end

-- Create main tutorial frame
local function createTutorialFrame(fusionScope: Fusion.Scope)
	-- Animated position for slide-in effect
	local framePosition = Spring(fusionScope, Computed(fusionScope, function(use)
		local visible = use(frameVisible :: any)
		return if visible then UDim2.new(0.5, 0, 0.75, 0) else UDim2.new(0.5, 0, 1, 0)
	end), 15, 0.8)

	-- Animated transparency for fade-out effect (faster when skipping)
	local frameTransparency = Spring(fusionScope, Computed(fusionScope, function(use)
		local visible = use(frameVisible :: any)
		local skipping = use(isSkipping :: any)
		-- When not visible, fade to fully transparent
		-- Skipping uses same target, but the Spring speed below handles the speed difference
		return if visible then 0 else 1
	end), Computed(fusionScope, function(use)
		local skipping = use(isSkipping :: any)
		-- Use faster speed (40) when skipping, normal speed (15) otherwise
		return if skipping then 40 else 15
	end), 0.8)

	-- Computed for background transparency (combines base transparency with fade)
	local bgTransparency = Computed(fusionScope, function(use)
		local fade = use(frameTransparency)
		-- Base transparency is 0.1, blend towards 1 (fully transparent)
		return 0.1 + (fade * 0.9)
	end)

	-- Computed for content transparency (text, icons, etc.)
	local contentTransparency = Computed(fusionScope, function(use)
		return use(frameTransparency)
	end)

	-- Computed for stroke transparency
	local strokeTransparency = Computed(fusionScope, function(use)
		local fade = use(frameTransparency)
		return 0.3 + (fade * 0.7)
	end)

	-- Step content
	local iconText = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and step.icon or "📖"
	end)

	local titleText = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and step.title or "Tutorial"
	end)

	local messageText = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and step.message or ""
	end)

	local actionText = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and step.action and ("▶ " .. step.action) or ""
	end)

	local showAction = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and step.action ~= nil
	end)

	local showContinue = Computed(fusionScope, function(use)
		local stepIndex = use(currentStepIndex :: any)
		local step = currentConfig.steps[stepIndex]
		return step and not step.waitForAction
	end)

	return New(fusionScope, "Frame")({
		Name = "TutorialFrame",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = framePosition,
		Size = UDim2.new(0, 450, 0, 140),
		BackgroundColor3 = COLORS.background,
		BackgroundTransparency = bgTransparency,
		BorderSizePixel = 0,

		[Children] = {
			-- Rounded corners
			New(fusionScope, "UICorner")({
				CornerRadius = UDim.new(0, 14),
			}),

			-- Border stroke
			New(fusionScope, "UIStroke")({
				Color = COLORS.stroke,
				Thickness = 2,
				Transparency = strokeTransparency,
			}),

			-- Icon
			New(fusionScope, "TextLabel")({
				Name = "IconLabel",
				Size = UDim2.new(0, 50, 0, 50),
				Position = UDim2.new(0, 15, 0, 15),
				BackgroundTransparency = 1,
				Text = iconText,
				TextSize = 36,
				TextColor3 = COLORS.text,
				TextTransparency = contentTransparency,
			}),

			-- Title (sized to not overlap with Skip button which starts at x=380)
			New(fusionScope, "TextLabel")({
				Name = "TitleLabel",
				Size = UDim2.new(0, 290, 0, 28),
				Position = UDim2.new(0, 75, 0, 12),
				BackgroundTransparency = 1,
				Text = titleText,
				TextSize = 20,
				TextColor3 = COLORS.text,
				TextTransparency = contentTransparency,
				FontFace = Theme.Typography.PrimaryBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),

			-- Message
			New(fusionScope, "TextLabel")({
				Name = "MessageLabel",
				Size = UDim2.new(1, -90, 0, 48),
				Position = UDim2.new(0, 75, 0, 40),
				BackgroundTransparency = 1,
				Text = messageText,
				TextSize = 14,
				TextColor3 = COLORS.textSecondary,
				TextTransparency = contentTransparency,
				FontFace = Theme.Typography.Primary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
			}),

			-- Action hint
			New(fusionScope, "TextLabel")({
				Name = "ActionLabel",
				Size = UDim2.new(1, -90, 0, 20),
				Position = UDim2.new(0, 75, 1, -30),
				BackgroundTransparency = 1,
				Text = actionText,
				TextSize = 12,
				TextColor3 = COLORS.action,
				TextTransparency = contentTransparency,
				FontFace = Theme.Typography.PrimarySemiBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Visible = showAction,
			}),

			-- Skip button
			currentConfig.skipEnabled and New(fusionScope, "TextButton")({
				Name = "SkipButton",
				Size = UDim2.new(0, 60, 0, 26),
				Position = UDim2.new(1, -70, 0, 10),
				BackgroundColor3 = COLORS.skipButton,
				BackgroundTransparency = contentTransparency,
				Text = "Skip",
				TextSize = 12,
				TextColor3 = COLORS.textSecondary,
				TextTransparency = contentTransparency,
				FontFace = Theme.Typography.PrimarySemiBold,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				ZIndex = 10,

				[OnEvent("MouseButton1Click")] = function()
					print("[Tutorial] Skip button clicked")
					Tutorial.skip()
				end,

				[Children] = {
					New(fusionScope, "UICorner")({
						CornerRadius = UDim.new(0, 6),
					}),
				},
			}) or nil,

			-- Continue button
			New(fusionScope, "TextButton")({
				Name = "ContinueButton",
				Size = UDim2.new(0, 100, 0, 30),
				Position = UDim2.new(1, -115, 1, -45),
				BackgroundColor3 = COLORS.continueButton,
				BackgroundTransparency = contentTransparency,
				Text = "Continue →",
				TextSize = 14,
				TextColor3 = COLORS.text,
				TextTransparency = contentTransparency,
				FontFace = Theme.Typography.PrimaryBold,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Visible = showContinue,

				[OnEvent("MouseButton1Click")] = function()
					Tutorial.nextStep()
				end,

				[Children] = {
					New(fusionScope, "UICorner")({
						CornerRadius = UDim.new(0, 8),
					}),
				},
			}),

			-- Progress dots
			createProgressDots(fusionScope, #currentConfig.steps, contentTransparency),
		},
	})
end

-- Setup auto-advance timer for non-action steps
local function setupAutoAdvance(duration: number)
	if advanceConnection then
		advanceConnection:Disconnect()
		advanceConnection = nil
	end

	local startTime = tick()
	advanceConnection = RunService.Heartbeat:Connect(function()
		if not isActive or not peek(isActive) then
			return
		end
		if isPaused and peek(isPaused) then
			return
		end

		if tick() - startTime >= duration then
			if advanceConnection then
				advanceConnection:Disconnect()
				advanceConnection = nil
			end
			Tutorial.nextStep()
		end
	end)
end

-- Initialize the tutorial UI
function Tutorial.create(config: TutorialConfig?): boolean
	local player = Players.LocalPlayer
	if not player then
		warn("Tutorial: No LocalPlayer found")
		return false
	end

	-- Clean up existing UI
	Tutorial.destroy()

	currentConfig = config or DEFAULT_CONFIG

	-- Create Fusion scope
	scope = Fusion.scoped({})

	-- Initialize reactive state
	currentStepIndex = Value(scope, 0)
	isActive = Value(scope, false)
	isPaused = Value(scope, false)
	frameVisible = Value(scope, false)
	isSkipping = Value(scope, false)

	-- Create ScreenGui
	screenGui = New(scope, "ScreenGui")({
		Name = "TutorialUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		DisplayOrder = 100,
		Parent = player:WaitForChild("PlayerGui"),

		[Children] = {
			createTutorialFrame(scope),
		},
	})

	-- Create 3D arrow indicator
	createArrowIndicator()

	return true
end

-- Destroy the tutorial UI
function Tutorial.destroy()
	if advanceConnection then
		advanceConnection:Disconnect()
		advanceConnection = nil
	end

	stopArrowUpdates()

	if scope then
		Fusion.doCleanup(scope)
		scope = nil
	end

	screenGui = nil
	currentStepIndex = nil
	isActive = nil
	isPaused = nil
	frameVisible = nil
	isSkipping = nil
	onCompleteCallback = nil
	onSkipCallback = nil
	onStepCompleteCallback = nil
end

-- Start the tutorial
function Tutorial.start()
	if not screenGui or not isActive then
		warn("Tutorial: UI not created. Call create() first.")
		return
	end

	if peek(isActive) then
		return
	end

	if isActive then isActive:set(true) end
	if isPaused then isPaused:set(false) end
	if isSkipping then isSkipping:set(false) end
	if currentStepIndex then currentStepIndex:set(1) end
	if frameVisible then frameVisible:set(true) end

	-- Start arrow updates
	startArrowUpdates()

	local firstStep = currentConfig.steps[1]
	if firstStep then
		if firstStep.targetPosition then
			setArrowLabel(firstStep.title)
		end

		if not firstStep.waitForAction and firstStep.duration then
			setupAutoAdvance(firstStep.duration)
		end
	end
end

-- Go to next step
function Tutorial.nextStep()
	if not isActive or not peek(isActive) then
		return
	end
	if isPaused and peek(isPaused) then
		return
	end

	local stepIndex = peek(currentStepIndex) or 0
	local currentStep = currentConfig.steps[stepIndex]

	-- Notify step completion
	if currentStep and onStepCompleteCallback then
		onStepCompleteCallback(currentStep.id)
	end

	stepIndex = stepIndex + 1
	if currentStepIndex then currentStepIndex:set(stepIndex) end

	if stepIndex > #currentConfig.steps then
		Tutorial.complete()
		return
	end

	local nextStep = currentConfig.steps[stepIndex]
	if nextStep then
		-- Dynamically set targetPosition for place_egg step
		if nextStep.id == "place_egg" and not nextStep.targetPosition then
			local coopCenter = getPlayerCoopCenter()
			if coopCenter then
				nextStep.targetPosition = coopCenter
			end
		end

		if nextStep.targetPosition then
			setArrowLabel(nextStep.title)
		end

		if not nextStep.waitForAction and nextStep.duration then
			setupAutoAdvance(nextStep.duration)
		end
	end
end

-- Complete a specific step (for external triggers)
function Tutorial.completeStep(stepId: string)
	if not isActive or not peek(isActive) then
		return
	end
	if isPaused and peek(isPaused) then
		return
	end

	local stepIndex = peek(currentStepIndex) or 0
	local currentStep = currentConfig.steps[stepIndex]
	if currentStep and currentStep.id == stepId and currentStep.waitForAction then
		Tutorial.nextStep()
	end
end

-- Skip the tutorial
function Tutorial.skip()
	print("[Tutorial] skip() called, isActive =", isActive and peek(isActive) or "nil")
	if not isActive or not peek(isActive) then
		print("[Tutorial] skip() returning early - tutorial not active")
		return
	end

	print("[Tutorial] Skipping tutorial...")
	if isActive then isActive:set(false) end

	if advanceConnection then
		advanceConnection:Disconnect()
		advanceConnection = nil
	end

	stopArrowUpdates()

	-- Set isSkipping BEFORE frameVisible to trigger fast fade animation
	if isSkipping then isSkipping:set(true) end
	if frameVisible then frameVisible:set(false) end

	task.delay(0.3, function()
		-- Reset skipping state after animation completes
		if isSkipping then isSkipping:set(false) end
		if onSkipCallback then
			print("[Tutorial] Calling onSkipCallback")
			onSkipCallback()
		else
			print("[Tutorial] No onSkipCallback registered!")
		end
	end)
end

-- Complete the tutorial
function Tutorial.complete()
	if not isActive or not peek(isActive) then
		return
	end

	if isActive then isActive:set(false) end

	if advanceConnection then
		advanceConnection:Disconnect()
		advanceConnection = nil
	end

	stopArrowUpdates()

	if frameVisible then frameVisible:set(false) end

	task.delay(0.3, function()
		if onCompleteCallback then
			onCompleteCallback()
		end
	end)
end

-- Pause the tutorial
function Tutorial.pause()
	if isPaused then
		isPaused:set(true)
	end
end

-- Resume the tutorial
function Tutorial.resume()
	if isPaused then
		isPaused:set(false)
	end
end

-- Check if tutorial is active
function Tutorial.isActive(): boolean
	return isActive ~= nil and peek(isActive) == true
end

-- Check if tutorial is paused
function Tutorial.isPaused(): boolean
	return isPaused ~= nil and peek(isPaused) == true
end

-- Check if tutorial is created
function Tutorial.isCreated(): boolean
	return screenGui ~= nil
end

-- Get current step index
function Tutorial.getCurrentStepIndex(): number
	return currentStepIndex and peek(currentStepIndex) or 0
end

-- Get current step
function Tutorial.getCurrentStep(): TutorialStep?
	local stepIndex = currentStepIndex and peek(currentStepIndex) or 0
	if stepIndex > 0 and stepIndex <= #currentConfig.steps then
		return currentConfig.steps[stepIndex]
	end
	return nil
end

-- Get total steps
function Tutorial.getTotalSteps(): number
	return #currentConfig.steps
end

-- Set callback for tutorial completion
function Tutorial.onComplete(callback: () -> ())
	onCompleteCallback = callback
end

-- Set callback for tutorial skip
function Tutorial.onSkip(callback: () -> ())
	onSkipCallback = callback
end

-- Set callback for step completion
function Tutorial.onStepComplete(callback: (stepId: string) -> ())
	onStepCompleteCallback = callback
end

-- Check if player should see tutorial (new player detection)
function Tutorial.shouldShowTutorial(playerData: PlayerData.PlayerDataSchema?): boolean
	if not playerData then
		return true
	end
	return playerData.tutorialComplete ~= true
end

-- Get default tutorial steps
function Tutorial.getDefaultSteps(): { TutorialStep }
	local copy = {}
	for i, step in ipairs(TUTORIAL_STEPS) do
		copy[i] = {
			id = step.id,
			title = step.title,
			message = step.message,
			icon = step.icon,
			action = step.action,
			waitForAction = step.waitForAction,
			duration = step.duration,
		}
	end
	return copy
end

-- Get default configuration
function Tutorial.getDefaultConfig(): TutorialConfig
	return {
		steps = Tutorial.getDefaultSteps(),
		skipEnabled = DEFAULT_CONFIG.skipEnabled,
		autoAdvanceDelay = DEFAULT_CONFIG.autoAdvanceDelay,
	}
end

return Tutorial
