--[[
	PredatorHealthBar Component (Fusion)
	Creates and manages health bar UI above predator models using Fusion reactive state.
	Shows predator name, threat level, and health bar that updates in real-time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local peek = Fusion.peek

-- Types
export type HealthBarState = {
	predatorId: string,
	predatorType: string,
	threatLevel: string,
	currentHealth: Fusion.Value<number>,
	maxHealth: Fusion.Value<number>,
	scope: Fusion.Scope?,
	billboard: BillboardGui?,
}

-- Health bar color thresholds
local HEALTH_COLORS = {
	high = Color3.fromRGB(50, 200, 50),
	medium = Color3.fromRGB(220, 180, 50),
	low = Color3.fromRGB(200, 50, 50),
}

-- UI sizing
local HEALTH_BAR_WIDTH = 120
local HEALTH_BAR_HEIGHT = 50

-- Damage number animation constants
local DAMAGE_NUMBER_LIFETIME = 1.0
local DAMAGE_NUMBER_RISE_STUDS = 3

-- Module state
local PredatorHealthBar = {}
local activeHealthBars: { [string]: HealthBarState } = {}

-- Get color based on health percentage
local function getHealthColor(healthPercent: number): Color3
	if healthPercent > 0.6 then
		return HEALTH_COLORS.high
	elseif healthPercent > 0.3 then
		return HEALTH_COLORS.medium
	else
		return HEALTH_COLORS.low
	end
end

-- Get threat level color for name display
local function getThreatColor(threatLevel: string): Color3
	local colors: { [string]: Color3 } = {
		Minor = Color3.fromRGB(150, 150, 150),
		Moderate = Color3.fromRGB(200, 180, 80),
		Dangerous = Color3.fromRGB(255, 140, 50),
		Severe = Color3.fromRGB(255, 80, 80),
		Deadly = Color3.fromRGB(200, 50, 150),
		Catastrophic = Color3.fromRGB(150, 50, 200),
	}
	return colors[threatLevel] or colors.Minor
end

-- Create the health bar billboard GUI using Fusion
local function createHealthBarBillboard(parent: BasePart, state: HealthBarState): BillboardGui
	local scope = Fusion.scoped({})
	state.scope = scope

	-- Get predator config for display name
	local config = PredatorConfig.get(state.predatorType)
	local displayName = config and config.displayName or state.predatorType

	-- Compute health percentage
	local healthPercent = Computed(scope, function(use)
		local current = use(state.currentHealth)
		local max = use(state.maxHealth)
		if max > 0 then
			return current / max
		end
		return 1
	end)

	-- Animated health for smooth bar movement
	local animatedPercent = Spring(scope, healthPercent, 20, 0.7)

	-- Health bar color
	local healthColor = Computed(scope, function(use)
		return getHealthColor(use(healthPercent))
	end)

	-- Health text
	local healthText = Computed(scope, function(use)
		local current = use(state.currentHealth)
		local max = use(state.maxHealth)
		return string.format("%d/%d", math.max(0, current), max)
	end)

	local billboard = New(scope, "BillboardGui")({
		Name = "PredatorHealthBar",
		Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT),
		StudsOffset = Vector3.new(0, 3, 0),
		AlwaysOnTop = false,
		Adornee = parent,
		Parent = parent,

		[Children] = {
			-- Main container frame
			New(scope, "Frame")({
				Name = "Container",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,

				[Children] = {
					New(scope, "UICorner")({
						CornerRadius = UDim.new(0, 6),
					}),

					-- Predator name label
					New(scope, "TextLabel")({
						Name = "NameLabel",
						Size = UDim2.new(1, 0, 0.45, 0),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						TextSize = 12,
						TextColor3 = getThreatColor(state.threatLevel),
						Text = displayName,
					}),

					-- Health bar background
					New(scope, "Frame")({
						Name = "HealthBarBg",
						Size = UDim2.new(0.9, 0, 0.3, 0),
						Position = UDim2.new(0.05, 0, 0.45, 0),
						BackgroundColor3 = Color3.fromRGB(60, 60, 60),
						BorderSizePixel = 0,

						[Children] = {
							New(scope, "UICorner")({
								CornerRadius = UDim.new(0, 4),
							}),

							-- Health bar fill
							New(scope, "Frame")({
								Name = "HealthBarFill",
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
						Size = UDim2.new(1, 0, 0.25, 0),
						Position = UDim2.new(0, 0, 0.75, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.Gotham,
						TextSize = 10,
						TextColor3 = Color3.fromRGB(200, 200, 200),
						Text = healthText,
					}),
				},
			}),
		},
	})

	return billboard :: BillboardGui
end

-- Create a health bar for a predator
function PredatorHealthBar.create(
	predatorId: string,
	predatorType: string,
	threatLevel: string,
	model: Model
): HealthBarState?
	-- Remove existing health bar for this predator
	if activeHealthBars[predatorId] then
		PredatorHealthBar.destroy(predatorId)
	end

	local primaryPart = model.PrimaryPart
	if not primaryPart then
		return nil
	end

	-- Get max health from config
	local maxHealthValue = PredatorConfig.getBatHitsRequired(predatorType)

	-- Create a temporary scope for the Value objects
	local tempScope = Fusion.scoped({})

	-- Create state with Fusion Values
	local state: HealthBarState = {
		predatorId = predatorId,
		predatorType = predatorType,
		threatLevel = threatLevel,
		currentHealth = Value(tempScope, maxHealthValue),
		maxHealth = Value(tempScope, maxHealthValue),
		scope = nil,
		billboard = nil,
	}

	-- Create billboard
	state.billboard = createHealthBarBillboard(primaryPart, state)

	-- Clean up temp scope
	Fusion.doCleanup(tempScope)

	activeHealthBars[predatorId] = state

	return state
end

-- Update health for a predator
function PredatorHealthBar.updateHealth(predatorId: string, newHealth: number): boolean
	local state = activeHealthBars[predatorId]
	if not state then
		return false
	end

	state.currentHealth:set(newHealth)
	return true
end

-- Apply damage to a predator's health bar
function PredatorHealthBar.applyDamage(predatorId: string, damage: number): boolean
	local state = activeHealthBars[predatorId]
	if not state then
		return false
	end

	local currentHealthValue = peek(state.currentHealth)
	state.currentHealth:set(math.max(0, currentHealthValue - damage))
	return true
end

-- Destroy a health bar
function PredatorHealthBar.destroy(predatorId: string): boolean
	local state = activeHealthBars[predatorId]
	if not state then
		return false
	end

	if state.scope then
		Fusion.doCleanup(state.scope)
	end

	activeHealthBars[predatorId] = nil
	return true
end

-- Get a health bar state
function PredatorHealthBar.get(predatorId: string): HealthBarState?
	return activeHealthBars[predatorId]
end

-- Get all active health bars
function PredatorHealthBar.getAll(): { [string]: HealthBarState }
	return activeHealthBars
end

-- Get count of active health bars
function PredatorHealthBar.getActiveCount(): number
	local count = 0
	for _ in pairs(activeHealthBars) do
		count = count + 1
	end
	return count
end

-- Cleanup all health bars
function PredatorHealthBar.cleanup()
	for predatorId in pairs(activeHealthBars) do
		PredatorHealthBar.destroy(predatorId)
	end
end

-- Get summary for debugging
function PredatorHealthBar.getSummary(): {
	activeCount: number,
	healthBars: { { predatorId: string, health: string } },
}
	local healthBars = {}
	for predatorId, state in pairs(activeHealthBars) do
		local currentHealthValue = peek(state.currentHealth)
		local maxHealthValue = peek(state.maxHealth)
		table.insert(healthBars, {
			predatorId = predatorId,
			health = string.format("%d/%d", currentHealthValue, maxHealthValue),
		})
	end

	return {
		activeCount = PredatorHealthBar.getActiveCount(),
		healthBars = healthBars,
	}
end

-- Show a floating damage number above a predator
function PredatorHealthBar.showDamageNumber(predatorId: string, damage: number): boolean
	local state = activeHealthBars[predatorId]
	if not state or not state.billboard then
		return false
	end

	local adornee = state.billboard.Adornee :: BasePart?
	if not adornee then
		return false
	end

	-- Create a BillboardGui for the damage number (non-Fusion for animation)
	local damageBillboard = Instance.new("BillboardGui")
	damageBillboard.Name = "DamageNumber"
	damageBillboard.Size = UDim2.new(0, 60, 0, 30)
	damageBillboard.StudsOffset = Vector3.new(math.random(-1, 1), 4, 0)
	damageBillboard.AlwaysOnTop = true
	damageBillboard.Adornee = adornee
	damageBillboard.Parent = adornee

	-- Create damage text label
	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "DamageText"
	damageLabel.Size = UDim2.new(1, 0, 1, 0)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = string.format("-%.0f", damage)
	damageLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	damageLabel.TextStrokeTransparency = 0.3
	damageLabel.TextStrokeColor3 = Color3.fromRGB(50, 0, 0)
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.TextSize = 20
	damageLabel.TextScaled = false
	damageLabel.Parent = damageBillboard

	-- Animate floating up and fading out
	local startOffset = damageBillboard.StudsOffset
	local endOffset = startOffset + Vector3.new(0, DAMAGE_NUMBER_RISE_STUDS, 0)

	local tweenInfo = TweenInfo.new(DAMAGE_NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local moveTween = TweenService:Create(damageBillboard, tweenInfo, {
		StudsOffset = endOffset,
	})

	local fadeTween = TweenService:Create(damageLabel, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()

	moveTween.Completed:Connect(function()
		damageBillboard:Destroy()
	end)

	return true
end

return PredatorHealthBar
