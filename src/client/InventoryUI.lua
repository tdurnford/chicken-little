--[[
	InventoryUI Module
	Creates and manages the inventory UI showing eggs and chickens the player owns.
	Supports item selection, action buttons, and scrolling for large inventories.
]]

local InventoryUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

-- Type definitions
export type InventoryConfig = {
  anchorPoint: Vector2?,
  position: UDim2?,
  size: UDim2?,
  backgroundColor: Color3?,
  slotSize: number?,
  slotPadding: number?,
}

export type SelectedItem = {
  itemType: "egg" | "chicken",
  itemId: string,
  itemData: any,
}

export type InventoryState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  tabFrame: Frame?,
  contentFrame: ScrollingFrame?,
  actionFrame: Frame?,
  selectedItem: SelectedItem?,
  currentTab: "eggs" | "chickens",
  isVisible: boolean,
  slots: { [string]: Frame },
  onItemSelected: ((SelectedItem?) -> ())?,
  onAction: ((string, SelectedItem) -> ())?,
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
local DEFAULT_CONFIG: InventoryConfig = {
  anchorPoint = Vector2.new(1, 0.5),
  position = UDim2.new(1, -20, 0.5, 0),
  size = UDim2.new(0, 320, 0, 450),
  backgroundColor = Color3.fromRGB(30, 30, 40),
  slotSize = 70,
  slotPadding = 8,
}

-- Helper: Format money rate for display ($/s)
local function formatMoneyRate(rate: number): string
  if rate >= 1000 then
    return string.format("$%.1fK/s", rate / 1000)
  elseif rate >= 100 then
    return string.format("$%.0f/s", rate)
  elseif rate >= 10 then
    return string.format("$%.1f/s", rate)
  else
    return string.format("$%.2f/s", rate)
  end
end

-- Module state
local state: InventoryState = {
  screenGui = nil,
  mainFrame = nil,
  tabFrame = nil,
  contentFrame = nil,
  actionFrame = nil,
  selectedItem = nil,
  currentTab = "eggs",
  isVisible = false, -- Start hidden, player opens with I key
  slots = {},
  onItemSelected = nil,
  onAction = nil,
}

-- Callback for visibility changes
local onVisibilityChanged: ((boolean) -> ())? = nil

-- Cached player data for refreshing inventory when opened
local cachedPlayerData: any = nil

local currentConfig: InventoryConfig = DEFAULT_CONFIG

-- Create a tab button
local function createTabButton(
  parent: Frame,
  text: string,
  tabType: "eggs" | "chickens",
  position: UDim2
): TextButton
  local button = Instance.new("TextButton")
  button.Name = tabType .. "Tab"
  button.Size = UDim2.new(0.5, -4, 1, 0)
  button.Position = position
  button.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
  button.Text = text
  button.TextColor3 = Color3.fromRGB(200, 200, 200)
  button.TextSize = 14
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = button

  button.MouseButton1Click:Connect(function()
    InventoryUI.setTab(tabType)
  end)

  return button
end

-- Create the tab frame with eggs/chickens tabs
local function createTabFrame(parent: Frame): Frame
  local tabFrame = Instance.new("Frame")
  tabFrame.Name = "TabFrame"
  tabFrame.Size = UDim2.new(1, -16, 0, 36)
  tabFrame.Position = UDim2.new(0, 8, 0, 8)
  tabFrame.BackgroundTransparency = 1
  tabFrame.Parent = parent

  createTabButton(tabFrame, "🥚 Eggs", "eggs", UDim2.new(0, 0, 0, 0))
  createTabButton(tabFrame, "🐔 Chickens", "chickens", UDim2.new(0.5, 4, 0, 0))

  return tabFrame
end

-- Create the scrolling content frame
local function createContentFrame(parent: Frame): ScrollingFrame
  local scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "ContentFrame"
  scrollFrame.Size = UDim2.new(1, -16, 1, -110)
  scrollFrame.Position = UDim2.new(0, 8, 0, 52)
  scrollFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
  scrollFrame.BackgroundTransparency = 0.3
  scrollFrame.BorderSizePixel = 0
  scrollFrame.ScrollBarThickness = 6
  scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
  scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
  scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
  scrollFrame.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = scrollFrame

  -- Grid layout for items
  local gridLayout = Instance.new("UIGridLayout")
  gridLayout.CellSize = UDim2.new(0, currentConfig.slotSize or 70, 0, currentConfig.slotSize or 70)
  gridLayout.CellPadding =
    UDim2.new(0, currentConfig.slotPadding or 8, 0, currentConfig.slotPadding or 8)
  gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
  gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  gridLayout.Parent = scrollFrame

  -- Padding
  local padding = Instance.new("UIPadding")
  padding.PaddingTop = UDim.new(0, 8)
  padding.PaddingBottom = UDim.new(0, 8)
  padding.PaddingLeft = UDim.new(0, 8)
  padding.PaddingRight = UDim.new(0, 8)
  padding.Parent = scrollFrame

  return scrollFrame
end

-- Create the action buttons frame
local function createActionFrame(parent: Frame): Frame
  local actionFrame = Instance.new("Frame")
  actionFrame.Name = "ActionFrame"
  actionFrame.Size = UDim2.new(1, -16, 0, 44)
  actionFrame.Position = UDim2.new(0, 8, 1, -52)
  actionFrame.BackgroundTransparency = 1
  actionFrame.Parent = parent

  return actionFrame
end

-- Create an action button
local function createActionButton(
  parent: Frame,
  text: string,
  actionType: string,
  position: UDim2,
  color: Color3
): TextButton
  local button = Instance.new("TextButton")
  button.Name = actionType .. "Button"
  button.Size = UDim2.new(0.5, -4, 1, 0)
  button.Position = position
  button.BackgroundColor3 = color
  button.Text = text
  button.TextColor3 = Color3.fromRGB(255, 255, 255)
  button.TextSize = 14
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.Visible = false
  button.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = button

  button.MouseButton1Click:Connect(function()
    if state.selectedItem and state.onAction then
      state.onAction(actionType, state.selectedItem)
    end
  end)

  return button
end

-- Create an item slot
local function createItemSlot(
  itemType: "egg" | "chicken",
  itemData: any,
  layoutOrder: number
): Frame
  local slotFrame = Instance.new("Frame")
  slotFrame.Name = "Slot_" .. itemData.id
  slotFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
  slotFrame.BorderSizePixel = 0
  slotFrame.LayoutOrder = layoutOrder

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = slotFrame

  -- Rarity border
  local rarity = itemData.rarity
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

  local stroke = Instance.new("UIStroke")
  stroke.Color = rarityColor
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = slotFrame

  -- Icon/Image placeholder (centered emoji for now)
  -- Adjust layout: chickens need more vertical space for rate label
  local icon = Instance.new("TextLabel")
  icon.Name = "Icon"
  icon.Size = UDim2.new(1, 0, 0.45, 0)
  icon.Position = UDim2.new(0, 0, 0, 2)
  icon.BackgroundTransparency = 1
  icon.Text = itemType == "egg" and "🥚" or "🐔"
  icon.TextSize = 24
  icon.TextColor3 = rarityColor
  icon.Parent = slotFrame

  -- Get display name and config from config
  local displayName = ""
  local moneyPerSecond: number? = nil
  if itemType == "egg" then
    local config = EggConfig.get(itemData.eggType)
    displayName = config and config.displayName or itemData.eggType
  else
    local config = ChickenConfig.get(itemData.chickenType)
    displayName = config and config.displayName or itemData.chickenType
    moneyPerSecond = config and config.moneyPerSecond or nil
  end

  -- Item name label
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, -4, 0.28, 0)
  nameLabel.Position = UDim2.new(0, 2, 0.45, 0)
  nameLabel.BackgroundTransparency = 1
  nameLabel.TextScaled = true
  nameLabel.TextWrapped = true
  nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
  nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  nameLabel.Text = displayName
  nameLabel.Parent = slotFrame

  -- Money rate label for chickens ($/s)
  if itemType == "chicken" and moneyPerSecond then
    local rateLabel = Instance.new("TextLabel")
    rateLabel.Name = "RateLabel"
    rateLabel.Size = UDim2.new(1, -4, 0.22, 0)
    rateLabel.Position = UDim2.new(0, 2, 0.73, 0)
    rateLabel.BackgroundTransparency = 1
    rateLabel.Text = formatMoneyRate(moneyPerSecond)
    rateLabel.TextColor3 = Color3.fromRGB(255, 220, 100) -- Gold color matching placed chickens
    rateLabel.TextSize = 10
    rateLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    rateLabel.Parent = slotFrame
  end

  -- Click detection
  local clickButton = Instance.new("TextButton")
  clickButton.Name = "ClickButton"
  clickButton.Size = UDim2.new(1, 0, 1, 0)
  clickButton.BackgroundTransparency = 1
  clickButton.Text = ""
  clickButton.Parent = slotFrame

  clickButton.MouseButton1Click:Connect(function()
    InventoryUI.selectItem(itemType, itemData.id, itemData)
  end)

  return slotFrame
end

-- Update tab button appearance
local function updateTabAppearance()
  if not state.tabFrame then
    return
  end

  local eggsTab = state.tabFrame:FindFirstChild("eggsTab")
  local chickensTab = state.tabFrame:FindFirstChild("chickensTab")

  if eggsTab then
    eggsTab.BackgroundColor3 = state.currentTab == "eggs" and Color3.fromRGB(80, 80, 100)
      or Color3.fromRGB(50, 50, 60)
    eggsTab.TextColor3 = state.currentTab == "eggs" and Color3.fromRGB(255, 255, 255)
      or Color3.fromRGB(180, 180, 180)
  end

  if chickensTab then
    chickensTab.BackgroundColor3 = state.currentTab == "chickens" and Color3.fromRGB(80, 80, 100)
      or Color3.fromRGB(50, 50, 60)
    chickensTab.TextColor3 = state.currentTab == "chickens" and Color3.fromRGB(255, 255, 255)
      or Color3.fromRGB(180, 180, 180)
  end
end

-- Update action buttons based on selection
local function updateActionButtons()
  if not state.actionFrame then
    return
  end

  -- Clear existing buttons
  for _, child in ipairs(state.actionFrame:GetChildren()) do
    if child:IsA("TextButton") then
      child:Destroy()
    end
  end

  if not state.selectedItem then
    return
  end

  if state.selectedItem.itemType == "egg" then
    -- Egg actions: Place (to hatch in coop), Sell
    createActionButton(
      state.actionFrame,
      "📍 Place",
      "place",
      UDim2.new(0, 0, 0, 0),
      Color3.fromRGB(80, 160, 80)
    ).Visible =
      true
    createActionButton(
      state.actionFrame,
      "💰 Sell",
      "sell",
      UDim2.new(0.5, 4, 0, 0),
      Color3.fromRGB(200, 80, 80)
    ).Visible =
      true
  else
    -- Chicken actions: Place, Sell
    createActionButton(
      state.actionFrame,
      "📍 Place",
      "place",
      UDim2.new(0, 0, 0, 0),
      Color3.fromRGB(80, 120, 200)
    ).Visible =
      true
    createActionButton(
      state.actionFrame,
      "💰 Sell",
      "sell",
      UDim2.new(0.5, 4, 0, 0),
      Color3.fromRGB(200, 80, 80)
    ).Visible =
      true
  end
end

-- Update selection visual
local function updateSelectionVisual()
  -- Reset all slot borders
  for _, slotFrame in pairs(state.slots) do
    local stroke = slotFrame:FindFirstChildOfClass("UIStroke")
    if stroke then
      stroke.Thickness = 2
      stroke.Transparency = 0.3
    end
  end

  -- Highlight selected slot
  if state.selectedItem then
    local selectedSlot = state.slots[state.selectedItem.itemId]
    if selectedSlot then
      local stroke = selectedSlot:FindFirstChildOfClass("UIStroke")
      if stroke then
        stroke.Thickness = 3
        stroke.Transparency = 0
      end
    end
  end
end

-- Create the main frame
local function createMainFrame(screenGui: ScreenGui, config: InventoryConfig): Frame
  local frame = Instance.new("Frame")
  frame.Name = "InventoryFrame"
  frame.AnchorPoint = config.anchorPoint or DEFAULT_CONFIG.anchorPoint
  frame.Position = config.position or DEFAULT_CONFIG.position
  frame.Size = config.size or DEFAULT_CONFIG.size
  frame.BackgroundColor3 = config.backgroundColor or DEFAULT_CONFIG.backgroundColor
  frame.BackgroundTransparency = 0.2
  frame.BorderSizePixel = 0
  frame.Parent = screenGui

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = frame

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(80, 80, 100)
  stroke.Thickness = 2
  stroke.Transparency = 0.5
  stroke.Parent = frame

  -- Title bar
  local titleBar = Instance.new("Frame")
  titleBar.Name = "TitleBar"
  titleBar.Size = UDim2.new(1, 0, 0, 36)
  titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  titleBar.BorderSizePixel = 0
  titleBar.Parent = frame

  local titleCorner = Instance.new("UICorner")
  titleCorner.CornerRadius = UDim.new(0, 12)
  titleCorner.Parent = titleBar

  -- Cover bottom corners of title bar
  local titleCover = Instance.new("Frame")
  titleCover.Size = UDim2.new(1, 0, 0, 12)
  titleCover.Position = UDim2.new(0, 0, 1, -12)
  titleCover.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
  titleCover.BorderSizePixel = 0
  titleCover.Parent = titleBar

  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "Title"
  titleLabel.Size = UDim2.new(1, -40, 1, 0)
  titleLabel.Position = UDim2.new(0, 12, 0, 0)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "📦 Inventory"
  titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  titleLabel.TextSize = 16
  titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.Parent = titleBar

  -- Close button
  local closeButton = Instance.new("TextButton")
  closeButton.Name = "CloseButton"
  closeButton.Size = UDim2.new(0, 28, 0, 28)
  closeButton.Position = UDim2.new(1, -32, 0, 4)
  closeButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
  closeButton.Text = "✕"
  closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  closeButton.TextSize = 14
  closeButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  closeButton.BorderSizePixel = 0
  closeButton.Parent = titleBar

  local closeCorner = Instance.new("UICorner")
  closeCorner.CornerRadius = UDim.new(0, 6)
  closeCorner.Parent = closeButton

  closeButton.MouseButton1Click:Connect(function()
    InventoryUI.setVisible(false)
  end)

  -- Content container (offset for title bar)
  local contentContainer = Instance.new("Frame")
  contentContainer.Name = "ContentContainer"
  contentContainer.Size = UDim2.new(1, 0, 1, -36)
  contentContainer.Position = UDim2.new(0, 0, 0, 36)
  contentContainer.BackgroundTransparency = 1
  contentContainer.Parent = frame

  return frame, contentContainer
end

-- Create the screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "InventoryUI"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Initialize the Inventory UI
function InventoryUI.create(config: InventoryConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("InventoryUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  InventoryUI.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  local mainFrame, contentContainer = createMainFrame(state.screenGui, currentConfig)
  state.mainFrame = mainFrame

  state.tabFrame = createTabFrame(contentContainer)
  state.contentFrame = createContentFrame(contentContainer)
  state.actionFrame = createActionFrame(contentContainer)

  -- Set initial tab appearance
  updateTabAppearance()

  -- Set initial visibility (start hidden, player opens with I key)
  state.isVisible = false
  state.mainFrame.Visible = false

  return true
end

-- Destroy the Inventory UI
function InventoryUI.destroy()
  if state.screenGui then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.mainFrame = nil
  state.tabFrame = nil
  state.contentFrame = nil
  state.actionFrame = nil
  state.selectedItem = nil
  state.currentTab = "eggs"
  state.isVisible = false
  state.slots = {}
end

-- Set the current tab
function InventoryUI.setTab(tab: "eggs" | "chickens")
  state.currentTab = tab
  state.selectedItem = nil
  updateTabAppearance()
  updateActionButtons()
end

-- Update inventory from player data
function InventoryUI.updateFromPlayerData(playerData: any)
  -- Always cache the player data so we can refresh when inventory is opened
  cachedPlayerData = playerData

  if not state.contentFrame then
    return
  end

  -- Clear existing slots and empty labels
  for _, child in ipairs(state.contentFrame:GetChildren()) do
    if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyLabel") then
      child:Destroy()
    end
  end
  state.slots = {}

  -- Get items based on current tab
  local items: { any } = {}
  if state.currentTab == "eggs" then
    if playerData.inventory and playerData.inventory.eggs then
      items = playerData.inventory.eggs
    end
  else
    if playerData.inventory and playerData.inventory.chickens then
      items = playerData.inventory.chickens
    end
  end

  -- Create slots for each item
  for i, itemData in ipairs(items) do
    local slot = createItemSlot(state.currentTab == "eggs" and "egg" or "chicken", itemData, i)
    slot.Parent = state.contentFrame
    state.slots[itemData.id] = slot
  end

  -- Show empty message if no items
  if #items == 0 then
    local emptyLabel = Instance.new("TextLabel")
    emptyLabel.Name = "EmptyLabel"
    emptyLabel.Size = UDim2.new(1, -20, 0, 60)
    emptyLabel.Position = UDim2.new(0, 10, 0, 10)
    emptyLabel.BackgroundTransparency = 1
    emptyLabel.Text = state.currentTab == "eggs"
        and "No eggs in inventory\nBuy some from the store!"
      or "No chickens in inventory\nHatch some eggs!"
    emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    emptyLabel.TextSize = 14
    emptyLabel.TextWrapped = true
    emptyLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    emptyLabel.Parent = state.contentFrame
  end

  -- Update selection visual in case item was removed
  updateSelectionVisual()
  updateActionButtons()
end

-- Select an item
function InventoryUI.selectItem(itemType: "egg" | "chicken", itemId: string, itemData: any)
  -- Deselect if same item clicked
  if state.selectedItem and state.selectedItem.itemId == itemId then
    state.selectedItem = nil
  else
    state.selectedItem = {
      itemType = itemType,
      itemId = itemId,
      itemData = itemData,
    }
  end

  updateSelectionVisual()
  updateActionButtons()

  if state.onItemSelected then
    state.onItemSelected(state.selectedItem)
  end
end

-- Get current selection
function InventoryUI.getSelectedItem(): SelectedItem?
  return state.selectedItem
end

-- Clear selection
function InventoryUI.clearSelection()
  state.selectedItem = nil
  updateSelectionVisual()
  updateActionButtons()

  if state.onItemSelected then
    state.onItemSelected(nil)
  end
end

-- Set visibility
function InventoryUI.setVisible(visible: boolean)
  state.isVisible = visible
  if state.mainFrame then
    state.mainFrame.Visible = visible
  else
    warn("[InventoryUI] Cannot set visibility - mainFrame is nil. Was create() called?")
  end
  -- Refresh inventory with cached data when becoming visible
  if visible and cachedPlayerData then
    InventoryUI.updateFromPlayerData(cachedPlayerData)
  end
  if onVisibilityChanged then
    onVisibilityChanged(visible)
  end
end

-- Get visibility
function InventoryUI.isVisible(): boolean
  return state.isVisible
end

-- Toggle visibility
function InventoryUI.toggle()
  InventoryUI.setVisible(not state.isVisible)
end

-- Check if created
function InventoryUI.isCreated(): boolean
  return state.screenGui ~= nil and state.mainFrame ~= nil
end

-- Set callback for item selection
function InventoryUI.onItemSelected(callback: (SelectedItem?) -> ())
  state.onItemSelected = callback
end

-- Set callback for action button clicks
function InventoryUI.onAction(callback: (string, SelectedItem) -> ())
  state.onAction = callback
end

-- Get current tab
function InventoryUI.getCurrentTab(): "eggs" | "chickens"
  return state.currentTab
end

-- Get the screen GUI for adding additional elements
function InventoryUI.getScreenGui(): ScreenGui?
  return state.screenGui
end

-- Get the main frame
function InventoryUI.getMainFrame(): Frame?
  return state.mainFrame
end

-- Update position for responsive layout
function InventoryUI.setPosition(position: UDim2)
  if state.mainFrame then
    state.mainFrame.Position = position
  end
end

-- Update size for responsive layout
function InventoryUI.setSize(size: UDim2)
  if state.mainFrame then
    state.mainFrame.Size = size
  end
end

-- Get item counts
function InventoryUI.getItemCounts(playerData: any): { eggs: number, chickens: number }
  local eggCount = 0
  local chickenCount = 0

  if playerData.inventory then
    if playerData.inventory.eggs then
      eggCount = #playerData.inventory.eggs
    end
    if playerData.inventory.chickens then
      chickenCount = #playerData.inventory.chickens
    end
  end

  return {
    eggs = eggCount,
    chickens = chickenCount,
  }
end

-- Get default config
function InventoryUI.getDefaultConfig(): InventoryConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

-- Get rarity colors (for external use)
function InventoryUI.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

-- Set callback for visibility changes
function InventoryUI.onVisibilityChanged(callback: (boolean) -> ())
  onVisibilityChanged = callback
end

return InventoryUI
