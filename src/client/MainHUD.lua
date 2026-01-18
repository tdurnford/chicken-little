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
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

-- TopbarPlus for native topbar integration
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Icon = require(Packages:WaitForChild("TopbarPlus"))

-- UI Signals for local event communication
local UISignals = require(Shared:WaitForChild("UISignals"))

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
  -- Inventory button state (using TopbarPlus Icon)
  inventoryIcon: any?, -- TopbarPlus Icon instance
  inventoryItemCount: number,
  onInventoryClick: (() -> ())?,
  -- Chicken count state
  chickenCountFrame: Frame?,
  chickenCountLabel: TextLabel?,
  chickenCount: number,
  chickenMax: number,
  -- Level/XP state
  levelFrame: Frame?,
  levelLabel: TextLabel?,
  xpProgressBar: Frame?,
  xpProgressFill: Frame?,
  currentLevel: number,
  currentXP: number,
  xpProgress: number,
}

-- Default configuration
local DEFAULT_CONFIG: HUDConfig = {
  anchorPoint = Vector2.new(0, 1), -- Bottom-left anchor
  position = UDim2.new(0, 10, 1, -10), -- Bottom-left corner - tight to edge
  size = UDim2.new(0, 280, 0, 44), -- Reduced height since only money label remains
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
  -- Inventory button state (using TopbarPlus Icon)
  inventoryIcon = nil,
  inventoryItemCount = 0,
  onInventoryClick = nil,
  -- Chicken count state
  chickenCountFrame = nil,
  chickenCountLabel = nil,
  chickenCount = 0,
  chickenMax = 15,
  -- Level/XP state
  levelFrame = nil,
  levelLabel = nil,
  xpProgressBar = nil,
  xpProgressFill = nil,
  currentLevel = 1,
  currentXP = 0,
  xpProgress = 0,
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

-- Create inventory button using TopbarPlus
local function createInventoryIcon(): any
  local icon = Icon.new()
    :setImage("rbxasset://textures/ui/TopBar/inventoryOn.png") -- Native Roblox backpack icon
    :setImageScale(0.85) -- Make the icon larger
    :setOrder(1)

  -- Wire click to signal and callback
  icon.selected:Connect(function()
    -- Fire the signal for signal-based consumers
    UISignals.InventoryClicked:Fire()
    -- Also call legacy callback for backward compatibility
    if state.onInventoryClick then
      state.onInventoryClick()
    end
    -- Deselect immediately so it acts like a button, not a toggle
    icon:deselect()
  end)

  return icon
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
  icon.Size = UDim2.new(0, 24, 1, 0)
  icon.Position = UDim2.new(0, 0, 0, 0)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 24
  icon.Parent = frame

  -- Count label
  local label = Instance.new("TextLabel")
  label.Name = "ChickenCountLabel"
  label.Size = UDim2.new(1, -26, 1, 0)
  label.Position = UDim2.new(0, 26, 0, 0)
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

-- Create level and XP display frame
local function createLevelFrame(screenGui: ScreenGui): (Frame, TextLabel, Frame, Frame)
  local frame = Instance.new("Frame")
  frame.Name = "LevelFrame"
  frame.Size = UDim2.new(0, 140, 0, 50)
  frame.Position = UDim2.new(0, 10, 0, 10) -- Top left corner (inventory button is now in topbar)
  frame.AnchorPoint = Vector2.new(0, 0)
  frame.BackgroundTransparency = 1 -- No background
  frame.BorderSizePixel = 0
  frame.Parent = screenGui

  -- Level text (e.g., "Level 5")
  local levelLabel = Instance.new("TextLabel")
  levelLabel.Name = "LevelLabel"
  levelLabel.Size = UDim2.new(1, 0, 0, 28)
  levelLabel.Position = UDim2.new(0, 0, 0, 0)
  levelLabel.BackgroundTransparency = 1
  levelLabel.Text = "Level 1"
  levelLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
  levelLabel.TextSize = 22
  levelLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  levelLabel.TextXAlignment = Enum.TextXAlignment.Left
  levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  levelLabel.TextStrokeTransparency = 0
  levelLabel.Parent = frame

  -- XP progress bar background
  local xpProgressBar = Instance.new("Frame")
  xpProgressBar.Name = "XPProgressBar"
  xpProgressBar.Size = UDim2.new(1, 0, 0, 8)
  xpProgressBar.Position = UDim2.new(0, 0, 0, 32)
  xpProgressBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
  xpProgressBar.BorderSizePixel = 0
  xpProgressBar.Parent = frame

  local barCorner = Instance.new("UICorner")
  barCorner.CornerRadius = UDim.new(0, 4)
  barCorner.Parent = xpProgressBar

  -- XP progress bar fill
  local xpProgressFill = Instance.new("Frame")
  xpProgressFill.Name = "XPProgressFill"
  xpProgressFill.Size = UDim2.new(0, 0, 1, 0) -- Width set by progress
  xpProgressFill.Position = UDim2.new(0, 0, 0, 0)
  xpProgressFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold to match level text
  xpProgressFill.BorderSizePixel = 0
  xpProgressFill.Parent = xpProgressBar

  local fillCorner = Instance.new("UICorner")
  fillCorner.CornerRadius = UDim.new(0, 4)
  fillCorner.Parent = xpProgressFill

  return frame, levelLabel, xpProgressBar, xpProgressFill
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

-- Update level and XP display
local function updateLevelDisplay()
  if not state.levelLabel or not state.xpProgressFill then
    return
  end

  state.levelLabel.Text = "Level " .. state.currentLevel

  -- Update XP progress bar width
  local progress = math.clamp(state.xpProgress, 0, 1)
  state.xpProgressFill.Size = UDim2.new(progress, 0, 1, 0)
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

  -- Create inventory button using TopbarPlus
  state.inventoryIcon = createInventoryIcon()

  -- Create chicken count display
  state.chickenCountFrame, state.chickenCountLabel = createChickenCountFrame(state.screenGui)

  -- Create level/XP display
  state.levelFrame, state.levelLabel, state.xpProgressBar, state.xpProgressFill =
    createLevelFrame(state.screenGui)

  -- Initialize display
  updateMoneyDisplay(false)
  updateChickenCountDisplay()
  updateLevelDisplay()

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
  if state.inventoryIcon then
    state.inventoryIcon:destroy()
  end
  state.inventoryIcon = nil
  state.inventoryItemCount = 0
  state.chickenCountFrame = nil
  state.chickenCountLabel = nil
  state.chickenCount = 0
  state.chickenMax = 15
  state.levelFrame = nil
  state.levelLabel = nil
  state.xpProgressBar = nil
  state.xpProgressFill = nil
  state.currentLevel = 1
  state.currentXP = 0
  state.xpProgress = 0
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
  -- Update level and XP display
  if playerData then
    local xp = playerData.xp or 0
    local level = playerData.level or LevelConfig.getLevelFromXP(xp)
    local progress = LevelConfig.getLevelProgress(xp)
    MainHUD.setLevelAndXP(level, xp, progress)
  end
end

-- Set callback for inventory button click
function MainHUD.onInventoryClick(callback: () -> ())
  state.onInventoryClick = callback
end

-- Update inventory item count badge
function MainHUD.setInventoryItemCount(count: number)
  local previousCount = state.inventoryItemCount
  state.inventoryItemCount = count

  if state.inventoryIcon then
    -- Clear existing notices first
    state.inventoryIcon:clearNotices()
    -- Add notices for each item (TopbarPlus shows count automatically)
    for _ = 1, math.min(count, 99) do
      state.inventoryIcon:notify()
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

-- Set level and XP progress
function MainHUD.setLevelAndXP(level: number, xp: number, progress: number)
  state.currentLevel = math.max(1, level)
  state.currentXP = math.max(0, xp)
  state.xpProgress = math.clamp(progress, 0, 1)
  updateLevelDisplay()
end

-- Get current level
function MainHUD.getLevel(): number
  return state.currentLevel
end

-- Get current XP
function MainHUD.getXP(): number
  return state.currentXP
end

-- Get XP progress (0-1)
function MainHUD.getXPProgress(): number
  return state.xpProgress
end

-- Show level up celebration notification
function MainHUD.showLevelUp(newLevel: number, unlocks: { string }?)
  if not state.screenGui then
    return
  end

  -- Create a celebration notification frame
  local notificationFrame = Instance.new("Frame")
  notificationFrame.Name = "LevelUpNotification"
  notificationFrame.Size = UDim2.new(0, 300, 0, 100)
  notificationFrame.Position = UDim2.new(0.5, 0, 0.3, 0)
  notificationFrame.AnchorPoint = Vector2.new(0.5, 0.5)
  notificationFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
  notificationFrame.BackgroundTransparency = 0.1
  notificationFrame.BorderSizePixel = 0
  notificationFrame.Parent = state.screenGui

  -- Corner rounding
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = notificationFrame

  -- Golden border
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(255, 215, 0) -- Gold
  stroke.Thickness = 3
  stroke.Parent = notificationFrame

  -- Level up title
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "TitleLabel"
  titleLabel.Size = UDim2.new(1, -20, 0, 36)
  titleLabel.Position = UDim2.new(0, 10, 0, 10)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "⬆️ LEVEL UP! ⬆️"
  titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
  titleLabel.TextSize = 24
  titleLabel.Font = Enum.Font.GothamBold
  titleLabel.TextXAlignment = Enum.TextXAlignment.Center
  titleLabel.Parent = notificationFrame

  -- Level number
  local levelLabel = Instance.new("TextLabel")
  levelLabel.Name = "LevelLabel"
  levelLabel.Size = UDim2.new(1, -20, 0, 30)
  levelLabel.Position = UDim2.new(0, 10, 0, 48)
  levelLabel.BackgroundTransparency = 1
  levelLabel.Text = "Level " .. newLevel
  levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  levelLabel.TextSize = 20
  levelLabel.Font = Enum.Font.GothamBold
  levelLabel.TextXAlignment = Enum.TextXAlignment.Center
  levelLabel.Parent = notificationFrame

  -- Unlocks text (if any)
  if unlocks and #unlocks > 0 then
    notificationFrame.Size = UDim2.new(0, 300, 0, 130)

    local unlocksLabel = Instance.new("TextLabel")
    unlocksLabel.Name = "UnlocksLabel"
    unlocksLabel.Size = UDim2.new(1, -20, 0, 24)
    unlocksLabel.Position = UDim2.new(0, 10, 0, 82)
    unlocksLabel.BackgroundTransparency = 1
    unlocksLabel.Text = "🔓 " .. table.concat(unlocks, ", ")
    unlocksLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
    unlocksLabel.TextSize = 14
    unlocksLabel.Font = Enum.Font.Gotham
    unlocksLabel.TextWrapped = true
    unlocksLabel.TextXAlignment = Enum.TextXAlignment.Center
    unlocksLabel.Parent = notificationFrame
  end

  -- Animate in (scale up)
  notificationFrame.Size = UDim2.new(0, 0, 0, 0)
  local targetSize = unlocks and #unlocks > 0 and UDim2.new(0, 300, 0, 130)
    or UDim2.new(0, 300, 0, 100)

  local scaleIn = TweenService:Create(
    notificationFrame,
    TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = targetSize }
  )
  scaleIn:Play()

  -- Auto-dismiss after 3 seconds
  task.delay(3, function()
    if notificationFrame and notificationFrame.Parent then
      local scaleOut = TweenService:Create(
        notificationFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        { Size = UDim2.new(0, 0, 0, 0) }
      )
      scaleOut:Play()
      scaleOut.Completed:Connect(function()
        if notificationFrame and notificationFrame.Parent then
          notificationFrame:Destroy()
        end
      end)
    end
  end)
end

-- Show XP gain floating text
function MainHUD.showXPGain(amount: number)
  if not state.levelFrame or not state.screenGui then
    return
  end

  local xpText = Instance.new("TextLabel")
  xpText.Name = "XPGainText"
  xpText.Size = UDim2.new(0, 100, 0, 24)
  xpText.Position = UDim2.new(0, 150, 0, 20) -- Near level display
  xpText.AnchorPoint = Vector2.new(0.5, 0.5)
  xpText.BackgroundTransparency = 1
  xpText.Text = "+" .. amount .. " XP"
  xpText.TextColor3 = Color3.fromRGB(100, 200, 255) -- Light blue
  xpText.TextSize = 18
  xpText.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  xpText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  xpText.TextStrokeTransparency = 0
  xpText.Parent = state.screenGui

  -- Float up and fade out
  local floatTween = TweenService:Create(
    xpText,
    TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { Position = UDim2.new(0, 150, 0, -20), TextTransparency = 1, TextStrokeTransparency = 1 }
  )
  floatTween:Play()
  floatTween.Completed:Connect(function()
    if xpText and xpText.Parent then
      xpText:Destroy()
    end
  end)
end

return MainHUD
