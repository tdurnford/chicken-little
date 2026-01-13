--[[
	TradeUI Module
	Creates and manages the trading UI for players to initiate and manage trades.
	Supports trade requests, offer management, and confirmation flow.
]]

local TradeUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

-- Type definitions
export type TradeItem = {
  itemType: "egg" | "chicken",
  itemId: string,
  itemData: any,
}

export type TradeOffer = {
  items: { TradeItem },
  confirmed: boolean,
}

export type TradeState = {
  isActive: boolean,
  partnerId: number?,
  partnerName: string?,
  localOffer: TradeOffer,
  partnerOffer: TradeOffer,
  status: "pending" | "negotiating" | "confirming" | "completed" | "cancelled",
}

export type TradeRequest = {
  fromPlayerId: number,
  fromPlayerName: string,
  timestamp: number,
}

export type UIState = {
  screenGui: ScreenGui?,
  tradeFrame: Frame?,
  requestFrame: Frame?,
  localOfferFrame: ScrollingFrame?,
  partnerOfferFrame: ScrollingFrame?,
  confirmButton: TextButton?,
  cancelButton: TextButton?,
  isVisible: boolean,
  pendingRequests: { TradeRequest },
  onTradeRequest: ((number) -> ())?,
  onTradeAccept: ((number) -> ())?,
  onTradeDecline: ((number) -> ())?,
  onAddItem: ((TradeItem) -> ())?,
  onRemoveItem: ((string) -> ())?,
  onConfirm: (() -> ())?,
  onCancel: (() -> ())?,
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

-- Module state
local uiState: UIState = {
  screenGui = nil,
  tradeFrame = nil,
  requestFrame = nil,
  localOfferFrame = nil,
  partnerOfferFrame = nil,
  confirmButton = nil,
  cancelButton = nil,
  isVisible = false,
  pendingRequests = {},
  onTradeRequest = nil,
  onTradeAccept = nil,
  onTradeDecline = nil,
  onAddItem = nil,
  onRemoveItem = nil,
  onConfirm = nil,
  onCancel = nil,
}

local tradeState: TradeState = {
  isActive = false,
  partnerId = nil,
  partnerName = nil,
  localOffer = { items = {}, confirmed = false },
  partnerOffer = { items = {}, confirmed = false },
  status = "pending",
}

-- Animation settings
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Create a trade item slot
local function createTradeItemSlot(item: TradeItem, isLocal: boolean, layoutOrder: number): Frame
  local slotFrame = Instance.new("Frame")
  slotFrame.Name = "TradeSlot_" .. item.itemId
  slotFrame.Size = UDim2.new(1, -8, 0, 50)
  slotFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
  slotFrame.BorderSizePixel = 0
  slotFrame.LayoutOrder = layoutOrder

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 6)
  corner.Parent = slotFrame

  -- Rarity border
  local rarity = item.itemData.rarity
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

  local stroke = Instance.new("UIStroke")
  stroke.Color = rarityColor
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = slotFrame

  -- Icon
  local icon = Instance.new("TextLabel")
  icon.Name = "Icon"
  icon.Size = UDim2.new(0, 40, 0, 40)
  icon.Position = UDim2.new(0, 5, 0.5, -20)
  icon.BackgroundTransparency = 1
  icon.Text = item.itemType == "egg" and "🥚" or "🐔"
  icon.TextSize = 24
  icon.TextColor3 = rarityColor
  icon.Parent = slotFrame

  -- Item name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, -90, 0, 20)
  nameLabel.Position = UDim2.new(0, 50, 0, 5)
  nameLabel.BackgroundTransparency = 1
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
  nameLabel.TextSize = 13
  nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  nameLabel.Parent = slotFrame

  -- Get display name
  local displayName = ""
  if item.itemType == "egg" then
    local config = EggConfig.get(item.itemData.eggType)
    displayName = config and config.displayName or item.itemData.eggType
  else
    local config = ChickenConfig.get(item.itemData.chickenType)
    displayName = config and config.displayName or item.itemData.chickenType
  end
  nameLabel.Text = displayName

  -- Rarity label
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "RarityLabel"
  rarityLabel.Size = UDim2.new(1, -90, 0, 16)
  rarityLabel.Position = UDim2.new(0, 50, 0, 26)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
  rarityLabel.TextColor3 = rarityColor
  rarityLabel.TextSize = 11
  rarityLabel.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  rarityLabel.Text = rarity
  rarityLabel.Parent = slotFrame

  -- Remove button (only for local items)
  if isLocal then
    local removeButton = Instance.new("TextButton")
    removeButton.Name = "RemoveButton"
    removeButton.Size = UDim2.new(0, 28, 0, 28)
    removeButton.Position = UDim2.new(1, -34, 0.5, -14)
    removeButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
    removeButton.Text = "✕"
    removeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    removeButton.TextSize = 14
    removeButton.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    removeButton.BorderSizePixel = 0
    removeButton.Parent = slotFrame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = removeButton

    removeButton.MouseButton1Click:Connect(function()
      if uiState.onRemoveItem then
        uiState.onRemoveItem(item.itemId)
      end
    end)
  end

  return slotFrame
end

-- Create the offer panel
local function createOfferPanel(
  parent: Frame,
  title: string,
  isLocal: boolean,
  position: UDim2
): ScrollingFrame
  local panelFrame = Instance.new("Frame")
  panelFrame.Name = isLocal and "LocalOfferPanel" or "PartnerOfferPanel"
  panelFrame.Size = UDim2.new(0.5, -12, 1, -60)
  panelFrame.Position = position
  panelFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
  panelFrame.BorderSizePixel = 0
  panelFrame.Parent = parent

  local panelCorner = Instance.new("UICorner")
  panelCorner.CornerRadius = UDim.new(0, 8)
  panelCorner.Parent = panelFrame

  -- Title
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "Title"
  titleLabel.Size = UDim2.new(1, -12, 0, 30)
  titleLabel.Position = UDim2.new(0, 6, 0, 4)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = title
  titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
  titleLabel.TextSize = 14
  titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.Parent = panelFrame

  -- Status indicator
  local statusIndicator = Instance.new("Frame")
  statusIndicator.Name = "StatusIndicator"
  statusIndicator.Size = UDim2.new(0, 12, 0, 12)
  statusIndicator.Position = UDim2.new(1, -18, 0, 12)
  statusIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
  statusIndicator.Parent = panelFrame

  local statusCorner = Instance.new("UICorner")
  statusCorner.CornerRadius = UDim.new(1, 0)
  statusCorner.Parent = statusIndicator

  -- Scrolling content
  local scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "ItemsFrame"
  scrollFrame.Size = UDim2.new(1, -12, 1, -44)
  scrollFrame.Position = UDim2.new(0, 6, 0, 38)
  scrollFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
  scrollFrame.BackgroundTransparency = 0.5
  scrollFrame.BorderSizePixel = 0
  scrollFrame.ScrollBarThickness = 4
  scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
  scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
  scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
  scrollFrame.Parent = panelFrame

  local scrollCorner = Instance.new("UICorner")
  scrollCorner.CornerRadius = UDim.new(0, 6)
  scrollCorner.Parent = scrollFrame

  -- List layout
  local listLayout = Instance.new("UIListLayout")
  listLayout.SortOrder = Enum.SortOrder.LayoutOrder
  listLayout.Padding = UDim.new(0, 4)
  listLayout.Parent = scrollFrame

  -- Padding
  local padding = Instance.new("UIPadding")
  padding.PaddingTop = UDim.new(0, 4)
  padding.PaddingBottom = UDim.new(0, 4)
  padding.PaddingLeft = UDim.new(0, 4)
  padding.PaddingRight = UDim.new(0, 4)
  padding.Parent = scrollFrame

  return scrollFrame
end

-- Create action buttons
local function createActionButtons(parent: Frame): (TextButton, TextButton)
  local buttonFrame = Instance.new("Frame")
  buttonFrame.Name = "ButtonFrame"
  buttonFrame.Size = UDim2.new(1, -16, 0, 44)
  buttonFrame.Position = UDim2.new(0, 8, 1, -52)
  buttonFrame.BackgroundTransparency = 1
  buttonFrame.Parent = parent

  -- Confirm button
  local confirmButton = Instance.new("TextButton")
  confirmButton.Name = "ConfirmButton"
  confirmButton.Size = UDim2.new(0.5, -4, 1, 0)
  confirmButton.Position = UDim2.new(0, 0, 0, 0)
  confirmButton.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
  confirmButton.Text = "✓ Confirm"
  confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  confirmButton.TextSize = 14
  confirmButton.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  confirmButton.BorderSizePixel = 0
  confirmButton.AutoButtonColor = true
  confirmButton.Parent = buttonFrame

  local confirmCorner = Instance.new("UICorner")
  confirmCorner.CornerRadius = UDim.new(0, 8)
  confirmCorner.Parent = confirmButton

  confirmButton.MouseButton1Click:Connect(function()
    if uiState.onConfirm then
      uiState.onConfirm()
    end
  end)

  -- Cancel button
  local cancelButton = Instance.new("TextButton")
  cancelButton.Name = "CancelButton"
  cancelButton.Size = UDim2.new(0.5, -4, 1, 0)
  cancelButton.Position = UDim2.new(0.5, 4, 0, 0)
  cancelButton.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
  cancelButton.Text = "✕ Cancel"
  cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  cancelButton.TextSize = 14
  cancelButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  cancelButton.BorderSizePixel = 0
  cancelButton.AutoButtonColor = true
  cancelButton.Parent = buttonFrame

  local cancelCorner = Instance.new("UICorner")
  cancelCorner.CornerRadius = UDim.new(0, 8)
  cancelCorner.Parent = cancelButton

  cancelButton.MouseButton1Click:Connect(function()
    if uiState.onCancel then
      uiState.onCancel()
    end
  end)

  return confirmButton, cancelButton
end

-- Create the main trade frame
local function createTradeFrame(screenGui: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "TradeFrame"
  frame.AnchorPoint = Vector2.new(0.5, 0.5)
  frame.Position = UDim2.new(0.5, 0, 0.5, 0)
  frame.Size = UDim2.new(0, 500, 0, 400)
  frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
  frame.BackgroundTransparency = 0.1
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.Parent = screenGui

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = frame

  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(80, 80, 100)
  stroke.Thickness = 2
  stroke.Parent = frame

  -- Title bar
  local titleBar = Instance.new("Frame")
  titleBar.Name = "TitleBar"
  titleBar.Size = UDim2.new(1, 0, 0, 40)
  titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  titleBar.BorderSizePixel = 0
  titleBar.Parent = frame

  local titleCorner = Instance.new("UICorner")
  titleCorner.CornerRadius = UDim.new(0, 12)
  titleCorner.Parent = titleBar

  local titleCover = Instance.new("Frame")
  titleCover.Size = UDim2.new(1, 0, 0, 12)
  titleCover.Position = UDim2.new(0, 0, 1, -12)
  titleCover.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  titleCover.BorderSizePixel = 0
  titleCover.Parent = titleBar

  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "Title"
  titleLabel.Size = UDim2.new(1, -20, 1, 0)
  titleLabel.Position = UDim2.new(0, 12, 0, 0)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "🤝 Trade"
  titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  titleLabel.TextSize = 16
  titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.Parent = titleBar

  -- Content container
  local contentContainer = Instance.new("Frame")
  contentContainer.Name = "ContentContainer"
  contentContainer.Size = UDim2.new(1, -16, 1, -100)
  contentContainer.Position = UDim2.new(0, 8, 0, 48)
  contentContainer.BackgroundTransparency = 1
  contentContainer.Parent = frame

  -- Create offer panels
  uiState.localOfferFrame =
    createOfferPanel(contentContainer, "Your Offer", true, UDim2.new(0, 0, 0, 0))
  uiState.partnerOfferFrame =
    createOfferPanel(contentContainer, "Partner's Offer", false, UDim2.new(0.5, 8, 0, 0))

  -- Create action buttons
  uiState.confirmButton, uiState.cancelButton = createActionButtons(frame)

  return frame
end

-- Create the request notification frame
local function createRequestFrame(screenGui: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "RequestFrame"
  frame.AnchorPoint = Vector2.new(0.5, 0)
  frame.Position = UDim2.new(0.5, 0, 0, 60)
  frame.Size = UDim2.new(0, 300, 0, 80)
  frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  frame.BackgroundTransparency = 0.1
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.Parent = screenGui

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 10)
  corner.Parent = frame

  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 150, 255)
  stroke.Thickness = 2
  stroke.Parent = frame

  -- Request text
  local requestText = Instance.new("TextLabel")
  requestText.Name = "RequestText"
  requestText.Size = UDim2.new(1, -16, 0, 30)
  requestText.Position = UDim2.new(0, 8, 0, 8)
  requestText.BackgroundTransparency = 1
  requestText.Text = "Trade Request from Player"
  requestText.TextColor3 = Color3.fromRGB(220, 220, 220)
  requestText.TextSize = 14
  requestText.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  requestText.TextXAlignment = Enum.TextXAlignment.Center
  requestText.Parent = frame

  -- Accept button
  local acceptButton = Instance.new("TextButton")
  acceptButton.Name = "AcceptButton"
  acceptButton.Size = UDim2.new(0.5, -12, 0, 32)
  acceptButton.Position = UDim2.new(0, 8, 1, -40)
  acceptButton.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
  acceptButton.Text = "✓ Accept"
  acceptButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  acceptButton.TextSize = 13
  acceptButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  acceptButton.BorderSizePixel = 0
  acceptButton.AutoButtonColor = true
  acceptButton.Parent = frame

  local acceptCorner = Instance.new("UICorner")
  acceptCorner.CornerRadius = UDim.new(0, 6)
  acceptCorner.Parent = acceptButton

  -- Decline button
  local declineButton = Instance.new("TextButton")
  declineButton.Name = "DeclineButton"
  declineButton.Size = UDim2.new(0.5, -12, 0, 32)
  declineButton.Position = UDim2.new(0.5, 4, 1, -40)
  declineButton.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
  declineButton.Text = "✕ Decline"
  declineButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  declineButton.TextSize = 13
  declineButton.FontFace =
    Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  declineButton.BorderSizePixel = 0
  declineButton.AutoButtonColor = true
  declineButton.Parent = frame

  local declineCorner = Instance.new("UICorner")
  declineCorner.CornerRadius = UDim.new(0, 6)
  declineCorner.Parent = declineButton

  return frame
end

-- Create the screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "TradeUI"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Update the offer display
local function updateOfferDisplay(scrollFrame: ScrollingFrame, offer: TradeOffer, isLocal: boolean)
  if not scrollFrame then
    return
  end

  -- Clear existing items
  for _, child in ipairs(scrollFrame:GetChildren()) do
    if child:IsA("Frame") then
      child:Destroy()
    end
  end

  -- Add items
  for i, item in ipairs(offer.items) do
    local slot = createTradeItemSlot(item, isLocal, i)
    slot.Parent = scrollFrame
  end

  -- Show empty message if no items
  if #offer.items == 0 then
    local emptyLabel = Instance.new("TextLabel")
    emptyLabel.Name = "EmptyLabel"
    emptyLabel.Size = UDim2.new(1, -8, 0, 40)
    emptyLabel.BackgroundTransparency = 1
    emptyLabel.Text = isLocal and "Add items to trade" or "Waiting for items..."
    emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    emptyLabel.TextSize = 12
    emptyLabel.TextWrapped = true
    emptyLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    emptyLabel.Parent = scrollFrame
  end
end

-- Update confirmation status indicator
local function updateConfirmationStatus(panelFrame: Frame?, confirmed: boolean)
  if not panelFrame then
    return
  end
  local parent = panelFrame.Parent
  if not parent then
    return
  end
  local statusIndicator = parent:FindFirstChild("StatusIndicator")
  if statusIndicator then
    statusIndicator.BackgroundColor3 = confirmed and Color3.fromRGB(80, 200, 80)
      or Color3.fromRGB(100, 100, 100)
  end
end

-- Initialize the Trade UI
function TradeUI.create(): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("TradeUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  TradeUI.destroy()

  -- Create UI elements
  uiState.screenGui = createScreenGui(player)
  uiState.tradeFrame = createTradeFrame(uiState.screenGui)
  uiState.requestFrame = createRequestFrame(uiState.screenGui)

  return true
end

-- Destroy the Trade UI
function TradeUI.destroy()
  if uiState.screenGui then
    uiState.screenGui:Destroy()
  end

  uiState.screenGui = nil
  uiState.tradeFrame = nil
  uiState.requestFrame = nil
  uiState.localOfferFrame = nil
  uiState.partnerOfferFrame = nil
  uiState.confirmButton = nil
  uiState.cancelButton = nil
  uiState.isVisible = false
  uiState.pendingRequests = {}

  TradeUI.resetTradeState()
end

-- Reset trade state
function TradeUI.resetTradeState()
  tradeState = {
    isActive = false,
    partnerId = nil,
    partnerName = nil,
    localOffer = { items = {}, confirmed = false },
    partnerOffer = { items = {}, confirmed = false },
    status = "pending",
  }
end

-- Show trade request notification
function TradeUI.showTradeRequest(fromPlayerId: number, fromPlayerName: string)
  local request: TradeRequest = {
    fromPlayerId = fromPlayerId,
    fromPlayerName = fromPlayerName,
    timestamp = os.time(),
  }
  table.insert(uiState.pendingRequests, request)

  if uiState.requestFrame then
    local requestText = uiState.requestFrame:FindFirstChild("RequestText")
    if requestText then
      requestText.Text = "🤝 Trade request from " .. fromPlayerName
    end

    -- Setup button handlers
    local acceptButton = uiState.requestFrame:FindFirstChild("AcceptButton")
    local declineButton = uiState.requestFrame:FindFirstChild("DeclineButton")

    if acceptButton then
      -- Disconnect previous connections
      for _, conn in ipairs(acceptButton:GetPropertyChangedSignal("Parent"):GetConnections() or {}) do
        -- Note: We'll handle this with fresh connections
      end
      acceptButton.MouseButton1Click:Connect(function()
        if uiState.onTradeAccept then
          uiState.onTradeAccept(fromPlayerId)
        end
        TradeUI.hideTradeRequest()
      end)
    end

    if declineButton then
      declineButton.MouseButton1Click:Connect(function()
        if uiState.onTradeDecline then
          uiState.onTradeDecline(fromPlayerId)
        end
        TradeUI.hideTradeRequest()
      end)
    end

    uiState.requestFrame.Visible = true

    -- Animate in
    local tween = TweenService:Create(uiState.requestFrame, FADE_INFO, {
      BackgroundTransparency = 0.1,
    })
    tween:Play()
  end
end

-- Hide trade request notification
function TradeUI.hideTradeRequest()
  if uiState.requestFrame then
    uiState.requestFrame.Visible = false
  end
  -- Remove oldest request
  if #uiState.pendingRequests > 0 then
    table.remove(uiState.pendingRequests, 1)
  end
end

-- Start a trade with a player
function TradeUI.startTrade(partnerId: number, partnerName: string)
  tradeState.isActive = true
  tradeState.partnerId = partnerId
  tradeState.partnerName = partnerName
  tradeState.status = "negotiating"
  tradeState.localOffer = { items = {}, confirmed = false }
  tradeState.partnerOffer = { items = {}, confirmed = false }

  -- Update title
  if uiState.tradeFrame then
    local titleBar = uiState.tradeFrame:FindFirstChild("TitleBar")
    if titleBar then
      local titleLabel = titleBar:FindFirstChild("Title")
      if titleLabel then
        titleLabel.Text = "🤝 Trade with " .. partnerName
      end
    end
  end

  -- Update partner panel title
  if uiState.partnerOfferFrame and uiState.partnerOfferFrame.Parent then
    local title = uiState.partnerOfferFrame.Parent:FindFirstChild("Title")
    if title then
      title.Text = partnerName .. "'s Offer"
    end
  end

  TradeUI.show()
  TradeUI.updateDisplay()
end

-- Add item to local offer
function TradeUI.addItemToOffer(item: TradeItem): boolean
  -- Check if item already in offer
  for _, existingItem in ipairs(tradeState.localOffer.items) do
    if existingItem.itemId == item.itemId then
      return false
    end
  end

  -- Reset confirmation when offer changes
  tradeState.localOffer.confirmed = false

  table.insert(tradeState.localOffer.items, item)
  TradeUI.updateDisplay()

  if uiState.onAddItem then
    uiState.onAddItem(item)
  end

  return true
end

-- Remove item from local offer
function TradeUI.removeItemFromOffer(itemId: string): boolean
  for i, item in ipairs(tradeState.localOffer.items) do
    if item.itemId == itemId then
      table.remove(tradeState.localOffer.items, i)
      -- Reset confirmation when offer changes
      tradeState.localOffer.confirmed = false
      TradeUI.updateDisplay()
      return true
    end
  end
  return false
end

-- Update partner's offer (called from network)
function TradeUI.updatePartnerOffer(items: { TradeItem }, confirmed: boolean)
  tradeState.partnerOffer.items = items
  tradeState.partnerOffer.confirmed = confirmed
  TradeUI.updateDisplay()
end

-- Confirm local offer
function TradeUI.confirmOffer()
  tradeState.localOffer.confirmed = true
  TradeUI.updateDisplay()
end

-- Unconfirm local offer
function TradeUI.unconfirmOffer()
  tradeState.localOffer.confirmed = false
  TradeUI.updateDisplay()
end

-- Check if both parties confirmed
function TradeUI.areBothConfirmed(): boolean
  return tradeState.localOffer.confirmed and tradeState.partnerOffer.confirmed
end

-- Update the display
function TradeUI.updateDisplay()
  updateOfferDisplay(uiState.localOfferFrame, tradeState.localOffer, true)
  updateOfferDisplay(uiState.partnerOfferFrame, tradeState.partnerOffer, false)

  -- Update confirmation status
  if uiState.localOfferFrame then
    updateConfirmationStatus(uiState.localOfferFrame, tradeState.localOffer.confirmed)
  end
  if uiState.partnerOfferFrame then
    updateConfirmationStatus(uiState.partnerOfferFrame, tradeState.partnerOffer.confirmed)
  end

  -- Update confirm button text
  if uiState.confirmButton then
    if tradeState.localOffer.confirmed then
      uiState.confirmButton.Text = "✓ Confirmed"
      uiState.confirmButton.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    else
      uiState.confirmButton.Text = "✓ Confirm"
      uiState.confirmButton.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
    end
  end
end

-- End trade
function TradeUI.endTrade(status: "completed" | "cancelled")
  tradeState.status = status
  tradeState.isActive = false
  TradeUI.hide()
  TradeUI.resetTradeState()
end

-- Show the trade UI
function TradeUI.show()
  uiState.isVisible = true
  if uiState.tradeFrame then
    uiState.tradeFrame.Visible = true

    -- Animate in
    uiState.tradeFrame.Size = UDim2.new(0, 500, 0, 0)
    local tween = TweenService:Create(uiState.tradeFrame, TWEEN_INFO, {
      Size = UDim2.new(0, 500, 0, 400),
    })
    tween:Play()
  end
end

-- Hide the trade UI
function TradeUI.hide()
  uiState.isVisible = false
  if uiState.tradeFrame then
    uiState.tradeFrame.Visible = false
  end
end

-- Toggle visibility
function TradeUI.toggle()
  if uiState.isVisible then
    TradeUI.hide()
  else
    TradeUI.show()
  end
end

-- Check if visible
function TradeUI.isVisible(): boolean
  return uiState.isVisible
end

-- Check if created
function TradeUI.isCreated(): boolean
  return uiState.screenGui ~= nil
end

-- Check if trade is active
function TradeUI.isTradeActive(): boolean
  return tradeState.isActive
end

-- Get current trade state
function TradeUI.getTradeState(): TradeState
  return tradeState
end

-- Get local offer
function TradeUI.getLocalOffer(): TradeOffer
  return tradeState.localOffer
end

-- Get partner offer
function TradeUI.getPartnerOffer(): TradeOffer
  return tradeState.partnerOffer
end

-- Get partner info
function TradeUI.getPartnerInfo(): (number?, string?)
  return tradeState.partnerId, tradeState.partnerName
end

-- Set callback for trade requests
function TradeUI.setOnTradeRequest(callback: (number) -> ())
  uiState.onTradeRequest = callback
end

-- Set callback for accepting trades
function TradeUI.setOnTradeAccept(callback: (number) -> ())
  uiState.onTradeAccept = callback
end

-- Set callback for declining trades
function TradeUI.setOnTradeDecline(callback: (number) -> ())
  uiState.onTradeDecline = callback
end

-- Set callback for adding items
function TradeUI.setOnAddItem(callback: (TradeItem) -> ())
  uiState.onAddItem = callback
end

-- Set callback for removing items
function TradeUI.setOnRemoveItem(callback: (string) -> ())
  uiState.onRemoveItem = callback
end

-- Set callback for confirming
function TradeUI.setOnConfirm(callback: () -> ())
  uiState.onConfirm = callback
end

-- Set callback for cancelling
function TradeUI.setOnCancel(callback: () -> ())
  uiState.onCancel = callback
end

-- Get pending requests
function TradeUI.getPendingRequests(): { TradeRequest }
  return uiState.pendingRequests
end

-- Clear pending requests
function TradeUI.clearPendingRequests()
  uiState.pendingRequests = {}
  TradeUI.hideTradeRequest()
end

-- Get the screen GUI
function TradeUI.getScreenGui(): ScreenGui?
  return uiState.screenGui
end

return TradeUI
