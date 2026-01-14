--[[
	ShieldUI Module
	Creates and manages the area shield button UI.
	Shows shield activation button, countdown timer, and cooldown status.
]]

local ShieldUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Type definitions
export type ShieldUIState = {
  screenGui: ScreenGui?,
  buttonFrame: Frame?,
  shieldButton: TextButton?,
  statusLabel: TextLabel?,
  timerLabel: TextLabel?,
  progressBar: Frame?,
  progressFill: Frame?,
  isActive: boolean,
  isOnCooldown: boolean,
  remainingDuration: number,
  remainingCooldown: number,
  durationTotal: number,
  cooldownTotal: number,
  updateConnection: RBXScriptConnection?,
  onActivateCallback: (() -> ())?,
}

-- Configuration
local SHIELD_BUTTON_SIZE = UDim2.new(0, 60, 0, 60)
local SHIELD_BUTTON_POSITION = UDim2.new(1, -140, 0, 10) -- Next to inventory button

-- Colors
local COLORS = {
  ready = Color3.fromRGB(80, 180, 80), -- Green - ready to activate
  active = Color3.fromRGB(100, 150, 255), -- Blue - shield active
  cooldown = Color3.fromRGB(150, 150, 150), -- Gray - on cooldown
  disabled = Color3.fromRGB(80, 80, 80),
  text = Color3.fromRGB(255, 255, 255),
  progressBg = Color3.fromRGB(40, 40, 50),
  progressActive = Color3.fromRGB(100, 180, 255), -- Blue progress
  progressCooldown = Color3.fromRGB(255, 180, 80), -- Orange progress
}

-- Module state
local state: ShieldUIState = {
  screenGui = nil,
  buttonFrame = nil,
  shieldButton = nil,
  statusLabel = nil,
  timerLabel = nil,
  progressBar = nil,
  progressFill = nil,
  isActive = false,
  isOnCooldown = false,
  remainingDuration = 0,
  remainingCooldown = 0,
  durationTotal = 60,
  cooldownTotal = 300,
  updateConnection = nil,
  onActivateCallback = nil,
}

-- Format seconds to MM:SS
local function formatTime(seconds: number): string
  if seconds <= 0 then
    return "0:00"
  end
  local mins = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("%d:%02d", mins, secs)
end

-- Create the shield button
local function createShieldButton(
  parent: ScreenGui
): (Frame, TextButton, TextLabel, TextLabel, Frame, Frame)
  -- Main container frame
  local buttonFrame = Instance.new("Frame")
  buttonFrame.Name = "ShieldButtonFrame"
  buttonFrame.Size = SHIELD_BUTTON_SIZE
  buttonFrame.Position = SHIELD_BUTTON_POSITION
  buttonFrame.AnchorPoint = Vector2.new(0, 0)
  buttonFrame.BackgroundTransparency = 1
  buttonFrame.Parent = parent

  -- Shield button
  local button = Instance.new("TextButton")
  button.Name = "ShieldButton"
  button.Size = UDim2.new(1, 0, 1, 0)
  button.Position = UDim2.new(0, 0, 0, 0)
  button.BackgroundColor3 = COLORS.ready
  button.BackgroundTransparency = 0.2
  button.BorderSizePixel = 0
  button.Text = "🛡️"
  button.TextSize = 28
  button.TextColor3 = COLORS.text
  button.AutoButtonColor = true
  button.Parent = buttonFrame

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = button

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 200, 100)
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = button

  -- Progress bar container (below button)
  local progressBar = Instance.new("Frame")
  progressBar.Name = "ProgressBar"
  progressBar.Size = UDim2.new(1, 0, 0, 6)
  progressBar.Position = UDim2.new(0, 0, 1, 2)
  progressBar.BackgroundColor3 = COLORS.progressBg
  progressBar.BorderSizePixel = 0
  progressBar.Visible = false
  progressBar.Parent = buttonFrame

  local progressCorner = Instance.new("UICorner")
  progressCorner.CornerRadius = UDim.new(0, 3)
  progressCorner.Parent = progressBar

  -- Progress fill
  local progressFill = Instance.new("Frame")
  progressFill.Name = "ProgressFill"
  progressFill.Size = UDim2.new(1, 0, 1, 0)
  progressFill.Position = UDim2.new(0, 0, 0, 0)
  progressFill.BackgroundColor3 = COLORS.progressActive
  progressFill.BorderSizePixel = 0
  progressFill.Parent = progressBar

  local fillCorner = Instance.new("UICorner")
  fillCorner.CornerRadius = UDim.new(0, 3)
  fillCorner.Parent = progressFill

  -- Status label (shows "Active", "Cooldown", or "Ready")
  local statusLabel = Instance.new("TextLabel")
  statusLabel.Name = "StatusLabel"
  statusLabel.Size = UDim2.new(0, 80, 0, 16)
  statusLabel.Position = UDim2.new(0.5, 0, 1, 12)
  statusLabel.AnchorPoint = Vector2.new(0.5, 0)
  statusLabel.BackgroundTransparency = 1
  statusLabel.TextColor3 = COLORS.text
  statusLabel.TextSize = 11
  statusLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  statusLabel.Text = "Ready"
  statusLabel.Visible = false
  statusLabel.Parent = buttonFrame

  -- Timer label (shows countdown)
  local timerLabel = Instance.new("TextLabel")
  timerLabel.Name = "TimerLabel"
  timerLabel.Size = UDim2.new(0, 80, 0, 14)
  timerLabel.Position = UDim2.new(0.5, 0, 1, 28)
  timerLabel.AnchorPoint = Vector2.new(0.5, 0)
  timerLabel.BackgroundTransparency = 1
  timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
  timerLabel.TextSize = 10
  timerLabel.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  timerLabel.Text = ""
  timerLabel.Visible = false
  timerLabel.Parent = buttonFrame

  -- Tooltip on hover
  local tooltip = Instance.new("TextLabel")
  tooltip.Name = "Tooltip"
  tooltip.Size = UDim2.new(0, 100, 0, 20)
  tooltip.Position = UDim2.new(0.5, 0, 0, -24)
  tooltip.AnchorPoint = Vector2.new(0.5, 1)
  tooltip.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
  tooltip.BackgroundTransparency = 0.2
  tooltip.Text = "Area Shield"
  tooltip.TextColor3 = Color3.fromRGB(180, 180, 180)
  tooltip.TextSize = 10
  tooltip.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  tooltip.BorderSizePixel = 0
  tooltip.Visible = false
  tooltip.Parent = buttonFrame

  local tooltipCorner = Instance.new("UICorner")
  tooltipCorner.CornerRadius = UDim.new(0, 4)
  tooltipCorner.Parent = tooltip

  -- Show/hide tooltip on hover
  button.MouseEnter:Connect(function()
    tooltip.Visible = true
  end)

  button.MouseLeave:Connect(function()
    tooltip.Visible = false
  end)

  -- Wire click handler
  button.MouseButton1Click:Connect(function()
    if state.onActivateCallback and not state.isActive and not state.isOnCooldown then
      state.onActivateCallback()
    end
  end)

  return buttonFrame, button, statusLabel, timerLabel, progressBar, progressFill
end

-- Update the visual state of the button
local function updateVisualState()
  if not state.shieldButton or not state.statusLabel or not state.timerLabel then
    return
  end

  if state.isActive then
    -- Shield is active
    state.shieldButton.BackgroundColor3 = COLORS.active
    state.shieldButton.Text = "🛡️"
    state.statusLabel.Text = "ACTIVE"
    state.statusLabel.TextColor3 = COLORS.active
    state.statusLabel.Visible = true
    state.timerLabel.Text = formatTime(state.remainingDuration)
    state.timerLabel.Visible = true

    -- Show progress bar
    if state.progressBar and state.progressFill then
      state.progressBar.Visible = true
      state.progressFill.BackgroundColor3 = COLORS.progressActive
      local progress = state.durationTotal > 0 and (state.remainingDuration / state.durationTotal)
        or 0
      state.progressFill.Size = UDim2.new(math.max(0, math.min(1, progress)), 0, 1, 0)
    end

    -- Update stroke color
    local stroke = state.shieldButton:FindFirstChildOfClass("UIStroke")
    if stroke then
      stroke.Color = COLORS.active
    end
  elseif state.isOnCooldown then
    -- On cooldown
    state.shieldButton.BackgroundColor3 = COLORS.cooldown
    state.shieldButton.Text = "⏳"
    state.statusLabel.Text = "COOLDOWN"
    state.statusLabel.TextColor3 = COLORS.cooldown
    state.statusLabel.Visible = true
    state.timerLabel.Text = formatTime(state.remainingCooldown)
    state.timerLabel.Visible = true

    -- Show progress bar (filling up as cooldown completes)
    if state.progressBar and state.progressFill then
      state.progressBar.Visible = true
      state.progressFill.BackgroundColor3 = COLORS.progressCooldown
      local progress = state.cooldownTotal > 0
          and (1 - state.remainingCooldown / state.cooldownTotal)
        or 1
      state.progressFill.Size = UDim2.new(math.max(0, math.min(1, progress)), 0, 1, 0)
    end

    -- Update stroke color
    local stroke = state.shieldButton:FindFirstChildOfClass("UIStroke")
    if stroke then
      stroke.Color = COLORS.cooldown
    end
  else
    -- Ready to activate
    state.shieldButton.BackgroundColor3 = COLORS.ready
    state.shieldButton.Text = "🛡️"
    state.statusLabel.Text = "Ready"
    state.statusLabel.Visible = false
    state.timerLabel.Visible = false

    -- Hide progress bar
    if state.progressBar then
      state.progressBar.Visible = false
    end

    -- Update stroke color
    local stroke = state.shieldButton:FindFirstChildOfClass("UIStroke")
    if stroke then
      stroke.Color = Color3.fromRGB(100, 200, 100)
    end
  end
end

-- Initialize the Shield UI
function ShieldUI.create(existingScreenGui: ScreenGui?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("ShieldUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing
  ShieldUI.destroy()

  -- Use existing ScreenGui or create new one
  if existingScreenGui then
    state.screenGui = existingScreenGui
  else
    state.screenGui = Instance.new("ScreenGui")
    state.screenGui.Name = "ShieldUI"
    state.screenGui.ResetOnSpawn = false
    state.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    state.screenGui.Parent = player:WaitForChild("PlayerGui")
  end

  -- Create UI elements
  state.buttonFrame, state.shieldButton, state.statusLabel, state.timerLabel, state.progressBar, state.progressFill =
    createShieldButton(state.screenGui)

  -- Initial visual state
  updateVisualState()

  return true
end

-- Destroy the Shield UI
function ShieldUI.destroy()
  if state.updateConnection then
    state.updateConnection:Disconnect()
    state.updateConnection = nil
  end

  if state.buttonFrame then
    state.buttonFrame:Destroy()
  end

  -- Only destroy screenGui if we created it
  if state.screenGui and state.screenGui.Name == "ShieldUI" then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.buttonFrame = nil
  state.shieldButton = nil
  state.statusLabel = nil
  state.timerLabel = nil
  state.progressBar = nil
  state.progressFill = nil
  state.isActive = false
  state.isOnCooldown = false
  state.remainingDuration = 0
  state.remainingCooldown = 0
  state.onActivateCallback = nil
end

-- Update shield status from server
function ShieldUI.updateStatus(data: {
  isActive: boolean,
  isOnCooldown: boolean,
  canActivate: boolean,
  remainingDuration: number,
  remainingCooldown: number,
  durationTotal: number,
  cooldownTotal: number,
})
  state.isActive = data.isActive
  state.isOnCooldown = data.isOnCooldown
  state.remainingDuration = data.remainingDuration
  state.remainingCooldown = data.remainingCooldown
  state.durationTotal = data.durationTotal
  state.cooldownTotal = data.cooldownTotal

  updateVisualState()
end

-- Set the callback for shield activation
function ShieldUI.onActivate(callback: () -> ())
  state.onActivateCallback = callback
end

-- Show activation feedback
function ShieldUI.showActivationFeedback(success: boolean, message: string)
  if not state.shieldButton then
    return
  end

  -- Flash the button
  local originalColor = state.shieldButton.BackgroundColor3
  local flashColor = success and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 150, 150)

  state.shieldButton.BackgroundColor3 = flashColor

  local tween = TweenService:Create(
    state.shieldButton,
    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { BackgroundColor3 = originalColor }
  )
  tween:Play()
end

-- Check if UI is created
function ShieldUI.isCreated(): boolean
  return state.buttonFrame ~= nil
end

-- Set visibility
function ShieldUI.setVisible(visible: boolean)
  if state.buttonFrame then
    state.buttonFrame.Visible = visible
  end
end

-- Get the button frame for positioning
function ShieldUI.getButtonFrame(): Frame?
  return state.buttonFrame
end

return ShieldUI
