--[[
	MobileTouchControls Module
	Detects mobile devices and creates contextual touch buttons for all actions.
	Replaces keyboard controls (E, F, Escape) with on-screen touch buttons.
]]

local MobileTouchControls = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- Type definitions
export type TouchConfig = {
  buttonSize: UDim2?, -- Size of action buttons
  buttonPadding: number?, -- Padding between buttons
  anchorPosition: UDim2?, -- Anchor position for button container
  fadeInDuration: number?, -- Animation duration for showing buttons
  fadeOutDuration: number?, -- Animation duration for hiding buttons
}

export type ButtonType = "pickup" | "place" | "cancel" | "sell" | "hatch" | "confirm"

export type ButtonConfig = {
  text: string,
  icon: string?,
  color: Color3,
  action: () -> (),
}

export type TouchState = {
  screenGui: ScreenGui?,
  buttonContainer: Frame?,
  buttons: { [ButtonType]: TextButton },
  isVisible: boolean,
  isMobile: boolean,
  activeButtons: { ButtonType },
}

-- Button configurations
local BUTTON_CONFIGS: { [ButtonType]: { text: string, icon: string?, color: Color3 } } = {
  pickup = {
    text = "Pick Up",
    icon = "🐔",
    color = Color3.fromRGB(80, 160, 80),
  },
  place = {
    text = "Place",
    icon = "📍",
    color = Color3.fromRGB(80, 140, 200),
  },
  cancel = {
    text = "Cancel",
    icon = "✕",
    color = Color3.fromRGB(180, 80, 80),
  },
  sell = {
    text = "Sell",
    icon = "💰",
    color = Color3.fromRGB(200, 160, 60),
  },
  hatch = {
    text = "Hatch",
    icon = "🥚",
    color = Color3.fromRGB(160, 100, 200),
  },
  confirm = {
    text = "Confirm",
    icon = "✓",
    color = Color3.fromRGB(80, 180, 80),
  },
}

-- Default configuration
local DEFAULT_CONFIG: TouchConfig = {
  buttonSize = UDim2.new(0, 100, 0, 50),
  buttonPadding = 10,
  anchorPosition = UDim2.new(1, -20, 1, -150),
  fadeInDuration = 0.2,
  fadeOutDuration = 0.15,
}

-- Module state
local state: TouchState = {
  screenGui = nil,
  buttonContainer = nil,
  buttons = {},
  isVisible = false,
  isMobile = false,
  activeButtons = {},
}

local currentConfig: TouchConfig = DEFAULT_CONFIG

-- Button action callbacks (set by external modules)
local buttonActions: { [ButtonType]: () -> () } = {}

-- Detect if device is mobile
local function detectMobile(): boolean
  -- Check for touch capability without mouse
  local isTouchDevice = UserInputService.TouchEnabled

  -- Check if mouse is present (excludes tablets with attached mice)
  local hasMouseInput = UserInputService.MouseEnabled

  -- Check if keyboard is present
  local hasKeyboard = UserInputService.KeyboardEnabled

  -- Check Roblox platform detection
  local guiInset = GuiService:GetGuiInset()
  local hasMobileInset = guiInset.Y > 0 -- Mobile devices typically have top inset

  -- Consider it mobile if: touch enabled AND (no keyboard OR has mobile inset)
  -- This handles phones, tablets, and touch-screen laptops appropriately
  if isTouchDevice and (not hasKeyboard or hasMobileInset) then
    return true
  end

  -- Also consider mobile if touch enabled and no mouse (pure touch device)
  if isTouchDevice and not hasMouseInput then
    return true
  end

  return false
end

-- Create screen GUI for touch controls
local function createScreenGui(player: Player): ScreenGui
  local gui = Instance.new("ScreenGui")
  gui.Name = "MobileTouchControls"
  gui.ResetOnSpawn = false
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.IgnoreGuiInset = false
  gui.DisplayOrder = 80 -- Below modal UIs but above game elements
  gui.Parent = player:WaitForChild("PlayerGui")
  return gui
end

-- Create the button container (right side of screen)
local function createButtonContainer(parent: ScreenGui): Frame
  local container = Instance.new("Frame")
  container.Name = "ButtonContainer"
  container.AnchorPoint = Vector2.new(1, 1)
  container.Position = currentConfig.anchorPosition or DEFAULT_CONFIG.anchorPosition
  container.Size = UDim2.new(0, 110, 0, 300)
  container.BackgroundTransparency = 1
  container.BorderSizePixel = 0
  container.Parent = parent

  -- Layout for stacking buttons
  local layout = Instance.new("UIListLayout")
  layout.Name = "ButtonLayout"
  layout.FillDirection = Enum.FillDirection.Vertical
  layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
  layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
  layout.SortOrder = Enum.SortOrder.LayoutOrder
  layout.Padding = UDim.new(0, currentConfig.buttonPadding or DEFAULT_CONFIG.buttonPadding)
  layout.Parent = container

  return container
end

-- Create a single touch button
local function createButton(parent: Frame, buttonType: ButtonType, layoutOrder: number): TextButton
  local config = BUTTON_CONFIGS[buttonType]
  if not config then
    warn("MobileTouchControls: Unknown button type:", buttonType)
    -- Return a placeholder button
    local placeholder = Instance.new("TextButton")
    placeholder.Parent = parent
    return placeholder
  end

  local button = Instance.new("TextButton")
  button.Name = buttonType .. "Button"
  button.Size = currentConfig.buttonSize or DEFAULT_CONFIG.buttonSize
  button.BackgroundColor3 = config.color
  button.BorderSizePixel = 0
  button.Text = ""
  button.AutoButtonColor = true
  button.LayoutOrder = layoutOrder
  button.Visible = false -- Start hidden
  button.Parent = parent

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = button

  -- Subtle shadow/stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(255, 255, 255)
  stroke.Thickness = 2
  stroke.Transparency = 0.7
  stroke.Parent = button

  -- Icon (left side)
  if config.icon then
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 30, 1, 0)
    icon.Position = UDim2.new(0, 5, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = config.icon
    icon.TextSize = 20
    icon.TextColor3 = Color3.fromRGB(255, 255, 255)
    icon.Parent = button
  end

  -- Label (right side)
  local label = Instance.new("TextLabel")
  label.Name = "Label"
  label.Size = UDim2.new(1, -40, 1, 0)
  label.Position = UDim2.new(0, 35, 0, 0)
  label.BackgroundTransparency = 1
  label.Text = config.text
  label.TextSize = 16
  label.TextColor3 = Color3.fromRGB(255, 255, 255)
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.Parent = button

  -- Connect button press
  button.MouseButton1Click:Connect(function()
    local action = buttonActions[buttonType]
    if action then
      action()
    end
  end)

  return button
end

-- Show a button with animation
local function showButton(button: TextButton)
  if not button then
    return
  end

  button.Visible = true
  button.BackgroundTransparency = 1

  local duration = currentConfig.fadeInDuration or DEFAULT_CONFIG.fadeInDuration
  TweenService
    :Create(button, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
      BackgroundTransparency = 0,
    })
    :Play()
end

-- Hide a button with animation
local function hideButton(button: TextButton)
  if not button then
    return
  end

  local duration = currentConfig.fadeOutDuration or DEFAULT_CONFIG.fadeOutDuration
  local tween = TweenService:Create(
    button,
    TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
    {
      BackgroundTransparency = 1,
    }
  )
  tween:Play()
  tween.Completed:Connect(function()
    if button then
      button.Visible = false
    end
  end)
end

-- Initialize the mobile touch controls
function MobileTouchControls.create(config: TouchConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("MobileTouchControls: No LocalPlayer found")
    return false
  end

  -- Clean up existing
  MobileTouchControls.destroy()

  -- Detect mobile device
  state.isMobile = detectMobile()

  -- If not mobile, don't create UI but return success
  if not state.isMobile then
    return true
  end

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  state.buttonContainer = createButtonContainer(state.screenGui)

  -- Create all button types (hidden by default)
  local layoutOrder = 1
  for buttonType, _ in pairs(BUTTON_CONFIGS) do
    state.buttons[buttonType :: ButtonType] =
      createButton(state.buttonContainer, buttonType :: ButtonType, layoutOrder)
    layoutOrder = layoutOrder + 1
  end

  state.activeButtons = {}
  state.isVisible = true

  return true
end

-- Destroy the touch controls
function MobileTouchControls.destroy()
  if state.screenGui then
    state.screenGui:Destroy()
    state.screenGui = nil
  end

  state.buttonContainer = nil
  state.buttons = {}
  state.activeButtons = {}
  state.isVisible = false
end

-- Check if device is mobile
function MobileTouchControls.isMobile(): boolean
  return state.isMobile
end

-- Check if controls are created
function MobileTouchControls.isCreated(): boolean
  return state.screenGui ~= nil
end

-- Set action callback for a button type
function MobileTouchControls.setAction(buttonType: ButtonType, callback: () -> ())
  buttonActions[buttonType] = callback
end

-- Clear action callback for a button type
function MobileTouchControls.clearAction(buttonType: ButtonType)
  buttonActions[buttonType] = nil
end

-- Show specific buttons
function MobileTouchControls.showButtons(buttonTypes: { ButtonType })
  if not state.isMobile or not state.buttonContainer then
    return
  end

  -- Hide buttons no longer needed
  for _, activeType in ipairs(state.activeButtons) do
    local stillNeeded = false
    for _, newType in ipairs(buttonTypes) do
      if activeType == newType then
        stillNeeded = true
        break
      end
    end
    if not stillNeeded then
      hideButton(state.buttons[activeType])
    end
  end

  -- Show new buttons
  for _, buttonType in ipairs(buttonTypes) do
    local alreadyActive = false
    for _, activeType in ipairs(state.activeButtons) do
      if buttonType == activeType then
        alreadyActive = true
        break
      end
    end
    if not alreadyActive then
      showButton(state.buttons[buttonType])
    end
  end

  state.activeButtons = buttonTypes
end

-- Hide all buttons
function MobileTouchControls.hideAllButtons()
  if not state.isMobile or not state.buttonContainer then
    return
  end

  for _, button in pairs(state.buttons) do
    hideButton(button)
  end

  state.activeButtons = {}
end

-- Show pickup context (near a chicken, not holding)
function MobileTouchControls.showPickupContext()
  MobileTouchControls.showButtons({ "pickup" })
end

-- Show place context (holding a chicken)
function MobileTouchControls.showPlaceContext()
  MobileTouchControls.showButtons({ "place", "cancel" })
end

-- Show sell context (near a chicken, can sell)
function MobileTouchControls.showSellContext()
  MobileTouchControls.showButtons({ "sell" })
end

-- Show sell confirmation context
function MobileTouchControls.showSellConfirmContext()
  MobileTouchControls.showButtons({ "confirm", "cancel" })
end

-- Show hatch context (viewing egg hatch preview)
function MobileTouchControls.showHatchContext()
  MobileTouchControls.showButtons({ "hatch", "cancel" })
end

-- Show combined pickup and sell context (near own chicken)
function MobileTouchControls.showChickenContext()
  MobileTouchControls.showButtons({ "pickup", "sell" })
end

-- Update button text dynamically (e.g., for sell price)
function MobileTouchControls.updateButtonText(buttonType: ButtonType, text: string)
  local button = state.buttons[buttonType]
  if not button then
    return
  end

  local label = button:FindFirstChild("Label") :: TextLabel?
  if label then
    label.Text = text
  end
end

-- Update button color dynamically
function MobileTouchControls.updateButtonColor(buttonType: ButtonType, color: Color3)
  local button = state.buttons[buttonType]
  if button then
    button.BackgroundColor3 = color
  end
end

-- Get current active buttons
function MobileTouchControls.getActiveButtons(): { ButtonType }
  local copy = {}
  for i, buttonType in ipairs(state.activeButtons) do
    copy[i] = buttonType
  end
  return copy
end

-- Check if a specific button is active
function MobileTouchControls.isButtonActive(buttonType: ButtonType): boolean
  for _, activeType in ipairs(state.activeButtons) do
    if activeType == buttonType then
      return true
    end
  end
  return false
end

-- Get the screen GUI (for external positioning)
function MobileTouchControls.getScreenGui(): ScreenGui?
  return state.screenGui
end

-- Get button container (for layout adjustments)
function MobileTouchControls.getButtonContainer(): Frame?
  return state.buttonContainer
end

-- Get a specific button (for custom modifications)
function MobileTouchControls.getButton(buttonType: ButtonType): TextButton?
  return state.buttons[buttonType]
end

-- Get default configuration
function MobileTouchControls.getDefaultConfig(): TouchConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Force mobile mode (for testing on desktop)
function MobileTouchControls.forceMobileMode(enabled: boolean)
  if enabled then
    state.isMobile = true
    -- Create UI if not already created
    if not state.screenGui then
      local player = Players.LocalPlayer
      if player then
        state.screenGui = createScreenGui(player)
        state.buttonContainer = createButtonContainer(state.screenGui)

        local layoutOrder = 1
        for buttonType, _ in pairs(BUTTON_CONFIGS) do
          state.buttons[buttonType :: ButtonType] =
            createButton(state.buttonContainer, buttonType :: ButtonType, layoutOrder)
          layoutOrder = layoutOrder + 1
        end

        state.isVisible = true
      end
    end
  else
    state.isMobile = detectMobile()
    if not state.isMobile and state.screenGui then
      MobileTouchControls.destroy()
    end
  end
end

-- Re-detect mobile status (e.g., after device change)
function MobileTouchControls.refreshMobileDetection()
  local wasMobile = state.isMobile
  state.isMobile = detectMobile()

  if state.isMobile and not wasMobile and not state.screenGui then
    -- Became mobile, create UI
    local player = Players.LocalPlayer
    if player then
      MobileTouchControls.create(currentConfig)
    end
  elseif not state.isMobile and wasMobile and state.screenGui then
    -- Was mobile but now isn't, destroy UI
    MobileTouchControls.destroy()
  end
end

return MobileTouchControls
