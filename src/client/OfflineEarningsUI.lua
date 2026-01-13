--[[
	OfflineEarningsUI Module
	Creates and manages the "Welcome Back" popup showing offline earnings.
	Displays money earned, eggs collected, and time away with claim functionality.
]]

local OfflineEarningsUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

-- Type definitions
export type PopupConfig = {
  anchorPoint: Vector2?,
  position: UDim2?,
  size: UDim2?,
  backgroundColor: Color3?,
  accentColor: Color3?,
}

export type PopupState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  moneyEarned: number,
  eggsCollected: number,
  timeAwaySeconds: number,
  isVisible: boolean,
  onClaim: ((moneyEarned: number, eggsCollected: number) -> ())?,
  onDismiss: (() -> ())?,
}

-- Rarity colors for egg display
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(180, 180, 180),
  Uncommon = Color3.fromRGB(100, 200, 100),
  Rare = Color3.fromRGB(100, 150, 255),
  Epic = Color3.fromRGB(180, 100, 255),
  Legendary = Color3.fromRGB(255, 180, 50),
  Mythic = Color3.fromRGB(255, 100, 150),
}

-- Default configuration
local DEFAULT_CONFIG: PopupConfig = {
  anchorPoint = Vector2.new(0.5, 0.5),
  position = UDim2.new(0.5, 0, 0.5, 0),
  size = UDim2.new(0, 380, 0, 340),
  backgroundColor = Color3.fromRGB(30, 30, 40),
  accentColor = Color3.fromRGB(255, 215, 0), -- Gold
}

-- Animation settings
local FADE_IN_DURATION = 0.3
local SCALE_IN_DURATION = 0.25
local COIN_ANIMATION_DELAY = 0.1

-- Module state
local state: PopupState = {
  screenGui = nil,
  mainFrame = nil,
  moneyEarned = 0,
  eggsCollected = 0,
  timeAwaySeconds = 0,
  isVisible = false,
  onClaim = nil,
  onDismiss = nil,
}

local currentConfig: PopupConfig = DEFAULT_CONFIG

-- Create a dimmed backdrop
local function createBackdrop(parent: ScreenGui): Frame
  local backdrop = Instance.new("Frame")
  backdrop.Name = "Backdrop"
  backdrop.Size = UDim2.new(1, 0, 1, 0)
  backdrop.Position = UDim2.new(0, 0, 0, 0)
  backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
  backdrop.BackgroundTransparency = 1 -- Start transparent for animation
  backdrop.BorderSizePixel = 0
  backdrop.ZIndex = 1
  backdrop.Parent = parent
  return backdrop
end

-- Create the main popup frame
local function createMainFrame(parent: ScreenGui, config: PopupConfig): Frame
  local frame = Instance.new("Frame")
  frame.Name = "OfflineEarningsPopup"
  frame.AnchorPoint = config.anchorPoint or DEFAULT_CONFIG.anchorPoint
  frame.Position = config.position or DEFAULT_CONFIG.position
  frame.Size = config.size or DEFAULT_CONFIG.size
  frame.BackgroundColor3 = config.backgroundColor or DEFAULT_CONFIG.backgroundColor
  frame.BackgroundTransparency = 0.1
  frame.BorderSizePixel = 0
  frame.ZIndex = 2

  -- Start scaled down for animation
  frame.Size = UDim2.new(0, 0, 0, 0)
  frame.Parent = parent

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 16)
  corner.Parent = frame

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = config.accentColor or DEFAULT_CONFIG.accentColor
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = frame

  return frame
end

-- Create welcome back header
local function createHeader(parent: Frame): TextLabel
  local header = Instance.new("TextLabel")
  header.Name = "Header"
  header.Size = UDim2.new(1, -24, 0, 40)
  header.Position = UDim2.new(0, 12, 0, 12)
  header.BackgroundTransparency = 1
  header.Text = "🎉 Welcome Back!"
  header.TextColor3 = Color3.fromRGB(255, 255, 255)
  header.TextSize = 28
  header.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  header.TextXAlignment = Enum.TextXAlignment.Center
  header.ZIndex = 3
  header.Parent = parent
  return header
end

-- Create time away display
local function createTimeAwayLabel(parent: Frame): TextLabel
  local label = Instance.new("TextLabel")
  label.Name = "TimeAwayLabel"
  label.Size = UDim2.new(1, -24, 0, 24)
  label.Position = UDim2.new(0, 12, 0, 52)
  label.BackgroundTransparency = 1
  label.Text = "You were away for 0 hours"
  label.TextColor3 = Color3.fromRGB(180, 180, 200)
  label.TextSize = 14
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  label.TextXAlignment = Enum.TextXAlignment.Center
  label.ZIndex = 3
  label.Parent = parent
  return label
end

-- Create earnings section (money or eggs)
local function createEarningsSection(
  parent: Frame,
  name: string,
  icon: string,
  yPosition: number,
  accentColor: Color3
): Frame
  local section = Instance.new("Frame")
  section.Name = name .. "Section"
  section.Size = UDim2.new(1, -32, 0, 70)
  section.Position = UDim2.new(0, 16, 0, yPosition)
  section.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  section.BackgroundTransparency = 0.3
  section.BorderSizePixel = 0
  section.ZIndex = 3
  section.Parent = parent

  local sectionCorner = Instance.new("UICorner")
  sectionCorner.CornerRadius = UDim.new(0, 10)
  sectionCorner.Parent = section

  -- Icon
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 50, 1, 0)
  iconLabel.Position = UDim2.new(0, 8, 0, 0)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = icon
  iconLabel.TextSize = 32
  iconLabel.TextColor3 = accentColor
  iconLabel.ZIndex = 4
  iconLabel.Parent = section

  -- Label
  local labelText = Instance.new("TextLabel")
  labelText.Name = "Label"
  labelText.Size = UDim2.new(1, -70, 0, 22)
  labelText.Position = UDim2.new(0, 60, 0, 10)
  labelText.BackgroundTransparency = 1
  labelText.Text = name .. " Earned"
  labelText.TextColor3 = Color3.fromRGB(180, 180, 200)
  labelText.TextSize = 14
  labelText.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  labelText.TextXAlignment = Enum.TextXAlignment.Left
  labelText.ZIndex = 4
  labelText.Parent = section

  -- Value
  local valueLabel = Instance.new("TextLabel")
  valueLabel.Name = "Value"
  valueLabel.Size = UDim2.new(1, -70, 0, 30)
  valueLabel.Position = UDim2.new(0, 60, 0, 32)
  valueLabel.BackgroundTransparency = 1
  valueLabel.Text = "$0"
  valueLabel.TextColor3 = accentColor
  valueLabel.TextSize = 24
  valueLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  valueLabel.TextXAlignment = Enum.TextXAlignment.Left
  valueLabel.ZIndex = 4
  valueLabel.Parent = section

  return section
end

-- Create claim button
local function createClaimButton(parent: Frame): TextButton
  local button = Instance.new("TextButton")
  button.Name = "ClaimButton"
  button.Size = UDim2.new(1, -32, 0, 50)
  button.Position = UDim2.new(0, 16, 1, -66)
  button.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
  button.Text = "✓ Claim Rewards"
  button.TextColor3 = Color3.fromRGB(255, 255, 255)
  button.TextSize = 18
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.ZIndex = 3
  button.Parent = parent

  local buttonCorner = Instance.new("UICorner")
  buttonCorner.CornerRadius = UDim.new(0, 10)
  buttonCorner.Parent = button

  -- Hover effect
  local originalColor = button.BackgroundColor3
  button.MouseEnter:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.15), {
      BackgroundColor3 = Color3.fromRGB(100, 200, 100),
    }):Play()
  end)
  button.MouseLeave:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.15), {
      BackgroundColor3 = originalColor,
    }):Play()
  end)

  button.MouseButton1Click:Connect(function()
    OfflineEarningsUI.claim()
  end)

  return button
end

-- Create screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "OfflineEarningsUI"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.DisplayOrder = 100 -- Above other UIs
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Animate the popup appearing
local function animatePopupIn(backdrop: Frame, mainFrame: Frame, config: PopupConfig)
  local targetSize = config.size or DEFAULT_CONFIG.size

  -- Backdrop fade in
  TweenService:Create(backdrop, TweenInfo.new(FADE_IN_DURATION, Enum.EasingStyle.Quad), {
    BackgroundTransparency = 0.6,
  }):Play()

  -- Main frame scale in
  TweenService:Create(
    mainFrame,
    TweenInfo.new(SCALE_IN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    {
      Size = targetSize,
    }
  ):Play()
end

-- Animate the popup disappearing
local function animatePopupOut(backdrop: Frame, mainFrame: Frame, callback: () -> ())
  -- Backdrop fade out
  TweenService:Create(backdrop, TweenInfo.new(FADE_IN_DURATION, Enum.EasingStyle.Quad), {
    BackgroundTransparency = 1,
  }):Play()

  -- Main frame scale out
  local tween = TweenService:Create(
    mainFrame,
    TweenInfo.new(SCALE_IN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
    {
      Size = UDim2.new(0, 0, 0, 0),
    }
  )
  tween:Play()
  tween.Completed:Connect(callback)
end

-- Update the display values
local function updateDisplay()
  if not state.mainFrame then
    return
  end

  -- Update time away
  local timeLabel = state.mainFrame:FindFirstChild("TimeAwayLabel")
  if timeLabel then
    timeLabel.Text = "You were away for " .. OfflineEarnings.formatDuration(state.timeAwaySeconds)
  end

  -- Update money value
  local moneySection = state.mainFrame:FindFirstChild("MoneySection")
  if moneySection then
    local valueLabel = moneySection:FindFirstChild("Value")
    if valueLabel then
      valueLabel.Text = MoneyScaling.formatCurrency(state.moneyEarned)
    end
  end

  -- Update eggs value
  local eggsSection = state.mainFrame:FindFirstChild("EggsSection")
  if eggsSection then
    local valueLabel = eggsSection:FindFirstChild("Value")
    if valueLabel then
      valueLabel.Text = tostring(state.eggsCollected)
        .. " egg"
        .. (state.eggsCollected == 1 and "" or "s")
    end
  end
end

-- Initialize the popup UI (hidden by default)
function OfflineEarningsUI.create(config: PopupConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("OfflineEarningsUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  OfflineEarningsUI.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  state.screenGui.Enabled = false -- Start hidden

  local backdrop = createBackdrop(state.screenGui)
  state.mainFrame = createMainFrame(state.screenGui, currentConfig)

  -- Create content elements
  createHeader(state.mainFrame)
  createTimeAwayLabel(state.mainFrame)
  createEarningsSection(
    state.mainFrame,
    "Money",
    "💰",
    88,
    currentConfig.accentColor or DEFAULT_CONFIG.accentColor
  )
  createEarningsSection(state.mainFrame, "Eggs", "🥚", 168, Color3.fromRGB(255, 220, 150))
  createClaimButton(state.mainFrame)

  state.isVisible = false

  return true
end

-- Destroy the popup UI
function OfflineEarningsUI.destroy()
  if state.screenGui then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.mainFrame = nil
  state.moneyEarned = 0
  state.eggsCollected = 0
  state.timeAwaySeconds = 0
  state.isVisible = false
  state.onClaim = nil
  state.onDismiss = nil
end

-- Show the popup with earnings data
function OfflineEarningsUI.show(moneyEarned: number, eggsCollected: number, timeAwaySeconds: number)
  if not state.screenGui or not state.mainFrame then
    warn("OfflineEarningsUI: UI not created. Call create() first.")
    return
  end

  -- Skip if no earnings
  if moneyEarned <= 0 and eggsCollected <= 0 then
    return
  end

  state.moneyEarned = moneyEarned
  state.eggsCollected = eggsCollected
  state.timeAwaySeconds = timeAwaySeconds

  -- Update display values
  updateDisplay()

  -- Show and animate
  state.screenGui.Enabled = true
  state.isVisible = true

  local backdrop = state.screenGui:FindFirstChild("Backdrop")
  if backdrop then
    animatePopupIn(backdrop, state.mainFrame, currentConfig)
  end
end

-- Show popup from OfflineEarningsResult
function OfflineEarningsUI.showFromResult(result: OfflineEarnings.OfflineEarningsResult)
  OfflineEarningsUI.show(result.cappedMoney, #result.eggsEarned, result.cappedSeconds)
end

-- Show popup from preview data
function OfflineEarningsUI.showFromPreview(preview: {
  hasPendingEarnings: boolean,
  estimatedMoney: number,
  estimatedEggs: number,
  offlineHours: number,
  placedChickenCount: number,
})
  if preview.hasPendingEarnings then
    OfflineEarningsUI.show(
      preview.estimatedMoney,
      preview.estimatedEggs,
      preview.offlineHours * 3600
    )
  end
end

-- Hide the popup
function OfflineEarningsUI.hide()
  if not state.screenGui or not state.mainFrame then
    return
  end

  local backdrop = state.screenGui:FindFirstChild("Backdrop")
  if backdrop then
    animatePopupOut(backdrop, state.mainFrame, function()
      if state.screenGui then
        state.screenGui.Enabled = false
      end
      state.isVisible = false
    end)
  else
    state.screenGui.Enabled = false
    state.isVisible = false
  end
end

-- Claim the rewards and close
function OfflineEarningsUI.claim()
  local money = state.moneyEarned
  local eggs = state.eggsCollected

  -- Call callback before hiding
  if state.onClaim then
    state.onClaim(money, eggs)
  end

  -- Hide the popup
  OfflineEarningsUI.hide()
end

-- Dismiss without claiming (for edge cases)
function OfflineEarningsUI.dismiss()
  if state.onDismiss then
    state.onDismiss()
  end
  OfflineEarningsUI.hide()
end

-- Check if popup is visible
function OfflineEarningsUI.isVisible(): boolean
  return state.isVisible
end

-- Check if popup is created
function OfflineEarningsUI.isCreated(): boolean
  return state.screenGui ~= nil and state.mainFrame ~= nil
end

-- Set callback for when rewards are claimed
function OfflineEarningsUI.onClaim(callback: (moneyEarned: number, eggsCollected: number) -> ())
  state.onClaim = callback
end

-- Set callback for when popup is dismissed
function OfflineEarningsUI.onDismiss(callback: () -> ())
  state.onDismiss = callback
end

-- Get current earnings being displayed
function OfflineEarningsUI.getDisplayedEarnings(): { money: number, eggs: number, timeAway: number }
  return {
    money = state.moneyEarned,
    eggs = state.eggsCollected,
    timeAway = state.timeAwaySeconds,
  }
end

-- Get the screen GUI
function OfflineEarningsUI.getScreenGui(): ScreenGui?
  return state.screenGui
end

-- Get the main frame
function OfflineEarningsUI.getMainFrame(): Frame?
  return state.mainFrame
end

-- Get default configuration
function OfflineEarningsUI.getDefaultConfig(): PopupConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Get rarity colors (for external use)
function OfflineEarningsUI.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

return OfflineEarningsUI
