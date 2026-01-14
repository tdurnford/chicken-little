--[[
	ChickenVisuals Module
	Manages chicken model creation, animations (idle, laying), and visual effects
	including money generation indicators. Provides rarity-based visual variations.
]]

local ChickenVisuals = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Get shared modules path
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

-- Type definitions
export type AnimationState = "idle" | "laying" | "celebrating" | "walking"

export type VisualConfig = {
  baseSize: Vector3,
  idleBobAmount: number,
  idleBobSpeed: number,
  layingSquashAmount: number,
  layingDuration: number,
  moneyPopDuration: number,
  celebrationDuration: number,
}

export type ChickenVisualState = {
  model: Model?,
  chickenType: string,
  rarity: string,
  currentAnimation: AnimationState,
  animationConnection: RBXScriptConnection?,
  moneyIndicator: BillboardGui?,
  accumulatedMoney: number,
  moneyPerSecond: number,
  position: Vector3,
  spotIndex: number?,
  healthPercent: number,
  isDamaged: boolean,
}

export type MoneyPopConfig = {
  amount: number,
  position: Vector3,
  isLarge: boolean,
}

-- Rarity colors for visual distinction and glow effects
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(180, 180, 180),
  Uncommon = Color3.fromRGB(100, 200, 100),
  Rare = Color3.fromRGB(100, 150, 255),
  Epic = Color3.fromRGB(180, 100, 255),
  Legendary = Color3.fromRGB(255, 180, 50),
  Mythic = Color3.fromRGB(255, 100, 150),
}

-- Rarity glow intensities
local RARITY_GLOW_INTENSITY: { [string]: number } = {
  Common = 0,
  Uncommon = 0.1,
  Rare = 0.3,
  Epic = 0.5,
  Legendary = 0.8,
  Mythic = 1.0,
}

-- Base chicken scale per rarity (rarer = slightly larger)
local RARITY_SCALE_MULTIPLIER: { [string]: number } = {
  Common = 1.0,
  Uncommon = 1.05,
  Rare = 1.1,
  Epic = 1.15,
  Legendary = 1.2,
  Mythic = 1.3,
}

-- Default visual configuration
local DEFAULT_VISUAL_CONFIG: VisualConfig = {
  baseSize = Vector3.new(2, 2, 2),
  idleBobAmount = 0.1,
  idleBobSpeed = 2,
  layingSquashAmount = 0.2,
  layingDuration = 1.5,
  moneyPopDuration = 1.0,
  celebrationDuration = 2.0,
}

-- Animation timing
local IDLE_BOB_SPEED = 2.0
local LAYING_SQUASH_DURATION = 0.3
local LAYING_HOLD_DURATION = 0.5
local CELEBRATION_SPIN_SPEED = 3.0
local MONEY_POP_RISE_HEIGHT = 2.0
local MONEY_POP_FADE_DURATION = 1.0

-- Module state
local activeChickens: { [string]: ChickenVisualState } = {}
local currentConfig: VisualConfig = DEFAULT_VISUAL_CONFIG
local updateConnection: RBXScriptConnection? = nil
local animationTime: number = 0

-- Helper: Get rarity color
local function getRarityColor(rarity: string): Color3
  return RARITY_COLORS[rarity] or RARITY_COLORS.Common
end

-- Helper: Get rarity glow intensity
local function getGlowIntensity(rarity: string): number
  return RARITY_GLOW_INTENSITY[rarity] or 0
end

-- Helper: Get rarity scale multiplier
local function getScaleMultiplier(rarity: string): number
  return RARITY_SCALE_MULTIPLIER[rarity] or 1.0
end

-- Helper: Format money for display
local function formatMoney(amount: number): string
  if amount >= 1e12 then
    return string.format("%.1fT", amount / 1e12)
  elseif amount >= 1e9 then
    return string.format("%.1fB", amount / 1e9)
  elseif amount >= 1e6 then
    return string.format("%.1fM", amount / 1e6)
  elseif amount >= 1e3 then
    return string.format("%.1fK", amount / 1e3)
  else
    return string.format("$%d", math.floor(amount))
  end
end

-- Create a placeholder chicken model (to be replaced with actual assets)
local function createPlaceholderModel(chickenType: string, rarity: string): Model
  local model = Instance.new("Model")
  model.Name = chickenType

  -- Create body part (sphere-like using a Part)
  local body = Instance.new("Part")
  body.Name = "Body"
  body.Shape = Enum.PartType.Ball
  local scale = getScaleMultiplier(rarity)
  body.Size = currentConfig.baseSize * scale
  body.Color = getRarityColor(rarity)
  body.Material = Enum.Material.SmoothPlastic
  body.Anchored = true
  body.CanCollide = false
  body.CastShadow = true
  body.Parent = model

  -- Create head (smaller sphere)
  local head = Instance.new("Part")
  head.Name = "Head"
  head.Shape = Enum.PartType.Ball
  head.Size = Vector3.new(1, 1, 1) * scale
  head.Color = getRarityColor(rarity)
  head.Material = Enum.Material.SmoothPlastic
  head.Anchored = true
  head.CanCollide = false
  head.CastShadow = true
  head.Position = body.Position + Vector3.new(0, 1.2 * scale, 0.5 * scale)
  head.Parent = model

  -- Create beak (small wedge)
  local beak = Instance.new("Part")
  beak.Name = "Beak"
  beak.Size = Vector3.new(0.3, 0.2, 0.4) * scale
  beak.Color = Color3.fromRGB(255, 180, 50)
  beak.Material = Enum.Material.SmoothPlastic
  beak.Anchored = true
  beak.CanCollide = false
  beak.Position = head.Position + Vector3.new(0, -0.1 * scale, 0.5 * scale)
  beak.Parent = model

  -- Add glow effect for rare+ chickens
  local glowIntensity = getGlowIntensity(rarity)
  if glowIntensity > 0 then
    local pointLight = Instance.new("PointLight")
    pointLight.Name = "RarityGlow"
    pointLight.Color = getRarityColor(rarity)
    pointLight.Brightness = glowIntensity * 2
    pointLight.Range = 4 + (glowIntensity * 4)
    pointLight.Shadows = false
    pointLight.Parent = body

    -- Add particle effect for Legendary+ chickens
    if rarity == "Legendary" or rarity == "Mythic" then
      local particles = Instance.new("ParticleEmitter")
      particles.Name = "RarityParticles"
      particles.Color = ColorSequence.new(getRarityColor(rarity))
      particles.Size = NumberSequence.new(0.2, 0)
      particles.Transparency = NumberSequence.new(0, 1)
      particles.Lifetime = NumberRange.new(1, 2)
      particles.Rate = 5 + (glowIntensity * 10)
      particles.Speed = NumberRange.new(1, 2)
      particles.SpreadAngle = Vector2.new(180, 180)
      particles.Parent = body
    end
  end

  -- Set PrimaryPart for positioning
  model.PrimaryPart = body

  return model
end

-- Helper: Format money rate for display ($/s)
local function formatMoneyRate(rate: number): string
  if rate >= 1000 then
    return string.format("$%.1fK/s", rate / 1000)
  elseif rate >= 100 then
    return string.format("$%.0f/s", rate)
  elseif rate >= 10 then
    return string.format("$%.1f/s", rate)
  else
    return string.format("$%.2f/s", rate)
  end
end

-- Create money indicator billboard GUI
local function createMoneyIndicator(parent: BasePart, moneyPerSecond: number): BillboardGui
  local billboard = Instance.new("BillboardGui")
  billboard.Name = "MoneyIndicator"
  billboard.Size = UDim2.new(0, 80, 0, 50)
  billboard.StudsOffset = Vector3.new(0, 2.5, 0)
  billboard.AlwaysOnTop = true
  billboard.Adornee = parent
  billboard.Parent = parent

  -- Background frame
  local bg = Instance.new("Frame")
  bg.Name = "Background"
  bg.Size = UDim2.new(1, 0, 1, 0)
  bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  bg.BackgroundTransparency = 0.3
  bg.BorderSizePixel = 0
  bg.Parent = billboard

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = bg

  -- Rate text ($/s) - top portion
  local rateText = Instance.new("TextLabel")
  rateText.Name = "RateText"
  rateText.Size = UDim2.new(1, 0, 0.5, 0)
  rateText.Position = UDim2.new(0, 0, 0, 0)
  rateText.BackgroundTransparency = 1
  rateText.Font = Enum.Font.GothamBold
  rateText.TextSize = 12
  rateText.TextColor3 = Color3.fromRGB(255, 220, 100)
  rateText.Text = formatMoneyRate(moneyPerSecond)
  rateText.Parent = bg

  -- Money text (accumulated) - bottom portion
  local moneyText = Instance.new("TextLabel")
  moneyText.Name = "MoneyText"
  moneyText.Size = UDim2.new(1, 0, 0.5, 0)
  moneyText.Position = UDim2.new(0, 0, 0.5, 0)
  moneyText.BackgroundTransparency = 1
  moneyText.Font = Enum.Font.GothamBold
  moneyText.TextSize = 14
  moneyText.TextColor3 = Color3.fromRGB(100, 255, 100)
  moneyText.Text = "$0"
  moneyText.Parent = bg

  return billboard
end

-- Update money indicator display
local function updateMoneyIndicator(state: ChickenVisualState)
  if not state.moneyIndicator then
    return
  end

  local bg = state.moneyIndicator:FindFirstChild("Background")
  if not bg then
    return
  end

  local moneyText = bg:FindFirstChild("MoneyText") :: TextLabel?
  if moneyText then
    moneyText.Text = formatMoney(state.accumulatedMoney)

    -- Scale color based on amount (greener for more money)
    local intensity = math.min(1, state.accumulatedMoney / 1000)
    moneyText.TextColor3 = Color3.fromRGB(100 + intensity * 155, 255, 100)
  end
end

-- Apply idle bobbing animation
local function applyIdleAnimation(state: ChickenVisualState, deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  local bobOffset = math.sin(animationTime * IDLE_BOB_SPEED) * currentConfig.idleBobAmount
  local targetPosition = state.position + Vector3.new(0, bobOffset, 0)

  state.model:SetPrimaryPartCFrame(CFrame.new(targetPosition))
end

-- Play egg laying animation
function ChickenVisuals.playLayingAnimation(chickenId: string): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "laying"

  local body = state.model.PrimaryPart
  local originalSize = body.Size

  -- Squash animation (flatten body)
  local squashTween = TweenService:Create(
    body,
    TweenInfo.new(LAYING_SQUASH_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
    {
      Size = Vector3.new(
        originalSize.X * (1 + currentConfig.layingSquashAmount),
        originalSize.Y * (1 - currentConfig.layingSquashAmount),
        originalSize.Z * (1 + currentConfig.layingSquashAmount)
      ),
    }
  )

  -- Stretch back animation
  local stretchTween = TweenService:Create(
    body,
    TweenInfo.new(LAYING_SQUASH_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = originalSize }
  )

  squashTween:Play()
  squashTween.Completed:Connect(function()
    -- Hold for a moment then stretch back
    task.wait(LAYING_HOLD_DURATION)
    stretchTween:Play()
    stretchTween.Completed:Connect(function()
      state.currentAnimation = "idle"
    end)
  end)

  return true
end

-- Play celebration animation (for rare hatches)
function ChickenVisuals.playCelebrationAnimation(chickenId: string): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "celebrating"

  local body = state.model.PrimaryPart
  local startCFrame = body.CFrame

  -- Spin and bounce animation
  local spinDuration = currentConfig.celebrationDuration
  local startTime = tick()

  local connection
  connection = RunService.Heartbeat:Connect(function()
    local elapsed = tick() - startTime
    if elapsed >= spinDuration then
      connection:Disconnect()
      state.currentAnimation = "idle"
      return
    end

    local progress = elapsed / spinDuration
    local bounceHeight = math.sin(progress * math.pi * 4) * 0.5
    local spinAngle = progress * math.pi * 2 * CELEBRATION_SPIN_SPEED

    local newCFrame = CFrame.new(state.position + Vector3.new(0, bounceHeight, 0))
      * CFrame.Angles(0, spinAngle, 0)

    state.model:SetPrimaryPartCFrame(newCFrame)
  end)

  return true
end

-- Create a money pop effect when collecting money
function ChickenVisuals.createMoneyPopEffect(config: MoneyPopConfig)
  -- Create floating text
  local part = Instance.new("Part")
  part.Name = "MoneyPop"
  part.Size = Vector3.new(0.1, 0.1, 0.1)
  part.Transparency = 1
  part.Anchored = true
  part.CanCollide = false
  part.Position = config.position
  part.Parent = workspace

  local billboard = Instance.new("BillboardGui")
  billboard.Name = "MoneyPopGui"
  billboard.Size = UDim2.new(0, 100, 0, 40)
  billboard.StudsOffset = Vector3.new(0, 0, 0)
  billboard.AlwaysOnTop = true
  billboard.Adornee = part
  billboard.Parent = part

  local text = Instance.new("TextLabel")
  text.Name = "AmountText"
  text.Size = UDim2.new(1, 0, 1, 0)
  text.BackgroundTransparency = 1
  text.Font = Enum.Font.GothamBold
  text.TextSize = config.isLarge and 24 or 18
  text.TextColor3 = config.isLarge and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(100, 255, 100)
  text.TextStrokeTransparency = 0.5
  text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  text.Text = "+" .. formatMoney(config.amount)
  text.Parent = billboard

  -- Animate rising and fading
  local startPos = config.position
  local endPos = startPos + Vector3.new(0, MONEY_POP_RISE_HEIGHT, 0)

  local positionTween = TweenService:Create(
    part,
    TweenInfo.new(MONEY_POP_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { Position = endPos }
  )

  local fadeTween = TweenService:Create(
    text,
    TweenInfo.new(MONEY_POP_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
    { TextTransparency = 1, TextStrokeTransparency = 1 }
  )

  positionTween:Play()
  fadeTween:Play()

  fadeTween.Completed:Connect(function()
    part:Destroy()
  end)
end

-- Create a chicken visual at a position
function ChickenVisuals.create(
  chickenId: string,
  chickenType: string,
  position: Vector3,
  spotIndex: number?
): ChickenVisualState?
  -- Get chicken config for rarity
  local config = ChickenConfig.get(chickenType)
  if not config then
    return nil
  end

  -- Remove existing chicken with same ID
  if activeChickens[chickenId] then
    ChickenVisuals.destroy(chickenId)
  end

  -- Create model
  local model = createPlaceholderModel(chickenType, config.rarity)
  model:SetPrimaryPartCFrame(CFrame.new(position))
  model.Parent = workspace

  -- Create money indicator only for placed chickens (arena chickens have no spotIndex)
  local moneyIndicator: BillboardGui? = nil
  local chickenMoneyPerSecond = config.moneyPerSecond or 1
  if spotIndex ~= nil then
    moneyIndicator = createMoneyIndicator(model.PrimaryPart, chickenMoneyPerSecond)
  end

  -- Create state
  local state: ChickenVisualState = {
    model = model,
    chickenType = chickenType,
    rarity = config.rarity,
    currentAnimation = "idle",
    animationConnection = nil,
    moneyIndicator = moneyIndicator,
    accumulatedMoney = 0,
    moneyPerSecond = config.moneyPerSecond or 1,
    position = position,
    spotIndex = spotIndex,
    healthPercent = 1.0,
    isDamaged = false,
  }

  activeChickens[chickenId] = state

  -- Start update loop if not running
  if not updateConnection then
    updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
      animationTime = animationTime + deltaTime
      for _, chickenState in pairs(activeChickens) do
        if chickenState.currentAnimation == "idle" then
          applyIdleAnimation(chickenState, deltaTime)
        end
        -- Client-side money accumulation for smooth counter (only for placed chickens)
        -- Apply health multiplier to money generation rate
        if chickenState.moneyPerSecond > 0 and chickenState.spotIndex ~= nil then
          local effectiveMoneyPerSecond = chickenState.moneyPerSecond * chickenState.healthPercent
          chickenState.accumulatedMoney = chickenState.accumulatedMoney
            + (effectiveMoneyPerSecond * deltaTime)
          updateMoneyIndicator(chickenState)
        end
      end
    end)
  end

  return state
end

-- Update accumulated money display
function ChickenVisuals.updateMoney(chickenId: string, amount: number)
  local state = activeChickens[chickenId]
  if state then
    state.accumulatedMoney = amount
    updateMoneyIndicator(state)
  end
end

-- Update chicken health state and apply visual damage indicator
-- Damaged chickens have reduced color saturation and show income penalty
function ChickenVisuals.updateHealthState(chickenId: string, healthPercent: number): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  state.healthPercent = healthPercent
  state.isDamaged = healthPercent < 1.0

  -- Apply visual damage indicator (desaturated/darkened color)
  local body = state.model:FindFirstChild("Body") :: BasePart?
  local head = state.model:FindFirstChild("Head") :: BasePart?

  if body or head then
    local baseColor = getRarityColor(state.rarity)

    if state.isDamaged then
      -- Desaturate and darken based on health loss
      -- At 50% health, chicken is 50% darker/greyer
      local damageAmount = 1 - healthPercent
      local h, s, v = baseColor:ToHSV()
      -- Reduce saturation and value based on damage
      local newS = s * healthPercent
      local newV = v * (0.5 + 0.5 * healthPercent) -- At 0% health, 50% brightness
      local damagedColor = Color3.fromHSV(h, newS, newV)

      if body then
        body.Color = damagedColor
      end
      if head then
        head.Color = damagedColor
      end
    else
      -- Restore original color at full health
      if body then
        body.Color = baseColor
      end
      if head then
        head.Color = baseColor
      end
    end
  end

  -- Update money indicator to show reduced income
  if state.moneyIndicator then
    local bg = state.moneyIndicator:FindFirstChild("Background")
    if bg then
      local moneyText = bg:FindFirstChild("MoneyText") :: TextLabel?
      local rateText = bg:FindFirstChild("RateText") :: TextLabel?
      if state.isDamaged then
        -- Show reduced income with orange/red tint
        local intensity = healthPercent
        if moneyText then
          moneyText.TextColor3 = Color3.fromRGB(255, math.floor(100 + intensity * 155), 50)
        end
        -- Update rate text to show effective rate
        if rateText then
          local effectiveRate = state.moneyPerSecond * healthPercent
          rateText.Text = formatMoneyRate(effectiveRate)
          rateText.TextColor3 = Color3.fromRGB(255, math.floor(150 + intensity * 70), 50)
        end
      else
        -- Restore normal colors at full health
        if moneyText then
          moneyText.TextColor3 = Color3.fromRGB(100, 255, 100)
        end
        if rateText then
          rateText.Text = formatMoneyRate(state.moneyPerSecond)
          rateText.TextColor3 = Color3.fromRGB(255, 220, 100)
        end
      end
    end
  end

  return true
end

-- Get whether a chicken is damaged (reduced income)
function ChickenVisuals.isDamaged(chickenId: string): boolean
  local state = activeChickens[chickenId]
  return state and state.isDamaged or false
end

-- Get income multiplier for a chicken (based on health)
function ChickenVisuals.getIncomeMultiplier(chickenId: string): number
  local state = activeChickens[chickenId]
  if state then
    return state.healthPercent or 1.0
  end
  return 1.0
end

-- Destroy a chicken visual
function ChickenVisuals.destroy(chickenId: string): boolean
  local state = activeChickens[chickenId]
  if not state then
    return false
  end

  if state.animationConnection then
    state.animationConnection:Disconnect()
  end

  if state.model then
    state.model:Destroy()
  end

  activeChickens[chickenId] = nil

  -- Stop update loop if no more chickens
  if next(activeChickens) == nil and updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  return true
end

-- Get chicken visual state
function ChickenVisuals.get(chickenId: string): ChickenVisualState?
  return activeChickens[chickenId]
end

-- Get accumulated money for a chicken (real-time client-side value)
function ChickenVisuals.getAccumulatedMoney(chickenId: string): number
  local state = activeChickens[chickenId]
  if state then
    return state.accumulatedMoney or 0
  end
  return 0
end

-- Reset accumulated money for a chicken (called after server collection)
function ChickenVisuals.resetAccumulatedMoney(chickenId: string, remainder: number?)
  local state = activeChickens[chickenId]
  if state then
    state.accumulatedMoney = remainder or 0
    -- Update the money display immediately
    if state.moneyLabel then
      local displayAmount = math.floor(state.accumulatedMoney)
      state.moneyLabel.Text = "$" .. tostring(displayAmount)
    end
  end
end

-- Get all active chicken visuals
function ChickenVisuals.getAll(): { [string]: ChickenVisualState }
  return activeChickens
end

-- Get count of active visuals
function ChickenVisuals.getActiveCount(): number
  local count = 0
  for _ in pairs(activeChickens) do
    count = count + 1
  end
  return count
end

-- Set position for a chicken
function ChickenVisuals.setPosition(chickenId: string, position: Vector3): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  state.position = position
  state.model:SetPrimaryPartCFrame(CFrame.new(position))
  return true
end

-- Move chicken to a new spot (updates position and spotIndex)
function ChickenVisuals.moveToSpot(
  chickenId: string,
  position: Vector3,
  newSpotIndex: number
): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  state.position = position
  state.spotIndex = newSpotIndex
  state.model:SetPrimaryPartCFrame(CFrame.new(position))
  return true
end

-- Update position with facing direction and animation state (for wandering chickens)
function ChickenVisuals.updatePosition(
  chickenId: string,
  position: Vector3,
  facingDirection: Vector3,
  isIdle: boolean
): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  state.position = position

  -- Update animation state based on movement
  if isIdle then
    state.currentAnimation = "idle"
  else
    state.currentAnimation = "walking"
  end

  -- Create CFrame with rotation toward facing direction
  local lookAt = position + facingDirection
  local cframe = CFrame.lookAt(position, lookAt)

  -- Apply position and rotation
  state.model:SetPrimaryPartCFrame(cframe)

  return true
end

-- Configure visual settings
function ChickenVisuals.configure(config: VisualConfig)
  currentConfig = config
end

-- Get current configuration
function ChickenVisuals.getConfig(): VisualConfig
  return currentConfig
end

-- Get rarity color for external use
function ChickenVisuals.getRarityColor(rarity: string): Color3
  return getRarityColor(rarity)
end

-- Get all rarity colors
function ChickenVisuals.getRarityColors(): { [string]: Color3 }
  return RARITY_COLORS
end

-- Cleanup all chicken visuals
function ChickenVisuals.cleanup()
  for chickenId in pairs(activeChickens) do
    ChickenVisuals.destroy(chickenId)
  end

  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  animationTime = 0
end

-- Get summary for debugging
function ChickenVisuals.getSummary(): { activeCount: number, animationTime: number }
  return {
    activeCount = ChickenVisuals.getActiveCount(),
    animationTime = animationTime,
  }
end

return ChickenVisuals
