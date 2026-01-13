--[[
	HatchPreviewUI Module
	Shows a preview of the 3 possible chickens with probabilities before hatching an egg.
	Displays when player selects an egg to hatch, with E key binding and hatch button.
]]

local HatchPreviewUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local EggHatching = require(Shared:WaitForChild("EggHatching"))

-- Type definitions
export type PreviewConfig = {
  anchorPoint: Vector2?,
  position: UDim2?,
  size: UDim2?,
  backgroundColor: Color3?,
}

export type PreviewState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  currentEggId: string?,
  currentEggType: string?,
  isVisible: boolean,
  onHatch: ((eggId: string, eggType: string) -> ())?,
  onCancel: (() -> ())?,
  inputConnection: RBXScriptConnection?,
}

-- Rarity colors for visual distinction
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(180, 180, 180),
  Uncommon = Color3.fromRGB(100, 200, 100),
  Rare = Color3.fromRGB(100, 150, 255),
  Epic = Color3.fromRGB(180, 100, 255),
  Legendary = Color3.fromRGB(255, 180, 50),
  Mythic = Color3.fromRGB(255, 100, 150),
}

-- Default configuration
local DEFAULT_CONFIG: PreviewConfig = {
  anchorPoint = Vector2.new(0.5, 0.5),
  position = UDim2.new(0.5, 0, 0.5, 0),
  size = UDim2.new(0, 420, 0, 380),
  backgroundColor = Color3.fromRGB(30, 30, 40),
}

-- Animation settings
local FADE_IN_DURATION = 0.3
local SCALE_IN_DURATION = 0.25
local OUTCOME_ANIMATION_DELAY = 0.1

-- Module state
local state: PreviewState = {
  screenGui = nil,
  mainFrame = nil,
  currentEggId = nil,
  currentEggType = nil,
  isVisible = false,
  onHatch = nil,
  onCancel = nil,
  inputConnection = nil,
}

local currentConfig: PreviewConfig = DEFAULT_CONFIG

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

  -- Click backdrop to cancel
  local clickDetector = Instance.new("TextButton")
  clickDetector.Name = "ClickDetector"
  clickDetector.Size = UDim2.new(1, 0, 1, 0)
  clickDetector.BackgroundTransparency = 1
  clickDetector.Text = ""
  clickDetector.ZIndex = 1
  clickDetector.Parent = backdrop

  clickDetector.MouseButton1Click:Connect(function()
    HatchPreviewUI.cancel()
  end)

  return backdrop
end

-- Create the main popup frame
local function createMainFrame(parent: ScreenGui, config: PreviewConfig): Frame
  local frame = Instance.new("Frame")
  frame.Name = "HatchPreviewPopup"
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
  stroke.Color = Color3.fromRGB(255, 220, 100)
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = frame

  return frame
end

-- Create header section
local function createHeader(parent: Frame, eggDisplayName: string): TextLabel
  local header = Instance.new("TextLabel")
  header.Name = "Header"
  header.Size = UDim2.new(1, -24, 0, 40)
  header.Position = UDim2.new(0, 12, 0, 12)
  header.BackgroundTransparency = 1
  header.Text = "🥚 " .. eggDisplayName
  header.TextColor3 = Color3.fromRGB(255, 255, 255)
  header.TextSize = 24
  header.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  header.TextXAlignment = Enum.TextXAlignment.Center
  header.ZIndex = 3
  header.Parent = parent
  return header
end

-- Create subtitle
local function createSubtitle(parent: Frame): TextLabel
  local subtitle = Instance.new("TextLabel")
  subtitle.Name = "Subtitle"
  subtitle.Size = UDim2.new(1, -24, 0, 24)
  subtitle.Position = UDim2.new(0, 12, 0, 52)
  subtitle.BackgroundTransparency = 1
  subtitle.Text = "Possible Hatches"
  subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
  subtitle.TextSize = 14
  subtitle.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  subtitle.TextXAlignment = Enum.TextXAlignment.Center
  subtitle.ZIndex = 3
  subtitle.Parent = parent
  return subtitle
end

-- Create a single outcome card
local function createOutcomeCard(
  parent: Frame,
  chickenType: string,
  probability: number,
  index: number
): Frame
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return Instance.new("Frame")
  end

  local cardWidth = 110
  local cardSpacing = 16
  local totalWidth = (cardWidth * 3) + (cardSpacing * 2)
  local startX = (420 - totalWidth) / 2
  local xPosition = startX + ((index - 1) * (cardWidth + cardSpacing))

  local card = Instance.new("Frame")
  card.Name = "OutcomeCard_" .. index
  card.Size = UDim2.new(0, cardWidth, 0, 160)
  card.Position = UDim2.new(0, xPosition, 0, 88)
  card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  card.BackgroundTransparency = 0.2
  card.BorderSizePixel = 0
  card.ZIndex = 3
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 12)
  cardCorner.Parent = card

  -- Rarity-colored border
  local rarity = chickenConfig.rarity
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

  local cardStroke = Instance.new("UIStroke")
  cardStroke.Color = rarityColor
  cardStroke.Thickness = 2
  cardStroke.Transparency = 0.3
  cardStroke.Parent = card

  -- Chicken icon (emoji placeholder)
  local icon = Instance.new("TextLabel")
  icon.Name = "Icon"
  icon.Size = UDim2.new(1, 0, 0, 50)
  icon.Position = UDim2.new(0, 0, 0, 10)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 36
  icon.TextColor3 = rarityColor
  icon.ZIndex = 4
  icon.Parent = card

  -- Chicken name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, -8, 0, 32)
  nameLabel.Position = UDim2.new(0, 4, 0, 60)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = chickenConfig.displayName
  nameLabel.TextScaled = true
  nameLabel.TextWrapped = true
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  nameLabel.ZIndex = 4
  nameLabel.Parent = card

  -- Rarity label
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "RarityLabel"
  rarityLabel.Size = UDim2.new(1, -8, 0, 18)
  rarityLabel.Position = UDim2.new(0, 4, 0, 94)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.Text = rarity
  rarityLabel.TextSize = 12
  rarityLabel.TextColor3 = rarityColor
  rarityLabel.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  rarityLabel.ZIndex = 4
  rarityLabel.Parent = card

  -- Probability display
  local probFrame = Instance.new("Frame")
  probFrame.Name = "ProbabilityFrame"
  probFrame.Size = UDim2.new(1, -16, 0, 28)
  probFrame.Position = UDim2.new(0, 8, 1, -36)
  probFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
  probFrame.BorderSizePixel = 0
  probFrame.ZIndex = 4
  probFrame.Parent = card

  local probCorner = Instance.new("UICorner")
  probCorner.CornerRadius = UDim.new(0, 6)
  probCorner.Parent = probFrame

  local probLabel = Instance.new("TextLabel")
  probLabel.Name = "ProbabilityLabel"
  probLabel.Size = UDim2.new(1, 0, 1, 0)
  probLabel.BackgroundTransparency = 1
  probLabel.Text = probability .. "%"
  probLabel.TextSize = 16
  probLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
  probLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  probLabel.ZIndex = 5
  probLabel.Parent = probFrame

  return card
end

-- Create outcomes container with all 3 cards
local function createOutcomesContainer(parent: Frame, outcomes: { EggConfig.HatchOutcome }): Frame
  local container = Instance.new("Frame")
  container.Name = "OutcomesContainer"
  container.Size = UDim2.new(1, 0, 0, 180)
  container.Position = UDim2.new(0, 0, 0, 80)
  container.BackgroundTransparency = 1
  container.ZIndex = 3
  container.Parent = parent

  -- Create cards for each outcome
  for i, outcome in ipairs(outcomes) do
    createOutcomeCard(parent, outcome.chickenType, outcome.probability, i)
  end

  return container
end

-- Create hatch button
local function createHatchButton(parent: Frame): TextButton
  local button = Instance.new("TextButton")
  button.Name = "HatchButton"
  button.Size = UDim2.new(0, 180, 0, 50)
  button.Position = UDim2.new(0.5, -90, 1, -120)
  button.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
  button.Text = "🐣 Hatch [E]"
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
    HatchPreviewUI.confirmHatch()
  end)

  return button
end

-- Create cancel button
local function createCancelButton(parent: Frame): TextButton
  local button = Instance.new("TextButton")
  button.Name = "CancelButton"
  button.Size = UDim2.new(0, 180, 0, 40)
  button.Position = UDim2.new(0.5, -90, 1, -60)
  button.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
  button.Text = "Cancel"
  button.TextColor3 = Color3.fromRGB(200, 200, 200)
  button.TextSize = 14
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.ZIndex = 3
  button.Parent = parent

  local buttonCorner = Instance.new("UICorner")
  buttonCorner.CornerRadius = UDim.new(0, 8)
  buttonCorner.Parent = button

  button.MouseButton1Click:Connect(function()
    HatchPreviewUI.cancel()
  end)

  return button
end

-- Create screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "HatchPreviewUI"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.DisplayOrder = 99 -- Above most UIs but below critical ones
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Animate the popup appearing
local function animatePopupIn(backdrop: Frame, mainFrame: Frame, config: PreviewConfig)
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

-- Setup E key binding
local function setupKeyBinding()
  if state.inputConnection then
    state.inputConnection:Disconnect()
  end

  state.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
      return
    end

    if input.KeyCode == Enum.KeyCode.E then
      if state.isVisible and state.currentEggId then
        HatchPreviewUI.confirmHatch()
      end
    elseif input.KeyCode == Enum.KeyCode.Escape then
      if state.isVisible then
        HatchPreviewUI.cancel()
      end
    end
  end)
end

-- Clear UI content (for rebuilding with new egg)
local function clearContent()
  if not state.mainFrame then
    return
  end

  for _, child in ipairs(state.mainFrame:GetChildren()) do
    if not child:IsA("UICorner") and not child:IsA("UIStroke") then
      child:Destroy()
    end
  end
end

-- Build UI content for a specific egg
local function buildContent(eggType: string)
  if not state.mainFrame then
    return
  end

  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return
  end

  -- Create UI elements
  createHeader(state.mainFrame, eggConfig.displayName)
  createSubtitle(state.mainFrame)
  createOutcomesContainer(state.mainFrame, eggConfig.hatchOutcomes)
  createHatchButton(state.mainFrame)
  createCancelButton(state.mainFrame)
end

-- Initialize the preview UI (hidden by default)
function HatchPreviewUI.create(config: PreviewConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("HatchPreviewUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  HatchPreviewUI.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  state.screenGui.Enabled = false -- Start hidden

  createBackdrop(state.screenGui)
  state.mainFrame = createMainFrame(state.screenGui, currentConfig)

  -- Setup key bindings
  setupKeyBinding()

  state.isVisible = false

  return true
end

-- Destroy the preview UI
function HatchPreviewUI.destroy()
  if state.inputConnection then
    state.inputConnection:Disconnect()
    state.inputConnection = nil
  end

  if state.screenGui then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.mainFrame = nil
  state.currentEggId = nil
  state.currentEggType = nil
  state.isVisible = false
  state.onHatch = nil
  state.onCancel = nil
end

-- Show the preview for a specific egg
function HatchPreviewUI.show(eggId: string, eggType: string)
  if not state.screenGui or not state.mainFrame then
    warn("HatchPreviewUI: UI not created. Call create() first.")
    return
  end

  -- Validate egg type
  if not EggConfig.isValidType(eggType) then
    warn("HatchPreviewUI: Invalid egg type: " .. eggType)
    return
  end

  state.currentEggId = eggId
  state.currentEggType = eggType

  -- Clear and rebuild content
  clearContent()
  buildContent(eggType)

  -- Show and animate
  state.screenGui.Enabled = true
  state.isVisible = true

  local backdrop = state.screenGui:FindFirstChild("Backdrop")
  if backdrop then
    animatePopupIn(backdrop, state.mainFrame, currentConfig)
  end
end

-- Hide the preview
function HatchPreviewUI.hide()
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
      state.currentEggId = nil
      state.currentEggType = nil
    end)
  else
    state.screenGui.Enabled = false
    state.isVisible = false
    state.currentEggId = nil
    state.currentEggType = nil
  end
end

-- Confirm the hatch and trigger callback
function HatchPreviewUI.confirmHatch()
  if not state.currentEggId or not state.currentEggType then
    return
  end

  local eggId = state.currentEggId
  local eggType = state.currentEggType

  -- Call callback before hiding
  if state.onHatch then
    state.onHatch(eggId, eggType)
  end

  -- Hide the popup
  HatchPreviewUI.hide()
end

-- Cancel without hatching
function HatchPreviewUI.cancel()
  if state.onCancel then
    state.onCancel()
  end
  HatchPreviewUI.hide()
end

-- Check if preview is visible
function HatchPreviewUI.isVisible(): boolean
  return state.isVisible
end

-- Check if preview is created
function HatchPreviewUI.isCreated(): boolean
  return state.screenGui ~= nil and state.mainFrame ~= nil
end

-- Get current egg being previewed
function HatchPreviewUI.getCurrentEgg(): (string?, string?)
  return state.currentEggId, state.currentEggType
end

-- Set callback for when hatch is confirmed
function HatchPreviewUI.onHatch(callback: (eggId: string, eggType: string) -> ())
  state.onHatch = callback
end

-- Set callback for when preview is cancelled
function HatchPreviewUI.onCancel(callback: () -> ())
  state.onCancel = callback
end

-- Get the screen GUI
function HatchPreviewUI.getScreenGui(): ScreenGui?
  return state.screenGui
end

-- Get the main frame
function HatchPreviewUI.getMainFrame(): Frame?
  return state.mainFrame
end

-- Get hatch preview data for an egg type (convenience wrapper)
function HatchPreviewUI.getPreviewData(eggType: string): { EggConfig.HatchOutcome }?
  return EggHatching.getHatchPreview(eggType)
end

-- Get rarity colors (for external use)
function HatchPreviewUI.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

-- Get default configuration
function HatchPreviewUI.getDefaultConfig(): PreviewConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Show the result of a successful hatch
function HatchPreviewUI.showResult(chickenType: string, rarity: string, onDismiss: (() -> ())?)
  if not state.screenGui then
    HatchPreviewUI.create()
  end
  
  if not state.mainFrame then
    return
  end
  
  -- Clear existing content
  for _, child in ipairs(state.mainFrame:GetChildren()) do
    if not child:IsA("UICorner") and not child:IsA("UIStroke") then
      child:Destroy()
    end
  end
  
  -- Get chicken config
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    warn("[HatchPreviewUI] Unknown chicken type:", chickenType)
    return
  end
  
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  
  -- Create "You Got!" header
  local header = Instance.new("TextLabel")
  header.Name = "Header"
  header.Size = UDim2.new(1, 0, 0, 40)
  header.Position = UDim2.new(0, 0, 0, 15)
  header.BackgroundTransparency = 1
  header.Text = "🎉 You Got! 🎉"
  header.TextSize = 24
  header.TextColor3 = Color3.fromRGB(255, 220, 100)
  header.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  header.ZIndex = 3
  header.Parent = state.mainFrame
  
  -- Create large chicken card in center
  local cardSize = 160
  local card = Instance.new("Frame")
  card.Name = "ResultCard"
  card.Size = UDim2.new(0, cardSize, 0, cardSize + 40)
  card.Position = UDim2.new(0.5, -cardSize/2, 0, 65)
  card.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
  card.BorderSizePixel = 0
  card.ZIndex = 3
  card.Parent = state.mainFrame
  
  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 12)
  cardCorner.Parent = card
  
  -- Glowing border
  local cardStroke = Instance.new("UIStroke")
  cardStroke.Color = rarityColor
  cardStroke.Thickness = 3
  cardStroke.Transparency = 0
  cardStroke.Parent = card
  
  -- Large chicken emoji
  local icon = Instance.new("TextLabel")
  icon.Name = "Icon"
  icon.Size = UDim2.new(1, 0, 0, 80)
  icon.Position = UDim2.new(0, 0, 0, 15)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 64
  icon.TextColor3 = rarityColor
  icon.ZIndex = 4
  icon.Parent = card
  
  -- Chicken name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, -10, 0, 36)
  nameLabel.Position = UDim2.new(0, 5, 0, 95)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = chickenConfig.displayName
  nameLabel.TextScaled = true
  nameLabel.TextWrapped = true
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  nameLabel.ZIndex = 4
  nameLabel.Parent = card
  
  -- Rarity badge
  local rarityBadge = Instance.new("Frame")
  rarityBadge.Name = "RarityBadge"
  rarityBadge.Size = UDim2.new(0, 100, 0, 28)
  rarityBadge.Position = UDim2.new(0.5, -50, 0, 135)
  rarityBadge.BackgroundColor3 = rarityColor
  rarityBadge.BorderSizePixel = 0
  rarityBadge.ZIndex = 4
  rarityBadge.Parent = card
  
  local badgeCorner = Instance.new("UICorner")
  badgeCorner.CornerRadius = UDim.new(0, 6)
  badgeCorner.Parent = rarityBadge
  
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "RarityLabel"
  rarityLabel.Size = UDim2.new(1, 0, 1, 0)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.Text = rarity
  rarityLabel.TextSize = 14
  rarityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  rarityLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  rarityLabel.ZIndex = 5
  rarityLabel.Parent = rarityBadge
  
  -- Stats display
  local statsFrame = Instance.new("Frame")
  statsFrame.Name = "StatsFrame"
  statsFrame.Size = UDim2.new(0, 180, 0, 50)
  statsFrame.Position = UDim2.new(0.5, -90, 0, 280)
  statsFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
  statsFrame.BorderSizePixel = 0
  statsFrame.ZIndex = 3
  statsFrame.Parent = state.mainFrame
  
  local statsCorner = Instance.new("UICorner")
  statsCorner.CornerRadius = UDim.new(0, 8)
  statsCorner.Parent = statsFrame
  
  local moneyPerSecond = chickenConfig.moneyPerSecond or 1
  local statsLabel = Instance.new("TextLabel")
  statsLabel.Name = "StatsLabel"
  statsLabel.Size = UDim2.new(1, -10, 1, 0)
  statsLabel.Position = UDim2.new(0, 5, 0, 0)
  statsLabel.BackgroundTransparency = 1
  statsLabel.Text = string.format("💰 $%.2f/sec", moneyPerSecond)
  statsLabel.TextSize = 16
  statsLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
  statsLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  statsLabel.ZIndex = 4
  statsLabel.Parent = statsFrame
  
  -- Dismiss button
  local dismissButton = Instance.new("TextButton")
  dismissButton.Name = "DismissButton"
  dismissButton.Size = UDim2.new(0, 160, 0, 45)
  dismissButton.Position = UDim2.new(0.5, -80, 1, -60)
  dismissButton.BackgroundColor3 = Color3.fromRGB(80, 140, 200)
  dismissButton.Text = "Awesome! ✓"
  dismissButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  dismissButton.TextSize = 18
  dismissButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  dismissButton.BorderSizePixel = 0
  dismissButton.AutoButtonColor = true
  dismissButton.ZIndex = 3
  dismissButton.Parent = state.mainFrame
  
  local buttonCorner = Instance.new("UICorner")
  buttonCorner.CornerRadius = UDim.new(0, 10)
  buttonCorner.Parent = dismissButton
  
  -- Dismiss handler
  dismissButton.MouseButton1Click:Connect(function()
    HatchPreviewUI.hide()
    if onDismiss then
      onDismiss()
    end
  end)
  
  -- Show the UI
  state.isVisible = true
  state.mainFrame.Visible = true
  state.screenGui.Enabled = true
  
  -- Animate in
  local backdrop = state.screenGui:FindFirstChild("Backdrop")
  if backdrop then
    backdrop.BackgroundTransparency = 1
    TweenService:Create(backdrop, TweenInfo.new(FADE_IN_DURATION), {
      BackgroundTransparency = 0.5,
    }):Play()
  end
  
  state.mainFrame.Size = UDim2.new(0, 0, 0, 0)
  state.mainFrame.Position = currentConfig.position
  TweenService:Create(state.mainFrame, TweenInfo.new(SCALE_IN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = currentConfig.size,
  }):Play()
  
  -- Pulse animation on the card border
  task.spawn(function()
    while state.isVisible and card and card.Parent do
      TweenService:Create(cardStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
        Transparency = 0.5,
      }):Play()
      task.wait(0.8)
      if not state.isVisible or not card or not card.Parent then break end
      TweenService:Create(cardStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
        Transparency = 0,
      }):Play()
      task.wait(0.8)
    end
  end)
end

return HatchPreviewUI
