--[[
	MainHUD Module
	Creates and manages the main HUD with money display and real-time updates.
	Handles number formatting (K, M, B, T, Qa, Qi) and money change animations.
]]

local MainHUD = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

-- Type definitions
export type HUDConfig = {
  anchorPoint: Vector2?,
  position: UDim2?,
  size: UDim2?,
  backgroundColor: Color3?,
  textColor: Color3?,
  fontFace: Font?,
}

export type HUDState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  moneyLabel: TextLabel?,
  moneyPerSecLabel: TextLabel?,
  currentMoney: number,
  displayedMoney: number,
  moneyPerSecond: number,
  isAnimating: boolean,
  animationConnection: RBXScriptConnection?,
  -- Protection timer state
  protectionFrame: Frame?,
  protectionLabel: TextLabel?,
  protectionEndTime: number?,
  protectionUpdateConnection: RBXScriptConnection?,
  -- Inventory button state
  inventoryButton: ImageButton?,
  inventoryBadge: TextLabel?,
  inventoryItemCount: number,
  onInventoryClick: (() -> ())?,
  -- Chicken count state
  chickenCountFrame: Frame?,
  chickenCountLabel: TextLabel?,
  chickenCount: number,
  chickenMax: number,
}

-- Default configuration
local DEFAULT_CONFIG: HUDConfig = {
  anchorPoint = Vector2.new(0, 1), -- Bottom-left anchor
  position = UDim2.new(0, 10, 1, -10), -- Bottom-left corner - tight to edge
  size = UDim2.new(0, 280, 0, 70),
  backgroundColor = Color3.fromRGB(30, 30, 40),
  textColor = Color3.fromRGB(133, 187, 101), -- Money green (#85BB65 - bright)
  fontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}

-- Animation settings
local MONEY_ANIMATION_SPEED = 0.15 -- Tween duration
local MONEY_INCREMENT_RATE = 30 -- Updates per second for smooth counting
local FLASH_COLOR_GAIN = Color3.fromRGB(100, 255, 100) -- Green flash on gain
local FLASH_COLOR_LOSS = Color3.fromRGB(255, 100, 100) -- Red flash on loss

-- Module state
local state: HUDState = {
  screenGui = nil,
  mainFrame = nil,
  moneyLabel = nil,
  moneyPerSecLabel = nil,
  currentMoney = 0,
  displayedMoney = 0,
  moneyPerSecond = 0,
  isAnimating = false,
  animationConnection = nil,
  -- Protection timer state
  protectionFrame = nil,
  protectionLabel = nil,
  protectionEndTime = nil,
  protectionUpdateConnection = nil,
  -- Inventory button state
  inventoryButton = nil,
  inventoryBadge = nil,
  inventoryItemCount = 0,
  onInventoryClick = nil,
  -- Chicken count state
  chickenCountFrame = nil,
  chickenCountLabel = nil,
  chickenCount = 0,
  chickenMax = 15,
}

-- Create the money icon
local function createMoneyIcon(parent: Frame): ImageLabel
  local icon = Instance.new("ImageLabel")
  icon.Name = "MoneyIcon"
  icon.Size = UDim2.new(0, 36, 0, 36)
  icon.Position = UDim2.new(0, 6, 0, 10)
  icon.BackgroundTransparency = 1
  icon.Image = "rbxassetid://6034973115" -- Coin icon
  icon.ImageColor3 = Color3.fromRGB(133, 187, 101) -- Money green to match text
  icon.ScaleType = Enum.ScaleType.Fit
  icon.Parent = parent
  return icon
end

-- Create the money text label
local function createMoneyLabel(parent: Frame, config: HUDConfig): TextLabel
  local label = Instance.new("TextLabel")
  label.Name = "MoneyLabel"
  label.Size = UDim2.new(1, -10, 0, 36)
  label.Position = UDim2.new(0, 6, 0, 4)
  label.BackgroundTransparency = 1
  label.Text = "$0"
  label.TextColor3 = config.textColor or DEFAULT_CONFIG.textColor
  label.TextSize = 34 -- Increased from 28 for visibility in corner
  label.FontFace = config.fontFace or DEFAULT_CONFIG.fontFace
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.TextScaled = false
  label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) -- Black outline
  label.TextStrokeTransparency = 0 -- Solid outline
  label.Parent = parent
  return label
end

-- Create money per second label
local function createMoneyPerSecLabel(parent: Frame, config: HUDConfig): TextLabel
  local label = Instance.new("TextLabel")
  label.Name = "MoneyPerSecLabel"
  label.Size = UDim2.new(1, -55, 0, 20)
  label.Position = UDim2.new(0, 50, 0, 42)
  label.BackgroundTransparency = 1
  label.Text = "+$0/s"
  label.TextColor3 = Color3.fromRGB(150, 210, 130) -- Lighter money green
  label.TextSize = 16 -- Slightly larger for visibility
  label.FontFace = config.fontFace or DEFAULT_CONFIG.fontFace
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.TextTransparency = 0
  label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) -- Black outline
  label.TextStrokeTransparency = 0.3 -- Slightly transparent outline
  label.Parent = parent
  return label
end

-- Create inventory button with item count badge
local function createInventoryButton(screenGui: ScreenGui): (ImageButton, TextLabel)
  local button = Instance.new("ImageButton")
  button.Name = "InventoryButton"
  button.Size = UDim2.new(0, 60, 0, 60) -- Unified size with shield button
  button.Position = UDim2.new(1, -70, 0, 50) -- Aligned vertically with shield button
  button.AnchorPoint = Vector2.new(0, 0)
  button.BackgroundColor3 = Color3.fromRGB(60, 60, 75) -- Unified neutral color
  button.BackgroundTransparency = 0.2
  button.BorderSizePixel = 0
  button.Image = "rbxassetid://6034684949" -- Backpack icon
  button.ImageColor3 = Color3.fromRGB(220, 200, 160)
  button.ScaleType = Enum.ScaleType.Fit
  button.AutoButtonColor = true
  button.Parent = screenGui

  -- Rounded corners - unified with shield button
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = button

  -- Border stroke - unified with shield button style
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 100, 120)
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = button

  -- Padding for the image
  local padding = Instance.new("UIPadding")
  padding.PaddingTop = UDim.new(0, 8)
  padding.PaddingBottom = UDim.new(0, 8)
  padding.PaddingLeft = UDim.new(0, 8)
  padding.PaddingRight = UDim.new(0, 8)
  padding.Parent = button

  -- Item count badge (shows number of items in inventory)
  local badge = Instance.new("TextLabel")
  badge.Name = "ItemBadge"
  badge.Size = UDim2.new(0, 22, 0, 22)
  badge.Position = UDim2.new(1, -6, 0, -6)
  badge.AnchorPoint = Vector2.new(0.5, 0.5)
  badge.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
  badge.Text = "0"
  badge.TextColor3 = Color3.fromRGB(255, 255, 255)
  badge.TextSize = 12
  badge.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  badge.BorderSizePixel = 0
  badge.Visible = false -- Hidden when count is 0
  badge.Parent = button

  local badgeCorner = Instance.new("UICorner")
  badgeCorner.CornerRadius = UDim.new(1, 0) -- Fully round
  badgeCorner.Parent = badge

  -- Tooltip showing keybind
  local tooltip = Instance.new("TextLabel")
  tooltip.Name = "Tooltip"
  tooltip.Size = UDim2.new(0, 80, 0, 20)
  tooltip.Position = UDim2.new(0.5, 0, 1, 4)
  tooltip.AnchorPoint = Vector2.new(0.5, 0)
  tooltip.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
  tooltip.BackgroundTransparency = 0.2
  tooltip.Text = "Inventory (I)"
  tooltip.TextColor3 = Color3.fromRGB(180, 180, 180)
  tooltip.TextSize = 10
  tooltip.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  tooltip.BorderSizePixel = 0
  tooltip.Visible = false
  tooltip.Parent = button

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

  -- Wire click to callback
  button.MouseButton1Click:Connect(function()
    if state.onInventoryClick then
      state.onInventoryClick()
    end
  end)

  return button, badge
end

-- Create chicken count display frame
local function createChickenCountFrame(screenGui: ScreenGui): (Frame, TextLabel)
  local frame = Instance.new("Frame")
  frame.Name = "ChickenCountFrame"
  frame.Size = UDim2.new(0, 120, 0, 40)
  frame.Position = UDim2.new(1, -20, 1, -20) -- Bottom right corner
  frame.AnchorPoint = Vector2.new(1, 1) -- Anchor to bottom-right
  frame.BackgroundTransparency = 1 -- No visible background
  frame.BorderSizePixel = 0
  frame.Parent = screenGui

  -- Chicken icon (emoji)
  local icon = Instance.new("TextLabel")
  icon.Name = "ChickenIcon"
  icon.Size = UDim2.new(0, 32, 1, 0)
  icon.Position = UDim2.new(0, 0, 0, 0)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 24
  icon.Parent = frame

  -- Count label
  local label = Instance.new("TextLabel")
  label.Name = "ChickenCountLabel"
  label.Size = UDim2.new(1, -30, 1, 0)
  label.Position = UDim2.new(0, 30, 0, 0)
  label.BackgroundTransparency = 1
  label.TextColor3 = Color3.fromRGB(255, 220, 150) -- Warm yellow
  label.TextSize = 28 -- Larger to match money display style
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.TextXAlignment = Enum.TextXAlignment.Right -- Align right for bottom-right positioning
  label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) -- Black outline
  label.TextStrokeTransparency = 0 -- Solid outline for visibility
  label.Text = "0/15"
  label.Parent = frame

  return frame, label
end

-- Create the main HUD frame
local function createMainFrame(screenGui: ScreenGui, config: HUDConfig): Frame
  local frame = Instance.new("Frame")
  frame.Name = "MoneyFrame"
  frame.AnchorPoint = config.anchorPoint or DEFAULT_CONFIG.anchorPoint
  frame.Position = config.position or DEFAULT_CONFIG.position
  frame.Size = config.size or DEFAULT_CONFIG.size
  frame.BackgroundTransparency = 1 -- No visible background
  frame.BorderSizePixel = 0
  frame.Parent = screenGui

  return frame
end

-- Create the screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "MainHUD"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Flash animation for money changes
local function flashMoneyLabel(isGain: boolean)
  if not state.moneyLabel then
    return
  end

  local flashColor = isGain and FLASH_COLOR_GAIN or FLASH_COLOR_LOSS
  local originalColor = DEFAULT_CONFIG.textColor

  -- Create flash tween
  state.moneyLabel.TextColor3 = flashColor

  local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  local tween = TweenService:Create(state.moneyLabel, tweenInfo, {
    TextColor3 = originalColor,
  })
  tween:Play()
end

-- Scale animation for money changes
local function scaleMoneyLabel(isGain: boolean)
  if not state.moneyLabel then
    return
  end

  local baseTextSize = 34 -- Updated base text size
  local targetScale = isGain and 1.15 or 0.95

  -- Scale up
  local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
  local scaleTween = TweenService:Create(state.moneyLabel, tweenInfo, {
    TextSize = baseTextSize * targetScale,
  })
  scaleTween:Play()

  -- Scale back
  scaleTween.Completed:Connect(function()
    local returnTween = TweenService:Create(
      state.moneyLabel,
      TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { TextSize = baseTextSize }
    )
    returnTween:Play()
  end)
end

-- Update the money display with animation
local function updateMoneyDisplay(animate: boolean?)
  if not state.moneyLabel then
    return
  end

  local targetMoney = state.currentMoney
  local formattedMoney = MoneyScaling.formatCurrency(targetMoney)

  if animate and targetMoney ~= state.displayedMoney then
    local isGain = targetMoney > state.displayedMoney

    -- Start animations
    flashMoneyLabel(isGain)
    scaleMoneyLabel(isGain)

    -- Smooth counting animation
    if state.animationConnection then
      state.animationConnection:Disconnect()
    end

    local startMoney = state.displayedMoney
    local startTime = tick()
    local duration = MONEY_ANIMATION_SPEED

    state.isAnimating = true

    state.animationConnection = game:GetService("RunService").RenderStepped:Connect(function()
      local elapsed = tick() - startTime
      local progress = math.min(elapsed / duration, 1)

      -- Ease out quad
      progress = 1 - (1 - progress) * (1 - progress)

      local currentValue = startMoney + (targetMoney - startMoney) * progress
      state.displayedMoney = currentValue
      state.moneyLabel.Text = MoneyScaling.formatCurrency(math.floor(currentValue))

      if progress >= 1 then
        state.isAnimating = false
        state.animationConnection:Disconnect()
        state.animationConnection = nil
        state.displayedMoney = targetMoney
        state.moneyLabel.Text = formattedMoney
      end
    end)
  else
    state.displayedMoney = targetMoney
    state.moneyLabel.Text = formattedMoney
  end
end

-- Update money per second display
local function updateMoneyPerSecDisplay()
  if not state.moneyPerSecLabel then
    return
  end

  local mps = state.moneyPerSecond
  if mps <= 0 then
    state.moneyPerSecLabel.Text = "+$0/s"
    state.moneyPerSecLabel.TextTransparency = 0.5
  else
    state.moneyPerSecLabel.Text = "+" .. MoneyScaling.formatCurrency(mps) .. "/s"
    state.moneyPerSecLabel.TextTransparency = 0.2
  end
end

-- Update chicken count display
local function updateChickenCountDisplay()
  if not state.chickenCountLabel then
    return
  end

  local count = state.chickenCount
  local max = state.chickenMax

  state.chickenCountLabel.Text = count .. "/" .. max

  -- Change color when at limit
  if count >= max then
    state.chickenCountLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Red when at limit
  elseif count >= max - 2 then
    state.chickenCountLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Yellow when close to limit
  else
    state.chickenCountLabel.TextColor3 = Color3.fromRGB(255, 220, 150) -- Normal warm yellow
  end
end

-- Initialize the HUD
function MainHUD.create(config: HUDConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("MainHUD: No LocalPlayer found")
    return false
  end

  -- Clean up existing HUD
  MainHUD.destroy()

  local hudConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  state.mainFrame = createMainFrame(state.screenGui, hudConfig)
  -- Note: Money icon removed for cleaner UI
  state.moneyLabel = createMoneyLabel(state.mainFrame, hudConfig)
  -- Note: Money per second label removed for cleaner UI

  -- Create inventory button
  state.inventoryButton, state.inventoryBadge = createInventoryButton(state.screenGui)

  -- Create chicken count display
  state.chickenCountFrame, state.chickenCountLabel = createChickenCountFrame(state.screenGui)

  -- Initialize display
  updateMoneyDisplay(false)
  updateChickenCountDisplay()

  return true
end

-- Destroy the HUD
function MainHUD.destroy()
  if state.animationConnection then
    state.animationConnection:Disconnect()
    state.animationConnection = nil
  end

  if state.protectionUpdateConnection then
    state.protectionUpdateConnection:Disconnect()
    state.protectionUpdateConnection = nil
  end

  if state.screenGui then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.mainFrame = nil
  state.moneyLabel = nil
  state.moneyPerSecLabel = nil
  state.currentMoney = 0
  state.displayedMoney = 0
  state.moneyPerSecond = 0
  state.isAnimating = false
  state.protectionFrame = nil
  state.protectionLabel = nil
  state.protectionEndTime = nil
  state.inventoryButton = nil
  state.inventoryBadge = nil
  state.inventoryItemCount = 0
  state.chickenCountFrame = nil
  state.chickenCountLabel = nil
  state.chickenCount = 0
  state.chickenMax = 15
end

-- Set current money (with optional animation)
function MainHUD.setMoney(amount: number, animate: boolean?)
  local shouldAnimate = animate ~= false -- Default to true
  state.currentMoney = math.max(0, amount)
  updateMoneyDisplay(shouldAnimate)
end

-- Add money (convenience function with animation)
function MainHUD.addMoney(amount: number)
  MainHUD.setMoney(state.currentMoney + amount, true)
end

-- Subtract money (convenience function with animation)
function MainHUD.subtractMoney(amount: number)
  MainHUD.setMoney(state.currentMoney - amount, true)
end

-- Set money per second display (deprecated - display removed for cleaner UI)
function MainHUD.setMoneyPerSecond(amount: number)
  state.moneyPerSecond = math.max(0, amount)
  -- Display removed - function kept for API compatibility
end

-- Get current displayed money
function MainHUD.getMoney(): number
  return state.currentMoney
end

-- Get money per second
function MainHUD.getMoneyPerSecond(): number
  return state.moneyPerSecond
end

-- Check if HUD is created
function MainHUD.isCreated(): boolean
  return state.screenGui ~= nil and state.mainFrame ~= nil
end

-- Check if money animation is in progress
function MainHUD.isAnimating(): boolean
  return state.isAnimating
end

-- Set visibility
function MainHUD.setVisible(visible: boolean)
  if state.mainFrame then
    state.mainFrame.Visible = visible
  end
end

-- Get visibility
function MainHUD.isVisible(): boolean
  return state.mainFrame and state.mainFrame.Visible or false
end

-- Update HUD position for responsive layout
function MainHUD.setPosition(position: UDim2)
  if state.mainFrame then
    state.mainFrame.Position = position
  end
end

-- Update HUD size for responsive layout
function MainHUD.setSize(size: UDim2)
  if state.mainFrame then
    state.mainFrame.Size = size
  end
end

-- Get the screen GUI (for adding additional elements)
function MainHUD.getScreenGui(): ScreenGui?
  return state.screenGui
end

-- Get the main frame (for positioning relative to HUD)
function MainHUD.getMainFrame(): Frame?
  return state.mainFrame
end

-- Update from player data (convenience function)
function MainHUD.updateFromPlayerData(playerData: any, moneyPerSecond: number?)
  if playerData and type(playerData.money) == "number" then
    MainHUD.setMoney(playerData.money, true)
  end
  if moneyPerSecond then
    MainHUD.setMoneyPerSecond(moneyPerSecond)
  end
end

-- Set callback for inventory button click
function MainHUD.onInventoryClick(callback: () -> ())
  state.onInventoryClick = callback
end

-- Update inventory item count badge
function MainHUD.setInventoryItemCount(count: number)
  state.inventoryItemCount = count

  if state.inventoryBadge then
    if count <= 0 then
      state.inventoryBadge.Visible = false
    else
      state.inventoryBadge.Visible = true
      -- Format count (show 99+ for large numbers)
      if count > 99 then
        state.inventoryBadge.Text = "99+"
        state.inventoryBadge.Size = UDim2.new(0, 28, 0, 22)
      else
        state.inventoryBadge.Text = tostring(count)
        state.inventoryBadge.Size = UDim2.new(0, 22, 0, 22)
      end
    end
  end
end

-- Get inventory item count
function MainHUD.getInventoryItemCount(): number
  return state.inventoryItemCount
end

-- Set chicken count for area display
function MainHUD.setChickenCount(current: number, max: number?)
  state.chickenCount = math.max(0, current)
  if max then
    state.chickenMax = math.max(1, max)
  end
  updateChickenCountDisplay()
end

-- Get current chicken count
function MainHUD.getChickenCount(): number
  return state.chickenCount
end

-- Get max chickens per area
function MainHUD.getChickenMax(): number
  return state.chickenMax
end

-- Check if at chicken limit
function MainHUD.isAtChickenLimit(): boolean
  return state.chickenCount >= state.chickenMax
end

-- Get configuration defaults
function MainHUD.getDefaultConfig(): HUDConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Create protection timer UI frame
local function createProtectionFrame(screenGui: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "ProtectionFrame"
  frame.Size = UDim2.new(0, 220, 0, 40)
  frame.Position = UDim2.new(0.5, 0, 0, 10) -- Top center of screen
  frame.AnchorPoint = Vector2.new(0.5, 0)
  frame.BackgroundColor3 = Color3.fromRGB(20, 60, 20) -- Dark green
  frame.BackgroundTransparency = 0.3
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.Parent = screenGui

  -- Corner rounding
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = frame

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 200, 100) -- Light green border
  stroke.Thickness = 2
  stroke.Parent = frame

  -- Shield icon
  local icon = Instance.new("TextLabel")
  icon.Name = "ShieldIcon"
  icon.Size = UDim2.new(0, 30, 1, 0)
  icon.Position = UDim2.new(0, 5, 0, 0)
  icon.BackgroundTransparency = 1
  icon.Text = "🛡️"
  icon.TextSize = 20
  icon.Parent = frame

  -- Protection label
  local label = Instance.new("TextLabel")
  label.Name = "ProtectionLabel"
  label.Size = UDim2.new(1, -45, 1, 0)
  label.Position = UDim2.new(0, 40, 0, 0)
  label.BackgroundTransparency = 1
  label.TextColor3 = Color3.fromRGB(150, 255, 150) -- Light green text
  label.TextSize = 16
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.Text = "Protected: 3:00"
  label.Parent = frame

  return frame
end

-- Format seconds as M:SS
local function formatTime(seconds: number): string
  local mins = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("%d:%02d", mins, secs)
end

-- Update protection timer display
local function updateProtectionDisplay()
  if not state.protectionFrame or not state.protectionLabel or not state.protectionEndTime then
    return
  end

  local remaining = state.protectionEndTime - os.time()
  if remaining <= 0 then
    -- Protection has expired
    state.protectionFrame.Visible = false
    if state.protectionUpdateConnection then
      state.protectionUpdateConnection:Disconnect()
      state.protectionUpdateConnection = nil
    end
    state.protectionEndTime = nil
  else
    state.protectionLabel.Text = "Protected: " .. formatTime(remaining)
  end
end

-- Set protection status from server
function MainHUD.setProtectionStatus(data: {
  isProtected: boolean,
  remainingSeconds: number,
  totalDuration: number,
})
  if not state.screenGui then
    return
  end

  -- Create protection frame if needed
  if not state.protectionFrame then
    state.protectionFrame = createProtectionFrame(state.screenGui)
    state.protectionLabel = state.protectionFrame:FindFirstChild("ProtectionLabel") :: TextLabel
  end

  if data.isProtected and data.remainingSeconds > 0 then
    -- Show protection timer
    state.protectionEndTime = os.time() + data.remainingSeconds
    state.protectionFrame.Visible = true
    updateProtectionDisplay()

    -- Start update loop if not already running
    if not state.protectionUpdateConnection then
      local RunService = game:GetService("RunService")
      state.protectionUpdateConnection = RunService.Heartbeat:Connect(function()
        updateProtectionDisplay()
      end)
    end
  else
    -- Hide protection timer
    state.protectionFrame.Visible = false
    if state.protectionUpdateConnection then
      state.protectionUpdateConnection:Disconnect()
      state.protectionUpdateConnection = nil
    end
    state.protectionEndTime = nil
  end
end

-- Show a general notification message
function MainHUD.showNotification(message: string, color: Color3?, duration: number?)
  if not state.screenGui then
    return
  end

  local notificationColor = color or Color3.fromRGB(255, 200, 100) -- Default amber
  local showDuration = duration or 4

  -- Create a notification frame
  local notificationFrame = Instance.new("Frame")
  notificationFrame.Name = "GeneralNotification"
  notificationFrame.Size = UDim2.new(0, 400, 0, 50)
  notificationFrame.Position = UDim2.new(0.5, 0, 0.15, 0)
  notificationFrame.AnchorPoint = Vector2.new(0.5, 0.5)
  notificationFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
  notificationFrame.BackgroundTransparency = 0.15
  notificationFrame.BorderSizePixel = 0
  notificationFrame.Parent = state.screenGui

  -- Corner rounding
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 10)
  corner.Parent = notificationFrame

  -- Border stroke with notification color
  local stroke = Instance.new("UIStroke")
  stroke.Color = notificationColor
  stroke.Thickness = 2
  stroke.Parent = notificationFrame

  -- Message label
  local messageLabel = Instance.new("TextLabel")
  messageLabel.Name = "MessageLabel"
  messageLabel.Size = UDim2.new(1, -20, 1, -10)
  messageLabel.Position = UDim2.new(0, 10, 0, 5)
  messageLabel.BackgroundTransparency = 1
  messageLabel.Text = message
  messageLabel.TextColor3 = notificationColor
  messageLabel.TextStrokeTransparency = 0.5
  messageLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  messageLabel.TextSize = 18
  messageLabel.Font = Enum.Font.GothamBold
  messageLabel.TextWrapped = true
  messageLabel.TextXAlignment = Enum.TextXAlignment.Center
  messageLabel.Parent = notificationFrame

  -- Animate in (slide down from top)
  notificationFrame.Position = UDim2.new(0.5, 0, 0, -60)
  local slideIn = TweenService:Create(
    notificationFrame,
    TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Position = UDim2.new(0.5, 0, 0.15, 0) }
  )
  slideIn:Play()

  -- Auto-dismiss after duration
  task.delay(showDuration, function()
    if notificationFrame and notificationFrame.Parent then
      local fadeOut = TweenService:Create(
        notificationFrame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
      )
      local labelFade = TweenService:Create(
        messageLabel,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1, TextStrokeTransparency = 1 }
      )
      fadeOut:Play()
      labelFade:Play()
      fadeOut.Completed:Connect(function()
        if notificationFrame and notificationFrame.Parent then
          notificationFrame:Destroy()
        end
      end)
    end
  end)
end

-- Show bankruptcy assistance notification
function MainHUD.showBankruptcyAssistance(data: {
  moneyAwarded: number,
  message: string,
})
  if not state.screenGui then
    return
  end

  -- Create a notification frame
  local notificationFrame = Instance.new("Frame")
  notificationFrame.Name = "BankruptcyNotification"
  notificationFrame.Size = UDim2.new(0, 300, 0, 80)
  notificationFrame.Position = UDim2.new(0.5, 0, 0.35, 0)
  notificationFrame.AnchorPoint = Vector2.new(0.5, 0.5)
  notificationFrame.BackgroundColor3 = Color3.fromRGB(20, 60, 100) -- Dark blue
  notificationFrame.BackgroundTransparency = 0.1
  notificationFrame.BorderSizePixel = 0
  notificationFrame.Parent = state.screenGui

  -- Corner rounding
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = notificationFrame

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 180, 255) -- Light blue border
  stroke.Thickness = 3
  stroke.Parent = notificationFrame

  -- Title label
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "TitleLabel"
  titleLabel.Size = UDim2.new(1, -20, 0, 28)
  titleLabel.Position = UDim2.new(0, 10, 0, 8)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "💰 Starter Assistance"
  titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
  titleLabel.TextSize = 18
  titleLabel.Font = Enum.Font.GothamBold
  titleLabel.TextXAlignment = Enum.TextXAlignment.Center
  titleLabel.Parent = notificationFrame

  -- Message label
  local messageLabel = Instance.new("TextLabel")
  messageLabel.Name = "MessageLabel"
  messageLabel.Size = UDim2.new(1, -20, 0, 36)
  messageLabel.Position = UDim2.new(0, 10, 0, 38)
  messageLabel.BackgroundTransparency = 1
  messageLabel.Text = data.message
  messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  messageLabel.TextSize = 14
  messageLabel.Font = Enum.Font.Gotham
  messageLabel.TextWrapped = true
  messageLabel.TextXAlignment = Enum.TextXAlignment.Center
  messageLabel.Parent = notificationFrame

  -- Animate in
  notificationFrame.BackgroundTransparency = 1
  local tween = TweenService:Create(
    notificationFrame,
    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { BackgroundTransparency = 0.1 }
  )
  tween:Play()

  -- Auto-dismiss after 4 seconds
  task.delay(4, function()
    if notificationFrame and notificationFrame.Parent then
      local fadeOut = TweenService:Create(
        notificationFrame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
      )
      fadeOut:Play()
      fadeOut.Completed:Connect(function()
        if notificationFrame and notificationFrame.Parent then
          notificationFrame:Destroy()
        end
      end)
    end
  end)
end

return MainHUD
