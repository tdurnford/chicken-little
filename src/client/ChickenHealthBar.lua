--[[
	ChickenHealthBar Module
	Creates and manages health bar UI above chicken models.
	Shows health bar only when chicken is damaged, hides at full health.
]]

local ChickenHealthBar = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

-- Type definitions
export type HealthBarState = {
  chickenId: string,
  chickenType: string,
  rarity: string,
  currentHealth: number,
  maxHealth: number,
  billboard: BillboardGui?,
  isVisible: boolean,
}

-- Health bar color thresholds
local HEALTH_COLORS = {
  high = Color3.fromRGB(50, 200, 50), -- Green (>60%)
  medium = Color3.fromRGB(220, 180, 50), -- Yellow (30-60%)
  low = Color3.fromRGB(200, 50, 50), -- Red (<30%)
}

-- UI sizing
local HEALTH_BAR_WIDTH = 80
local HEALTH_BAR_HEIGHT = 20

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

-- Create the health bar billboard GUI
local function createHealthBarBillboard(parent: BasePart, state: HealthBarState): BillboardGui
  local billboard = Instance.new("BillboardGui")
  billboard.Name = "ChickenHealthBar"
  billboard.Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT)
  billboard.StudsOffset = Vector3.new(0, 2.5, 0)
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
  containerCorner.CornerRadius = UDim.new(0, 4)
  containerCorner.Parent = container

  -- Health bar background
  local healthBarBg = Instance.new("Frame")
  healthBarBg.Name = "HealthBarBg"
  healthBarBg.Size = UDim2.new(0.9, 0, 0.6, 0)
  healthBarBg.Position = UDim2.new(0.05, 0, 0.2, 0)
  healthBarBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  healthBarBg.BorderSizePixel = 0
  healthBarBg.Parent = container

  local healthBarBgCorner = Instance.new("UICorner")
  healthBarBgCorner.CornerRadius = UDim.new(0, 3)
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
  healthBarFillCorner.CornerRadius = UDim.new(0, 3)
  healthBarFillCorner.Parent = healthBarFill

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
  local healthPercent = state.maxHealth > 0 and (state.currentHealth / state.maxHealth) or 0

  if healthBarFill then
    healthBarFill.Size = UDim2.new(math.max(0, healthPercent), 0, 1, 0)
    healthBarFill.BackgroundColor3 = getHealthColor(healthPercent)
  end
end

-- Show or hide the health bar based on health state
local function updateVisibility(state: HealthBarState)
  if not state.billboard then
    return
  end

  local shouldBeVisible = state.currentHealth < state.maxHealth and state.currentHealth > 0
  state.isVisible = shouldBeVisible
  state.billboard.Enabled = shouldBeVisible
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
    -- Try to find body part
    primaryPart = model:FindFirstChild("Body") :: BasePart?
    if not primaryPart then
      return nil
    end
  end

  -- Get config for rarity and health
  local config = ChickenConfig.get(chickenType)
  local rarity = config and config.rarity or "Common"
  local maxHealth = ChickenConfig.getMaxHealthForType(chickenType)

  -- Create state
  local state: HealthBarState = {
    chickenId = chickenId,
    chickenType = chickenType,
    rarity = rarity,
    currentHealth = maxHealth,
    maxHealth = maxHealth,
    billboard = nil,
    isVisible = false,
  }

  -- Create billboard
  state.billboard = createHealthBarBillboard(primaryPart, state)
  state.billboard.Enabled = false -- Hidden by default (full health)

  activeHealthBars[chickenId] = state

  return state
end

-- Update health for a chicken
function ChickenHealthBar.updateHealth(chickenId: string, currentHealth: number): boolean
  local state = activeHealthBars[chickenId]
  if not state then
    return false
  end

  state.currentHealth = currentHealth
  updateHealthBarDisplay(state)
  updateVisibility(state)
  return true
end

-- Set max health for a chicken (if needed)
function ChickenHealthBar.setMaxHealth(chickenId: string, maxHealth: number): boolean
  local state = activeHealthBars[chickenId]
  if not state then
    return false
  end

  state.maxHealth = maxHealth
  updateHealthBarDisplay(state)
  updateVisibility(state)
  return true
end

-- Destroy a health bar
function ChickenHealthBar.destroy(chickenId: string): boolean
  local state = activeHealthBars[chickenId]
  if not state then
    return false
  end

  if state.billboard then
    state.billboard:Destroy()
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
    table.insert(healthBars, {
      chickenId = chickenId,
      health = string.format("%d/%d", state.currentHealth, state.maxHealth),
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
