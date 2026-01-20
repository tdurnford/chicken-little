--[[
	ChickenHealthBar Component (Fusion)
	Creates and manages health bar UI above chicken models using Fusion reactive state.
	Shows health bar only when chicken is damaged, hides at full health.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local peek = Fusion.peek

-- Types
export type HealthBarState = {
	chickenId: string,
	chickenType: string,
	rarity: string,
	currentHealth: Fusion.Value<number>,
	maxHealth: Fusion.Value<number>,
	scope: Fusion.Scope?,
	billboard: BillboardGui?,
	isVisible: boolean,
}

-- Health bar color thresholds
local HEALTH_COLORS = {
	high = Color3.fromRGB(50, 200, 50),
	medium = Color3.fromRGB(220, 180, 50),
	low = Color3.fromRGB(200, 50, 50),
}

-- UI sizing
local HEALTH_BAR_WIDTH = 80
local HEALTH_BAR_HEIGHT = 20

-- Module state
local ChickenHealthBar = {}
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

-- Create the health bar billboard GUI using Fusion
local function createHealthBarBillboard(parent: BasePart, state: HealthBarState): BillboardGui
	local scope = Fusion.scoped({})
	state.scope = scope

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

	-- Visibility based on health state
	local shouldBeVisible = Computed(scope, function(use)
		local current = use(state.currentHealth)
		local max = use(state.maxHealth)
		return current < max and current > 0
	end)

	local billboard = New(scope, "BillboardGui")({
		Name = "ChickenHealthBar",
		Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT),
		StudsOffset = Vector3.new(0, 2.5, 0),
		AlwaysOnTop = false,
		Adornee = parent,
		Parent = parent,
		Enabled = shouldBeVisible,

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
						CornerRadius = UDim.new(0, 4),
					}),

					-- Health bar background
					New(scope, "Frame")({
						Name = "HealthBarBg",
						Size = UDim2.new(0.9, 0, 0.6, 0),
						Position = UDim2.new(0.05, 0, 0.2, 0),
						BackgroundColor3 = Color3.fromRGB(60, 60, 60),
						BorderSizePixel = 0,

						[Children] = {
							New(scope, "UICorner")({
								CornerRadius = UDim.new(0, 3),
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
										CornerRadius = UDim.new(0, 3),
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})

	return billboard :: BillboardGui
end

-- Create a health bar for a chicken
function ChickenHealthBar.create(
	chickenId: string,
	chickenType: string,
	model: Model
): HealthBarState?
	-- Remove existing health bar for this chicken
	if activeHealthBars[chickenId] then
		ChickenHealthBar.destroy(chickenId)
	end

	local primaryPart = model.PrimaryPart
	if not primaryPart then
		primaryPart = model:FindFirstChild("Body") :: BasePart?
		if not primaryPart then
			return nil
		end
	end

	-- Get config for rarity and health
	local config = ChickenConfig.get(chickenType)
	local rarity = config and config.rarity or "Common"
	local maxHealthValue = ChickenConfig.getMaxHealthForType(chickenType)

	-- Create a temporary scope for the Value objects
	local tempScope = Fusion.scoped({})

	-- Create state with Fusion Values
	local state: HealthBarState = {
		chickenId = chickenId,
		chickenType = chickenType,
		rarity = rarity,
		currentHealth = Value(tempScope, maxHealthValue),
		maxHealth = Value(tempScope, maxHealthValue),
		scope = nil,
		billboard = nil,
		isVisible = false,
	}

	-- Create billboard (this will create its own scope and transfer the values)
	state.billboard = createHealthBarBillboard(primaryPart, state)

	-- Clean up temp scope (values are now managed by billboard scope)
	Fusion.doCleanup(tempScope)

	activeHealthBars[chickenId] = state

	return state
end

-- Update health for a chicken
function ChickenHealthBar.updateHealth(chickenId: string, newHealth: number): boolean
	local state = activeHealthBars[chickenId]
	if not state then
		return false
	end

	state.currentHealth:set(newHealth)

	-- Update visibility tracking
	local maxHealthValue = peek(state.maxHealth)
	state.isVisible = newHealth < maxHealthValue and newHealth > 0

	return true
end

-- Set max health for a chicken
function ChickenHealthBar.setMaxHealth(chickenId: string, newMaxHealth: number): boolean
	local state = activeHealthBars[chickenId]
	if not state then
		return false
	end

	state.maxHealth:set(newMaxHealth)
	return true
end

-- Destroy a health bar
function ChickenHealthBar.destroy(chickenId: string): boolean
	local state = activeHealthBars[chickenId]
	if not state then
		return false
	end

	if state.scope then
		Fusion.doCleanup(state.scope)
	end

	activeHealthBars[chickenId] = nil
	return true
end

-- Get a health bar state
function ChickenHealthBar.get(chickenId: string): HealthBarState?
	return activeHealthBars[chickenId]
end

-- Get all active health bars
function ChickenHealthBar.getAll(): { [string]: HealthBarState }
	return activeHealthBars
end

-- Get count of active health bars
function ChickenHealthBar.getActiveCount(): number
	local count = 0
	for _ in pairs(activeHealthBars) do
		count = count + 1
	end
	return count
end

-- Get count of visible health bars (damaged chickens)
function ChickenHealthBar.getVisibleCount(): number
	local count = 0
	for _, state in pairs(activeHealthBars) do
		if state.isVisible then
			count = count + 1
		end
	end
	return count
end

-- Cleanup all health bars
function ChickenHealthBar.cleanup()
	for chickenId in pairs(activeHealthBars) do
		ChickenHealthBar.destroy(chickenId)
	end
end

-- Get summary for debugging
function ChickenHealthBar.getSummary(): {
	activeCount: number,
	visibleCount: number,
	healthBars: { { chickenId: string, health: string, visible: boolean } },
}
	local healthBars = {}
	for chickenId, state in pairs(activeHealthBars) do
		local currentHealthValue = peek(state.currentHealth)
		local maxHealthValue = peek(state.maxHealth)
		table.insert(healthBars, {
			chickenId = chickenId,
			health = string.format("%d/%d", currentHealthValue, maxHealthValue),
			visible = state.isVisible,
		})
	end

	return {
		activeCount = ChickenHealthBar.getActiveCount(),
		visibleCount = ChickenHealthBar.getVisibleCount(),
		healthBars = healthBars,
	}
end

return ChickenHealthBar
