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
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))
local Store = require(Shared:WaitForChild("Store"))

-- Callback for sell prompt triggered
local onSellPromptTriggered: ((chickenId: string) -> ())?

-- Callback for claim prompt triggered (random chickens)
local onClaimPromptTriggered: ((chickenId: string) -> ())?

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
  maxMoneyCapacity: number, -- Maximum money capacity before generation stops
  position: Vector3,
  targetPosition: Vector3?,
  targetFacingDirection: Vector3?,
  currentFacingDirection: Vector3?,
  walkSpeed: number, -- Walk speed from server for smooth client-side movement
  isPlaced: boolean,
  healthPercent: number,
  isDamaged: boolean,
  isAtMaxCapacity: boolean, -- Whether chicken is at max capacity
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

-- Smooth movement interpolation
local POSITION_LERP_SPEED = 10 -- Higher = faster interpolation
local ROTATION_LERP_SPEED = 8 -- Angular interpolation speed

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

-- Helper: Format money for display (floored to remove decimals)
local function formatMoney(amount: number): string
  return MoneyScaling.formatCurrency(math.floor(amount))
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

-- Helper: Format money rate for display (always per-second, no decimals)
local function formatMoneyRate(rate: number): string
  if rate >= 1000 then
    local kValue = rate / 1000
    if kValue == math.floor(kValue) then
      return string.format("$%dK/s", kValue)
    else
      return string.format("$%.1fK/s", kValue)
    end
  elseif rate >= 10 then
    if rate == math.floor(rate) then
      return string.format("$%d/s", rate)
    else
      return string.format("$%.1f/s", rate)
    end
  else
    if rate == math.floor(rate) then
      return string.format("$%d/s", rate)
    else
      return string.format("$%.1f/s", rate)
    end
  end
end

-- Create money indicator billboard GUI
local function createMoneyIndicator(parent: BasePart, moneyPerSecond: number): BillboardGui
  local billboard = Instance.new("BillboardGui")
  billboard.Name = "MoneyIndicator"
  billboard.Size = UDim2.new(0, 80, 0, 60) -- Slightly taller to fit status text
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

  -- Status text (FULL indicator) - top portion, hidden by default
  local statusText = Instance.new("TextLabel")
  statusText.Name = "StatusText"
  statusText.Size = UDim2.new(1, 0, 0.25, 0)
  statusText.Position = UDim2.new(0, 0, 0, 0)
  statusText.BackgroundTransparency = 1
  statusText.Font = Enum.Font.GothamBold
  statusText.TextSize = 11
  statusText.TextColor3 = Color3.fromRGB(255, 100, 100)
  statusText.Text = "FULL!"
  statusText.Visible = false
  statusText.Parent = bg

  -- Rate text ($/s) - middle portion
  local rateText = Instance.new("TextLabel")
  rateText.Name = "RateText"
  rateText.Size = UDim2.new(1, 0, 0.35, 0)
  rateText.Position = UDim2.new(0, 0, 0.25, 0)
  rateText.BackgroundTransparency = 1
  rateText.Font = Enum.Font.GothamBold
  rateText.TextSize = 12
  rateText.TextColor3 = Color3.fromRGB(255, 220, 100)
  rateText.Text = formatMoneyRate(moneyPerSecond)
  rateText.Parent = bg

  -- Money text (accumulated) - bottom portion
  local moneyText = Instance.new("TextLabel")
  moneyText.Name = "MoneyText"
  moneyText.Size = UDim2.new(1, 0, 0.4, 0)
  moneyText.Position = UDim2.new(0, 0, 0.6, 0)
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

  -- Check if at max capacity
  local wasAtMaxCapacity = state.isAtMaxCapacity
  state.isAtMaxCapacity = state.accumulatedMoney >= state.maxMoneyCapacity

  local moneyText = bg:FindFirstChild("MoneyText") :: TextLabel?
  local statusText = bg:FindFirstChild("StatusText") :: TextLabel?
  local rateText = bg:FindFirstChild("RateText") :: TextLabel?

  if moneyText then
    moneyText.Text = formatMoney(state.accumulatedMoney)

    if state.isAtMaxCapacity then
      -- Gold/amber color when at capacity
      moneyText.TextColor3 = Color3.fromRGB(255, 215, 0)
    else
      -- Scale color based on amount (greener for more money)
      local intensity = math.min(1, state.accumulatedMoney / 1000)
      moneyText.TextColor3 = Color3.fromRGB(100 + intensity * 155, 255, 100)
    end
  end

  -- Show/hide FULL status indicator
  if statusText then
    statusText.Visible = state.isAtMaxCapacity
  end

  -- Update rate text when capacity changes
  if rateText and state.isAtMaxCapacity ~= wasAtMaxCapacity then
    if state.isAtMaxCapacity then
      -- Show paused rate when full
      rateText.Text = "(paused)"
      rateText.TextColor3 = Color3.fromRGB(180, 180, 180)
    else
      -- Restore normal rate display
      rateText.Text = formatMoneyRate(state.moneyPerSecond * state.healthPercent)
      rateText.TextColor3 = Color3.fromRGB(255, 220, 100)
    end
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

-- Apply smooth walking animation with interpolation
-- Uses walk speed from server for proper movement speed
local function applyWalkingAnimation(state: ChickenVisualState, deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  -- Move toward target at walk speed (client-side movement)
  if state.targetPosition then
    local toTarget = state.targetPosition - state.position
    local distance = toTarget.Magnitude

    if distance > 0.1 then
      -- Move at walk speed
      local moveDistance = state.walkSpeed * deltaTime
      if moveDistance >= distance then
        -- Reached target
        state.position = state.targetPosition
      else
        -- Move toward target
        local direction = toTarget.Unit
        state.position = state.position + direction * moveDistance
        -- Update facing direction to match movement
        state.targetFacingDirection = direction
      end
    else
      -- Close enough, snap to target
      state.position = state.targetPosition
    end
  end

  -- Lerp facing direction for smooth rotation
  if state.targetFacingDirection and state.currentFacingDirection then
    local rotLerpFactor = math.min(1, deltaTime * ROTATION_LERP_SPEED)
    state.currentFacingDirection =
      state.currentFacingDirection:Lerp(state.targetFacingDirection, rotLerpFactor)
  elseif state.targetFacingDirection then
    state.currentFacingDirection = state.targetFacingDirection
  end

  -- Add subtle bob while walking
  local bobOffset = math.sin(animationTime * IDLE_BOB_SPEED * 1.5)
    * (currentConfig.idleBobAmount * 0.5)
  local displayPosition = state.position + Vector3.new(0, bobOffset, 0)

  -- Apply position and rotation
  -- Note: Chicken model faces +Z, but CFrame.lookAt faces -Z, so we negate the direction
  if state.currentFacingDirection and state.currentFacingDirection.Magnitude > 0.001 then
    local lookAt = displayPosition - state.currentFacingDirection
    state.model:SetPrimaryPartCFrame(CFrame.lookAt(displayPosition, lookAt))
  else
    state.model:SetPrimaryPartCFrame(CFrame.new(displayPosition))
  end
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
  billboard.Size = UDim2.new(0, 150, 0, 50)
  billboard.StudsOffset = Vector3.new(0, 0, 0)
  billboard.AlwaysOnTop = true
  billboard.Adornee = part
  billboard.Parent = part

  local text = Instance.new("TextLabel")
  text.Name = "AmountText"
  text.Size = UDim2.new(1, 0, 1, 0)
  text.BackgroundTransparency = 1
  text.Font = Enum.Font.GothamBold
  text.TextScaled = false
  text.TextSize = config.isLarge and 28 or 22
  text.TextColor3 = config.isLarge and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(100, 255, 100)
  text.TextStrokeTransparency = 0
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
  isPlaced: boolean?
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

  -- Create money indicator only for placed chickens (random/wandering chickens are not placed)
  local moneyIndicator: BillboardGui? = nil
  local chickenMoneyPerSecond = config.moneyPerSecond or 1
  local chickenIsPlaced = isPlaced == true
  if chickenIsPlaced then
    moneyIndicator = createMoneyIndicator(model.PrimaryPart, chickenMoneyPerSecond)

    -- Add ProximityPrompt for selling (placed chickens only)
    local sellPrice = Store.getChickenValue(chickenType)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "SellPrompt"
    prompt.ObjectText = "Chicken"
    prompt.ActionText = "Sell (" .. MoneyScaling.formatCurrency(sellPrice) .. ")"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.Parent = model.PrimaryPart

    -- Store chickenId in prompt for reference
    prompt:SetAttribute("ChickenId", chickenId)

    -- Handle sell trigger
    prompt.Triggered:Connect(function(playerWhoTriggered: Player)
      if playerWhoTriggered == Players.LocalPlayer and onSellPromptTriggered then
        onSellPromptTriggered(chickenId)
      end
    end)
  else
    -- Add ProximityPrompt for claiming (random/wandering chickens only)
    local claimPrompt = Instance.new("ProximityPrompt")
    claimPrompt.Name = "ClaimPrompt"
    claimPrompt.ObjectText = config.displayName or chickenType
    claimPrompt.ActionText = "Collect"
    claimPrompt.HoldDuration = 0
    claimPrompt.MaxActivationDistance = 10 -- Slightly less than server CLAIM_RANGE to ensure valid claims
    claimPrompt.RequiresLineOfSight = false
    claimPrompt.KeyboardKeyCode = Enum.KeyCode.E
    claimPrompt.Parent = model.PrimaryPart

    -- Store chickenId in prompt for reference
    claimPrompt:SetAttribute("ChickenId", chickenId)

    -- Handle claim trigger
    claimPrompt.Triggered:Connect(function(playerWhoTriggered: Player)
      if playerWhoTriggered == Players.LocalPlayer and onClaimPromptTriggered then
        onClaimPromptTriggered(chickenId)
      end
    end)
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
    maxMoneyCapacity = ChickenConfig.getMaxMoneyCapacityForType(chickenType),
    position = position,
    targetPosition = nil,
    targetFacingDirection = nil,
    currentFacingDirection = nil,
    walkSpeed = 4, -- Default walk speed, updated from server
    isPlaced = chickenIsPlaced,
    healthPercent = 1.0,
    isDamaged = false,
    isAtMaxCapacity = false,
  }

  activeChickens[chickenId] = state

  -- Start update loop if not running
  if not updateConnection then
    updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
      animationTime = animationTime + deltaTime
      for _, chickenState in pairs(activeChickens) do
        if chickenState.currentAnimation == "idle" then
          applyIdleAnimation(chickenState, deltaTime)
        elseif chickenState.currentAnimation == "walking" then
          applyWalkingAnimation(chickenState, deltaTime)
        end
        -- Client-side money accumulation for smooth counter (only for placed chickens)
        -- Apply health multiplier to money generation rate
        -- Stop accumulation if at max capacity
        if chickenState.moneyPerSecond > 0 and chickenState.isPlaced then
          if chickenState.accumulatedMoney < chickenState.maxMoneyCapacity then
            local effectiveMoneyPerSecond = chickenState.moneyPerSecond * chickenState.healthPercent
            local newAmount = chickenState.accumulatedMoney + (effectiveMoneyPerSecond * deltaTime)
            -- Cap at max capacity
            chickenState.accumulatedMoney = math.min(newAmount, chickenState.maxMoneyCapacity)
          end
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

-- Check if a chicken visual is at max capacity
function ChickenVisuals.isAtMaxCapacity(chickenId: string): boolean
  local state = activeChickens[chickenId]
  if state then
    return state.isAtMaxCapacity or false
  end
  return false
end

-- Get the max money capacity for a chicken visual
function ChickenVisuals.getMaxCapacity(chickenId: string): number
  local state = activeChickens[chickenId]
  if state then
    return state.maxMoneyCapacity or 0
  end
  return 0
end

-- Reset accumulated money for a chicken (called after server collection)
function ChickenVisuals.resetAccumulatedMoney(chickenId: string, remainder: number?)
  local state = activeChickens[chickenId]
  if state then
    state.accumulatedMoney = remainder or 0
    state.isAtMaxCapacity = false -- Reset capacity flag after collection
    -- Update the money display immediately
    updateMoneyIndicator(state)

    -- Flash animation to indicate collection
    if state.moneyIndicator then
      local bg = state.moneyIndicator:FindFirstChild("Background")
      if bg then
        local moneyText = bg:FindFirstChild("MoneyText") :: TextLabel?
        if moneyText then
          -- Flash white then return to green
          moneyText.TextColor3 = Color3.fromRGB(255, 255, 255)
          local flashTween = TweenService:Create(
            moneyText,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextColor3 = Color3.fromRGB(100, 255, 100) }
          )
          flashTween:Play()
        end
      end
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

-- Move chicken to a new position (for placed chickens)
function ChickenVisuals.moveToPosition(chickenId: string, position: Vector3): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  state.position = position
  state.model:SetPrimaryPartCFrame(CFrame.new(position))
  return true
end

-- Update position with facing direction and animation state (for wandering chickens)
-- Now receives target position (where chicken is walking to) and walk speed for client-side movement
-- The client handles smooth movement toward the target at the specified walk speed
function ChickenVisuals.updatePosition(
  chickenId: string,
  currentPosition: Vector3,
  targetPosition: Vector3?,
  facingDirection: Vector3,
  walkSpeed: number?,
  isIdle: boolean
): boolean
  local state = activeChickens[chickenId]
  if not state or not state.model then
    return false
  end

  -- Update walk speed from server
  if walkSpeed then
    state.walkSpeed = walkSpeed
  end

  -- Store target position for smooth client-side movement
  -- When walking, client moves toward target at walk speed
  -- When idle, snap to current position
  if isIdle then
    state.position = currentPosition
    state.targetPosition = currentPosition
    state.currentAnimation = "idle"
  else
    -- Sync position with server to prevent drift
    -- Only snap if we're too far off (more than 2 studs difference)
    local drift = (state.position - currentPosition).Magnitude
    if drift > 2 then
      state.position = currentPosition
    end
    -- Use target position if provided, otherwise fall back to current position
    state.targetPosition = targetPosition or currentPosition
    state.currentAnimation = "walking"
  end

  state.targetFacingDirection = facingDirection

  -- Initialize current facing direction if not set
  if not state.currentFacingDirection then
    state.currentFacingDirection = facingDirection
  end

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

-- Set callback for when sell proximity prompt is triggered
function ChickenVisuals.setOnSellPromptTriggered(callback: (chickenId: string) -> ())
  onSellPromptTriggered = callback
end

-- Set callback for when claim proximity prompt is triggered (random chickens)
function ChickenVisuals.setOnClaimPromptTriggered(callback: (chickenId: string) -> ())
  onClaimPromptTriggered = callback
end

-- Update sell prompt price for a chicken (call when accumulated money changes significantly)
function ChickenVisuals.updateSellPromptPrice(chickenId: string)
  local state = activeChickens[chickenId]
  if not state or not state.model or not state.isPlaced then
    return
  end

  local primaryPart = state.model.PrimaryPart
  if not primaryPart then
    return
  end

  local prompt = primaryPart:FindFirstChild("SellPrompt") :: ProximityPrompt?
  if prompt then
    local basePrice = Store.getChickenValue(state.chickenType)
    local totalValue = basePrice + math.floor(state.accumulatedMoney)
    prompt.ActionText = "Sell (" .. MoneyScaling.formatCurrency(totalValue) .. ")"
  end
end

-- Note: showTargetIndicator, clearAllTargetIndicators, and updateTargetIndicator
-- have been removed as part of the UI cleanup (remove-predator-target-bar feature)

return ChickenVisuals
