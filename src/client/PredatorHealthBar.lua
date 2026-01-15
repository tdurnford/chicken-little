--[[
	PredatorHealthBar Module
	Creates and manages health bar UI above predator models.
	Shows predator name, threat level, and health bar that updates in real-time.
]]

local PredatorHealthBar = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Type definitions
export type HealthBarState = {
  predatorId: string,
  predatorType: string,
  threatLevel: string,
  currentHealth: number,
  maxHealth: number,
  billboard: BillboardGui?,
}

-- Health bar color thresholds
local HEALTH_COLORS = {
  high = Color3.fromRGB(50, 200, 50), -- Green (>60%)
  medium = Color3.fromRGB(220, 180, 50), -- Yellow (30-60%)
  low = Color3.fromRGB(200, 50, 50), -- Red (<30%)
}

-- UI sizing
local HEALTH_BAR_WIDTH = 120
local HEALTH_BAR_HEIGHT = 50

-- Module state
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

-- Create the health bar billboard GUI
local function createHealthBarBillboard(parent: BasePart, state: HealthBarState): BillboardGui
  local billboard = Instance.new("BillboardGui")
  billboard.Name = "PredatorHealthBar"
  billboard.Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT)
  billboard.StudsOffset = Vector3.new(0, 3, 0)
  billboard.AlwaysOnTop = false
  billboard.Adornee = parent
  billboard.Parent = parent

  -- Main container frame
  local container = Instance.new("Frame")
  container.Name = "Container"
  container.Size = UDim2.new(1, 0, 1, 0)
  container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
  container.BackgroundTransparency = 0.3
  container.BorderSizePixel = 0
  container.Parent = billboard

  local containerCorner = Instance.new("UICorner")
  containerCorner.CornerRadius = UDim.new(0, 6)
  containerCorner.Parent = container

  -- Predator name label
  local config = PredatorConfig.get(state.predatorType)
  local displayName = config and config.displayName or state.predatorType

  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
  nameLabel.Position = UDim2.new(0, 0, 0, 0)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextSize = 12
  nameLabel.TextColor3 = getThreatColor(state.threatLevel)
  nameLabel.Text = displayName
  nameLabel.Parent = container

  -- Health bar background
  local healthBarBg = Instance.new("Frame")
  healthBarBg.Name = "HealthBarBg"
  healthBarBg.Size = UDim2.new(0.9, 0, 0.3, 0)
  healthBarBg.Position = UDim2.new(0.05, 0, 0.45, 0)
  healthBarBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  healthBarBg.BorderSizePixel = 0
  healthBarBg.Parent = container

  local healthBarBgCorner = Instance.new("UICorner")
  healthBarBgCorner.CornerRadius = UDim.new(0, 4)
  healthBarBgCorner.Parent = healthBarBg

  -- Health bar fill
  local healthPercent = state.maxHealth > 0 and (state.currentHealth / state.maxHealth) or 1
  local healthBarFill = Instance.new("Frame")
  healthBarFill.Name = "HealthBarFill"
  healthBarFill.Size = UDim2.new(healthPercent, 0, 1, 0)
  healthBarFill.BackgroundColor3 = getHealthColor(healthPercent)
  healthBarFill.BorderSizePixel = 0
  healthBarFill.Parent = healthBarBg

  local healthBarFillCorner = Instance.new("UICorner")
  healthBarFillCorner.CornerRadius = UDim.new(0, 4)
  healthBarFillCorner.Parent = healthBarFill

  -- Health text (e.g., "3/5")
  local healthText = Instance.new("TextLabel")
  healthText.Name = "HealthText"
  healthText.Size = UDim2.new(1, 0, 0.25, 0)
  healthText.Position = UDim2.new(0, 0, 0.75, 0)
  healthText.BackgroundTransparency = 1
  healthText.Font = Enum.Font.Gotham
  healthText.TextSize = 10
  healthText.TextColor3 = Color3.fromRGB(200, 200, 200)
  healthText.Text = string.format("%d/%d", state.currentHealth, state.maxHealth)
  healthText.Parent = container

  return billboard
end

-- Update the health bar display
local function updateHealthBarDisplay(state: HealthBarState)
  if not state.billboard then
    return
  end

  local container = state.billboard:FindFirstChild("Container")
  if not container then
    return
  end

  local healthBarBg = container:FindFirstChild("HealthBarBg")
  if not healthBarBg then
    return
  end

  local healthBarFill = healthBarBg:FindFirstChild("HealthBarFill") :: Frame?
  local healthText = container:FindFirstChild("HealthText") :: TextLabel?

  local healthPercent = state.maxHealth > 0 and (state.currentHealth / state.maxHealth) or 0

  if healthBarFill then
    healthBarFill.Size = UDim2.new(math.max(0, healthPercent), 0, 1, 0)
    healthBarFill.BackgroundColor3 = getHealthColor(healthPercent)
  end

  if healthText then
    healthText.Text = string.format("%d/%d", math.max(0, state.currentHealth), state.maxHealth)
  end
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
  local maxHealth = PredatorConfig.getBatHitsRequired(predatorType)

  -- Create state
  local state: HealthBarState = {
    predatorId = predatorId,
    predatorType = predatorType,
    threatLevel = threatLevel,
    currentHealth = maxHealth,
    maxHealth = maxHealth,
    billboard = nil,
  }

  -- Create billboard
  state.billboard = createHealthBarBillboard(primaryPart, state)
  activeHealthBars[predatorId] = state

  return state
end

-- Update health for a predator
function PredatorHealthBar.updateHealth(predatorId: string, currentHealth: number): boolean
  local state = activeHealthBars[predatorId]
  if not state then
    return false
  end

  state.currentHealth = currentHealth
  updateHealthBarDisplay(state)
  return true
end

-- Apply damage to a predator's health bar
function PredatorHealthBar.applyDamage(predatorId: string, damage: number): boolean
  local state = activeHealthBars[predatorId]
  if not state then
    return false
  end

  state.currentHealth = math.max(0, state.currentHealth - damage)
  updateHealthBarDisplay(state)
  return true
end

-- Destroy a health bar
function PredatorHealthBar.destroy(predatorId: string): boolean
  local state = activeHealthBars[predatorId]
  if not state then
    return false
  end

  if state.billboard then
    state.billboard:Destroy()
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
    table.insert(healthBars, {
      predatorId = predatorId,
      health = string.format("%d/%d", state.currentHealth, state.maxHealth),
    })
  end

  return {
    activeCount = PredatorHealthBar.getActiveCount(),
    healthBars = healthBars,
  }
end

-- Constants for damage number animation
local DAMAGE_NUMBER_LIFETIME = 1.0 -- Seconds for damage number to float and fade
local DAMAGE_NUMBER_RISE_STUDS = 3 -- How high the damage number floats

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

  -- Create a BillboardGui for the damage number
  local damageBillboard = Instance.new("BillboardGui")
  damageBillboard.Name = "DamageNumber"
  damageBillboard.Size = UDim2.new(0, 60, 0, 30)
  damageBillboard.StudsOffset = Vector3.new(math.random(-1, 1), 4, 0) -- Slight horizontal randomness
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

  local tweenInfo =
    TweenInfo.new(DAMAGE_NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
