--[[
	DamageUI Component (Fusion)
	Displays damage numbers floating up from the player and
	shows the combat health bar when taking damage using Fusion reactive state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local peek = Fusion.peek

-- Types
export type DamageUIProps = {
	healthBarPosition: UDim2?,
}

export type PlayerDamagedData = {
	damage: number,
	newHealth: number,
	maxHealth: number,
	source: string?,
}

export type PlayerKnockbackData = {
	duration: number,
	source: string?,
}

export type PlayerHealthChangedData = {
	health: number,
	maxHealth: number,
	isKnockedBack: boolean,
	inCombat: boolean,
}

export type PlayerIncapacitatedData = {
	duration: number,
	attackerId: string?,
	attackerName: string?,
}

export type MoneyLostData = {
	amount: number,
	source: string?,
}

-- Module state
local DamageUI = {}
local screenGui: ScreenGui? = nil
local damageScope: Fusion.Scope? = nil

-- Reactive state
local currentHealth = nil :: Fusion.Value<number>?
local maxHealth = nil :: Fusion.Value<number>?
local isHealthBarVisible = nil :: Fusion.Value<boolean>?

-- Constants
local DAMAGE_NUMBER_LIFETIME = 1.5
local DAMAGE_NUMBER_RISE = 50
local HEALTH_BAR_VISIBLE_DURATION = 3
local HEALTH_BAR_FADE_DURATION = 0.5

-- Health bar hide task
local healthBarHideTask: thread? = nil

-- Get color based on health percent
local function getHealthColor(percent: number): Color3
	if percent > 0.6 then
		return Color3.fromRGB(50, 200, 50)
	elseif percent > 0.3 then
		return Color3.fromRGB(255, 200, 50)
	else
		return Color3.fromRGB(220, 50, 50)
	end
end

-- Create the health bar component
local function createHealthBar(scope: Fusion.Scope, position: UDim2)
	local healthPercent = Computed(scope, function(use)
		local health = use(currentHealth :: any)
		local max = use(maxHealth :: any)
		if max > 0 then
			return health / max
		end
		return 1
	end)

	local healthColor = Computed(scope, function(use)
		return getHealthColor(use(healthPercent))
	end)

	local healthText = Computed(scope, function(use)
		local health = use(currentHealth :: any)
		local max = use(maxHealth :: any)
		return string.format("%.0f/%.0f", health, max)
	end)

	local animatedPercent = Spring(scope, healthPercent, 20, 0.7)

	return New(scope, "Frame")({
		Name = "HealthBarContainer",
		Size = UDim2.new(0, 200, 0, 30),
		Position = position,
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		Visible = Computed(scope, function(use)
			return use(isHealthBarVisible :: any)
		end),

		[Children] = {
			New(scope, "UICorner")({
				CornerRadius = UDim.new(0, 6),
			}),

			-- Background
			New(scope, "Frame")({
				Name = "Background",
				Size = UDim2.new(1, -8, 1, -8),
				Position = UDim2.new(0, 4, 0, 4),
				BackgroundColor3 = Color3.fromRGB(50, 50, 50),
				BorderSizePixel = 0,

				[Children] = {
					New(scope, "UICorner")({
						CornerRadius = UDim.new(0, 4),
					}),

					-- Fill
					New(scope, "Frame")({
						Name = "Fill",
						Size = Computed(scope, function(use)
							local percent = use(animatedPercent)
							return UDim2.new(math.clamp(percent, 0, 1), 0, 1, 0)
						end),
						BackgroundColor3 = healthColor,
						BorderSizePixel = 0,

						[Children] = {
							New(scope, "UICorner")({
								CornerRadius = UDim.new(0, 4),
							}),
						},
					}),
				},
			}),

			-- Health text
			New(scope, "TextLabel")({
				Name = "HealthText",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = healthText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextStrokeTransparency = 0.5,
				FontFace = Theme.Typography.PrimaryBold,
				TextSize = 14,
			}),
		},
	})
end

-- Initialize the DamageUI
function DamageUI.initialize(props: DamageUIProps?)
	local player = Players.LocalPlayer
	if not player then
		warn("DamageUI: No LocalPlayer found")
		return
	end

	-- Clean up existing
	DamageUI.cleanup()

	-- Create Fusion scope
	damageScope = Fusion.scoped({})

	-- Initialize reactive state
	currentHealth = Value(damageScope, 100)
	maxHealth = Value(damageScope, 100)
	isHealthBarVisible = Value(damageScope, false)

	local healthBarPosition = (props and props.healthBarPosition) or UDim2.new(0.5, -100, 0, 80)

	-- Create ScreenGui
	screenGui = New(damageScope, "ScreenGui")({
		Name = "DamageUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = player:WaitForChild("PlayerGui"),

		[Children] = {
			createHealthBar(damageScope, healthBarPosition),
		},
	})

	print("[DamageUI] Initialized")
end

-- Cleanup function
function DamageUI.cleanup()
	if healthBarHideTask then
		task.cancel(healthBarHideTask)
		healthBarHideTask = nil
	end

	if damageScope then
		Fusion.doCleanup(damageScope)
		damageScope = nil
	end

	screenGui = nil
	currentHealth = nil
	maxHealth = nil
	isHealthBarVisible = nil
end

-- Show a damage number floating up
function DamageUI.showDamageNumber(damage: number, source: string?)
	if not screenGui then
		return
	end

	if damage <= 0 then
		return
	end

	-- Create damage number label (non-Fusion for animation simplicity)
	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "DamageNumber"
	damageLabel.Size = UDim2.new(0, 100, 0, 30)
	local xOffset = math.random(-50, 50)
	damageLabel.Position = UDim2.new(0.5, xOffset - 50, 0.4, 0)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = string.format("-%.0f", damage)
	damageLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
	damageLabel.TextStrokeTransparency = 0.3
	damageLabel.TextStrokeColor3 = Color3.fromRGB(50, 0, 0)
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.TextSize = 24
	damageLabel.TextScaled = false
	damageLabel.Parent = screenGui

	-- Animate floating up and fading out
	local startPos = damageLabel.Position
	local endPos = UDim2.new(
		startPos.X.Scale,
		startPos.X.Offset,
		startPos.Y.Scale,
		startPos.Y.Offset - DAMAGE_NUMBER_RISE
	)

	local tweenInfo = TweenInfo.new(DAMAGE_NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local moveTween = TweenService:Create(damageLabel, tweenInfo, {
		Position = endPos,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	moveTween:Play()
	moveTween.Completed:Connect(function()
		damageLabel:Destroy()
	end)
end

-- Show money loss number floating up
function DamageUI.showMoneyLoss(amount: number, source: string?)
	if not screenGui then
		return
	end

	if amount <= 0 then
		return
	end

	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLoss"
	moneyLabel.Size = UDim2.new(0, 150, 0, 35)
	local xOffset = math.random(-30, 30)
	moneyLabel.Position = UDim2.new(0.5, xOffset - 75, 0.48, 0)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Text = string.format("-$%d", amount)
	moneyLabel.TextColor3 = Color3.fromRGB(255, 180, 50)
	moneyLabel.TextStrokeTransparency = 0
	moneyLabel.TextStrokeColor3 = Color3.fromRGB(100, 50, 0)
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextSize = 28
	moneyLabel.TextScaled = false
	moneyLabel.Parent = screenGui

	local startPos = moneyLabel.Position
	local endPos = UDim2.new(
		startPos.X.Scale,
		startPos.X.Offset,
		startPos.Y.Scale,
		startPos.Y.Offset - DAMAGE_NUMBER_RISE * 1.2
	)

	local tweenInfo = TweenInfo.new(
		DAMAGE_NUMBER_LIFETIME * 1.2,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local moveTween = TweenService:Create(moneyLabel, tweenInfo, {
		Position = endPos,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	moveTween:Play()
	moveTween.Completed:Connect(function()
		moneyLabel:Destroy()
	end)
end

-- Handle MoneyLost event from server
function DamageUI.onMoneyLost(data: MoneyLostData)
	DamageUI.showMoneyLoss(data.amount, data.source)
end

-- Show knockback effect
function DamageUI.showKnockback(duration: number, source: string?)
	if not screenGui then
		return
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "KnockbackOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	overlay.BackgroundTransparency = 0.7
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	local stunnedText = Instance.new("TextLabel")
	stunnedText.Name = "StunnedText"
	stunnedText.Size = UDim2.new(0, 300, 0, 60)
	stunnedText.Position = UDim2.new(0.5, -150, 0.4, -30)
	stunnedText.BackgroundTransparency = 1
	stunnedText.Text = "STUNNED!"
	stunnedText.TextColor3 = Color3.fromRGB(255, 255, 255)
	stunnedText.TextStrokeTransparency = 0
	stunnedText.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
	stunnedText.Font = Enum.Font.GothamBold
	stunnedText.TextSize = 48
	stunnedText.Parent = screenGui

	task.delay(duration * 0.7, function()
		local fadeInfo = TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local overlayFade = TweenService:Create(overlay, fadeInfo, { BackgroundTransparency = 1 })
		local textFade = TweenService:Create(stunnedText, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })

		overlayFade:Play()
		textFade:Play()

		overlayFade.Completed:Connect(function()
			overlay:Destroy()
			stunnedText:Destroy()
		end)
	end)
end

-- Show incapacitation effect
function DamageUI.showIncapacitation(duration: number, attackerName: string?)
	if not screenGui then
		return
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "IncapacitationOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
	overlay.BackgroundTransparency = 0.6
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	local incapText = Instance.new("TextLabel")
	incapText.Name = "IncapText"
	incapText.Size = UDim2.new(0, 400, 0, 60)
	incapText.Position = UDim2.new(0.5, -200, 0.35, -30)
	incapText.BackgroundTransparency = 1
	incapText.Text = "KNOCKED OUT!"
	incapText.TextColor3 = Color3.fromRGB(255, 255, 255)
	incapText.TextStrokeTransparency = 0
	incapText.TextStrokeColor3 = Color3.fromRGB(150, 80, 0)
	incapText.Font = Enum.Font.GothamBold
	incapText.TextSize = 48
	incapText.Parent = screenGui

	local attackerText = Instance.new("TextLabel")
	attackerText.Name = "AttackerText"
	attackerText.Size = UDim2.new(0, 400, 0, 30)
	attackerText.Position = UDim2.new(0.5, -200, 0.45, 0)
	attackerText.BackgroundTransparency = 1
	attackerText.Text = attackerName and ("Hit by " .. attackerName) or "Hit by another player"
	attackerText.TextColor3 = Color3.fromRGB(255, 220, 150)
	attackerText.TextStrokeTransparency = 0.5
	attackerText.Font = Enum.Font.GothamBold
	attackerText.TextSize = 24
	attackerText.Parent = screenGui

	-- Stars container
	local starsContainer = Instance.new("Frame")
	starsContainer.Name = "StarsContainer"
	starsContainer.Size = UDim2.new(0, 200, 0, 50)
	starsContainer.Position = UDim2.new(0.5, -100, 0.28, 0)
	starsContainer.BackgroundTransparency = 1
	starsContainer.Parent = screenGui

	-- Add spinning stars
	for i = 1, 5 do
		local star = Instance.new("TextLabel")
		star.Name = "Star" .. i
		star.Size = UDim2.new(0, 30, 0, 30)
		local angle = (i - 1) * (2 * math.pi / 5)
		local radius = 60
		star.Position = UDim2.new(0.5, math.cos(angle) * radius - 15, 0.5, math.sin(angle) * radius - 15)
		star.BackgroundTransparency = 1
		star.Text = "★"
		star.TextColor3 = Color3.fromRGB(255, 255, 100)
		star.TextStrokeTransparency = 0.5
		star.Font = Enum.Font.GothamBold
		star.TextSize = 24
		star.Parent = starsContainer

		task.spawn(function()
			local startTime = os.clock()
			while star and star.Parent do
				local elapsed = os.clock() - startTime
				if elapsed >= duration then
					break
				end
				local rotAngle = angle + elapsed * 3
				star.Position = UDim2.new(0.5, math.cos(rotAngle) * radius - 15, 0.5, math.sin(rotAngle) * radius - 15)
				task.wait(0.03)
			end
		end)
	end

	task.delay(duration * 0.7, function()
		local fadeInfo = TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local overlayFade = TweenService:Create(overlay, fadeInfo, { BackgroundTransparency = 1 })
		local textFade = TweenService:Create(incapText, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
		local attackerFade = TweenService:Create(attackerText, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })

		overlayFade:Play()
		textFade:Play()
		attackerFade:Play()

		overlayFade.Completed:Connect(function()
			overlay:Destroy()
			incapText:Destroy()
			attackerText:Destroy()
			starsContainer:Destroy()
		end)
	end)
end

-- Handle PlayerIncapacitated event from server
function DamageUI.onPlayerIncapacitated(data: PlayerIncapacitatedData)
	DamageUI.showIncapacitation(data.duration, data.attackerName)
end

-- Update health bar display
function DamageUI.updateHealthBar(health: number, max: number, showBar: boolean?)
	if currentHealth then
		currentHealth:set(health)
	end
	if maxHealth then
		maxHealth:set(max)
	end

	if showBar ~= false then
		if isHealthBarVisible then
			isHealthBarVisible:set(true)
		end

		-- Cancel existing hide task
		if healthBarHideTask then
			task.cancel(healthBarHideTask)
		end

		-- Schedule hide
		healthBarHideTask = task.delay(HEALTH_BAR_VISIBLE_DURATION, function()
			if isHealthBarVisible then
				isHealthBarVisible:set(false)
			end
			healthBarHideTask = nil
		end)
	end
end

-- Hide health bar
function DamageUI.hideHealthBar()
	if isHealthBarVisible then
		isHealthBarVisible:set(false)
	end
end

-- Update function (for compatibility - no longer needed with Fusion)
function DamageUI.update()
	-- Fusion handles updates reactively
end

-- Handle PlayerDamaged event from server
function DamageUI.onPlayerDamaged(data: PlayerDamagedData)
	DamageUI.showDamageNumber(data.damage, data.source)
	DamageUI.updateHealthBar(data.newHealth, data.maxHealth, true)
end

-- Handle PlayerKnockback event from server
function DamageUI.onPlayerKnockback(data: PlayerKnockbackData)
	DamageUI.showKnockback(data.duration, data.source)
end

-- Handle PlayerHealthChanged event from server
function DamageUI.onPlayerHealthChanged(data: PlayerHealthChangedData)
	DamageUI.updateHealthBar(data.health, data.maxHealth, data.inCombat)

	if data.health >= data.maxHealth and not data.inCombat then
		DamageUI.hideHealthBar()
	end
end

-- Check if UI is created
function DamageUI.isCreated(): boolean
	return screenGui ~= nil
end

-- Get the ScreenGui
function DamageUI.getScreenGui(): ScreenGui?
	return screenGui
end

return DamageUI
