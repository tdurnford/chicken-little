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
}

-- Default configuration
local DEFAULT_CONFIG: HUDConfig = {
  anchorPoint = Vector2.new(0.5, 0),
  position = UDim2.new(0.5, 0, 0, 10),
  size = UDim2.new(0, 280, 0, 70),
  backgroundColor = Color3.fromRGB(30, 30, 40),
  textColor = Color3.fromRGB(255, 215, 0), -- Gold
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
}

-- Create the money icon
local function createMoneyIcon(parent: Frame): ImageLabel
  local icon = Instance.new("ImageLabel")
  icon.Name = "MoneyIcon"
  icon.Size = UDim2.new(0, 32, 0, 32)
  icon.Position = UDim2.new(0, 10, 0.5, -16)
  icon.BackgroundTransparency = 1
  icon.Image = "rbxassetid://6034973115" -- Coin icon
  icon.ImageColor3 = Color3.fromRGB(255, 215, 0)
  icon.ScaleType = Enum.ScaleType.Fit
  icon.Parent = parent
  return icon
end

-- Create the money text label
local function createMoneyLabel(parent: Frame, config: HUDConfig): TextLabel
  local label = Instance.new("TextLabel")
  label.Name = "MoneyLabel"
  label.Size = UDim2.new(1, -55, 0, 30)
  label.Position = UDim2.new(0, 50, 0, 8)
  label.BackgroundTransparency = 1
  label.Text = "$0"
  label.TextColor3 = config.textColor or DEFAULT_CONFIG.textColor
  label.TextSize = 28
  label.FontFace = config.fontFace or DEFAULT_CONFIG.fontFace
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.TextScaled = false
  label.Parent = parent
  return label
end

-- Create money per second label
local function createMoneyPerSecLabel(parent: Frame, config: HUDConfig): TextLabel
  local label = Instance.new("TextLabel")
  label.Name = "MoneyPerSecLabel"
  label.Size = UDim2.new(1, -55, 0, 18)
  label.Position = UDim2.new(0, 50, 0, 40)
  label.BackgroundTransparency = 1
  label.Text = "+$0/s"
  label.TextColor3 = Color3.fromRGB(150, 200, 150) -- Lighter green
  label.TextSize = 14
  label.FontFace = config.fontFace or DEFAULT_CONFIG.fontFace
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.TextTransparency = 0.2
  label.Parent = parent
  return label
end

-- Create the main HUD frame
local function createMainFrame(screenGui: ScreenGui, config: HUDConfig): Frame
  local frame = Instance.new("Frame")
  frame.Name = "MoneyFrame"
  frame.AnchorPoint = config.anchorPoint or DEFAULT_CONFIG.anchorPoint
  frame.Position = config.position or DEFAULT_CONFIG.position
  frame.Size = config.size or DEFAULT_CONFIG.size
  frame.BackgroundColor3 = config.backgroundColor or DEFAULT_CONFIG.backgroundColor
  frame.BackgroundTransparency = 0.3
  frame.BorderSizePixel = 0
  frame.Parent = screenGui

  -- Add rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = frame

  -- Add subtle stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(80, 80, 100)
  stroke.Thickness = 2
  stroke.Transparency = 0.5
  stroke.Parent = frame

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

  local targetScale = isGain and 1.15 or 0.95

  -- Scale up
  local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
  local scaleTween = TweenService:Create(state.moneyLabel, tweenInfo, {
    TextSize = 28 * targetScale,
  })
  scaleTween:Play()

  -- Scale back
  scaleTween.Completed:Connect(function()
    local returnTween = TweenService:Create(
      state.moneyLabel,
      TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { TextSize = 28 }
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
  createMoneyIcon(state.mainFrame)
  state.moneyLabel = createMoneyLabel(state.mainFrame, hudConfig)
  state.moneyPerSecLabel = createMoneyPerSecLabel(state.mainFrame, hudConfig)

  -- Initialize display
  updateMoneyDisplay(false)
  updateMoneyPerSecDisplay()

  return true
end

-- Destroy the HUD
function MainHUD.destroy()
  if state.animationConnection then
    state.animationConnection:Disconnect()
    state.animationConnection = nil
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

-- Set money per second display
function MainHUD.setMoneyPerSecond(amount: number)
  state.moneyPerSecond = math.max(0, amount)
  updateMoneyPerSecDisplay()
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

-- Get configuration defaults
function MainHUD.getDefaultConfig(): HUDConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

return MainHUD
