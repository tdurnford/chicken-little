--[[
	ShieldUI Component (Fusion)
	Creates and manages the area shield button UI using Fusion reactive state.
	Shows shield activation button, countdown timer, and cooldown status.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local Cleanup = Fusion.Cleanup
local peek = Fusion.peek

-- Types
export type ShieldUIProps = {
	onActivate: (() -> ())?,
	position: UDim2?,
}

export type ShieldStatusData = {
	isActive: boolean,
	isOnCooldown: boolean,
	canActivate: boolean,
	remainingDuration: number,
	remainingCooldown: number,
	durationTotal: number,
	cooldownTotal: number,
}

-- Module state
local ShieldUI = {}
local screenGui: ScreenGui? = nil
local shieldScope: Fusion.Scope? = nil

-- Reactive state
local isActive = nil :: Fusion.Value<boolean>?
local isOnCooldown = nil :: Fusion.Value<boolean>?
local remainingDuration = nil :: Fusion.Value<number>?
local remainingCooldown = nil :: Fusion.Value<number>?
local durationTotal = nil :: Fusion.Value<number>?
local cooldownTotal = nil :: Fusion.Value<number>?
local onActivateCallback: (() -> ())? = nil

-- Configuration
local BUTTON_SIZE = UDim2.new(0, 60, 0, 60)
local DEFAULT_POSITION = UDim2.new(1, -140, 0, 10)

-- Colors
local COLORS = {
	ready = Color3.fromRGB(60, 60, 75),
	active = Color3.fromRGB(100, 150, 255),
	cooldown = Color3.fromRGB(150, 150, 150),
	text = Color3.fromRGB(255, 255, 255),
	progressBg = Color3.fromRGB(40, 40, 50),
	progressActive = Color3.fromRGB(100, 180, 255),
	progressCooldown = Color3.fromRGB(255, 180, 80),
	stroke = Color3.fromRGB(100, 100, 120),
}

-- Format seconds to MM:SS
local function formatTime(seconds: number): string
	if seconds <= 0 then
		return "0:00"
	end
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", mins, secs)
end

-- Create the progress bar component
local function createProgressBar(scope: Fusion.Scope)
	local progressValue = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		local duration = use(remainingDuration :: any)
		local cooldown = use(remainingCooldown :: any)
		local durTotal = use(durationTotal :: any)
		local cdTotal = use(cooldownTotal :: any)

		if active and durTotal > 0 then
			return duration / durTotal
		elseif onCooldown and cdTotal > 0 then
			return 1 - (cooldown / cdTotal)
		end
		return 0
	end)

	local progressColor = Computed(scope, function(use)
		local active = use(isActive :: any)
		if active then
			return COLORS.progressActive
		end
		return COLORS.progressCooldown
	end)

	local isProgressVisible = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		return active or onCooldown
	end)

	return New(scope, "Frame")({
		Name = "ProgressBar",
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0, -8),
		BackgroundColor3 = COLORS.progressBg,
		BorderSizePixel = 0,
		Visible = isProgressVisible,

		[Children] = {
			New(scope, "UICorner")({
				CornerRadius = UDim.new(0, 3),
			}),

			New(scope, "Frame")({
				Name = "ProgressFill",
				Size = Computed(scope, function(use)
					local progress = use(progressValue)
					return UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
				end),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = progressColor,
				BorderSizePixel = 0,

				[Children] = {
					New(scope, "UICorner")({
						CornerRadius = UDim.new(0, 3),
					}),
				},
			}),
		},
	})
end

-- Create the main shield button
local function createShieldButton(scope: Fusion.Scope, position: UDim2)
	-- Button background color based on state
	local buttonColor = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		if active then
			return COLORS.active
		elseif onCooldown then
			return COLORS.cooldown
		end
		return COLORS.ready
	end)

	-- Button text based on state
	local buttonText = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		if onCooldown and not active then
			return "⏳"
		end
		return "🛡️"
	end)

	-- Stroke color based on state
	local strokeColor = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		if active then
			return COLORS.active
		elseif onCooldown then
			return COLORS.cooldown
		end
		return COLORS.stroke
	end)

	-- Status label text
	local statusText = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		if active then
			return "ACTIVE"
		elseif onCooldown then
			return "COOLDOWN"
		end
		return "Ready"
	end)

	-- Status label color
	local statusColor = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		if active then
			return COLORS.active
		elseif onCooldown then
			return COLORS.cooldown
		end
		return COLORS.text
	end)

	-- Timer text
	local timerText = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		local duration = use(remainingDuration :: any)
		local cooldown = use(remainingCooldown :: any)
		if active then
			return formatTime(duration)
		elseif onCooldown then
			return formatTime(cooldown)
		end
		return ""
	end)

	-- Visibility for status/timer labels
	local showLabels = Computed(scope, function(use)
		local active = use(isActive :: any)
		local onCooldown = use(isOnCooldown :: any)
		return active or onCooldown
	end)

	-- Hover state for tooltip
	local isHovered = Value(scope, false)

	return New(scope, "Frame")({
		Name = "ShieldButtonFrame",
		Size = BUTTON_SIZE,
		Position = position,
		AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 1,

		[Children] = {
			-- Progress bar above button
			createProgressBar(scope),

			-- Timer label
			New(scope, "TextLabel")({
				Name = "TimerLabel",
				Size = UDim2.new(0, 80, 0, 14),
				Position = UDim2.new(0.5, 0, 0, -40),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 10,
				FontFace = Theme.Typography.Primary,
				Text = timerText,
				Visible = showLabels,
			}),

			-- Status label
			New(scope, "TextLabel")({
				Name = "StatusLabel",
				Size = UDim2.new(0, 80, 0, 16),
				Position = UDim2.new(0.5, 0, 0, -26),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				TextColor3 = statusColor,
				TextSize = 11,
				FontFace = Theme.Typography.PrimaryBold,
				Text = statusText,
				Visible = showLabels,
			}),

			-- Main button
			New(scope, "TextButton")({
				Name = "ShieldButton",
				Size = UDim2.new(1, 0, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = buttonColor,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Text = buttonText,
				TextSize = 28,
				TextColor3 = COLORS.text,
				AutoButtonColor = true,

				[OnEvent("MouseButton1Click")] = function()
					local active = isActive and peek(isActive) or false
					local onCooldown = isOnCooldown and peek(isOnCooldown) or false
					if onActivateCallback and not active and not onCooldown then
						onActivateCallback()
					end
				end,

				[OnEvent("MouseEnter")] = function()
					isHovered:set(true)
				end,

				[OnEvent("MouseLeave")] = function()
					isHovered:set(false)
				end,

				[Children] = {
					New(scope, "UICorner")({
						CornerRadius = UDim.new(0, 12),
					}),

					New(scope, "UIStroke")({
						Color = strokeColor,
						Thickness = 2,
						Transparency = 0.3,
					}),
				},
			}),

			-- Tooltip
			New(scope, "TextLabel")({
				Name = "Tooltip",
				Size = UDim2.new(0, 100, 0, 20),
				Position = UDim2.new(0.5, 0, 1, 4),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(20, 20, 28),
				BackgroundTransparency = 0.2,
				Text = "Area Shield",
				TextColor3 = Color3.fromRGB(180, 180, 180),
				TextSize = 10,
				FontFace = Theme.Typography.Primary,
				BorderSizePixel = 0,
				Visible = Computed(scope, function(use)
					return use(isHovered)
				end),

				[Children] = {
					New(scope, "UICorner")({
						CornerRadius = UDim.new(0, 4),
					}),
				},
			}),
		},
	})
end

-- Initialize the Shield UI
function ShieldUI.create(props: ShieldUIProps?): boolean
	local player = Players.LocalPlayer
	if not player then
		warn("ShieldUI: No LocalPlayer found")
		return false
	end

	-- Clean up existing
	ShieldUI.destroy()

	-- Create Fusion scope
	shieldScope = Fusion.scoped({})

	-- Initialize reactive state
	isActive = Value(shieldScope, false)
	isOnCooldown = Value(shieldScope, false)
	remainingDuration = Value(shieldScope, 0)
	remainingCooldown = Value(shieldScope, 0)
	durationTotal = Value(shieldScope, 60)
	cooldownTotal = Value(shieldScope, 300)

	-- Store callback
	if props and props.onActivate then
		onActivateCallback = props.onActivate
	end

	local position = (props and props.position) or DEFAULT_POSITION

	-- Create ScreenGui
	screenGui = New(shieldScope, "ScreenGui")({
		Name = "ShieldUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),

		[Children] = {
			createShieldButton(shieldScope, position),
		},
	})

	return true
end

-- Destroy the Shield UI
function ShieldUI.destroy()
	if shieldScope then
		Fusion.doCleanup(shieldScope)
		shieldScope = nil
	end

	screenGui = nil
	isActive = nil
	isOnCooldown = nil
	remainingDuration = nil
	remainingCooldown = nil
	durationTotal = nil
	cooldownTotal = nil
	onActivateCallback = nil
end

-- Update shield status from server
function ShieldUI.updateStatus(data: ShieldStatusData)
	if isActive then
		isActive:set(data.isActive)
	end
	if isOnCooldown then
		isOnCooldown:set(data.isOnCooldown)
	end
	if remainingDuration then
		remainingDuration:set(data.remainingDuration)
	end
	if remainingCooldown then
		remainingCooldown:set(data.remainingCooldown)
	end
	if durationTotal then
		durationTotal:set(data.durationTotal)
	end
	if cooldownTotal then
		cooldownTotal:set(data.cooldownTotal)
	end
end

-- Set the callback for shield activation
function ShieldUI.onActivate(callback: () -> ())
	onActivateCallback = callback
end

-- Show activation feedback (flash effect)
function ShieldUI.showActivationFeedback(success: boolean, message: string)
	-- With Fusion, color changes happen reactively
	-- This could be extended with a flash animation if needed
end

-- Check if UI is created
function ShieldUI.isCreated(): boolean
	return screenGui ~= nil
end

-- Set visibility
function ShieldUI.setVisible(visible: boolean)
	if screenGui then
		local buttonFrame = screenGui:FindFirstChild("ShieldButtonFrame")
		if buttonFrame then
			buttonFrame.Visible = visible
		end
	end
end

-- Get the button frame for positioning
function ShieldUI.getButtonFrame(): Frame?
	if screenGui then
		return screenGui:FindFirstChild("ShieldButtonFrame") :: Frame?
	end
	return nil
end

-- Get the ScreenGui
function ShieldUI.getScreenGui(): ScreenGui?
	return screenGui
end

return ShieldUI
