--[[
	PredatorWarning Module
	Displays warning notifications when predators spawn and attack chickens.
	Shows directional indicator, screen flash, and "Chicken Under Attack!" message.
]]

local PredatorWarning = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Type definitions
export type WarningState = {
  predatorId: string,
  predatorType: string,
  threatLevel: string,
  position: Vector3,
  startTime: number,
  isActive: boolean,
}

export type WarningUIElements = {
  container: ScreenGui?,
  overlay: Frame?,
  messageLabel: TextLabel?,
  predatorTypeLabel: TextLabel?,
  directionArrow: Frame?,
  edgeIndicators: { Frame },
}

-- Threat level colors
local THREAT_COLORS: { [string]: Color3 } = {
  Minor = Color3.fromRGB(150, 150, 100),
  Moderate = Color3.fromRGB(200, 180, 80),
  Dangerous = Color3.fromRGB(255, 140, 50),
  Severe = Color3.fromRGB(255, 80, 80),
  Deadly = Color3.fromRGB(200, 50, 150),
  Catastrophic = Color3.fromRGB(150, 50, 200),
}

-- Warning display settings
local WARNING_FLASH_DURATION = 0.5
local WARNING_FLASH_COLOR = Color3.fromRGB(255, 50, 50)
local WARNING_MESSAGE_DURATION = 4 -- Seconds to show warning message
local EDGE_INDICATOR_THICKNESS = 8
local DIRECTION_ARROW_SIZE = 50
local DIRECTION_UPDATE_RATE = 1 / 30 -- 30 FPS for direction updates

-- Module state
local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui? = nil
local uiElements: WarningUIElements = {
  container = nil,
  overlay = nil,
  messageLabel = nil,
  predatorTypeLabel = nil,
  directionArrow = nil,
  edgeIndicators = {},
}
local activeWarnings: { [string]: WarningState } = {}
local updateConnection: RBXScriptConnection? = nil

-- Get threat color
local function getThreatColor(threatLevel: string): Color3
  return THREAT_COLORS[threatLevel] or THREAT_COLORS.Minor
end

-- Create the warning UI container
local function createWarningUI()
  if uiElements.container then
    return
  end

  playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

  -- Main container
  local container = Instance.new("ScreenGui")
  container.Name = "PredatorWarningUI"
  container.ResetOnSpawn = false
  container.IgnoreGuiInset = true
  container.DisplayOrder = 150 -- Above most UI
  container.Parent = playerGui
  uiElements.container = container

  -- Screen flash overlay (initially invisible)
  local overlay = Instance.new("Frame")
  overlay.Name = "FlashOverlay"
  overlay.Size = UDim2.new(1, 0, 1, 0)
  overlay.BackgroundColor3 = WARNING_FLASH_COLOR
  overlay.BackgroundTransparency = 1
  overlay.BorderSizePixel = 0
  overlay.Visible = false
  overlay.Parent = container
  uiElements.overlay = overlay

  -- Warning message label
  local messageLabel = Instance.new("TextLabel")
  messageLabel.Name = "WarningMessage"
  messageLabel.Size = UDim2.new(0, 400, 0, 50)
  messageLabel.Position = UDim2.new(0.5, -200, 0, 120)
  messageLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  messageLabel.BackgroundTransparency = 0.3
  messageLabel.Text = "⚠️ CHICKEN UNDER ATTACK! ⚠️"
  messageLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
  messageLabel.TextStrokeTransparency = 0
  messageLabel.TextStrokeColor3 = Color3.fromRGB(100, 50, 0)
  messageLabel.Font = Enum.Font.GothamBold
  messageLabel.TextSize = 24
  messageLabel.Visible = false
  messageLabel.Parent = container

  local messageLabelCorner = Instance.new("UICorner")
  messageLabelCorner.CornerRadius = UDim.new(0, 8)
  messageLabelCorner.Parent = messageLabel

  uiElements.messageLabel = messageLabel

  -- Predator type label (below warning message)
  local predatorTypeLabel = Instance.new("TextLabel")
  predatorTypeLabel.Name = "PredatorTypeLabel"
  predatorTypeLabel.Size = UDim2.new(0, 300, 0, 30)
  predatorTypeLabel.Position = UDim2.new(0.5, -150, 0, 175)
  predatorTypeLabel.BackgroundTransparency = 1
  predatorTypeLabel.Text = ""
  predatorTypeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  predatorTypeLabel.TextStrokeTransparency = 0.5
  predatorTypeLabel.Font = Enum.Font.Gotham
  predatorTypeLabel.TextSize = 18
  predatorTypeLabel.Visible = false
  predatorTypeLabel.Parent = container
  uiElements.predatorTypeLabel = predatorTypeLabel

  -- Direction arrow (pointing to predator)
  local directionArrow = Instance.new("Frame")
  directionArrow.Name = "DirectionArrow"
  directionArrow.Size = UDim2.new(0, DIRECTION_ARROW_SIZE, 0, DIRECTION_ARROW_SIZE)
  directionArrow.Position =
    UDim2.new(0.5, -DIRECTION_ARROW_SIZE / 2, 0.5, -DIRECTION_ARROW_SIZE / 2)
  directionArrow.BackgroundTransparency = 1
  directionArrow.Visible = false
  directionArrow.Parent = container

  -- Arrow icon (using text label with arrow symbol)
  local arrowIcon = Instance.new("TextLabel")
  arrowIcon.Name = "ArrowIcon"
  arrowIcon.Size = UDim2.new(1, 0, 1, 0)
  arrowIcon.BackgroundTransparency = 1
  arrowIcon.Text = "▶"
  arrowIcon.TextColor3 = Color3.fromRGB(255, 50, 50)
  arrowIcon.TextStrokeTransparency = 0
  arrowIcon.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
  arrowIcon.Font = Enum.Font.GothamBold
  arrowIcon.TextSize = 36
  arrowIcon.Parent = directionArrow

  uiElements.directionArrow = directionArrow

  -- Create edge indicators (red glow on screen edges)
  local edgePositions = {
    {
      position = UDim2.new(0, 0, 0, 0),
      size = UDim2.new(0, EDGE_INDICATOR_THICKNESS, 1, 0),
      name = "LeftEdge",
    },
    {
      position = UDim2.new(1, -EDGE_INDICATOR_THICKNESS, 0, 0),
      size = UDim2.new(0, EDGE_INDICATOR_THICKNESS, 1, 0),
      name = "RightEdge",
    },
    {
      position = UDim2.new(0, 0, 0, 0),
      size = UDim2.new(1, 0, 0, EDGE_INDICATOR_THICKNESS),
      name = "TopEdge",
    },
    {
      position = UDim2.new(0, 0, 1, -EDGE_INDICATOR_THICKNESS),
      size = UDim2.new(1, 0, 0, EDGE_INDICATOR_THICKNESS),
      name = "BottomEdge",
    },
  }

  for _, edgeConfig in ipairs(edgePositions) do
    local edge = Instance.new("Frame")
    edge.Name = edgeConfig.name
    edge.Position = edgeConfig.position
    edge.Size = edgeConfig.size
    edge.BackgroundColor3 = WARNING_FLASH_COLOR
    edge.BackgroundTransparency = 1
    edge.BorderSizePixel = 0
    edge.Visible = false
    edge.Parent = container
    table.insert(uiElements.edgeIndicators, edge)
  end
end

-- Play screen flash effect
local function playScreenFlash(threatLevel: string)
  if not uiElements.overlay then
    return
  end

  local flashColor = getThreatColor(threatLevel)
  uiElements.overlay.BackgroundColor3 = flashColor
  uiElements.overlay.Visible = true
  uiElements.overlay.BackgroundTransparency = 0.6

  -- Flash animation
  local flashInfo =
    TweenInfo.new(WARNING_FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local flashTween =
    TweenService:Create(uiElements.overlay, flashInfo, { BackgroundTransparency = 1 })

  flashTween:Play()
  flashTween.Completed:Connect(function()
    if uiElements.overlay then
      uiElements.overlay.Visible = false
    end
  end)
end

-- Show edge indicators with pulsing animation
local function showEdgeIndicators(threatLevel: string)
  local color = getThreatColor(threatLevel)

  for _, edge in ipairs(uiElements.edgeIndicators) do
    edge.BackgroundColor3 = color
    edge.Visible = true
    edge.BackgroundTransparency = 0.5

    -- Pulse animation
    task.spawn(function()
      local pulseIn = TweenService:Create(
        edge,
        TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { BackgroundTransparency = 0.8 }
      )
      pulseIn:Play()
    end)
  end
end

-- Hide edge indicators
local function hideEdgeIndicators()
  for _, edge in ipairs(uiElements.edgeIndicators) do
    local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local fadeTween = TweenService:Create(edge, fadeInfo, { BackgroundTransparency = 1 })
    fadeTween:Play()
    fadeTween.Completed:Connect(function()
      edge.Visible = false
    end)
  end
end

-- Show warning message
local function showWarningMessage(predatorType: string, threatLevel: string)
  if not uiElements.messageLabel or not uiElements.predatorTypeLabel then
    return
  end

  -- Get display name from config
  local config = PredatorConfig.get(predatorType)
  local displayName = config and config.displayName or predatorType

  -- Set warning text with threat color
  local threatColor = getThreatColor(threatLevel)
  uiElements.messageLabel.TextColor3 = threatColor
  uiElements.messageLabel.Visible = true

  -- Set predator type label
  uiElements.predatorTypeLabel.Text = displayName .. " (" .. threatLevel .. " Threat)"
  uiElements.predatorTypeLabel.TextColor3 = threatColor
  uiElements.predatorTypeLabel.Visible = true

  -- Animate message appearance
  uiElements.messageLabel.TextTransparency = 0
  uiElements.predatorTypeLabel.TextTransparency = 0

  -- Auto-hide after duration
  task.delay(WARNING_MESSAGE_DURATION, function()
    if uiElements.messageLabel and uiElements.predatorTypeLabel then
      local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
      local messageFade = TweenService:Create(
        uiElements.messageLabel,
        fadeInfo,
        { TextTransparency = 1, TextStrokeTransparency = 1 }
      )
      local typeFade = TweenService:Create(
        uiElements.predatorTypeLabel,
        fadeInfo,
        { TextTransparency = 1, TextStrokeTransparency = 1 }
      )

      messageFade:Play()
      typeFade:Play()

      messageFade.Completed:Connect(function()
        if uiElements.messageLabel then
          uiElements.messageLabel.Visible = false
          uiElements.messageLabel.TextTransparency = 0
          uiElements.messageLabel.TextStrokeTransparency = 0
        end
      end)

      typeFade.Completed:Connect(function()
        if uiElements.predatorTypeLabel then
          uiElements.predatorTypeLabel.Visible = false
          uiElements.predatorTypeLabel.TextTransparency = 0
          uiElements.predatorTypeLabel.TextStrokeTransparency = 0
        end
      end)
    end
  end)
end

-- Update direction arrow to point towards predator
local function updateDirectionArrow()
  if not uiElements.directionArrow then
    return
  end

  -- Find the first active warning
  local targetPosition: Vector3? = nil
  local threatLevel: string = "Minor"

  for _, warning in pairs(activeWarnings) do
    if warning.isActive then
      targetPosition = warning.position
      threatLevel = warning.threatLevel
      break
    end
  end

  if not targetPosition then
    uiElements.directionArrow.Visible = false
    return
  end

  -- Get camera and calculate direction
  local camera = workspace.CurrentCamera
  if not camera then
    return
  end

  local character = localPlayer.Character
  if not character then
    return
  end

  local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
  if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
    return
  end

  -- Check if predator is on screen
  local screenPos, onScreen = camera:WorldToScreenPoint(targetPosition)

  if onScreen then
    -- Predator is visible, hide arrow
    uiElements.directionArrow.Visible = false
    return
  end

  -- Calculate direction from player to predator
  local playerPos = humanoidRootPart.Position
  local direction = (targetPosition - playerPos).Unit

  -- Project direction to screen space
  local cameraForward = camera.CFrame.LookVector
  local cameraRight = camera.CFrame.RightVector

  local dotForward = direction:Dot(cameraForward)
  local dotRight = direction:Dot(cameraRight)

  -- Calculate angle for arrow rotation
  local angle = math.atan2(dotRight, dotForward)

  -- Position arrow at edge of screen in the direction of predator
  local screenSize = camera.ViewportSize
  local centerX = screenSize.X / 2
  local centerY = screenSize.Y / 2
  local edgeOffset = 100 -- Distance from edge

  -- Calculate edge position based on angle
  local arrowX = centerX + math.sin(angle) * (centerX - edgeOffset)
  local arrowY = centerY - math.cos(angle) * (centerY - edgeOffset)

  -- Clamp to screen bounds
  arrowX = math.clamp(arrowX, edgeOffset, screenSize.X - edgeOffset)
  arrowY = math.clamp(arrowY, edgeOffset, screenSize.Y - edgeOffset)

  -- Update arrow position and rotation
  uiElements.directionArrow.Position =
    UDim2.new(0, arrowX - DIRECTION_ARROW_SIZE / 2, 0, arrowY - DIRECTION_ARROW_SIZE / 2)
  uiElements.directionArrow.Rotation = math.deg(angle)
  uiElements.directionArrow.Visible = true

  -- Update arrow color based on threat
  local arrowIcon = uiElements.directionArrow:FindFirstChild("ArrowIcon")
  if arrowIcon and arrowIcon:IsA("TextLabel") then
    arrowIcon.TextColor3 = getThreatColor(threatLevel)
  end
end

-- Start the update loop for direction arrow
local function startUpdateLoop()
  if updateConnection then
    return
  end

  updateConnection = RunService.Heartbeat:Connect(function()
    updateDirectionArrow()
  end)
end

-- Stop the update loop
local function stopUpdateLoop()
  if updateConnection then
    updateConnection:Disconnect()
    updateConnection = nil
  end
end

-- Initialize the warning system
function PredatorWarning.initialize()
  createWarningUI()
  print("[PredatorWarning] Initialized")
end

-- Show warning for a new predator
function PredatorWarning.show(
  predatorId: string,
  predatorType: string,
  threatLevel: string,
  position: Vector3
)
  -- Create warning state
  local warningState: WarningState = {
    predatorId = predatorId,
    predatorType = predatorType,
    threatLevel = threatLevel,
    position = position,
    startTime = os.clock(),
    isActive = true,
  }

  activeWarnings[predatorId] = warningState

  -- Create UI if not exists
  if not uiElements.container then
    createWarningUI()
  end

  -- Play visual effects
  playScreenFlash(threatLevel)
  showEdgeIndicators(threatLevel)
  showWarningMessage(predatorType, threatLevel)

  -- Start update loop for direction arrow
  startUpdateLoop()

  print("[PredatorWarning] Warning shown for", predatorType, "at", position)
end

-- Update predator position (for tracking)
function PredatorWarning.updatePosition(predatorId: string, position: Vector3)
  local warning = activeWarnings[predatorId]
  if warning then
    warning.position = position
  end
end

-- Clear warning for a specific predator
function PredatorWarning.clear(predatorId: string)
  local warning = activeWarnings[predatorId]
  if not warning then
    return
  end

  warning.isActive = false
  activeWarnings[predatorId] = nil

  -- Check if any warnings are still active
  local hasActiveWarnings = false
  for _, w in pairs(activeWarnings) do
    if w.isActive then
      hasActiveWarnings = true
      break
    end
  end

  -- Hide edge indicators and direction arrow if no more warnings
  if not hasActiveWarnings then
    hideEdgeIndicators()
    if uiElements.directionArrow then
      uiElements.directionArrow.Visible = false
    end
    stopUpdateLoop()
  end

  print("[PredatorWarning] Warning cleared for", predatorId)
end

-- Clear all warnings
function PredatorWarning.clearAll()
  for predatorId in pairs(activeWarnings) do
    PredatorWarning.clear(predatorId)
  end
end

-- Check if there are active warnings
function PredatorWarning.hasActiveWarnings(): boolean
  for _, warning in pairs(activeWarnings) do
    if warning.isActive then
      return true
    end
  end
  return false
end

-- Get count of active warnings
function PredatorWarning.getActiveCount(): number
  local count = 0
  for _, warning in pairs(activeWarnings) do
    if warning.isActive then
      count = count + 1
    end
  end
  return count
end

-- Get all active warnings
function PredatorWarning.getActiveWarnings(): { [string]: WarningState }
  return activeWarnings
end

-- Cleanup resources
function PredatorWarning.cleanup()
  stopUpdateLoop()

  if uiElements.container then
    uiElements.container:Destroy()
  end

  uiElements = {
    container = nil,
    overlay = nil,
    messageLabel = nil,
    predatorTypeLabel = nil,
    directionArrow = nil,
    edgeIndicators = {},
  }

  activeWarnings = {}
end

-- Get summary for debugging
function PredatorWarning.getSummary(): {
  activeCount: number,
  hasUI: boolean,
  warnings: { { predatorId: string, predatorType: string, threatLevel: string } },
}
  local warnings = {}
  for predatorId, warning in pairs(activeWarnings) do
    if warning.isActive then
      table.insert(warnings, {
        predatorId = predatorId,
        predatorType = warning.predatorType,
        threatLevel = warning.threatLevel,
      })
    end
  end

  return {
    activeCount = PredatorWarning.getActiveCount(),
    hasUI = uiElements.container ~= nil,
    warnings = warnings,
  }
end

return PredatorWarning
