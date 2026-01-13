--[[
	PredatorVisuals Module
	Manages predator model creation, animations (walk, attack, defeated, trapped),
	and visual effects including threat level-based variations.
]]

local PredatorVisuals = {}

-- Services
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Get shared modules path
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Type definitions
export type AnimationState = "idle" | "walking" | "attacking" | "defeated" | "trapped"

export type VisualConfig = {
  baseSize: Vector3,
  walkSpeed: number,
  walkBobAmount: number,
  attackDuration: number,
  defeatedDuration: number,
  trappedBounceAmount: number,
}

export type PredatorVisualState = {
  model: Model?,
  predatorType: string,
  threatLevel: string,
  currentAnimation: AnimationState,
  animationConnection: RBXScriptConnection?,
  position: Vector3,
  targetPosition: Vector3?,
  walkProgress: number,
  isTrapped: boolean,
}

export type AttackEffectConfig = {
  position: Vector3,
  targetPosition: Vector3,
  predatorType: string,
}

-- Threat level colors for visual distinction
local THREAT_COLORS: { [string]: Color3 } = {
  Minor = Color3.fromRGB(150, 130, 100),
  Moderate = Color3.fromRGB(180, 150, 80),
  Dangerous = Color3.fromRGB(200, 100, 50),
  Severe = Color3.fromRGB(180, 50, 50),
  Deadly = Color3.fromRGB(120, 30, 80),
  Catastrophic = Color3.fromRGB(80, 20, 120),
}

-- Eye colors become more menacing with threat level
local THREAT_EYE_COLORS: { [string]: Color3 } = {
  Minor = Color3.fromRGB(80, 80, 80),
  Moderate = Color3.fromRGB(200, 180, 50),
  Dangerous = Color3.fromRGB(255, 150, 0),
  Severe = Color3.fromRGB(255, 80, 0),
  Deadly = Color3.fromRGB(255, 50, 50),
  Catastrophic = Color3.fromRGB(255, 0, 0),
}

-- Threat level glow intensities
local THREAT_GLOW_INTENSITY: { [string]: number } = {
  Minor = 0,
  Moderate = 0.1,
  Dangerous = 0.3,
  Severe = 0.5,
  Deadly = 0.7,
  Catastrophic = 1.0,
}

-- Scale multipliers by threat level (more dangerous = larger)
local THREAT_SCALE_MULTIPLIER: { [string]: number } = {
  Minor = 0.8,
  Moderate = 1.0,
  Dangerous = 1.2,
  Severe = 1.4,
  Deadly = 1.7,
  Catastrophic = 2.2,
}

-- Default visual configuration
local DEFAULT_VISUAL_CONFIG: VisualConfig = {
  baseSize = Vector3.new(2, 1.5, 3),
  walkSpeed = 4,
  walkBobAmount = 0.15,
  attackDuration = 0.8,
  defeatedDuration = 1.5,
  trappedBounceAmount = 0.1,
}

-- Animation timing
local WALK_BOB_SPEED = 8.0
local ATTACK_LUNGE_DISTANCE = 2.0
local ATTACK_LUNGE_DURATION = 0.3
local DEFEATED_SPIN_SPEED = 5.0
local DEFEATED_SHRINK_DURATION = 1.0
local TRAPPED_SHAKE_SPEED = 12.0
local TRAPPED_SHAKE_INTENSITY = 0.08

-- Module state
local activePredators: { [string]: PredatorVisualState } = {}
local currentConfig: VisualConfig = DEFAULT_VISUAL_CONFIG
local updateConnection: RBXScriptConnection? = nil
local animationTime: number = 0

-- Helper: Get threat color
local function getThreatColor(threatLevel: string): Color3
  return THREAT_COLORS[threatLevel] or THREAT_COLORS.Minor
end

-- Helper: Get eye color
local function getEyeColor(threatLevel: string): Color3
  return THREAT_EYE_COLORS[threatLevel] or THREAT_EYE_COLORS.Minor
end

-- Helper: Get threat glow intensity
local function getGlowIntensity(threatLevel: string): number
  return THREAT_GLOW_INTENSITY[threatLevel] or 0
end

-- Helper: Get threat scale multiplier
local function getScaleMultiplier(threatLevel: string): number
  return THREAT_SCALE_MULTIPLIER[threatLevel] or 1.0
end

-- Create a placeholder predator model (to be replaced with actual assets)
local function createPlaceholderModel(predatorType: string, threatLevel: string): Model
  local model = Instance.new("Model")
  model.Name = predatorType

  local scale = getScaleMultiplier(threatLevel)
  local baseSize = currentConfig.baseSize * scale

  -- Create body part (elongated for predator shape)
  local body = Instance.new("Part")
  body.Name = "Body"
  body.Size = baseSize
  body.Color = getThreatColor(threatLevel)
  body.Material = Enum.Material.SmoothPlastic
  body.Anchored = true
  body.CanCollide = false
  body.CastShadow = true
  body.Parent = model

  -- Create head (sphere at front)
  local head = Instance.new("Part")
  head.Name = "Head"
  head.Shape = Enum.PartType.Ball
  head.Size = Vector3.new(baseSize.Y * 0.8, baseSize.Y * 0.8, baseSize.Y * 0.8)
  head.Color = getThreatColor(threatLevel)
  head.Material = Enum.Material.SmoothPlastic
  head.Anchored = true
  head.CanCollide = false
  head.CastShadow = true
  head.Position = body.Position + Vector3.new(0, baseSize.Y * 0.2, baseSize.Z * 0.5)
  head.Parent = model

  -- Create eyes (menacing glow)
  local eyeSize = 0.15 * scale
  local eyeSpacing = 0.25 * scale
  local eyeForward = 0.35 * scale

  local leftEye = Instance.new("Part")
  leftEye.Name = "LeftEye"
  leftEye.Shape = Enum.PartType.Ball
  leftEye.Size = Vector3.new(eyeSize, eyeSize, eyeSize)
  leftEye.Color = getEyeColor(threatLevel)
  leftEye.Material = Enum.Material.Neon
  leftEye.Anchored = true
  leftEye.CanCollide = false
  leftEye.Position = head.Position + Vector3.new(-eyeSpacing, eyeSize, eyeForward)
  leftEye.Parent = model

  local rightEye = Instance.new("Part")
  rightEye.Name = "RightEye"
  rightEye.Shape = Enum.PartType.Ball
  rightEye.Size = Vector3.new(eyeSize, eyeSize, eyeSize)
  rightEye.Color = getEyeColor(threatLevel)
  rightEye.Material = Enum.Material.Neon
  rightEye.Anchored = true
  rightEye.CanCollide = false
  rightEye.Position = head.Position + Vector3.new(eyeSpacing, eyeSize, eyeForward)
  rightEye.Parent = model

  -- Create legs (4 legs for quadruped)
  local legSize = Vector3.new(0.2, baseSize.Y * 0.6, 0.2) * scale
  local legOffsets = {
    Vector3.new(-baseSize.X * 0.3, -baseSize.Y * 0.5, baseSize.Z * 0.25),
    Vector3.new(baseSize.X * 0.3, -baseSize.Y * 0.5, baseSize.Z * 0.25),
    Vector3.new(-baseSize.X * 0.3, -baseSize.Y * 0.5, -baseSize.Z * 0.25),
    Vector3.new(baseSize.X * 0.3, -baseSize.Y * 0.5, -baseSize.Z * 0.25),
  }

  for i, offset in ipairs(legOffsets) do
    local leg = Instance.new("Part")
    leg.Name = "Leg" .. i
    leg.Size = legSize
    leg.Color = getThreatColor(threatLevel)
    leg.Material = Enum.Material.SmoothPlastic
    leg.Anchored = true
    leg.CanCollide = false
    leg.CastShadow = true
    leg.Position = body.Position + offset
    leg.Parent = model
  end

  -- Create tail
  local tail = Instance.new("Part")
  tail.Name = "Tail"
  tail.Size = Vector3.new(0.15, 0.15, baseSize.Z * 0.5) * scale
  tail.Color = getThreatColor(threatLevel)
  tail.Material = Enum.Material.SmoothPlastic
  tail.Anchored = true
  tail.CanCollide = false
  tail.Position = body.Position + Vector3.new(0, baseSize.Y * 0.2, -baseSize.Z * 0.6)
  tail.Parent = model

  -- Add glow effect for dangerous+ predators
  local glowIntensity = getGlowIntensity(threatLevel)
  if glowIntensity > 0 then
    -- Eye glow
    local leftEyeGlow = Instance.new("PointLight")
    leftEyeGlow.Name = "EyeGlow"
    leftEyeGlow.Color = getEyeColor(threatLevel)
    leftEyeGlow.Brightness = glowIntensity * 2
    leftEyeGlow.Range = 2 + (glowIntensity * 3)
    leftEyeGlow.Shadows = false
    leftEyeGlow.Parent = leftEye

    local rightEyeGlow = Instance.new("PointLight")
    rightEyeGlow.Name = "EyeGlow"
    rightEyeGlow.Color = getEyeColor(threatLevel)
    rightEyeGlow.Brightness = glowIntensity * 2
    rightEyeGlow.Range = 2 + (glowIntensity * 3)
    rightEyeGlow.Shadows = false
    rightEyeGlow.Parent = rightEye

    -- Add particle effect for Deadly+ predators
    if threatLevel == "Deadly" or threatLevel == "Catastrophic" then
      local particles = Instance.new("ParticleEmitter")
      particles.Name = "ThreatParticles"
      particles.Color = ColorSequence.new(getEyeColor(threatLevel))
      particles.Size = NumberSequence.new(0.2, 0)
      particles.Transparency = NumberSequence.new(0.3, 1)
      particles.Lifetime = NumberRange.new(0.5, 1)
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

-- Create trap visual overlay
local function createTrappedOverlay(model: Model, threatLevel: string)
  local body = model.PrimaryPart
  if not body then
    return
  end

  -- Create cage/net visual
  local cage = Instance.new("Part")
  cage.Name = "TrapCage"
  cage.Size = body.Size * 1.3
  cage.Transparency = 0.7
  cage.Color = Color3.fromRGB(100, 80, 60)
  cage.Material = Enum.Material.WoodPlanks
  cage.Anchored = true
  cage.CanCollide = false
  cage.Position = body.Position
  cage.Parent = model

  -- Add mesh for cage look
  local mesh = Instance.new("SpecialMesh")
  mesh.MeshType = Enum.MeshType.Sphere
  mesh.Scale = Vector3.new(1, 1, 1)
  mesh.Parent = cage
end

-- Remove trap visual overlay
local function removeTrappedOverlay(model: Model)
  local cage = model:FindFirstChild("TrapCage")
  if cage then
    cage:Destroy()
  end
end

-- Apply walking animation
local function applyWalkAnimation(state: PredatorVisualState, deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  -- Bob up and down while walking
  local bobOffset = math.sin(animationTime * WALK_BOB_SPEED) * currentConfig.walkBobAmount
  local targetPosition = state.position + Vector3.new(0, bobOffset, 0)

  -- Move legs alternately
  for i = 1, 4 do
    local leg = state.model:FindFirstChild("Leg" .. i)
    if leg and leg:IsA("BasePart") then
      local legPhase = (i % 2 == 0) and 0 or math.pi
      local legBob = math.sin(animationTime * WALK_BOB_SPEED + legPhase) * 0.1
      local basePos = state.model.PrimaryPart.Position
      local scale = getScaleMultiplier(state.threatLevel)
      local baseSize = currentConfig.baseSize * scale
      local offsets = {
        Vector3.new(-baseSize.X * 0.3, -baseSize.Y * 0.5 + legBob, baseSize.Z * 0.25),
        Vector3.new(baseSize.X * 0.3, -baseSize.Y * 0.5 + legBob, baseSize.Z * 0.25),
        Vector3.new(-baseSize.X * 0.3, -baseSize.Y * 0.5 - legBob, -baseSize.Z * 0.25),
        Vector3.new(baseSize.X * 0.3, -baseSize.Y * 0.5 - legBob, -baseSize.Z * 0.25),
      }
      leg.Position = basePos + offsets[i]
    end
  end

  state.model:SetPrimaryPartCFrame(CFrame.new(targetPosition))
end

-- Apply idle animation (subtle breathing)
local function applyIdleAnimation(state: PredatorVisualState, _deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  local breathOffset = math.sin(animationTime * 2) * 0.03
  local targetPosition = state.position + Vector3.new(0, breathOffset, 0)

  state.model:SetPrimaryPartCFrame(CFrame.new(targetPosition))
end

-- Apply trapped animation (struggling)
local function applyTrappedAnimation(state: PredatorVisualState, _deltaTime: number)
  if not state.model or not state.model.PrimaryPart then
    return
  end

  local shakeX = math.sin(animationTime * TRAPPED_SHAKE_SPEED) * TRAPPED_SHAKE_INTENSITY
  local shakeZ = math.cos(animationTime * TRAPPED_SHAKE_SPEED * 0.8) * TRAPPED_SHAKE_INTENSITY * 0.5
  local tiltAngle = math.sin(animationTime * TRAPPED_SHAKE_SPEED * 1.2) * 0.1

  local targetCFrame = CFrame.new(state.position + Vector3.new(shakeX, 0, shakeZ))
    * CFrame.Angles(0, 0, tiltAngle)

  state.model:SetPrimaryPartCFrame(targetCFrame)
end

-- Play attack animation (lunge forward)
function PredatorVisuals.playAttackAnimation(predatorId: string, targetPos: Vector3?): boolean
  local state = activePredators[predatorId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "attacking"

  local body = state.model.PrimaryPart
  local startPos = state.position
  local direction = Vector3.new(0, 0, 1)
  if targetPos then
    direction = (targetPos - startPos).Unit
  end
  local lungePos = startPos + direction * ATTACK_LUNGE_DISTANCE

  -- Lunge forward
  local lungeTween = TweenService:Create(
    body,
    TweenInfo.new(ATTACK_LUNGE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { CFrame = CFrame.new(lungePos) * CFrame.Angles(math.rad(-15), 0, 0) }
  )

  -- Return to position
  local returnTween = TweenService:Create(
    body,
    TweenInfo.new(ATTACK_LUNGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { CFrame = CFrame.new(startPos) }
  )

  lungeTween:Play()
  lungeTween.Completed:Connect(function()
    returnTween:Play()
    returnTween.Completed:Connect(function()
      state.currentAnimation = "idle"
    end)
  end)

  return true
end

-- Play defeated animation (spin and shrink)
function PredatorVisuals.playDefeatedAnimation(predatorId: string): boolean
  local state = activePredators[predatorId]
  if not state or not state.model or not state.model.PrimaryPart then
    return false
  end

  state.currentAnimation = "defeated"

  local body = state.model.PrimaryPart
  local startTime = tick()

  local connection
  connection = RunService.Heartbeat:Connect(function()
    local elapsed = tick() - startTime
    if elapsed >= DEFEATED_SHRINK_DURATION then
      connection:Disconnect()
      -- Destroy after animation
      PredatorVisuals.destroy(predatorId)
      return
    end

    local progress = elapsed / DEFEATED_SHRINK_DURATION
    local spinAngle = progress * math.pi * 2 * DEFEATED_SPIN_SPEED
    local shrinkScale = 1 - progress
    local riseHeight = progress * 2

    if state.model and state.model.PrimaryPart then
      local newCFrame = CFrame.new(state.position + Vector3.new(0, riseHeight, 0))
        * CFrame.Angles(0, spinAngle, progress * math.pi * 0.5)

      state.model:SetPrimaryPartCFrame(newCFrame)

      -- Shrink all parts
      for _, child in ipairs(state.model:GetChildren()) do
        if child:IsA("BasePart") then
          child.Transparency = progress
        end
      end
    end
  end)

  return true
end

-- Play trapped animation (enter trapped state)
function PredatorVisuals.playTrappedAnimation(predatorId: string): boolean
  local state = activePredators[predatorId]
  if not state or not state.model then
    return false
  end

  state.currentAnimation = "trapped"
  state.isTrapped = true

  -- Add visual trap overlay
  createTrappedOverlay(state.model, state.threatLevel)

  return true
end

-- Create a predator visual at a position
function PredatorVisuals.create(
  predatorId: string,
  predatorType: string,
  threatLevel: string,
  position: Vector3
): PredatorVisualState?
  -- Get predator config
  local config = PredatorConfig.get(predatorType)
  -- Use provided threatLevel or fall back to config
  local actualThreatLevel = threatLevel or (config and config.threatLevel) or "Minor"

  -- Remove existing predator with same ID
  if activePredators[predatorId] then
    PredatorVisuals.destroy(predatorId)
  end

  -- Create model
  local model = createPlaceholderModel(predatorType, actualThreatLevel)
  model:SetPrimaryPartCFrame(CFrame.new(position))
  model.Parent = workspace

  -- Create state
  local state: PredatorVisualState = {
    model = model,
    predatorType = predatorType,
    threatLevel = actualThreatLevel,
    currentAnimation = "idle",
    animationConnection = nil,
    position = position,
    targetPosition = nil,
    walkProgress = 0,
    isTrapped = false,
  }

  activePredators[predatorId] = state

  -- Start update loop if not running
  if not updateConnection then
    updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
      animationTime = animationTime + deltaTime
      for _, predatorState in pairs(activePredators) do
        if predatorState.currentAnimation == "idle" then
          applyIdleAnimation(predatorState, deltaTime)
        elseif predatorState.currentAnimation == "walking" then
          applyWalkAnimation(predatorState, deltaTime)
        elseif predatorState.currentAnimation == "trapped" then
          applyTrappedAnimation(predatorState, deltaTime)
        end
      end
    end)
  end

  return state
end

-- Set predator to walk towards a target
function PredatorVisuals.walkTo(predatorId: string, targetPosition: Vector3): boolean
  local state = activePredators[predatorId]
  if not state or state.isTrapped then
    return false
  end

  state.currentAnimation = "walking"
  state.targetPosition = targetPosition

  -- Face the target direction
  if state.model and state.model.PrimaryPart then
    local direction = (targetPosition - state.position).Unit
    local lookCFrame = CFrame.lookAt(state.position, state.position + direction)
    state.model:SetPrimaryPartCFrame(lookCFrame)
  end

  return true
end

-- Update predator position (for movement)
function PredatorVisuals.updatePosition(predatorId: string, position: Vector3)
  local state = activePredators[predatorId]
  if state then
    state.position = position
    if state.model and state.model.PrimaryPart and state.currentAnimation ~= "attacking" then
      state.model:SetPrimaryPartCFrame(CFrame.new(position))
    end
  end
end

-- Destroy a predator visual
function PredatorVisuals.destroy(predatorId: string): boolean
  local state = activePredators[predatorId]
  if not state then
    return false
  end

  if state.animationConnection then
    state.animationConnection:Disconnect()
  end

  if state.model then
    state.model:Destroy()
  end

  activePredators[predatorId] = nil

  -- Stop update loop if no more predators
  if next(activePredators) == nil and updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  return true
end

-- Get predator visual state
function PredatorVisuals.get(predatorId: string): PredatorVisualState?
  return activePredators[predatorId]
end

-- Get all active predator visuals
function PredatorVisuals.getAll(): { [string]: PredatorVisualState }
  return activePredators
end

-- Get count of active visuals
function PredatorVisuals.getActiveCount(): number
  local count = 0
  for _ in pairs(activePredators) do
    count = count + 1
  end
  return count
end

-- Set position for a predator
function PredatorVisuals.setPosition(predatorId: string, position: Vector3): boolean
  local state = activePredators[predatorId]
  if not state or not state.model then
    return false
  end

  state.position = position
  state.model:SetPrimaryPartCFrame(CFrame.new(position))
  return true
end

-- Set animation state
function PredatorVisuals.setAnimation(predatorId: string, animation: AnimationState): boolean
  local state = activePredators[predatorId]
  if not state then
    return false
  end

  -- Cannot change animation if trapped (except to defeated)
  if state.isTrapped and animation ~= "defeated" then
    return false
  end

  state.currentAnimation = animation
  return true
end

-- Release from trap
function PredatorVisuals.releaseFromTrap(predatorId: string): boolean
  local state = activePredators[predatorId]
  if not state or not state.isTrapped then
    return false
  end

  state.isTrapped = false
  state.currentAnimation = "idle"

  if state.model then
    removeTrappedOverlay(state.model)
  end

  return true
end

-- Configure visual settings
function PredatorVisuals.configure(config: VisualConfig)
  currentConfig = config
end

-- Get current configuration
function PredatorVisuals.getConfig(): VisualConfig
  return currentConfig
end

-- Get threat color for external use
function PredatorVisuals.getThreatColor(threatLevel: string): Color3
  return getThreatColor(threatLevel)
end

-- Get all threat colors
function PredatorVisuals.getThreatColors(): { [string]: Color3 }
  return THREAT_COLORS
end

-- Get eye color for external use
function PredatorVisuals.getEyeColor(threatLevel: string): Color3
  return getEyeColor(threatLevel)
end

-- Cleanup all predator visuals
function PredatorVisuals.cleanup()
  for predatorId in pairs(activePredators) do
    PredatorVisuals.destroy(predatorId)
  end

  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end

  animationTime = 0
end

-- Get summary for debugging
function PredatorVisuals.getSummary(): {
  activeCount: number,
  animationTime: number,
  trappedCount: number,
}
  local trappedCount = 0
  for _, state in pairs(activePredators) do
    if state.isTrapped then
      trappedCount = trappedCount + 1
    end
  end

  return {
    activeCount = PredatorVisuals.getActiveCount(),
    animationTime = animationTime,
    trappedCount = trappedCount,
  }
end

return PredatorVisuals
