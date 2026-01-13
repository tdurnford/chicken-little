--[[
	EggVisuals Module
	Manages egg model creation, hatch animations, and visual effects
	including rarity-based variations, shake anticipation, and particle effects.
]]

local EggVisuals = {}

-- Services
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Get shared modules path
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))

-- Type definitions
export type AnimationState = "idle" | "shaking" | "hatching" | "hatched"

export type VisualConfig = {
  baseSize: Vector3,
  shakeIntensity: number,
  shakeSpeed: number,
  hatchDuration: number,
  particleDuration: number,
}

export type EggVisualState = {
  model: Model?,
  eggType: string,
  rarity: string,
  currentAnimation: AnimationState,
  animationConnection: RBXScriptConnection?,
  position: Vector3,
  spotIndex: number?,
  shakeProgress: number,
}

export type HatchEffectConfig = {
  position: Vector3,
  rarity: string,
  chickenType: string,
}

-- Rarity colors for visual distinction
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(245, 235, 220),
  Uncommon = Color3.fromRGB(180, 230, 180),
  Rare = Color3.fromRGB(150, 200, 255),
  Epic = Color3.fromRGB(200, 150, 255),
  Legendary = Color3.fromRGB(255, 215, 100),
  Mythic = Color3.fromRGB(255, 150, 200),
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

-- Egg scale per rarity (rarer = slightly larger)
local RARITY_SCALE_MULTIPLIER: { [string]: number } = {
  Common = 1.0,
  Uncommon = 1.05,
  Rare = 1.1,
  Epic = 1.15,
  Legendary = 1.2,
  Mythic = 1.3,
}

-- Particle counts for hatch effects by rarity
local RARITY_PARTICLE_COUNT: { [string]: number } = {
  Common = 5,
  Uncommon = 10,
  Rare = 20,
  Epic = 35,
  Legendary = 50,
  Mythic = 75,
}

-- Default visual configuration
local DEFAULT_VISUAL_CONFIG: VisualConfig = {
  baseSize = Vector3.new(1.2, 1.6, 1.2),
  shakeIntensity = 0.1,
  shakeSpeed = 15,
  hatchDuration = 2.0,
  particleDuration = 1.5,
}

-- Animation timing
local SHAKE_PHASE_DURATION = 0.5
local SHAKE_PHASES = 3
local CRACK_DURATION = 0.3
local EXPLOSION_DURATION = 0.5
local SHELL_FADE_DURATION = 0.8

-- Module state
local activeEggs: { [string]: EggVisualState } = {}
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

-- Helper: Get particle count for rarity
local function getParticleCount(rarity: string): number
  return RARITY_PARTICLE_COUNT[rarity] or 5
end

-- Create a placeholder egg model
local function createPlaceholderModel(eggType: string, rarity: string): Model
  local model = Instance.new("Model")
  model.Name = eggType

  local scale = getScaleMultiplier(rarity)
  local baseSize = currentConfig.baseSize * scale

  -- Create main egg body (ellipsoid using Part)
  local body = Instance.new("Part")
  body.Name = "Body"
  body.Shape = Enum.PartType.Ball
  body.Size = baseSize
  body.Color = getRarityColor(rarity)
  body.Material = Enum.Material.SmoothPlastic
  body.Anchored = true
  body.CanCollide = false
  body.CastShadow = true
  body.Parent = model

  -- Add speckles for visual interest (small parts)
  local speckleColor = Color3.new(
    math.max(0, getRarityColor(rarity).R - 0.1),
    math.max(0, getRarityColor(rarity).G - 0.1),
    math.max(0, getRarityColor(rarity).B - 0.1)
  )

  for i = 1, 5 do
    local speckle = Instance.new("Part")
    speckle.Name = "Speckle" .. i
    speckle.Shape = Enum.PartType.Ball
    speckle.Size = Vector3.new(0.1, 0.1, 0.1) * scale
    speckle.Color = speckleColor
    speckle.Material = Enum.Material.SmoothPlastic
    speckle.Anchored = true
    speckle.CanCollide = false
    speckle.CastShadow = false

    -- Random position on egg surface
    local angle = math.random() * math.pi * 2
    local height = (math.random() - 0.5) * baseSize.Y * 0.6
    local radius = baseSize.X * 0.4 * math.cos(height / baseSize.Y * math.pi)
    speckle.Position = body.Position
      + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
    speckle.Parent = model
  end

  -- Add glow effect for rare+ eggs
  local glowIntensity = getGlowIntensity(rarity)
  if glowIntensity > 0 then
    local pointLight = Instance.new("PointLight")
    pointLight.Name = "RarityGlow"
    pointLight.Color = getRarityColor(rarity)
    pointLight.Brightness = glowIntensity * 1.5
    pointLight.Range = 3 + (glowIntensity * 3)
    pointLight.Shadows = false
    pointLight.Parent = body

    -- Add subtle particle effect for Legendary+ eggs
    if rarity == "Legendary" or rarity == "Mythic" then
      local particles = Instance.new("ParticleEmitter")
      particles.Name = "RarityParticles"
      particles.Color = ColorSequence.new(getRarityColor(rarity))
      particles.Size = NumberSequence.new(0.15, 0)
      particles.Transparency = NumberSequence.new(0.3, 1)
      particles.Lifetime = NumberRange.new(0.8, 1.5)
      particles.Rate = 3 + (glowIntensity * 5)
      particles.Speed = NumberRange.new(0.5, 1)
      particles.SpreadAngle = Vector2.new(180, 180)
      particles.Parent = body
    end
  end

  -- Set PrimaryPart for positioning
  model.PrimaryPart = body

  return model
end

-- Create shell fragment for hatch effect
local function createShellFragment(position: Vector3, color: Color3, scale: number): Part
  local fragment = Instance.new("Part")
  fragment.Name = "ShellFragment"
  fragment.Size = Vector3.new(0.3, 0.2, 0.1) * scale
  fragment.Color = color
  fragment.Material = Enum.Material.SmoothPlastic
  fragment.Anchored = false
  fragment.CanCollide = true
  fragment.Position = position

  -- Add random velocity
  local velocity = Instance.new("BodyVelocity")
  velocity.Velocity =
    Vector3.new((math.random() - 0.5) * 10, math.random() * 8 + 4, (math.random() - 0.5) * 10)
  velocity.MaxForce = Vector3.new(1000, 1000, 1000)
  velocity.Parent = fragment

  -- Add spin
  local angularVelocity = Instance.new("BodyAngularVelocity")
  angularVelocity.AngularVelocity =
    Vector3.new((math.random() - 0.5) * 20, (math.random() - 0.5) * 20, (math.random() - 0.5) * 20)
  angularVelocity.MaxTorque = Vector3.new(1000, 1000, 1000)
  angularVelocity.Parent = fragment

  -- Remove velocity after short time so gravity takes over
  task.delay(0.1, function()
    if velocity and velocity.Parent then
      velocity:Destroy()
    end
    if angularVelocity and angularVelocity.Parent then
      angularVelocity:Destroy()
    end
  end)

  return fragment
end

-- Create hatch particle burst
local function createHatchParticles(position: Vector3, rarity: string): Part
  local emitterPart = Instance.new("Part")
  emitterPart.Name = "HatchParticleEmitter"
  emitterPart.Size = Vector3.new(0.1, 0.1, 0.1)
  emitterPart.Transparency = 1
  emitterPart.Anchored = true
  emitterPart.CanCollide = false
  emitterPart.Position = position
  emitterPart.Parent = workspace

  local color = getRarityColor(rarity)
  local particleCount = getParticleCount(rarity)

  -- Main burst particles
  local burst = Instance.new("ParticleEmitter")
  burst.Name = "HatchBurst"
  burst.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, color),
    ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
  })
  burst.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.5, 0.3),
    NumberSequenceKeypoint.new(1, 0),
  })
  burst.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),
    NumberSequenceKeypoint.new(0.7, 0.3),
    NumberSequenceKeypoint.new(1, 1),
  })
  burst.Lifetime = NumberRange.new(0.5, 1.0)
  burst.Speed = NumberRange.new(5, 15)
  burst.SpreadAngle = Vector2.new(180, 180)
  burst.Acceleration = Vector3.new(0, -10, 0)
  burst.Enabled = false
  burst.Parent = emitterPart

  -- Emit burst
  burst:Emit(particleCount)

  -- Star/sparkle effect for rare+ eggs
  if getGlowIntensity(rarity) > 0.2 then
    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Name = "HatchSparkles"
    sparkles.Color = ColorSequence.new(Color3.new(1, 1, 0.8))
    sparkles.Size = NumberSequence.new(0.2, 0)
    sparkles.Transparency = NumberSequence.new(0, 1)
    sparkles.Lifetime = NumberRange.new(0.8, 1.5)
    sparkles.Speed = NumberRange.new(2, 5)
    sparkles.SpreadAngle = Vector2.new(180, 180)
    sparkles.LightEmission = 1
    sparkles.Enabled = false
    sparkles.Parent = emitterPart

    sparkles:Emit(math.floor(particleCount * 0.5))
  end

  -- Cleanup after particles fade
  task.delay(currentConfig.particleDuration + 0.5, function()
    if emitterPart and emitterPart.Parent then
      emitterPart:Destroy()
    end
  end)

  return emitterPart
end

-- Apply idle animation (subtle floating)
local function applyIdleAnimation(state: EggVisualState, _deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  local bobOffset = math.sin(animationTime * 2) * 0.05
  local targetPosition = state.position + Vector3.new(0, bobOffset, 0)

  state.model:SetPrimaryPartCFrame(CFrame.new(targetPosition))
end

-- Apply shake animation
local function applyShakeAnimation(state: EggVisualState, _deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  local shakeOffset = math.sin(animationTime * currentConfig.shakeSpeed)
    * currentConfig.shakeIntensity
  local shakeAngle = math.sin(animationTime * currentConfig.shakeSpeed * 1.3) * 0.1

  local targetCFrame = CFrame.new(state.position + Vector3.new(shakeOffset, 0, 0))
    * CFrame.Angles(0, 0, shakeAngle)

  state.model:SetPrimaryPartCFrame(targetCFrame)
end

-- Play anticipation shake animation
function EggVisuals.playShakeAnimation(eggId: string): boolean
  local state = activeEggs[eggId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "shaking"
  state.shakeProgress = 0

  -- Shake in phases with increasing intensity
  local startTime = tick()
  local totalDuration = SHAKE_PHASE_DURATION * SHAKE_PHASES

  local connection
  connection = RunService.Heartbeat:Connect(function()
    local elapsed = tick() - startTime
    if elapsed >= totalDuration then
      connection:Disconnect()
      -- Reset to center position
      if state.model and state.model.PrimaryPart then
        state.model:SetPrimaryPartCFrame(CFrame.new(state.position))
      end
      state.currentAnimation = "idle"
      return
    end

    state.shakeProgress = elapsed / totalDuration

    -- Increasing intensity through phases
    local phase = math.floor(elapsed / SHAKE_PHASE_DURATION) + 1
    local phaseProgress = (elapsed % SHAKE_PHASE_DURATION) / SHAKE_PHASE_DURATION
    local intensity = currentConfig.shakeIntensity * (phase * 0.5)

    local shakeX = math.sin(elapsed * currentConfig.shakeSpeed * phase) * intensity
    local shakeZ = math.cos(elapsed * currentConfig.shakeSpeed * phase * 0.8) * intensity * 0.5
    local tiltAngle = math.sin(elapsed * currentConfig.shakeSpeed * 1.3) * 0.15 * phase

    if state.model and state.model.PrimaryPart then
      local targetCFrame = CFrame.new(state.position + Vector3.new(shakeX, 0, shakeZ))
        * CFrame.Angles(tiltAngle * 0.5, 0, tiltAngle)
      state.model:SetPrimaryPartCFrame(targetCFrame)
    end
  end)

  return true
end

-- Play hatch animation with particle effects
function EggVisuals.playHatchAnimation(eggId: string, chickenType: string): boolean
  local state = activeEggs[eggId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "hatching"

  local body = state.model.PrimaryPart
  local originalSize = body.Size
  local color = getRarityColor(state.rarity)
  local scale = getScaleMultiplier(state.rarity)

  -- Phase 1: Final intense shake
  local shakeStartTime = tick()
  local shakeDuration = SHAKE_PHASE_DURATION

  local shakeConnection
  shakeConnection = RunService.Heartbeat:Connect(function()
    local elapsed = tick() - shakeStartTime
    if elapsed >= shakeDuration then
      shakeConnection:Disconnect()

      -- Phase 2: Crack and expand
      local expandTween = TweenService:Create(
        body,
        TweenInfo.new(CRACK_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
          Size = originalSize * 1.3,
        }
      )

      expandTween:Play()
      expandTween.Completed:Connect(function()
        -- Phase 3: Explosion - spawn shell fragments and particles
        local fragmentCount = 6 + math.floor(getGlowIntensity(state.rarity) * 6)
        for _ = 1, fragmentCount do
          local fragment = createShellFragment(state.position, color, scale)
          fragment.Parent = workspace

          -- Fade and destroy fragments
          task.delay(SHELL_FADE_DURATION, function()
            if fragment and fragment.Parent then
              local fadeTween =
                TweenService:Create(fragment, TweenInfo.new(0.3), { Transparency = 1 })
              fadeTween:Play()
              fadeTween.Completed:Connect(function()
                if fragment and fragment.Parent then
                  fragment:Destroy()
                end
              end)
            end
          end)
        end

        -- Create particle burst
        createHatchParticles(state.position, state.rarity)

        -- Fade out egg model
        local fadeTween = TweenService:Create(
          body,
          TweenInfo.new(EXPLOSION_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
          { Transparency = 1, Size = originalSize * 0.1 }
        )

        -- Fade speckles too
        for _, child in ipairs(state.model:GetChildren()) do
          if child:IsA("BasePart") and child.Name:match("Speckle") then
            TweenService:Create(child, TweenInfo.new(EXPLOSION_DURATION), { Transparency = 1 })
              :Play()
          end
        end

        fadeTween:Play()
        fadeTween.Completed:Connect(function()
          state.currentAnimation = "hatched"
        end)
      end)

      return
    end

    -- Intense final shake
    local intensity = currentConfig.shakeIntensity * 3 * (1 + elapsed / shakeDuration)
    local shakeX = math.sin(elapsed * 30) * intensity
    local shakeZ = math.cos(elapsed * 25) * intensity * 0.7
    local tiltAngle = math.sin(elapsed * 35) * 0.2

    if state.model and state.model.PrimaryPart then
      local targetCFrame = CFrame.new(state.position + Vector3.new(shakeX, 0, shakeZ))
        * CFrame.Angles(tiltAngle * 0.3, 0, tiltAngle)
      state.model:SetPrimaryPartCFrame(targetCFrame)
    end
  end)

  return true
end

-- Create an egg visual at a position
function EggVisuals.create(
  eggId: string,
  eggType: string,
  position: Vector3,
  spotIndex: number?
): EggVisualState?
  -- Get egg config for rarity
  local config = EggConfig.get(eggType)
  if not config then
    return nil
  end

  -- Remove existing egg with same ID
  if activeEggs[eggId] then
    EggVisuals.destroy(eggId)
  end

  -- Create model
  local model = createPlaceholderModel(eggType, config.rarity)
  model:SetPrimaryPartCFrame(CFrame.new(position))
  model.Parent = workspace

  -- Create state
  local state: EggVisualState = {
    model = model,
    eggType = eggType,
    rarity = config.rarity,
    currentAnimation = "idle",
    animationConnection = nil,
    position = position,
    spotIndex = spotIndex,
    shakeProgress = 0,
  }

  activeEggs[eggId] = state

  -- Start update loop if not running
  if not updateConnection then
    updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
      animationTime = animationTime + deltaTime
      for _, eggState in pairs(activeEggs) do
        if eggState.currentAnimation == "idle" then
          applyIdleAnimation(eggState, deltaTime)
        elseif eggState.currentAnimation == "shaking" then
          applyShakeAnimation(eggState, deltaTime)
        end
      end
    end)
  end

  return state
end

-- Destroy an egg visual
function EggVisuals.destroy(eggId: string): boolean
  local state = activeEggs[eggId]
  if not state then
    return false
  end

  if state.animationConnection then
    state.animationConnection:Disconnect()
  end

  if state.model then
    state.model:Destroy()
  end

  activeEggs[eggId] = nil

  -- Stop update loop if no more eggs
  if next(activeEggs) == nil and updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  return true
end

-- Get egg visual state
function EggVisuals.get(eggId: string): EggVisualState?
  return activeEggs[eggId]
end

-- Get all active egg visuals
function EggVisuals.getAll(): { [string]: EggVisualState }
  return activeEggs
end

-- Get count of active visuals
function EggVisuals.getActiveCount(): number
  local count = 0
  for _ in pairs(activeEggs) do
    count = count + 1
  end
  return count
end

-- Set position for an egg
function EggVisuals.setPosition(eggId: string, position: Vector3): boolean
  local state = activeEggs[eggId]
  if not state or not state.model then
    return false
  end

  state.position = position
  state.model:SetPrimaryPartCFrame(CFrame.new(position))
  return true
end

-- Configure visual settings
function EggVisuals.configure(config: VisualConfig)
  currentConfig = config
end

-- Get current configuration
function EggVisuals.getConfig(): VisualConfig
  return currentConfig
end

-- Get rarity color for external use
function EggVisuals.getRarityColor(rarity: string): Color3
  return getRarityColor(rarity)
end

-- Get all rarity colors
function EggVisuals.getRarityColors(): { [string]: Color3 }
  return RARITY_COLORS
end

-- Cleanup all egg visuals
function EggVisuals.cleanup()
  for eggId in pairs(activeEggs) do
    EggVisuals.destroy(eggId)
  end

  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  animationTime = 0
end

-- Get summary for debugging
function EggVisuals.getSummary(): { activeCount: number, animationTime: number }
  return {
    activeCount = EggVisuals.getActiveCount(),
    animationTime = animationTime,
  }
end

return EggVisuals
