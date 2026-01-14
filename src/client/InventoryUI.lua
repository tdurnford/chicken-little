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
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
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
  itemType: "egg" | "chicken" | "trap",
  itemId: string,
  itemData: any,
  stackCount: number?, -- Number of stacked items (nil = 1)
  stackedItemIds: { string }?, -- All item IDs in this stack
}

export type InventoryState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  tabFrame: Frame?,
  contentFrame: ScrollingFrame?,
  actionFrame: Frame?,
  selectedItem: SelectedItem?,
  selectedStackKey: string?, -- Stack key for the currently selected item
  currentTab: "eggs" | "chickens" | "traps",
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

-- Trap tier colors for visual distinction
local TRAP_TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Improved = Color3.fromRGB(100, 200, 100),
  Advanced = Color3.fromRGB(100, 150, 255),
  Expert = Color3.fromRGB(180, 100, 255),
  Master = Color3.fromRGB(255, 180, 50),
  Ultimate = Color3.fromRGB(255, 100, 150),
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
  selectedStackKey = nil,
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

-- Cached global chicken counts (chickenType -> count)
local cachedGlobalChickenCounts: { [string]: number } = {}

local currentConfig: InventoryConfig = DEFAULT_CONFIG

-- Fetch global chicken counts from server
local function fetchGlobalChickenCounts()
  local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
  if not Remotes then
    return
  end

  local getGlobalCountsFunc = Remotes:FindFirstChild("GetGlobalChickenCounts")
  if not getGlobalCountsFunc or not getGlobalCountsFunc:IsA("RemoteFunction") then
    return
  end

  local success, result = pcall(function()
    return getGlobalCountsFunc:InvokeServer()
  end)

  if success and result then
    cachedGlobalChickenCounts = result
  end
end

-- Create a tab button
local function createTabButton(
  parent: Frame,
  text: string,
  tabType: "eggs" | "chickens" | "traps",
  position: UDim2
): TextButton
  local button = Instance.new("TextButton")
  button.Name = tabType .. "Tab"
  button.Size = UDim2.new(0.333, -4, 1, 0)
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

-- Create the tab frame with eggs/chickens/traps tabs
local function createTabFrame(parent: Frame): Frame
  local tabFrame = Instance.new("Frame")
  tabFrame.Name = "TabFrame"
  tabFrame.Size = UDim2.new(1, -16, 0, 36)
  tabFrame.Position = UDim2.new(0, 8, 0, 8)
  tabFrame.BackgroundTransparency = 1
  tabFrame.Parent = parent

  createTabButton(tabFrame, "🥚 Eggs", "eggs", UDim2.new(0, 0, 0, 0))
  createTabButton(tabFrame, "🐔 Chickens", "chickens", UDim2.new(0.333, 2, 0, 0))
  createTabButton(tabFrame, "🪤 Traps", "traps", UDim2.new(0.666, 4, 0, 0))

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

-- Type for a stacked group of items
type StackedItem = {
  representativeItem: any, -- First item in the stack (used for display)
  count: number, -- Number of items in the stack
  itemIds: { string }, -- All item IDs in this stack
  stackKey: string, -- Key used for grouping (e.g., "BasicEgg_Common")
}

-- Generate a stack key for grouping identical items
local function getStackKey(itemType: "egg" | "chicken" | "trap", itemData: any): string
  if itemType == "egg" then
    return itemData.eggType .. "_" .. itemData.rarity
  elseif itemType == "chicken" then
    return itemData.chickenType .. "_" .. itemData.rarity
  else
    -- Traps stack by type
    return itemData.trapType
  end
end

-- Group items by type+rarity into stacks
local function groupItemsIntoStacks(
  itemType: "egg" | "chicken" | "trap",
  items: { any }
): { StackedItem }
  local stackMap: { [string]: StackedItem } = {}
  local orderedKeys: { string } = {}

  for _, itemData in ipairs(items) do
    local key = getStackKey(itemType, itemData)
    if not stackMap[key] then
      stackMap[key] = {
        representativeItem = itemData,
        count = 0,
        itemIds = {},
        stackKey = key,
      }
      table.insert(orderedKeys, key)
    end
    stackMap[key].count = stackMap[key].count + 1
    table.insert(stackMap[key].itemIds, itemData.id)
  end

  -- Return stacks in order they were first encountered
  local stacks: { StackedItem } = {}
  for _, key in ipairs(orderedKeys) do
    table.insert(stacks, stackMap[key])
  end
  return stacks
end

-- Create an item slot (now supports stacking)
local function createItemSlot(
  itemType: "egg" | "chicken" | "trap",
  stackedItem: StackedItem,
  layoutOrder: number
): Frame
  local itemData = stackedItem.representativeItem
  local stackCount = stackedItem.count

  local slotFrame = Instance.new("Frame")
  slotFrame.Name = "Slot_" .. stackedItem.stackKey
  slotFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
  slotFrame.BorderSizePixel = 0
  slotFrame.LayoutOrder = layoutOrder

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = slotFrame

  -- Get color based on item type (rarity for eggs/chickens, tier for traps)
  local borderColor: Color3
  local tierOrRarity: string = ""
  if itemType == "trap" then
    local config = TrapConfig.get(itemData.trapType)
    tierOrRarity = config and config.tier or "Basic"
    borderColor = TRAP_TIER_COLORS[tierOrRarity] or TRAP_TIER_COLORS.Basic
  else
    tierOrRarity = itemData.rarity
    borderColor = RARITY_COLORS[tierOrRarity] or RARITY_COLORS.Common
  end

  local stroke = Instance.new("UIStroke")
  stroke.Color = borderColor
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = slotFrame

  -- Icon/Image placeholder (centered emoji for now)
  local icon = Instance.new("TextLabel")
  icon.Name = "Icon"
  icon.Size = UDim2.new(1, 0, 0.32, 0)
  icon.Position = UDim2.new(0, 0, 0, 0)
  icon.BackgroundTransparency = 1
  if itemType == "egg" then
    icon.Text = "🥚"
  elseif itemType == "chicken" then
    icon.Text = "🐔"
  else
    icon.Text = "🪤"
  end
  icon.TextSize = 20
  icon.TextColor3 = borderColor
  icon.Parent = slotFrame

  -- Stack count badge (only show if more than 1)
  if stackCount > 1 then
    local countBadge = Instance.new("Frame")
    countBadge.Name = "CountBadge"
    countBadge.Size = UDim2.new(0, 24, 0, 16)
    countBadge.Position = UDim2.new(1, -26, 0, 2)
    countBadge.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    countBadge.BorderSizePixel = 0
    countBadge.Parent = slotFrame

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 4)
    badgeCorner.Parent = countBadge

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "CountLabel"
    countLabel.Size = UDim2.new(1, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = "x" .. tostring(stackCount)
    countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    countLabel.TextSize = 11
    countLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    countLabel.Parent = countBadge
  end

  -- Get display name and config based on item type
  local displayName = ""
  local moneyPerSecond: number? = nil
  local chickenType: string? = nil
  local trapTier: string? = nil
  local trapDurability: number? = nil

  if itemType == "egg" then
    local config = EggConfig.get(itemData.eggType)
    displayName = config and config.displayName or itemData.eggType
  elseif itemType == "chicken" then
    chickenType = itemData.chickenType
    local config = ChickenConfig.get(chickenType)
    displayName = config and config.displayName or chickenType
    moneyPerSecond = config and config.moneyPerSecond or nil
  else
    local config = TrapConfig.get(itemData.trapType)
    displayName = config and config.displayName or itemData.trapType
    trapTier = config and config.tier or "Basic"
    trapDurability = config and config.durability or nil
  end

  -- Item name label
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "NameLabel"
  nameLabel.Size = UDim2.new(1, -4, 0.20, 0)
  nameLabel.Position = UDim2.new(0, 2, 0.32, 0)
  nameLabel.BackgroundTransparency = 1
  nameLabel.TextScaled = true
  nameLabel.TextWrapped = true
  nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
  nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  nameLabel.Text = displayName
  nameLabel.Parent = slotFrame

  -- Rarity/Tier label (for chickens and traps)
  if itemType == "chicken" then
    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Name = "RarityLabel"
    rarityLabel.Size = UDim2.new(1, -4, 0.14, 0)
    rarityLabel.Position = UDim2.new(0, 2, 0.52, 0)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text = tierOrRarity
    rarityLabel.TextColor3 = borderColor
    rarityLabel.TextSize = 9
    rarityLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    rarityLabel.Parent = slotFrame
  elseif itemType == "trap" then
    local tierLabel = Instance.new("TextLabel")
    tierLabel.Name = "TierLabel"
    tierLabel.Size = UDim2.new(1, -4, 0.14, 0)
    tierLabel.Position = UDim2.new(0, 2, 0.52, 0)
    tierLabel.BackgroundTransparency = 1
    tierLabel.Text = trapTier or "Basic"
    tierLabel.TextColor3 = borderColor
    tierLabel.TextSize = 9
    tierLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    tierLabel.Parent = slotFrame
  end

  -- Money rate label for chickens ($/s)
  if itemType == "chicken" and moneyPerSecond then
    local rateLabel = Instance.new("TextLabel")
    rateLabel.Name = "RateLabel"
    rateLabel.Size = UDim2.new(1, -4, 0.16, 0)
    rateLabel.Position = UDim2.new(0, 2, 0.66, 0)
    rateLabel.BackgroundTransparency = 1
    rateLabel.Text = formatMoneyRate(moneyPerSecond)
    rateLabel.TextColor3 = Color3.fromRGB(255, 220, 100) -- Gold color matching placed chickens
    rateLabel.TextSize = 9
    rateLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    rateLabel.Parent = slotFrame
  end

  -- Durability label for traps
  if itemType == "trap" then
    local durabilityLabel = Instance.new("TextLabel")
    durabilityLabel.Name = "DurabilityLabel"
    durabilityLabel.Size = UDim2.new(1, -4, 0.16, 0)
    durabilityLabel.Position = UDim2.new(0, 2, 0.66, 0)
    durabilityLabel.BackgroundTransparency = 1
    if trapDurability and trapDurability > 0 then
      durabilityLabel.Text = trapDurability .. " uses"
    else
      durabilityLabel.Text = "∞ uses"
    end
    durabilityLabel.TextColor3 = Color3.fromRGB(150, 200, 150)
    durabilityLabel.TextSize = 9
    durabilityLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    durabilityLabel.Parent = slotFrame
  end

  -- Global count label for chickens
  if itemType == "chicken" and chickenType then
    local globalCount = cachedGlobalChickenCounts[chickenType] or 0
    local globalLabel = Instance.new("TextLabel")
    globalLabel.Name = "GlobalLabel"
    globalLabel.Size = UDim2.new(1, -4, 0.16, 0)
    globalLabel.Position = UDim2.new(0, 2, 0.82, 0)
    globalLabel.BackgroundTransparency = 1
    globalLabel.Text = tostring(globalCount) .. " exist"
    globalLabel.TextColor3 = Color3.fromRGB(150, 150, 180)
    globalLabel.TextSize = 8
    globalLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    globalLabel.Parent = slotFrame
  end

  -- Status label for traps (placed status)
  if itemType == "trap" then
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, -4, 0.16, 0)
    statusLabel.Position = UDim2.new(0, 2, 0.82, 0)
    statusLabel.BackgroundTransparency = 1
    if itemData.spotIndex and itemData.spotIndex > 0 then
      statusLabel.Text = "Placed"
      statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    else
      statusLabel.Text = "In Inventory"
      statusLabel.TextColor3 = Color3.fromRGB(150, 150, 180)
    end
    statusLabel.TextSize = 8
    statusLabel.FontFace =
      Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    statusLabel.Parent = slotFrame
  end

  -- Click detection
  local clickButton = Instance.new("TextButton")
  clickButton.Name = "ClickButton"
  clickButton.Size = UDim2.new(1, 0, 1, 0)
  clickButton.BackgroundTransparency = 1
  clickButton.Text = ""
  clickButton.Parent = slotFrame

  clickButton.MouseButton1Click:Connect(function()
    InventoryUI.selectItem(itemType, itemData.id, itemData, stackCount, stackedItem.itemIds)
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
  local trapsTab = state.tabFrame:FindFirstChild("trapsTab")

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

  if trapsTab then
    trapsTab.BackgroundColor3 = state.currentTab == "traps" and Color3.fromRGB(80, 80, 100)
      or Color3.fromRGB(50, 50, 60)
    trapsTab.TextColor3 = state.currentTab == "traps" and Color3.fromRGB(255, 255, 255)
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
  elseif state.selectedItem.itemType == "chicken" then
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
  else
    -- Trap actions: Place, Sell
    createActionButton(
      state.actionFrame,
      "📍 Place",
      "place",
      UDim2.new(0, 0, 0, 0),
      Color3.fromRGB(80, 160, 120)
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

  -- Highlight selected slot (use stack key instead of item ID)
  if state.selectedItem and state.selectedStackKey then
    local selectedSlot = state.slots[state.selectedStackKey]
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
  closeButton.Text = "X"
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
  state.selectedStackKey = nil
  state.currentTab = "eggs"
  state.isVisible = false
  state.slots = {}
end

-- Set the current tab
function InventoryUI.setTab(tab: "eggs" | "chickens" | "traps")
  state.currentTab = tab
  state.selectedItem = nil
  state.selectedStackKey = nil
  updateTabAppearance()
  updateActionButtons()
  -- Refresh inventory display to update global counts when switching to chickens tab
  if cachedPlayerData then
    InventoryUI.updateFromPlayerData(cachedPlayerData)
  end
end

-- Update inventory from player data
function InventoryUI.updateFromPlayerData(playerData: any)
  -- Always cache the player data so we can refresh when inventory is opened
  cachedPlayerData = playerData

  if not state.contentFrame then
    return
  end

  -- Fetch global chicken counts when on chickens tab
  if state.currentTab == "chickens" then
    fetchGlobalChickenCounts()
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
  local itemType: "egg" | "chicken" | "trap"

  if state.currentTab == "eggs" then
    if playerData.inventory and playerData.inventory.eggs then
      items = playerData.inventory.eggs
    end
    itemType = "egg"
  elseif state.currentTab == "chickens" then
    if playerData.inventory and playerData.inventory.chickens then
      items = playerData.inventory.chickens
    end
    itemType = "chicken"
  else
    -- Traps tab
    if playerData.traps then
      items = playerData.traps
    end
    itemType = "trap"
  end

  -- Group items into stacks by type+rarity (or just type for traps)
  local stacks = groupItemsIntoStacks(itemType, items)

  -- Create slots for each stack
  for i, stackedItem in ipairs(stacks) do
    local slot = createItemSlot(itemType, stackedItem, i)
    slot.Parent = state.contentFrame
    state.slots[stackedItem.stackKey] = slot
  end

  -- Show empty message if no items
  if #items == 0 then
    local emptyLabel = Instance.new("TextLabel")
    emptyLabel.Name = "EmptyLabel"
    emptyLabel.Size = UDim2.new(1, -20, 0, 60)
    emptyLabel.Position = UDim2.new(0, 10, 0, 10)
    emptyLabel.BackgroundTransparency = 1
    if state.currentTab == "eggs" then
      emptyLabel.Text = "No eggs in inventory\nBuy some from the store!"
    elseif state.currentTab == "chickens" then
      emptyLabel.Text = "No chickens in inventory\nHatch some eggs!"
    else
      emptyLabel.Text = "No traps in inventory\nBuy some from the store!"
    end
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

-- Select an item (with stack support)
function InventoryUI.selectItem(
  itemType: "egg" | "chicken" | "trap",
  itemId: string,
  itemData: any,
  stackCount: number?,
  stackedItemIds: { string }?
)
  -- Generate stack key for this item
  local stackKey = getStackKey(itemType, itemData)

  -- Deselect if same stack clicked
  if state.selectedStackKey and state.selectedStackKey == stackKey then
    state.selectedItem = nil
    state.selectedStackKey = nil
  else
    state.selectedItem = {
      itemType = itemType,
      itemId = itemId,
      itemData = itemData,
      stackCount = stackCount or 1,
      stackedItemIds = stackedItemIds or { itemId },
    }
    state.selectedStackKey = stackKey
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
  state.selectedStackKey = nil
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
function InventoryUI.getCurrentTab(): "eggs" | "chickens" | "traps"
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
function InventoryUI.getItemCounts(
  playerData: any
): { eggs: number, chickens: number, traps: number }
  local eggCount = 0
  local chickenCount = 0
  local trapCount = 0

  if playerData.inventory then
    if playerData.inventory.eggs then
      eggCount = #playerData.inventory.eggs
    end
    if playerData.inventory.chickens then
      chickenCount = #playerData.inventory.chickens
    end
  end

  if playerData.traps then
    trapCount = #playerData.traps
  end

  return {
    eggs = eggCount,
    chickens = chickenCount,
    traps = trapCount,
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
