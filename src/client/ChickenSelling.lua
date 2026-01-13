--[[
	ChickenSelling Module
	Handles selling chickens with F key and confirmation UI.
	Shows sell price before confirming, integrates with Store.sellChicken.
]]

local ChickenSelling = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

-- Type definitions
export type SellConfig = {
  sellRange: number?, -- Distance within which player can sell chicken
  confirmTimeout: number?, -- Seconds before confirmation dialog auto-cancels
}

export type SellState = {
  pendingChickenId: string?, -- ID of chicken awaiting sale confirmation
  pendingChickenType: string?, -- Type of chicken awaiting sale
  pendingChickenRarity: string?, -- Rarity of chicken awaiting sale
  pendingSpotIndex: number?, -- Spot index of chicken
  pendingAccumulatedMoney: number?, -- Accumulated money on chicken
  isConfirming: boolean,
}

export type SellResult = {
  success: boolean,
  message: string,
  chickenId: string?,
  amountReceived: number?,
  newBalance: number?,
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
local DEFAULT_CONFIG: SellConfig = {
  sellRange = 10,
  confirmTimeout = 10,
}

-- Animation settings
local FADE_DURATION = 0.2
local POPUP_SCALE_DURATION = 0.25

-- Module state
local state: SellState = {
  pendingChickenId = nil,
  pendingChickenType = nil,
  pendingChickenRarity = nil,
  pendingSpotIndex = nil,
  pendingAccumulatedMoney = nil,
  isConfirming = false,
}

local currentConfig: SellConfig = DEFAULT_CONFIG
local screenGui: ScreenGui? = nil
local confirmationFrame: Frame? = nil
local promptFrame: Frame? = nil
local inputConnection: RBXScriptConnection? = nil
local timeoutThread: thread? = nil

-- Callbacks
local onSell: ((chickenId: string, spotIndex: number?, amountReceived: number) -> ())? = nil
local onCancel: (() -> ())? = nil
local getNearbyChicken: ((position: Vector3) -> (string?, number?, string?, string?, number?)?)? =
  nil
local getPlayerData: (() -> any)? = nil
local updatePlayerData: ((data: any) -> ())? = nil

-- Create screen GUI
local function createScreenGui(player: Player): ScreenGui
  local gui = Instance.new("ScreenGui")
  gui.Name = "ChickenSellUI"
  gui.ResetOnSpawn = false
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.IgnoreGuiInset = false
  gui.DisplayOrder = 100 -- Above most other UI
  gui.Parent = player:WaitForChild("PlayerGui")
  return gui
end

-- Create sell prompt (shows near chickens)
local function createPromptUI(parent: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "SellPrompt"
  frame.AnchorPoint = Vector2.new(0.5, 1)
  frame.Size = UDim2.new(0, 150, 0, 40)
  frame.Position = UDim2.new(0.5, 0, 0.9, -20)
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
  label.Text = "[F] Sell"
  label.TextSize = 16
  label.TextColor3 = Color3.fromRGB(255, 255, 255)
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.ZIndex = 9
  label.Parent = frame

  return frame
end

-- Create confirmation dialog
local function createConfirmationUI(parent: ScreenGui): Frame
  -- Backdrop
  local backdrop = Instance.new("Frame")
  backdrop.Name = "SellConfirmBackdrop"
  backdrop.Size = UDim2.new(1, 0, 1, 0)
  backdrop.Position = UDim2.new(0, 0, 0, 0)
  backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
  backdrop.BackgroundTransparency = 0.6
  backdrop.BorderSizePixel = 0
  backdrop.Visible = false
  backdrop.ZIndex = 90
  backdrop.Parent = parent

  -- Main confirmation frame
  local frame = Instance.new("Frame")
  frame.Name = "SellConfirmation"
  frame.AnchorPoint = Vector2.new(0.5, 0.5)
  frame.Size = UDim2.new(0, 300, 0, 200)
  frame.Position = UDim2.new(0.5, 0, 0.5, 0)
  frame.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
  frame.BorderSizePixel = 0
  frame.ZIndex = 91
  frame.Parent = backdrop

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = frame

  local stroke = Instance.new("UIStroke")
  stroke.Name = "RarityStroke"
  stroke.Color = RARITY_COLORS.Common
  stroke.Thickness = 3
  stroke.Parent = frame

  -- Title
  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(1, 0, 0, 30)
  title.Position = UDim2.new(0, 0, 0, 10)
  title.BackgroundTransparency = 1
  title.Text = "Sell Chicken?"
  title.TextSize = 20
  title.TextColor3 = Color3.fromRGB(255, 255, 255)
  title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  title.ZIndex = 92
  title.Parent = frame

  -- Chicken icon
  local icon = Instance.new("TextLabel")
  icon.Name = "ChickenIcon"
  icon.Size = UDim2.new(0, 50, 0, 50)
  icon.Position = UDim2.new(0.5, -25, 0, 45)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 36
  icon.ZIndex = 92
  icon.Parent = frame

  -- Chicken name
  local chickenName = Instance.new("TextLabel")
  chickenName.Name = "ChickenName"
  chickenName.Size = UDim2.new(1, -20, 0, 20)
  chickenName.Position = UDim2.new(0, 10, 0, 95)
  chickenName.BackgroundTransparency = 1
  chickenName.Text = "Chicken Name"
  chickenName.TextSize = 16
  chickenName.TextColor3 = Color3.fromRGB(200, 200, 200)
  chickenName.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  chickenName.ZIndex = 92
  chickenName.Parent = frame

  -- Price display
  local priceLabel = Instance.new("TextLabel")
  priceLabel.Name = "PriceLabel"
  priceLabel.Size = UDim2.new(1, -20, 0, 25)
  priceLabel.Position = UDim2.new(0, 10, 0, 115)
  priceLabel.BackgroundTransparency = 1
  priceLabel.Text = "$0"
  priceLabel.TextSize = 22
  priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
  priceLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  priceLabel.ZIndex = 92
  priceLabel.Parent = frame

  -- Button container
  local buttonContainer = Instance.new("Frame")
  buttonContainer.Name = "ButtonContainer"
  buttonContainer.Size = UDim2.new(1, -20, 0, 40)
  buttonContainer.Position = UDim2.new(0, 10, 1, -50)
  buttonContainer.BackgroundTransparency = 1
  buttonContainer.ZIndex = 92
  buttonContainer.Parent = frame

  local buttonLayout = Instance.new("UIListLayout")
  buttonLayout.FillDirection = Enum.FillDirection.Horizontal
  buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  buttonLayout.Padding = UDim.new(0, 15)
  buttonLayout.Parent = buttonContainer

  -- Confirm button
  local confirmBtn = Instance.new("TextButton")
  confirmBtn.Name = "ConfirmButton"
  confirmBtn.Size = UDim2.new(0, 120, 0, 36)
  confirmBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
  confirmBtn.BorderSizePixel = 0
  confirmBtn.Text = "[F] Confirm"
  confirmBtn.TextSize = 14
  confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
  confirmBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  confirmBtn.ZIndex = 93
  confirmBtn.Parent = buttonContainer

  local confirmCorner = Instance.new("UICorner")
  confirmCorner.CornerRadius = UDim.new(0, 8)
  confirmCorner.Parent = confirmBtn

  -- Cancel button
  local cancelBtn = Instance.new("TextButton")
  cancelBtn.Name = "CancelButton"
  cancelBtn.Size = UDim2.new(0, 120, 0, 36)
  cancelBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
  cancelBtn.BorderSizePixel = 0
  cancelBtn.Text = "[Esc] Cancel"
  cancelBtn.TextSize = 14
  cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
  cancelBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  cancelBtn.ZIndex = 93
  cancelBtn.Parent = buttonContainer

  local cancelCorner = Instance.new("UICorner")
  cancelCorner.CornerRadius = UDim.new(0, 8)
  cancelCorner.Parent = cancelBtn

  -- Button hover effects
  confirmBtn.MouseEnter:Connect(function()
    TweenService
      :Create(confirmBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(70, 200, 100) })
      :Play()
  end)
  confirmBtn.MouseLeave:Connect(function()
    TweenService
      :Create(confirmBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(50, 180, 80) })
      :Play()
  end)

  cancelBtn.MouseEnter:Connect(function()
    TweenService
      :Create(cancelBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(200, 80, 80) })
      :Play()
  end)
  cancelBtn.MouseLeave:Connect(function()
    TweenService
      :Create(cancelBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(180, 60, 60) })
      :Play()
  end)

  -- Button click handlers
  confirmBtn.Activated:Connect(function()
    ChickenSelling.confirmSell()
  end)

  cancelBtn.Activated:Connect(function()
    ChickenSelling.cancelSell()
  end)

  -- Backdrop click to cancel
  backdrop.InputBegan:Connect(function(input)
    if
      input.UserInputType == Enum.UserInputType.MouseButton1
      or input.UserInputType == Enum.UserInputType.Touch
    then
      -- Only cancel if clicking backdrop, not the frame
      local pos = input.Position
      local frameAbsPos = frame.AbsolutePosition
      local frameAbsSize = frame.AbsoluteSize
      local isInsideFrame = pos.X >= frameAbsPos.X
        and pos.X <= frameAbsPos.X + frameAbsSize.X
        and pos.Y >= frameAbsPos.Y
        and pos.Y <= frameAbsPos.Y + frameAbsSize.Y
      if not isInsideFrame then
        ChickenSelling.cancelSell()
      end
    end
  end)

  return backdrop
end

-- Show the confirmation dialog
local function showConfirmation(
  chickenType: string,
  rarity: string,
  sellPrice: number,
  accumulatedMoney: number
)
  if not confirmationFrame then
    return
  end

  local mainFrame = confirmationFrame:FindFirstChild("SellConfirmation") :: Frame?
  if not mainFrame then
    return
  end

  -- Update rarity color
  local stroke = mainFrame:FindFirstChild("RarityStroke") :: UIStroke?
  if stroke then
    stroke.Color = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  end

  -- Update chicken name
  local config = ChickenConfig.get(chickenType)
  local nameLabel = mainFrame:FindFirstChild("ChickenName") :: TextLabel?
  if nameLabel and config then
    nameLabel.Text = config.displayName
    nameLabel.TextColor3 = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  end

  -- Update price display
  local priceLabel = mainFrame:FindFirstChild("PriceLabel") :: TextLabel?
  if priceLabel then
    local totalValue = sellPrice + math.floor(accumulatedMoney)
    local priceText = MoneyScaling.formatCurrency(totalValue)
    if accumulatedMoney > 0 then
      priceText = priceText
        .. " (+"
        .. MoneyScaling.formatCurrency(math.floor(accumulatedMoney))
        .. " accumulated)"
    end
    priceLabel.Text = priceText
  end

  -- Show with animation
  confirmationFrame.Visible = true
  confirmationFrame.BackgroundTransparency = 1

  mainFrame.Size = UDim2.new(0, 0, 0, 0)
  mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

  -- Fade in backdrop
  TweenService
    :Create(confirmationFrame, TweenInfo.new(FADE_DURATION), { BackgroundTransparency = 0.6 })
    :Play()

  -- Scale in popup
  TweenService:Create(
    mainFrame,
    TweenInfo.new(POPUP_SCALE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = UDim2.new(0, 300, 0, 200) }
  ):Play()

  -- Start timeout
  if timeoutThread then
    task.cancel(timeoutThread)
  end
  timeoutThread = task.delay(
    currentConfig.confirmTimeout or DEFAULT_CONFIG.confirmTimeout,
    function()
      if state.isConfirming then
        ChickenSelling.cancelSell()
      end
    end
  )
end

-- Hide the confirmation dialog
local function hideConfirmation()
  if not confirmationFrame then
    return
  end

  if timeoutThread then
    task.cancel(timeoutThread)
    timeoutThread = nil
  end

  local mainFrame = confirmationFrame:FindFirstChild("SellConfirmation") :: Frame?

  -- Scale out popup
  if mainFrame then
    local tween = TweenService:Create(
      mainFrame,
      TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad),
      { Size = UDim2.new(0, 0, 0, 0) }
    )
    tween:Play()
  end

  -- Fade out backdrop
  local backdropTween = TweenService:Create(
    confirmationFrame,
    TweenInfo.new(FADE_DURATION),
    { BackgroundTransparency = 1 }
  )
  backdropTween:Play()
  backdropTween.Completed:Connect(function()
    if confirmationFrame then
      confirmationFrame.Visible = false
    end
  end)
end

-- Update prompt visibility and text
local function updatePrompt(text: string?, visible: boolean)
  if not promptFrame then
    return
  end

  local label = promptFrame:FindFirstChild("PromptLabel") :: TextLabel?
  if label and text then
    label.Text = text
  end

  promptFrame.Visible = visible
end

-- Handle keyboard input
local function handleInput(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.KeyCode == Enum.KeyCode.F then
    if state.isConfirming then
      -- Confirm sell
      ChickenSelling.confirmSell()
    else
      -- Try to start selling
      ChickenSelling.trySell()
    end
  elseif input.KeyCode == Enum.KeyCode.Escape then
    if state.isConfirming then
      ChickenSelling.cancelSell()
    end
  end
end

-- Initialize the selling system
function ChickenSelling.create(config: SellConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("ChickenSelling: No LocalPlayer found")
    return false
  end

  -- Clean up existing
  ChickenSelling.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  screenGui = createScreenGui(player)
  promptFrame = createPromptUI(screenGui)
  confirmationFrame = createConfirmationUI(screenGui)

  -- Setup input handling
  inputConnection = UserInputService.InputBegan:Connect(handleInput)

  return true
end

-- Destroy the selling system
function ChickenSelling.destroy()
  if inputConnection then
    inputConnection:Disconnect()
    inputConnection = nil
  end

  if timeoutThread then
    task.cancel(timeoutThread)
    timeoutThread = nil
  end

  if screenGui then
    screenGui:Destroy()
    screenGui = nil
  end

  confirmationFrame = nil
  promptFrame = nil

  -- Reset state
  state = {
    pendingChickenId = nil,
    pendingChickenType = nil,
    pendingChickenRarity = nil,
    pendingSpotIndex = nil,
    pendingAccumulatedMoney = nil,
    isConfirming = false,
  }
end

-- Try to start selling a chicken at the player's position
function ChickenSelling.trySell(): SellResult
  if state.isConfirming then
    return {
      success = false,
      message = "Already confirming a sale",
      chickenId = state.pendingChickenId,
    }
  end

  -- Use callback to find nearby chicken
  if not getNearbyChicken then
    return {
      success = false,
      message = "No chicken detection callback set",
    }
  end

  local player = Players.LocalPlayer
  if not player or not player.Character then
    return {
      success = false,
      message = "No player character",
    }
  end

  local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not rootPart then
    return {
      success = false,
      message = "No player root part",
    }
  end

  local chickenId, spotIndex, chickenType, rarity, accumulatedMoney =
    getNearbyChicken(rootPart.Position)
  if not chickenId then
    return {
      success = false,
      message = "No chicken nearby to sell",
    }
  end

  -- Get sell price
  local sellPrice = Store.getChickenValue(chickenType or "")
  if sellPrice == 0 then
    return {
      success = false,
      message = "Could not determine chicken value",
    }
  end

  -- Update state
  state.pendingChickenId = chickenId
  state.pendingChickenType = chickenType
  state.pendingChickenRarity = rarity
  state.pendingSpotIndex = spotIndex
  state.pendingAccumulatedMoney = accumulatedMoney or 0
  state.isConfirming = true

  -- Show confirmation dialog
  showConfirmation(chickenType or "", rarity or "Common", sellPrice, accumulatedMoney or 0)
  updatePrompt(nil, false)

  return {
    success = true,
    message = "Showing sell confirmation",
    chickenId = chickenId,
  }
end

-- Confirm the pending sale
function ChickenSelling.confirmSell(): SellResult
  if not state.isConfirming or not state.pendingChickenId then
    return {
      success = false,
      message = "No pending sale to confirm",
    }
  end

  -- Get player data
  if not getPlayerData then
    return {
      success = false,
      message = "No player data callback set",
    }
  end

  local playerData = getPlayerData()
  if not playerData then
    return {
      success = false,
      message = "Could not get player data",
    }
  end

  local chickenId = state.pendingChickenId
  local chickenType = state.pendingChickenType
  local spotIndex = state.pendingSpotIndex

  -- Execute the sale
  local result = Store.sellChicken(playerData, chickenId)

  -- Clear state
  state.pendingChickenId = nil
  state.pendingChickenType = nil
  state.pendingChickenRarity = nil
  state.pendingSpotIndex = nil
  state.pendingAccumulatedMoney = nil
  state.isConfirming = false

  -- Hide confirmation
  hideConfirmation()

  if result.success then
    -- Notify about the sale
    if onSell and result.newBalance then
      local amountReceived = result.newBalance
        - (playerData.money - (result.newBalance - playerData.money))
      onSell(chickenId, spotIndex, result.newBalance - playerData.money + result.newBalance)
    end

    -- Update player data if callback is set
    if updatePlayerData then
      updatePlayerData(playerData)
    end

    return {
      success = true,
      message = result.message,
      chickenId = chickenId,
      amountReceived = result.newBalance,
      newBalance = result.newBalance,
    }
  else
    return {
      success = false,
      message = result.message,
      chickenId = chickenId,
    }
  end
end

-- Cancel the pending sale
function ChickenSelling.cancelSell(): SellResult
  if not state.isConfirming then
    return {
      success = false,
      message = "No pending sale to cancel",
    }
  end

  local chickenId = state.pendingChickenId

  -- Clear state
  state.pendingChickenId = nil
  state.pendingChickenType = nil
  state.pendingChickenRarity = nil
  state.pendingSpotIndex = nil
  state.pendingAccumulatedMoney = nil
  state.isConfirming = false

  -- Hide confirmation
  hideConfirmation()

  -- Trigger callback
  if onCancel then
    onCancel()
  end

  return {
    success = true,
    message = "Sale cancelled",
    chickenId = chickenId,
  }
end

-- Check if currently confirming a sale
function ChickenSelling.isConfirming(): boolean
  return state.isConfirming
end

-- Get the pending chicken info
function ChickenSelling.getPendingChicken(): (string?, string?, string?, number?)
  return state.pendingChickenId,
    state.pendingChickenType,
    state.pendingChickenRarity,
    state.pendingSpotIndex
end

-- Check if UI is created
function ChickenSelling.isCreated(): boolean
  return screenGui ~= nil and confirmationFrame ~= nil
end

-- Set callback for when chicken is sold
-- Callback receives: chickenId, spotIndex, amountReceived
function ChickenSelling.setOnSell(callback: (
  chickenId: string,
  spotIndex: number?,
  amountReceived: number
) -> ())
  onSell = callback
end

-- Set callback for when sale is cancelled
function ChickenSelling.setOnCancel(callback: () -> ())
  onCancel = callback
end

-- Set callback to find nearby chicken
-- Returns: chickenId, spotIndex, chickenType, rarity, accumulatedMoney (or nils)
-- This should be implemented by the game to check 3D world positions
function ChickenSelling.setGetNearbyChicken(
  callback: (
    position: Vector3
  ) -> (string?, number?, string?, string?, number?)
)
  getNearbyChicken = callback
end

-- Set callback to get current player data
function ChickenSelling.setGetPlayerData(callback: () -> any)
  getPlayerData = callback
end

-- Set callback to update player data after sale
function ChickenSelling.setUpdatePlayerData(callback: (data: any) -> ())
  updatePlayerData = callback
end

-- Show sell prompt (call when player is near an owned chicken)
function ChickenSelling.showSellPrompt(chickenType: string?)
  if not state.isConfirming then
    local promptText = "[F] Sell"
    if chickenType then
      local sellPrice = Store.getChickenValue(chickenType)
      if sellPrice > 0 then
        promptText = "[F] Sell (" .. MoneyScaling.formatCurrency(sellPrice) .. ")"
      end
    end
    updatePrompt(promptText, true)
  end
end

-- Hide any prompts
function ChickenSelling.hidePrompt()
  updatePrompt(nil, false)
end

-- Get sell range from config
function ChickenSelling.getSellRange(): number
  return currentConfig.sellRange or DEFAULT_CONFIG.sellRange
end

-- Get current configuration
function ChickenSelling.getConfig(): SellConfig
  local copy = {}
  for key, value in pairs(currentConfig) do
    copy[key] = value
  end
  return copy
end

-- Get default configuration
function ChickenSelling.getDefaultConfig(): SellConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Get rarity colors (for external use)
function ChickenSelling.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

-- Get screen GUI (for integration)
function ChickenSelling.getScreenGui(): ScreenGui?
  return screenGui
end

-- Get the sell value for a chicken type
function ChickenSelling.getSellValue(chickenType: string): number
  return Store.getChickenValue(chickenType)
end

-- Get the total sell value including accumulated money
function ChickenSelling.getTotalSellValue(chickenType: string, accumulatedMoney: number?): number
  return Store.getChickenValue(chickenType) + math.floor(accumulatedMoney or 0)
end

-- Mobile touch support: trigger sell action
function ChickenSelling.touchSell()
  if state.isConfirming then
    ChickenSelling.confirmSell()
  else
    ChickenSelling.trySell()
  end
end

-- Mobile touch support: trigger cancel action
function ChickenSelling.touchCancel()
  if state.isConfirming then
    ChickenSelling.cancelSell()
  end
end

return ChickenSelling
