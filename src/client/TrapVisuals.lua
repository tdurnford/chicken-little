--[[
	TrapVisuals Module
	Manages trap model creation and visual effects in the game world.
	Creates 3D representations of placed traps at their spot positions.
]]

local TrapVisuals = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Get shared modules path
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))

-- Type definitions
export type TrapVisualState = {
  id: string,
  trapType: string,
  tier: string,
  model: Model?,
  position: Vector3,
  spotIndex: number,
  hasCaughtPredator: boolean,
  isOnCooldown: boolean,
}

-- Tier colors for visual distinction
local TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(139, 90, 43), -- Brown wood
  Improved = Color3.fromRGB(150, 150, 150), -- Silver/metal
  Advanced = Color3.fromRGB(70, 130, 180), -- Steel blue
  Expert = Color3.fromRGB(180, 100, 255), -- Purple
  Master = Color3.fromRGB(255, 215, 0), -- Gold
  Ultimate = Color3.fromRGB(0, 255, 255), -- Cyan
}

-- Tier glow intensities
local TIER_GLOW_INTENSITY: { [string]: number } = {
  Basic = 0,
  Improved = 0.1,
  Advanced = 0.2,
  Expert = 0.4,
  Master = 0.6,
  Ultimate = 1.0,
}

-- Module state
local activeTraps: { [string]: TrapVisualState } = {}
local updateConnection: RBXScriptConnection? = nil
local animationTime: number = 0

-- Container for all trap visuals
local trapContainer: Folder? = nil

-- Helper: Get tier color
local function getTierColor(tier: string): Color3
  return TIER_COLORS[tier] or TIER_COLORS.Basic
end

-- Helper: Get glow intensity
local function getGlowIntensity(tier: string): number
  return TIER_GLOW_INTENSITY[tier] or 0
end

-- Get or create the trap container folder in Workspace
local function getTrapContainer(): Folder
  if trapContainer and trapContainer.Parent then
    return trapContainer
  end

  local workspace = game:GetService("Workspace")
  trapContainer = workspace:FindFirstChild("TrapVisuals") :: Folder?
  if not trapContainer then
    trapContainer = Instance.new("Folder")
    trapContainer.Name = "TrapVisuals"
    trapContainer.Parent = workspace
  end

  return trapContainer
end

-- Create a trap model based on trap type
local function createTrapModel(trapType: string, tier: string): Model
  local model = Instance.new("Model")
  model.Name = trapType

  local tierColor = getTierColor(tier)

  -- Create base plate
  local base = Instance.new("Part")
  base.Name = "Base"
  base.Size = Vector3.new(3, 0.3, 3)
  base.Color = tierColor
  base.Material = Enum.Material.Metal
  base.Anchored = true
  base.CanCollide = false
  base.CastShadow = true
  base.Parent = model

  -- Create trap mechanism (a cylindrical "cage" part on top)
  local mechanism = Instance.new("Part")
  mechanism.Name = "Mechanism"
  mechanism.Shape = Enum.PartType.Cylinder
  mechanism.Size = Vector3.new(1.5, 2.5, 2.5)
  mechanism.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90))
  mechanism.Color = tierColor
  mechanism.Material = Enum.Material.DiamondPlate
  mechanism.Anchored = true
  mechanism.CanCollide = false
  mechanism.CastShadow = true
  mechanism.Transparency = 0.3
  mechanism.Parent = model

  -- Add mesh effect for bars look
  local mesh = Instance.new("SpecialMesh")
  mesh.MeshType = Enum.MeshType.Cylinder
  mesh.Parent = mechanism

  -- Add glow effect for higher tier traps
  local glowIntensity = getGlowIntensity(tier)
  if glowIntensity > 0 then
    local pointLight = Instance.new("PointLight")
    pointLight.Name = "TierGlow"
    pointLight.Color = tierColor
    pointLight.Brightness = glowIntensity * 2
    pointLight.Range = 4 + (glowIntensity * 4)
    pointLight.Shadows = false
    pointLight.Parent = base

    -- Add particle effect for Master+ traps
    if tier == "Master" or tier == "Ultimate" then
      local particles = Instance.new("ParticleEmitter")
      particles.Name = "TierParticles"
      particles.Color = ColorSequence.new(tierColor)
      particles.Size = NumberSequence.new(0.1, 0)
      particles.Transparency = NumberSequence.new(0, 1)
      particles.Lifetime = NumberRange.new(0.5, 1)
      particles.Rate = 3 + (glowIntensity * 5)
      particles.Speed = NumberRange.new(0.5, 1)
      particles.SpreadAngle = Vector2.new(180, 180)
      particles.Parent = base
    end
  end

  -- Add status indicator (small sphere that shows ready/cooldown state)
  local indicator = Instance.new("Part")
  indicator.Name = "StatusIndicator"
  indicator.Shape = Enum.PartType.Ball
  indicator.Size = Vector3.new(0.5, 0.5, 0.5)
  indicator.Position = Vector3.new(0, 2, 0)
  indicator.Color = Color3.fromRGB(100, 255, 100) -- Green = ready
  indicator.Material = Enum.Material.Neon
  indicator.Anchored = true
  indicator.CanCollide = false
  indicator.CastShadow = false
  indicator.Parent = model

  -- Set PrimaryPart for positioning
  model.PrimaryPart = base

  return model
end

-- Create a trap visual at the specified position
function TrapVisuals.create(
  trapId: string,
  trapType: string,
  position: Vector3,
  spotIndex: number
): TrapVisualState?
  -- Get trap config for tier
  local config = TrapConfig.get(trapType)
  if not config then
    warn("[TrapVisuals] Unknown trap type:", trapType)
    return nil
  end

  local tier = config.tier

  -- Remove existing trap with same ID if it exists
  if activeTraps[trapId] then
    TrapVisuals.remove(trapId)
  end

  -- Create the model
  local model = createTrapModel(trapType, tier)

  -- Position the model
  local targetCFrame = CFrame.new(position)
  model:SetPrimaryPartCFrame(targetCFrame)

  -- Parent to container
  model.Parent = getTrapContainer()

  -- Play placement animation
  TrapVisuals.playPlacementAnimation(model, position)

  -- Create state
  local state: TrapVisualState = {
    id = trapId,
    trapType = trapType,
    tier = tier,
    model = model,
    position = position,
    spotIndex = spotIndex,
    hasCaughtPredator = false,
    isOnCooldown = false,
  }

  activeTraps[trapId] = state

  -- Start update loop if not already running (auto-start on first trap)
  if not updateConnection then
    TrapVisuals.startUpdateLoop()
  end

  return state
end

-- Play placement animation (trap appears with a bounce)
function TrapVisuals.playPlacementAnimation(model: Model, finalPosition: Vector3)
  if not model or not model.PrimaryPart then
    return
  end

  -- Start below ground and bounce up
  local startPosition = finalPosition - Vector3.new(0, 2, 0)
  local overshootPosition = finalPosition + Vector3.new(0, 0.5, 0)

  model:SetPrimaryPartCFrame(CFrame.new(startPosition))

  -- First tween: rise up and overshoot
  local tweenInfo1 = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local tween1 = TweenService:Create(model.PrimaryPart, tweenInfo1, {
    CFrame = CFrame.new(overshootPosition),
  })

  -- Second tween: settle to final position
  local tweenInfo2 = TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)

  tween1.Completed:Connect(function()
    if model and model.PrimaryPart then
      local tween2 = TweenService:Create(model.PrimaryPart, tweenInfo2, {
        CFrame = CFrame.new(finalPosition),
      })
      tween2:Play()
    end
  end)

  tween1:Play()
end

-- Remove a trap visual
function TrapVisuals.remove(trapId: string): boolean
  local state = activeTraps[trapId]
  if not state then
    return false
  end

  -- Play removal animation then destroy
  if state.model then
    TrapVisuals.playRemovalAnimation(state.model)
  end

  activeTraps[trapId] = nil
  return true
end

-- Play removal animation (trap sinks into ground)
function TrapVisuals.playRemovalAnimation(model: Model)
  if not model or not model.PrimaryPart then
    model:Destroy()
    return
  end

  local currentPosition = model.PrimaryPart.Position
  local endPosition = currentPosition - Vector3.new(0, 3, 0)

  local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
  local tween = TweenService:Create(model.PrimaryPart, tweenInfo, {
    CFrame = CFrame.new(endPosition),
  })

  tween.Completed:Connect(function()
    model:Destroy()
  end)

  tween:Play()
end

-- Update trap status (cooldown, caught predator, etc.)
function TrapVisuals.updateStatus(trapId: string, isOnCooldown: boolean, hasCaughtPredator: boolean)
  local state = activeTraps[trapId]
  if not state or not state.model then
    return
  end

  state.isOnCooldown = isOnCooldown
  state.hasCaughtPredator = hasCaughtPredator

  -- Update status indicator color
  local indicator = state.model:FindFirstChild("StatusIndicator") :: Part?
  if indicator then
    if hasCaughtPredator then
      indicator.Color = Color3.fromRGB(255, 180, 50) -- Orange = has predator
    elseif isOnCooldown then
      indicator.Color = Color3.fromRGB(255, 80, 80) -- Red = cooldown
    else
      indicator.Color = Color3.fromRGB(100, 255, 100) -- Green = ready
    end
  end

  -- Update mechanism transparency to show caught state
  local mechanism = state.model:FindFirstChild("Mechanism") :: Part?
  if mechanism then
    if hasCaughtPredator then
      mechanism.Transparency = 0.1 -- Less transparent when holding predator
    else
      mechanism.Transparency = 0.3
    end
  end
end

-- Play caught animation (trap snaps shut)
function TrapVisuals.playCaughtAnimation(trapId: string)
  local state = activeTraps[trapId]
  if not state or not state.model then
    return
  end

  local mechanism = state.model:FindFirstChild("Mechanism") :: Part?
  if not mechanism then
    return
  end

  -- Quick scale animation to simulate snapping
  local originalSize = mechanism.Size
  local squeezedSize = Vector3.new(originalSize.X * 0.7, originalSize.Y * 1.3, originalSize.Z * 0.7)

  local tweenInfo1 = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local tween1 = TweenService:Create(mechanism, tweenInfo1, { Size = squeezedSize })

  local tweenInfo2 = TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)

  tween1.Completed:Connect(function()
    local tween2 = TweenService:Create(mechanism, tweenInfo2, { Size = originalSize })
    tween2:Play()
  end)

  tween1:Play()
end

-- Get trap state by ID
function TrapVisuals.get(trapId: string): TrapVisualState?
  return activeTraps[trapId]
end

-- Get all active trap IDs
function TrapVisuals.getAllIds(): { string }
  local ids = {}
  for id, _ in pairs(activeTraps) do
    table.insert(ids, id)
  end
  return ids
end

-- Clear all trap visuals
function TrapVisuals.clearAll()
  for trapId, state in pairs(activeTraps) do
    if state.model then
      state.model:Destroy()
    end
  end
  activeTraps = {}
end

-- Get count of active trap visuals
function TrapVisuals.getCount(): number
  local count = 0
  for _ in pairs(activeTraps) do
    count = count + 1
  end
  return count
end

-- Initialize the update loop for animations
function TrapVisuals.startUpdateLoop()
  if updateConnection then
    return
  end

  updateConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
    animationTime = animationTime + deltaTime

    -- Animate status indicators with gentle pulse
    for _, state in pairs(activeTraps) do
      if state.model then
        local indicator = state.model:FindFirstChild("StatusIndicator") :: Part?
        if indicator then
          -- Gentle pulse animation
          local pulse = 1 + math.sin(animationTime * 3) * 0.1
          indicator.Size = Vector3.new(0.5 * pulse, 0.5 * pulse, 0.5 * pulse)
        end
      end
    end
  end)
end

-- Stop the update loop
function TrapVisuals.stopUpdateLoop()
  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end
end

-- Clean up when player leaves
function TrapVisuals.cleanup()
  TrapVisuals.stopUpdateLoop()
  TrapVisuals.clearAll()

  if trapContainer then
    trapContainer:Destroy()
    trapContainer = nil
  end
end

return TrapVisuals
