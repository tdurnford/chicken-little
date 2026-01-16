--[[
	ChickenPickup Module
	Handles picking up chickens with E key and placing them in new spots.
	Provides visual indicator of held chicken and manages placement flow.
]]

local ChickenPickup = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

-- Type definitions
export type PickupConfig = {
  pickupRange: number?, -- Distance within which player can pick up chicken
  indicatorSize: UDim2?, -- Size of held chicken indicator
  indicatorOffset: Vector2?, -- Offset from cursor
}

export type PickupState = {
  heldChickenId: string?, -- ID of currently held chicken
  heldChickenType: string?, -- Type of currently held chicken
  heldChickenRarity: string?, -- Rarity of currently held chicken
  previousSpotIndex: number?, -- Spot chicken was picked up from
  isHolding: boolean,
}

export type PickupResult = {
  success: boolean,
  message: string,
  chickenId: string?,
  chickenType: string?,
}

export type PlaceResult = {
  success: boolean,
  message: string,
  spotIndex: number?,
  chickenId: string?,
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
local DEFAULT_CONFIG: PickupConfig = {
  pickupRange = 10,
  indicatorSize = UDim2.new(0, 80, 0, 80),
  indicatorOffset = Vector2.new(0, -20),
}

-- Animation settings
local INDICATOR_FADE_DURATION = 0.2
local INDICATOR_BOUNCE_DURATION = 0.15

-- Module state
local state: PickupState = {
  heldChickenId = nil,
  heldChickenType = nil,
  heldChickenRarity = nil,
  previousSpotIndex = nil,
  isHolding = false,
}

local currentConfig: PickupConfig = DEFAULT_CONFIG
local screenGui: ScreenGui? = nil
local indicatorFrame: Frame? = nil
local inputConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil

-- Callbacks
local onPickup: ((chickenId: string, spotIndex: number) -> ())? = nil
local onPlace: ((chickenId: string, newSpotIndex: number) -> ())? = nil
local onCancel: (() -> ())? = nil
local getNearbyChicken: ((position: Vector3) -> (string?, number?)?)? = nil
local getAvailableSpot: ((position: Vector3) -> number?)? = nil
local getPlayerData: (() -> any)? = nil

-- Create screen GUI for indicator
local function createScreenGui(player: Player): ScreenGui
  local gui = Instance.new("ScreenGui")
  gui.Name = "ChickenPickupUI"
  gui.ResetOnSpawn = false
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.IgnoreGuiInset = false
  gui.DisplayOrder = 95 -- Below most modal UIs
  gui.Parent = player:WaitForChild("PlayerGui")
  return gui
end

-- Create the held chicken indicator
local function createIndicator(parent: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "HeldChickenIndicator"
  frame.AnchorPoint = Vector2.new(0.5, 0.5)
  frame.Size = currentConfig.indicatorSize or DEFAULT_CONFIG.indicatorSize
  frame.Position = UDim2.new(0.5, 0, 0.5, 0)
  frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  frame.BackgroundTransparency = 0.2
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.ZIndex = 10
  frame.Parent = parent

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = frame

  -- Border stroke (colored by rarity)
  local stroke = Instance.new("UIStroke")
  stroke.Name = "RarityStroke"
  stroke.Color = RARITY_COLORS.Common
  stroke.Thickness = 3
  stroke.Transparency = 0
  stroke.Parent = frame

  -- Chicken icon
  local icon = Instance.new("TextLabel")
  icon.Name = "ChickenIcon"
  icon.Size = UDim2.new(1, 0, 0.7, 0)
  icon.Position = UDim2.new(0, 0, 0, 0)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 36
  icon.TextColor3 = Color3.fromRGB(255, 255, 255)
  icon.ZIndex = 11
  icon.Parent = frame

  -- Held label
  local label = Instance.new("TextLabel")
  label.Name = "HeldLabel"
  label.Size = UDim2.new(1, -8, 0.3, 0)
  label.Position = UDim2.new(0, 4, 0.7, 0)
  label.BackgroundTransparency = 1
  label.Text = "Holding"
  label.TextScaled = true
  label.TextColor3 = Color3.fromRGB(200, 200, 200)
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  label.ZIndex = 11
  label.Parent = frame

  return frame
end

-- Create prompt UI that shows near chickens/spots
local function createPromptUI(parent: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "ActionPrompt"
  frame.AnchorPoint = Vector2.new(0.5, 1)
  frame.Size = UDim2.new(0, 150, 0, 40)
  frame.Position = UDim2.new(0.5, -85, 0.9, -20) -- Offset left to avoid overlap with sell prompt
  frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
  frame.BackgroundTransparency = 0.3
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.ZIndex = 8
  frame.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = frame

  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 100, 120)
  stroke.Thickness = 1
  stroke.Parent = frame

  local label = Instance.new("TextLabel")
  label.Name = "PromptLabel"
  label.Size = UDim2.new(1, -8, 1, 0)
  label.Position = UDim2.new(0, 4, 0, 0)
  label.BackgroundTransparency = 1
  label.Text = "[E] Pick Up"
  label.TextSize = 16
  label.TextColor3 = Color3.fromRGB(255, 255, 255)
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.ZIndex = 9
  label.Parent = frame

  return frame
end

-- Update indicator position to follow mouse
local function updateIndicatorPosition()
  if not indicatorFrame or not state.isHolding then
    return
  end

  local mouse = Players.LocalPlayer:GetMouse()
  local offset = currentConfig.indicatorOffset or DEFAULT_CONFIG.indicatorOffset
  indicatorFrame.Position = UDim2.new(0, mouse.X + offset.X, 0, mouse.Y + offset.Y)
end

-- Show the held chicken indicator
local function showIndicator(chickenType: string, rarity: string)
  if not indicatorFrame then
    return
  end

  -- Update rarity color
  local stroke = indicatorFrame:FindFirstChild("RarityStroke") :: UIStroke?
  if stroke then
    stroke.Color = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  end

  -- Get chicken config for display name
  local config = ChickenConfig.get(chickenType)
  local label = indicatorFrame:FindFirstChild("HeldLabel") :: TextLabel?
  if label and config then
    label.Text = config.displayName
    label.TextColor3 = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  end

  -- Show with animation
  indicatorFrame.Visible = true
  indicatorFrame.Size = UDim2.new(0, 0, 0, 0)

  local targetSize = currentConfig.indicatorSize or DEFAULT_CONFIG.indicatorSize
  TweenService:Create(
    indicatorFrame,
    TweenInfo.new(INDICATOR_BOUNCE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = targetSize }
  ):Play()
end

-- Hide the held chicken indicator
local function hideIndicator()
  if not indicatorFrame then
    return
  end

  local tween = TweenService:Create(
    indicatorFrame,
    TweenInfo.new(INDICATOR_FADE_DURATION, Enum.EasingStyle.Quad),
    { Size = UDim2.new(0, 0, 0, 0) }
  )
  tween:Play()
  tween.Completed:Connect(function()
    if indicatorFrame then
      indicatorFrame.Visible = false
    end
  end)
end

-- Update action prompt visibility and text
local function updatePrompt(text: string?, visible: boolean)
  if not screenGui then
    return
  end

  local prompt = screenGui:FindFirstChild("ActionPrompt") :: Frame?
  if not prompt then
    return
  end

  local label = prompt:FindFirstChild("PromptLabel") :: TextLabel?
  if label and text then
    label.Text = text
  end

  prompt.Visible = visible
end

-- Handle keyboard input
local function handleInput(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.KeyCode == Enum.KeyCode.E then
    if state.isHolding then
      -- Try to place chicken
      ChickenPickup.tryPlace()
    else
      -- Try to pick up chicken
      ChickenPickup.tryPickup()
    end
  elseif input.KeyCode == Enum.KeyCode.Escape then
    if state.isHolding then
      -- Cancel pickup and return chicken to original spot
      ChickenPickup.cancelPickup()
    end
  end
end

-- Initialize the pickup system
function ChickenPickup.create(config: PickupConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("ChickenPickup: No LocalPlayer found")
    return false
  end

  -- Clean up existing
  ChickenPickup.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  screenGui = createScreenGui(player)
  indicatorFrame = createIndicator(screenGui)
  createPromptUI(screenGui)

  -- Setup input handling
  inputConnection = UserInputService.InputBegan:Connect(handleInput)

  -- Setup render step for indicator following
  renderConnection = RunService.RenderStepped:Connect(updateIndicatorPosition)

  return true
end

-- Destroy the pickup system
function ChickenPickup.destroy()
  if inputConnection then
    inputConnection:Disconnect()
    inputConnection = nil
  end

  if renderConnection then
    renderConnection:Disconnect()
    renderConnection = nil
  end

  if screenGui then
    screenGui:Destroy()
    screenGui = nil
  end

  indicatorFrame = nil

  -- Reset state
  state = {
    heldChickenId = nil,
    heldChickenType = nil,
    heldChickenRarity = nil,
    previousSpotIndex = nil,
    isHolding = false,
  }
end

-- Try to pick up a chicken at the player's position
function ChickenPickup.tryPickup(): PickupResult
  if state.isHolding then
    return {
      success = false,
      message = "Already holding a chicken",
      chickenId = state.heldChickenId,
      chickenType = state.heldChickenType,
    }
  end

  -- Use callback to find nearby chicken
  if not getNearbyChicken then
    return {
      success = false,
      message = "No chicken detection callback set",
      chickenId = nil,
      chickenType = nil,
    }
  end

  local player = Players.LocalPlayer
  if not player or not player.Character then
    return {
      success = false,
      message = "No player character",
      chickenId = nil,
      chickenType = nil,
    }
  end

  local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not rootPart then
    return {
      success = false,
      message = "No player root part",
      chickenId = nil,
      chickenType = nil,
    }
  end

  local chickenId, spotIndex = getNearbyChicken(rootPart.Position)
  if not chickenId or not spotIndex then
    return {
      success = false,
      message = "No chicken nearby to pick up",
      chickenId = nil,
      chickenType = nil,
    }
  end

  -- Get player data for chicken info
  if not getPlayerData then
    return {
      success = false,
      message = "No player data callback set",
      chickenId = nil,
      chickenType = nil,
    }
  end

  local playerData = getPlayerData()
  if not playerData then
    return {
      success = false,
      message = "Could not get player data",
      chickenId = nil,
      chickenType = nil,
    }
  end

  -- Find chicken in placed chickens
  local chicken = ChickenPlacement.getChickenAtSpot(playerData, spotIndex)
  if not chicken or chicken.id ~= chickenId then
    return {
      success = false,
      message = "Chicken not found at spot",
      chickenId = nil,
      chickenType = nil,
    }
  end

  -- Update state
  state.heldChickenId = chickenId
  state.heldChickenType = chicken.chickenType
  state.heldChickenRarity = chicken.rarity
  state.previousSpotIndex = spotIndex
  state.isHolding = true

  -- Show indicator
  showIndicator(chicken.chickenType, chicken.rarity)
  updatePrompt("[E] Place | [Esc] Cancel", true)

  -- Trigger callback
  if onPickup then
    onPickup(chickenId, spotIndex)
  end

  return {
    success = true,
    message = "Picked up chicken",
    chickenId = chickenId,
    chickenType = chicken.chickenType,
  }
end

-- Try to place the held chicken in a new spot
function ChickenPickup.tryPlace(): PlaceResult
  if not state.isHolding or not state.heldChickenId then
    return {
      success = false,
      message = "Not holding a chicken",
      spotIndex = nil,
      chickenId = nil,
    }
  end

  -- Use callback to find available spot
  if not getAvailableSpot then
    return {
      success = false,
      message = "No spot detection callback set",
      spotIndex = nil,
      chickenId = state.heldChickenId,
    }
  end

  local player = Players.LocalPlayer
  if not player or not player.Character then
    return {
      success = false,
      message = "No player character",
      spotIndex = nil,
      chickenId = state.heldChickenId,
    }
  end

  local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not rootPart then
    return {
      success = false,
      message = "No player root part",
      spotIndex = nil,
      chickenId = state.heldChickenId,
    }
  end

  local newSpotIndex = getAvailableSpot(rootPart.Position)
  if not newSpotIndex then
    return {
      success = false,
      message = "No available spot nearby",
      spotIndex = nil,
      chickenId = state.heldChickenId,
    }
  end

  local chickenId = state.heldChickenId

  -- Clear state
  state.heldChickenId = nil
  state.heldChickenType = nil
  state.heldChickenRarity = nil
  state.previousSpotIndex = nil
  state.isHolding = false

  -- Hide indicator
  hideIndicator()
  updatePrompt(nil, false)

  -- Trigger callback
  if onPlace then
    onPlace(chickenId, newSpotIndex)
  end

  return {
    success = true,
    message = "Placed chicken at spot " .. newSpotIndex,
    spotIndex = newSpotIndex,
    chickenId = chickenId,
  }
end

-- Cancel pickup and return chicken to original spot
function ChickenPickup.cancelPickup(): PlaceResult
  if not state.isHolding or not state.heldChickenId then
    return {
      success = false,
      message = "Not holding a chicken",
      spotIndex = nil,
      chickenId = nil,
    }
  end

  local chickenId = state.heldChickenId
  local originalSpot = state.previousSpotIndex

  -- Clear state
  state.heldChickenId = nil
  state.heldChickenType = nil
  state.heldChickenRarity = nil
  state.previousSpotIndex = nil
  state.isHolding = false

  -- Hide indicator
  hideIndicator()
  updatePrompt(nil, false)

  -- Trigger callback
  if onCancel then
    onCancel()
  end

  -- Return to original spot
  if onPlace and originalSpot then
    onPlace(chickenId, originalSpot)
  end

  return {
    success = true,
    message = "Cancelled pickup, returning to spot " .. tostring(originalSpot),
    spotIndex = originalSpot,
    chickenId = chickenId,
  }
end

-- Check if currently holding a chicken
function ChickenPickup.isHolding(): boolean
  return state.isHolding
end

-- Get the currently held chicken info
function ChickenPickup.getHeldChicken(): (string?, string?, string?)
  return state.heldChickenId, state.heldChickenType, state.heldChickenRarity
end

-- Get the previous spot index (where chicken was picked up from)
function ChickenPickup.getPreviousSpot(): number?
  return state.previousSpotIndex
end

-- Check if UI is created
function ChickenPickup.isCreated(): boolean
  return screenGui ~= nil and indicatorFrame ~= nil
end

-- Set callback for when chicken is picked up
-- Callback receives: chickenId, spotIndex
function ChickenPickup.setOnPickup(callback: (chickenId: string, spotIndex: number) -> ())
  onPickup = callback
end

-- Set callback for when chicken is placed
-- Callback receives: chickenId, newSpotIndex
function ChickenPickup.setOnPlace(callback: (chickenId: string, newSpotIndex: number) -> ())
  onPlace = callback
end

-- Set callback for when pickup is cancelled
function ChickenPickup.setOnCancel(callback: () -> ())
  onCancel = callback
end

-- Set callback to find nearby chicken (returns chickenId, spotIndex or nil)
-- This should be implemented by the game to check 3D world positions
function ChickenPickup.setGetNearbyChicken(callback: (position: Vector3) -> (string?, number?))
  getNearbyChicken = callback
end

-- Set callback to find available spot near position
-- This should be implemented by the game to check 3D world positions
function ChickenPickup.setGetAvailableSpot(callback: (position: Vector3) -> number?)
  getAvailableSpot = callback
end

-- Set callback to get current player data
function ChickenPickup.setGetPlayerData(callback: () -> any)
  getPlayerData = callback
end

-- Show pickup prompt (call when player is near a chicken)
function ChickenPickup.showPickupPrompt()
  if not state.isHolding then
    updatePrompt("[E] Pick Up", true)
  end
end

-- Show place prompt (call when player is near an empty spot while holding)
function ChickenPickup.showPlacePrompt()
  if state.isHolding then
    updatePrompt("[E] Place | [Esc] Cancel", true)
  end
end

-- Hide any prompts
function ChickenPickup.hidePrompt()
  updatePrompt(nil, false)
end

-- Get pickup range from config
function ChickenPickup.getPickupRange(): number
  return currentConfig.pickupRange or DEFAULT_CONFIG.pickupRange
end

-- Get current configuration
function ChickenPickup.getConfig(): PickupConfig
  local copy = {}
  for key, value in pairs(currentConfig) do
    copy[key] = value
  end
  return copy
end

-- Get default configuration
function ChickenPickup.getDefaultConfig(): PickupConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Get rarity colors (for external use)
function ChickenPickup.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

-- Get screen GUI (for integration)
function ChickenPickup.getScreenGui(): ScreenGui?
  return screenGui
end

-- Mobile touch support: trigger pickup action
function ChickenPickup.touchPickup()
  if state.isHolding then
    ChickenPickup.tryPlace()
  else
    ChickenPickup.tryPickup()
  end
end

-- Mobile touch support: trigger cancel action
function ChickenPickup.touchCancel()
  if state.isHolding then
    ChickenPickup.cancelPickup()
  end
end

-- Clear holding state without triggering callbacks
-- Used when chicken was returned to inventory via server call
function ChickenPickup.clearHoldingState()
  state.heldChickenId = nil
  state.heldChickenType = nil
  state.heldChickenRarity = nil
  state.previousSpotIndex = nil
  state.isHolding = false
  hideIndicator()
  updatePrompt(nil, false)
end

return ChickenPickup
