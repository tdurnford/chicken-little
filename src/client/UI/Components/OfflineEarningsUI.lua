--[[
	OfflineEarningsUI Component (Fusion)
	Creates and manages the "Welcome Back" popup showing offline earnings.
	Displays money earned, eggs collected, and time away with claim functionality.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring

-- Types
export type PopupConfig = {
	anchorPoint: Vector2?,
	position: UDim2?,
	size: UDim2?,
	backgroundColor: Color3?,
	accentColor: Color3?,
}

export type PopupState = {
	moneyEarned: number,
	eggsCollected: number,
	timeAwaySeconds: number,
	isVisible: boolean,
}

-- Module state
local OfflineEarningsUI = {}
local screenGui: ScreenGui? = nil
local scope: Fusion.Scope? = nil

-- Reactive state
local moneyEarned: Fusion.Value<number>? = nil
local eggsCollected: Fusion.Value<number>? = nil
local timeAwaySeconds: Fusion.Value<number>? = nil
local isVisible: Fusion.Value<boolean>? = nil

-- Callbacks
local onClaimCallback: ((money: number, eggs: number) -> ())? = nil
local onDismissCallback: (() -> ())? = nil

-- Configuration
local DEFAULT_CONFIG: PopupConfig = {
	anchorPoint = Vector2.new(0.5, 0.5),
	position = UDim2.new(0.5, 0, 0.5, 0),
	size = UDim2.new(0, 380, 0, 340),
	backgroundColor = Color3.fromRGB(30, 30, 40),
	accentColor = Color3.fromRGB(255, 215, 0), -- Gold
}

-- Colors
local COLORS = {
	background = Color3.fromRGB(30, 30, 40),
	surface = Color3.fromRGB(40, 40, 55),
	text = Color3.fromRGB(255, 255, 255),
	textSecondary = Color3.fromRGB(180, 180, 200),
	accent = Color3.fromRGB(255, 215, 0), -- Gold
	eggAccent = Color3.fromRGB(255, 220, 150),
	claimButton = Color3.fromRGB(80, 180, 80),
	claimButtonHover = Color3.fromRGB(100, 200, 100),
	stroke = Color3.fromRGB(255, 215, 0),
}

-- Create backdrop
local function createBackdrop(fusionScope: Fusion.Scope, backdropVisible: Fusion.Value<boolean>)
	local backdropTransparency = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(backdropVisible) then 0.6 else 1
	end), 20)

	return New(fusionScope, "Frame")({
		Name = "Backdrop",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = backdropTransparency,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
end

-- Create earnings section (money or eggs)
local function createEarningsSection(
	fusionScope: Fusion.Scope,
	name: string,
	icon: string,
	yPosition: number,
	accentColor: Color3,
	valueText: Fusion.Computed<string>
)
	return New(fusionScope, "Frame")({
		Name = name .. "Section",
		Size = UDim2.new(1, -32, 0, 70),
		Position = UDim2.new(0, 16, 0, yPosition),
		BackgroundColor3 = COLORS.surface,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 3,

		[Children] = {
			New(fusionScope, "UICorner")({
				CornerRadius = UDim.new(0, 10),
			}),

			-- Icon
			New(fusionScope, "TextLabel")({
				Name = "Icon",
				Size = UDim2.new(0, 50, 1, 0),
				Position = UDim2.new(0, 8, 0, 0),
				BackgroundTransparency = 1,
				Text = icon,
				TextSize = 32,
				TextColor3 = accentColor,
				ZIndex = 4,
			}),

			-- Label
			New(fusionScope, "TextLabel")({
				Name = "Label",
				Size = UDim2.new(1, -70, 0, 22),
				Position = UDim2.new(0, 60, 0, 10),
				BackgroundTransparency = 1,
				Text = name .. " Earned",
				TextColor3 = COLORS.textSecondary,
				TextSize = 14,
				FontFace = Theme.Typography.Primary,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 4,
			}),

			-- Value
			New(fusionScope, "TextLabel")({
				Name = "Value",
				Size = UDim2.new(1, -70, 0, 30),
				Position = UDim2.new(0, 60, 0, 32),
				BackgroundTransparency = 1,
				Text = valueText,
				TextColor3 = accentColor,
				TextSize = 24,
				FontFace = Theme.Typography.PrimaryBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 4,
			}),
		},
	})
end

-- Create claim button
local function createClaimButton(fusionScope: Fusion.Scope)
	local isHovered = Value(fusionScope, false)

	local buttonColor = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(isHovered) then COLORS.claimButtonHover else COLORS.claimButton
	end), 20)

	return New(fusionScope, "TextButton")({
		Name = "ClaimButton",
		Size = UDim2.new(1, -32, 0, 50),
		Position = UDim2.new(0, 16, 1, -66),
		BackgroundColor3 = buttonColor,
		Text = "✓ Claim Rewards",
		TextColor3 = COLORS.text,
		TextSize = 18,
		FontFace = Theme.Typography.PrimaryBold,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		ZIndex = 3,

		[OnEvent("MouseButton1Click")] = function()
			OfflineEarningsUI.claim()
		end,

		[OnEvent("MouseEnter")] = function()
			isHovered:set(true)
		end,

		[OnEvent("MouseLeave")] = function()
			isHovered:set(false)
		end,

		[Children] = {
			New(fusionScope, "UICorner")({
				CornerRadius = UDim.new(0, 10),
			}),
		},
	})
end

-- Create main popup frame
local function createMainPopup(fusionScope: Fusion.Scope, config: PopupConfig)
	-- Animated size for scale-in effect
	local targetSize = config.size or DEFAULT_CONFIG.size
	local popupSize = Spring(fusionScope, Computed(fusionScope, function(use)
		return if use(isVisible :: any) then targetSize else UDim2.new(0, 0, 0, 0)
	end), 15, 0.8)

	-- Time away text
	local timeAwayText = Computed(fusionScope, function(use)
		local seconds = use(timeAwaySeconds :: any)
		return "You were away for " .. OfflineEarnings.formatDuration(seconds)
	end)

	-- Money value text
	local moneyText = Computed(fusionScope, function(use)
		local money = use(moneyEarned :: any)
		return MoneyScaling.formatCurrency(money)
	end)

	-- Eggs value text
	local eggsText = Computed(fusionScope, function(use)
		local eggs = use(eggsCollected :: any)
		return tostring(eggs) .. " egg" .. (if eggs == 1 then "" else "s")
	end)

	return New(fusionScope, "Frame")({
		Name = "OfflineEarningsPopup",
		AnchorPoint = config.anchorPoint or DEFAULT_CONFIG.anchorPoint,
		Position = config.position or DEFAULT_CONFIG.position,
		Size = popupSize,
		BackgroundColor3 = config.backgroundColor or DEFAULT_CONFIG.backgroundColor,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
		ClipsDescendants = true,

		[Children] = {
			-- Rounded corners
			New(fusionScope, "UICorner")({
				CornerRadius = UDim.new(0, 16),
			}),

			-- Border stroke
			New(fusionScope, "UIStroke")({
				Color = config.accentColor or DEFAULT_CONFIG.accentColor,
				Thickness = 2,
				Transparency = 0.3,
			}),

			-- Header
			New(fusionScope, "TextLabel")({
				Name = "Header",
				Size = UDim2.new(1, -24, 0, 40),
				Position = UDim2.new(0, 12, 0, 12),
				BackgroundTransparency = 1,
				Text = "🎉 Welcome Back!",
				TextColor3 = COLORS.text,
				TextSize = 28,
				FontFace = Theme.Typography.PrimaryBold,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 3,
			}),

			-- Time away label
			New(fusionScope, "TextLabel")({
				Name = "TimeAwayLabel",
				Size = UDim2.new(1, -24, 0, 24),
				Position = UDim2.new(0, 12, 0, 52),
				BackgroundTransparency = 1,
				Text = timeAwayText,
				TextColor3 = COLORS.textSecondary,
				TextSize = 14,
				FontFace = Theme.Typography.Primary,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 3,
			}),

			-- Money section
			createEarningsSection(fusionScope, "Money", "💰", 88, COLORS.accent, moneyText),

			-- Eggs section
			createEarningsSection(fusionScope, "Eggs", "🥚", 168, COLORS.eggAccent, eggsText),

			-- Claim button
			createClaimButton(fusionScope),
		},
	})
end

-- Initialize the popup UI (hidden by default)
function OfflineEarningsUI.create(config: PopupConfig?): boolean
	local player = Players.LocalPlayer
	if not player then
		warn("OfflineEarningsUI: No LocalPlayer found")
		return false
	end

	-- Clean up existing UI
	OfflineEarningsUI.destroy()

	local currentConfig = config or DEFAULT_CONFIG

	-- Create Fusion scope
	scope = Fusion.scoped({})

	-- Initialize reactive state
	moneyEarned = Value(scope, 0)
	eggsCollected = Value(scope, 0)
	timeAwaySeconds = Value(scope, 0)
	isVisible = Value(scope, false)

	-- Create ScreenGui
	screenGui = New(scope, "ScreenGui")({
		Name = "OfflineEarningsUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		DisplayOrder = 100,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),

		[Children] = {
			createBackdrop(scope, isVisible),
			createMainPopup(scope, currentConfig),
		},
	})

	return true
end

-- Destroy the popup UI
function OfflineEarningsUI.destroy()
	if scope then
		Fusion.doCleanup(scope)
		scope = nil
	end

	screenGui = nil
	moneyEarned = nil
	eggsCollected = nil
	timeAwaySeconds = nil
	isVisible = nil
	onClaimCallback = nil
	onDismissCallback = nil
end

-- Show the popup with earnings data
function OfflineEarningsUI.show(money: number, eggs: number, timeAway: number)
	if not screenGui or not isVisible then
		warn("OfflineEarningsUI: UI not created. Call create() first.")
		return
	end

	-- Skip if no earnings
	if money <= 0 and eggs <= 0 then
		return
	end

	-- Update reactive state
	if moneyEarned then
		(moneyEarned :: any):set(money)
	end
	if eggsCollected then
		(eggsCollected :: any):set(eggs)
	end
	if timeAwaySeconds then
		(timeAwaySeconds :: any):set(timeAway)
	end

	-- Show the popup
	screenGui.Enabled = true
	if isVisible then
		(isVisible :: any):set(true)
	end
end

-- Show popup from OfflineEarningsResult
function OfflineEarningsUI.showFromResult(result: OfflineEarnings.OfflineEarningsResult)
	OfflineEarningsUI.show(result.cappedMoney, #result.eggsEarned, result.cappedSeconds)
end

-- Show popup from preview data
function OfflineEarningsUI.showFromPreview(preview: {
	hasPendingEarnings: boolean,
	estimatedMoney: number,
	estimatedEggs: number,
	offlineHours: number,
	placedChickenCount: number,
})
	if preview.hasPendingEarnings then
		OfflineEarningsUI.show(
			preview.estimatedMoney,
			preview.estimatedEggs,
			preview.offlineHours * 3600
		)
	end
end

-- Hide the popup
function OfflineEarningsUI.hide()
	if not screenGui or not isVisible then
		return
	end

	(isVisible :: any):set(false)

	-- Delay disabling ScreenGui to allow animation
	task.delay(0.3, function()
		if screenGui and not (isVisible :: any):get() then
			screenGui.Enabled = false
		end
	end)
end

-- Claim the rewards and close
function OfflineEarningsUI.claim()
	local money = moneyEarned and (moneyEarned :: any):get() or 0
	local eggs = eggsCollected and (eggsCollected :: any):get() or 0

	-- Call callback before hiding
	if onClaimCallback then
		onClaimCallback(money, eggs)
	end

	-- Hide the popup
	OfflineEarningsUI.hide()
end

-- Dismiss without claiming (for edge cases)
function OfflineEarningsUI.dismiss()
	if onDismissCallback then
		onDismissCallback()
	end
	OfflineEarningsUI.hide()
end

-- Check if popup is visible
function OfflineEarningsUI.isVisible(): boolean
	return isVisible ~= nil and (isVisible :: any):get()
end

-- Check if popup is created
function OfflineEarningsUI.isCreated(): boolean
	return screenGui ~= nil
end

-- Set callback for when rewards are claimed
function OfflineEarningsUI.onClaim(callback: (moneyEarned: number, eggsCollected: number) -> ())
	onClaimCallback = callback
end

-- Set callback for when popup is dismissed
function OfflineEarningsUI.onDismiss(callback: () -> ())
	onDismissCallback = callback
end

-- Get current earnings being displayed
function OfflineEarningsUI.getDisplayedEarnings(): { money: number, eggs: number, timeAway: number }
	return {
		money = moneyEarned and (moneyEarned :: any):get() or 0,
		eggs = eggsCollected and (eggsCollected :: any):get() or 0,
		timeAway = timeAwaySeconds and (timeAwaySeconds :: any):get() or 0,
	}
end

-- Get the screen GUI
function OfflineEarningsUI.getScreenGui(): ScreenGui?
	return screenGui
end

-- Get default configuration
function OfflineEarningsUI.getDefaultConfig(): PopupConfig
	local copy = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		copy[key] = value
	end
	return copy
end

return OfflineEarningsUI
