--[[
	InventoryUI Component (Fusion)
	Displays player inventory (eggs, chickens, traps) using reactive Fusion state.
	Supports item selection, stacking, action buttons, and scrolling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)
local State = require(UIFolder.State)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local ForPairs = Fusion.ForPairs
local Spring = Fusion.Spring
local Cleanup = Fusion.Cleanup
local peek = Fusion.peek

-- Types
export type TabType = "eggs" | "chickens" | "traps"

export type SelectedItem = {
  itemType: TabType,
  itemId: string,
  itemData: any,
  stackCount: number?,
  stackedItemIds: { string }?,
}

export type InventoryUIProps = {
  onAction: ((action: string, item: SelectedItem) -> ())?,
  onItemSelected: ((item: SelectedItem?) -> ())?,
  onVisibilityChanged: ((visible: boolean) -> ())?,
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

-- Trap tier colors
local TRAP_TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Improved = Color3.fromRGB(100, 200, 100),
  Advanced = Color3.fromRGB(100, 150, 255),
  Expert = Color3.fromRGB(180, 100, 255),
  Master = Color3.fromRGB(255, 180, 50),
  Ultimate = Color3.fromRGB(255, 100, 150),
}

-- Constants
local SLOT_SIZE = 70
local SLOT_PADDING = 8

-- Module state
local InventoryUI = {}
local screenGui: ScreenGui? = nil
local inventoryScope: Fusion.Scope? = nil
local currentTab: Fusion.Value<TabType>? = nil
local selectedStackKey: Fusion.Value<string?>? = nil
local selectedItem: SelectedItem? = nil
local isVisible: Fusion.Value<boolean>? = nil
local cachedCallbacks: InventoryUIProps = {}

-- Helper: Format money rate
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

-- Helper: Get stack key for grouping items
local function getStackKey(itemType: TabType, itemData: any): string
  if itemType == "eggs" then
    return itemData.eggType .. "_" .. itemData.rarity
  elseif itemType == "chickens" then
    return itemData.chickenType .. "_" .. itemData.rarity
  else
    return itemData.trapType
  end
end

-- Helper: Get border color based on item type
local function getBorderColor(itemType: TabType, itemData: any): Color3
  if itemType == "traps" then
    local config = TrapConfig.get(itemData.trapType)
    local tier = config and config.tier or "Basic"
    return TRAP_TIER_COLORS[tier] or TRAP_TIER_COLORS.Basic
  else
    local rarity = itemData.rarity or "Common"
    return RARITY_COLORS[rarity] or RARITY_COLORS.Common
  end
end

-- Type for a stacked group of items
type StackedItem = {
  representativeItem: any,
  count: number,
  itemIds: { string },
  stackKey: string,
}

-- Group items into stacks
local function groupItemsIntoStacks(itemType: TabType, items: { any }): { StackedItem }
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

  local stacks: { StackedItem } = {}
  for _, key in ipairs(orderedKeys) do
    table.insert(stacks, stackMap[key])
  end
  return stacks
end

-- Create a single item slot
local function createItemSlot(
  scope: Fusion.Scope,
  itemType: TabType,
  stackedItem: StackedItem,
  layoutOrder: number,
  selectedKey: Fusion.Value<string?>,
  onSelect: (StackedItem) -> ()
)
  local itemData = stackedItem.representativeItem
  local stackCount = stackedItem.count
  local borderColor = getBorderColor(itemType, itemData)

  -- Get display info
  local displayName = ""
  local moneyPerSecond: number? = nil
  local tierOrRarity = ""

  if itemType == "eggs" then
    local config = EggConfig.get(itemData.eggType)
    displayName = config and config.displayName or itemData.eggType
    tierOrRarity = itemData.rarity or "Common"
  elseif itemType == "chickens" then
    local config = ChickenConfig.get(itemData.chickenType)
    displayName = config and config.displayName or itemData.chickenType
    moneyPerSecond = config and config.moneyPerSecond or nil
    tierOrRarity = itemData.rarity or "Common"
  else
    local config = TrapConfig.get(itemData.trapType)
    displayName = config and config.displayName or itemData.trapType
    tierOrRarity = config and config.tier or "Basic"
  end

  -- Computed selection state
  local isSelected = Computed(scope, function(use)
    return use(selectedKey) == stackedItem.stackKey
  end)

  local strokeThickness = Computed(scope, function(use)
    return if use(isSelected) then 3 else 2
  end)

  local strokeTransparency = Computed(scope, function(use)
    return if use(isSelected) then 0 else 0.3
  end)

  return New(scope, "Frame")({
    Name = "Slot_" .. stackedItem.stackKey,
    Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
    BackgroundColor3 = Color3.fromRGB(40, 40, 50),
    LayoutOrder = layoutOrder,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIStroke")({
        Color = borderColor,
        Thickness = strokeThickness,
        Transparency = strokeTransparency,
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(1, 0, 0.32, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = if itemType == "eggs"
          then "🥚"
          elseif itemType == "chickens" then "🐔"
          else "🪤",
        TextSize = 20,
        TextColor3 = borderColor,
      }),

      -- Stack count badge (only if > 1)
      stackCount > 1
          and New(scope, "Frame")({
            Name = "CountBadge",
            Size = UDim2.new(0, 24, 0, 16),
            Position = UDim2.new(1, -26, 0, 2),
            BackgroundColor3 = Color3.fromRGB(60, 60, 80),

            [Children] = {
              New(scope, "UICorner")({
                CornerRadius = UDim.new(0, 4),
              }),
              New(scope, "TextLabel")({
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "x" .. tostring(stackCount),
                TextColor3 = Color3.fromRGB(255, 255, 255),
                TextSize = 11,
                FontFace = Theme.Typography.PrimaryBold,
              }),
            },
          })
        or nil,

      -- Name label
      New(scope, "TextLabel")({
        Name = "NameLabel",
        Size = UDim2.new(1, -4, 0.20, 0),
        Position = UDim2.new(0, 2, 0.32, 0),
        BackgroundTransparency = 1,
        Text = displayName,
        TextScaled = true,
        TextWrapped = true,
        TextColor3 = Color3.fromRGB(220, 220, 220),
        FontFace = Theme.Typography.Primary,
      }),

      -- Rarity/Tier label
      New(scope, "TextLabel")({
        Name = "RarityLabel",
        Size = UDim2.new(1, -4, 0.14, 0),
        Position = UDim2.new(0, 2, 0.52, 0),
        BackgroundTransparency = 1,
        Text = tierOrRarity,
        TextColor3 = borderColor,
        TextSize = 9,
        FontFace = Theme.Typography.PrimaryBold,
      }),

      -- Money rate (chickens only)
      itemType == "chickens"
          and moneyPerSecond
          and New(scope, "TextLabel")({
            Name = "RateLabel",
            Size = UDim2.new(1, -4, 0.16, 0),
            Position = UDim2.new(0, 2, 0.66, 0),
            BackgroundTransparency = 1,
            Text = formatMoneyRate(moneyPerSecond),
            TextColor3 = Color3.fromRGB(255, 220, 100),
            TextSize = 9,
            FontFace = Theme.Typography.PrimaryBold,
          })
        or nil,

      -- Trap durability
      itemType == "traps"
          and New(scope, "TextLabel")({
            Name = "DurabilityLabel",
            Size = UDim2.new(1, -4, 0.16, 0),
            Position = UDim2.new(0, 2, 0.66, 0),
            BackgroundTransparency = 1,
            Text = (function()
              local config = TrapConfig.get(itemData.trapType)
              local dur = config and config.durability or 0
              return if dur > 0 then dur .. " uses" else "∞ uses"
            end)(),
            TextColor3 = Color3.fromRGB(150, 200, 150),
            TextSize = 9,
            FontFace = Theme.Typography.PrimaryBold,
          })
        or nil,

      -- Click button overlay
      New(scope, "TextButton")({
        Name = "ClickButton",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        [OnEvent("MouseButton1Click")] = function()
          onSelect(stackedItem)
        end,
      }),
    },
  })
end

-- Create tab button
local function createTabButton(
  scope: Fusion.Scope,
  text: string,
  tabType: TabType,
  position: UDim2,
  activeTab: Fusion.Value<TabType>,
  onTabClick: (TabType) -> ()
)
  local isActive = Computed(scope, function(use)
    return use(activeTab) == tabType
  end)

  local bgColor = Computed(scope, function(use)
    return if use(isActive) then Color3.fromRGB(80, 80, 100) else Color3.fromRGB(50, 50, 60)
  end)

  local textColor = Computed(scope, function(use)
    return if use(isActive) then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 180, 180)
  end)

  return New(scope, "TextButton")({
    Name = tabType .. "Tab",
    Size = UDim2.new(0.333, -4, 1, 0),
    Position = position,
    BackgroundColor3 = bgColor,
    Text = text,
    TextColor3 = textColor,
    TextSize = 14,
    FontFace = Theme.Typography.PrimaryBold,
    BorderSizePixel = 0,
    AutoButtonColor = true,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
    },

    [OnEvent("MouseButton1Click")] = function()
      onTabClick(tabType)
    end,
  })
end

-- Create action button
local function createActionButton(
  scope: Fusion.Scope,
  text: string,
  actionType: string,
  position: UDim2,
  color: Color3,
  visible: Fusion.Computed<boolean>,
  onAction: (string) -> ()
)
  return New(scope, "TextButton")({
    Name = actionType .. "Button",
    Size = UDim2.new(0.5, -4, 1, 0),
    Position = position,
    BackgroundColor3 = color,
    Text = text,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 14,
    FontFace = Theme.Typography.PrimaryBold,
    BorderSizePixel = 0,
    AutoButtonColor = true,
    Visible = visible,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
    },

    [OnEvent("MouseButton1Click")] = function()
      onAction(actionType)
    end,
  })
end

-- Create the scrolling content with items
local function createContentFrame(
  scope: Fusion.Scope,
  activeTab: Fusion.Value<TabType>,
  selectedKey: Fusion.Value<string?>,
  onSelect: (StackedItem) -> ()
)
  -- Computed items based on active tab
  local stacks = Computed(scope, function(use)
    local tab = use(activeTab)
    local items = {}

    if tab == "eggs" then
      items = use(State.Player.Eggs) or {}
    elseif tab == "chickens" then
      items = use(State.Player.InventoryChickens) or {}
    else
      -- Traps aren't in PlayerState yet, return empty for now
      items = {}
    end

    return groupItemsIntoStacks(tab, items)
  end)

  -- Create child elements
  local children = Computed(scope, function(use)
    local stackList = use(stacks)
    local tab = use(activeTab)
    local elements: { any } = {
      New(scope, "UIGridLayout")({
        CellSize = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
        CellPadding = UDim2.new(0, SLOT_PADDING, 0, SLOT_PADDING),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
      }),
      New(scope, "UIPadding")({
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
      }),
    }

    if #stackList == 0 then
      -- Empty message
      local emptyText = if tab == "eggs"
        then "No eggs in inventory\nBuy some from the store!"
        elseif tab == "chickens" then "No chickens in inventory\nHatch some eggs!"
        else "No traps in inventory\nBuy some from the store!"

      table.insert(
        elements,
        New(scope, "TextLabel")({
          Name = "EmptyLabel",
          Size = UDim2.new(1, -20, 0, 60),
          BackgroundTransparency = 1,
          Text = emptyText,
          TextColor3 = Color3.fromRGB(150, 150, 150),
          TextSize = 14,
          TextWrapped = true,
          FontFace = Theme.Typography.Primary,
        })
      )
    else
      -- Create slots for each stack
      for i, stack in ipairs(stackList) do
        local slot = createItemSlot(scope, tab, stack, i, selectedKey, onSelect)
        table.insert(elements, slot)
      end
    end

    return elements
  end)

  return New(scope, "ScrollingFrame")({
    Name = "ContentFrame",
    Size = UDim2.new(1, -16, 1, -110),
    Position = UDim2.new(0, 8, 0, 52),
    BackgroundColor3 = Color3.fromRGB(20, 20, 28),
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      children,
    },
  })
end

-- Create action bar with buttons
local function createActionBar(
  scope: Fusion.Scope,
  activeTab: Fusion.Value<TabType>,
  selectedKey: Fusion.Value<string?>,
  onAction: (string) -> ()
)
  local hasSelection = Computed(scope, function(use)
    return use(selectedKey) ~= nil
  end)

  local placeText = Computed(scope, function(use)
    local tab = use(activeTab)
    return if tab == "eggs" then "🐣 Hatch" else "📍 Place"
  end)

  local placeColor = Computed(scope, function(use)
    local tab = use(activeTab)
    if tab == "eggs" then
      return Color3.fromRGB(80, 160, 80)
    elseif tab == "chickens" then
      return Color3.fromRGB(80, 120, 200)
    else
      return Color3.fromRGB(80, 160, 120)
    end
  end)

  return New(scope, "Frame")({
    Name = "ActionFrame",
    Size = UDim2.new(1, -16, 0, 44),
    Position = UDim2.new(0, 8, 1, -52),
    BackgroundTransparency = 1,

    [Children] = {
      createActionButton(
        scope,
        placeText,
        "place",
        UDim2.new(0, 0, 0, 0),
        placeColor,
        hasSelection,
        onAction
      ),
      createActionButton(
        scope,
        "💰 Sell",
        "sell",
        UDim2.new(0.5, 4, 0, 0),
        Color3.fromRGB(200, 80, 80),
        hasSelection,
        onAction
      ),
    },
  })
end

-- Create the main inventory frame
local function createMainFrame(
  scope: Fusion.Scope,
  activeTab: Fusion.Value<TabType>,
  selectedKey: Fusion.Value<string?>,
  visible: Fusion.Value<boolean>,
  onSelect: (StackedItem) -> (),
  onAction: (string) -> (),
  onTabClick: (TabType) -> (),
  onClose: () -> ()
)
  return New(scope, "Frame")({
    Name = "InventoryFrame",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -20, 0.5, 0),
    Size = UDim2.new(0, 320, 0, 450),
    BackgroundColor3 = Theme.Colors.Background,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Visible = visible,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 12),
      }),
      New(scope, "UIStroke")({
        Color = Color3.fromRGB(80, 80, 100),
        Thickness = 2,
        Transparency = 0.5,
      }),

      -- Title bar
      New(scope, "Frame")({
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 12),
          }),
          -- Cover bottom corners
          New(scope, "Frame")({
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 1, -12),
            BackgroundColor3 = Color3.fromRGB(40, 40, 55),
            BorderSizePixel = 0,
          }),
          -- Title text
          New(scope, "TextLabel")({
            Name = "Title",
            Size = UDim2.new(1, -40, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Text = "📦 Inventory",
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 16,
            FontFace = Theme.Typography.PrimaryBold,
            TextXAlignment = Enum.TextXAlignment.Left,
          }),
          -- Close button
          New(scope, "TextButton")({
            Name = "CloseButton",
            Size = UDim2.new(0, 28, 0, 28),
            Position = UDim2.new(1, -32, 0, 4),
            BackgroundColor3 = Color3.fromRGB(200, 80, 80),
            Text = "X",
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 14,
            FontFace = Theme.Typography.PrimaryBold,
            BorderSizePixel = 0,

            [Children] = {
              New(scope, "UICorner")({
                CornerRadius = UDim.new(0, 6),
              }),
            },

            [OnEvent("MouseButton1Click")] = onClose,
          }),
        },
      }),

      -- Content container
      New(scope, "Frame")({
        Name = "ContentContainer",
        Size = UDim2.new(1, 0, 1, -36),
        Position = UDim2.new(0, 0, 0, 36),
        BackgroundTransparency = 1,

        [Children] = {
          -- Tab frame
          New(scope, "Frame")({
            Name = "TabFrame",
            Size = UDim2.new(1, -16, 0, 36),
            Position = UDim2.new(0, 8, 0, 8),
            BackgroundTransparency = 1,

            [Children] = {
              createTabButton(
                scope,
                "🥚 Eggs",
                "eggs",
                UDim2.new(0, 0, 0, 0),
                activeTab,
                onTabClick
              ),
              createTabButton(
                scope,
                "🐔 Chickens",
                "chickens",
                UDim2.new(0.333, 2, 0, 0),
                activeTab,
                onTabClick
              ),
              createTabButton(
                scope,
                "🪤 Traps",
                "traps",
                UDim2.new(0.666, 4, 0, 0),
                activeTab,
                onTabClick
              ),
            },
          }),

          -- Content (scrolling items)
          createContentFrame(scope, activeTab, selectedKey, onSelect),

          -- Action bar
          createActionBar(scope, activeTab, selectedKey, onAction),
        },
      }),
    },
  })
end

--[[
	Create the InventoryUI.
	
	@param props InventoryUIProps - Configuration props
	@return boolean - Success
]]
function InventoryUI.create(props: InventoryUIProps?): boolean
  if screenGui then
    warn("[InventoryUI] Already created")
    return false
  end

  props = props or {}
  cachedCallbacks = props

  local player = Players.LocalPlayer
  if not player then
    warn("[InventoryUI] No local player")
    return false
  end

  -- Create Fusion scope
  inventoryScope = Fusion.scoped({})
  local scope = inventoryScope :: Fusion.Scope

  -- State values
  currentTab = Value(scope, "eggs" :: TabType)
  selectedStackKey = Value(scope, nil :: string?)
  isVisible = Value(scope, false)

  -- Handlers
  local function onSelect(stack: StackedItem)
    local key = stack.stackKey
    local currentKey = peek(selectedStackKey :: Fusion.Value<string?>)

    if currentKey == key then
      -- Deselect
      (selectedStackKey :: Fusion.Value<string?>):set(nil)
      selectedItem = nil
    else
      -- Select
      (selectedStackKey :: Fusion.Value<string?>):set(key)
      selectedItem = {
        itemType = peek(currentTab :: Fusion.Value<TabType>),
        itemId = stack.itemIds[1],
        itemData = stack.representativeItem,
        stackCount = stack.count,
        stackedItemIds = stack.itemIds,
      }
    end

    if props.onItemSelected then
      props.onItemSelected(selectedItem)
    end
  end

  local function onAction(action: string)
    if selectedItem and props.onAction then
      props.onAction(action, selectedItem)
    end
  end

  local function onTabClick(tab: TabType)
    (currentTab :: Fusion.Value<TabType>):set(tab);
    (selectedStackKey :: Fusion.Value<string?>):set(nil)
    selectedItem = nil
    if props.onItemSelected then
      props.onItemSelected(nil)
    end
  end

  local function onClose()
    InventoryUI.setVisible(false)
  end

  -- Create ScreenGui
  screenGui = New(scope, "ScreenGui")({
    Name = "InventoryUI",
    Parent = player:WaitForChild("PlayerGui"),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,

    [Children] = {
      createMainFrame(
        scope,
        currentTab :: Fusion.Value<TabType>,
        selectedStackKey :: Fusion.Value<string?>,
        isVisible :: Fusion.Value<boolean>,
        onSelect,
        onAction,
        onTabClick,
        onClose
      ),
    },
  })

  return true
end

--[[
	Destroy the InventoryUI and cleanup.
]]
function InventoryUI.destroy()
  if inventoryScope then
    Fusion.doCleanup(inventoryScope)
    inventoryScope = nil
  end

  screenGui = nil
  currentTab = nil
  selectedStackKey = nil
  selectedItem = nil
  isVisible = nil
  cachedCallbacks = {}
end

--[[
	Check if created.
	
	@return boolean
]]
function InventoryUI.isCreated(): boolean
  return screenGui ~= nil
end

--[[
	Set visibility.
	
	@param visible boolean
]]
function InventoryUI.setVisible(visible: boolean)
  if isVisible then
    isVisible:set(visible)
  end

  if cachedCallbacks.onVisibilityChanged then
    cachedCallbacks.onVisibilityChanged(visible)
  end
end

--[[
	Get visibility.
	
	@return boolean
]]
function InventoryUI.isVisible(): boolean
  if isVisible then
    return peek(isVisible)
  end
  return false
end

--[[
	Toggle visibility.
]]
function InventoryUI.toggle()
  InventoryUI.setVisible(not InventoryUI.isVisible())
end

--[[
	Set the current tab.
	
	@param tab TabType
]]
function InventoryUI.setTab(tab: TabType)
  if currentTab then
    currentTab:set(tab)
    if selectedStackKey then
      selectedStackKey:set(nil)
    end
    selectedItem = nil
  end
end

--[[
	Get the current tab.
	
	@return TabType
]]
function InventoryUI.getCurrentTab(): TabType
  if currentTab then
    return peek(currentTab)
  end
  return "eggs"
end

--[[
	Get current selection.
	
	@return SelectedItem?
]]
function InventoryUI.getSelectedItem(): SelectedItem?
  return selectedItem
end

--[[
	Clear selection.
]]
function InventoryUI.clearSelection()
  if selectedStackKey then
    selectedStackKey:set(nil)
  end
  selectedItem = nil

  if cachedCallbacks.onItemSelected then
    cachedCallbacks.onItemSelected(nil)
  end
end

--[[
	Get the ScreenGui.
	
	@return ScreenGui?
]]
function InventoryUI.getScreenGui(): ScreenGui?
  return screenGui
end

--[[
	Set callback for item selection changes.
	
	@param callback (SelectedItem?) -> ()
]]
function InventoryUI.onItemSelected(callback: (SelectedItem?) -> ())
  cachedCallbacks.onItemSelected = callback
end

--[[
	Set callback for action button clicks.
	
	@param callback (string, SelectedItem) -> ()
]]
function InventoryUI.onAction(callback: (string, SelectedItem) -> ())
  cachedCallbacks.onAction = callback
end

--[[
	Set callback for visibility changes.
	
	@param callback (boolean) -> ()
]]
function InventoryUI.onVisibilityChanged(callback: (boolean) -> ())
  cachedCallbacks.onVisibilityChanged = callback
end

--[[
	Update from player data (legacy compatibility).
	The Fusion version auto-updates from State, but this preserves API.
	
	@param playerData any
]]
function InventoryUI.updateFromPlayerData(_playerData: any)
  -- No-op: Fusion version auto-updates from State.Player
end

--[[
	Get item counts from player data.
	
	@param playerData any
	@return { eggs: number, chickens: number, traps: number }
]]
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

--[[
	Get rarity colors (for external use).
	
	@return { [string]: Color3 }
]]
function InventoryUI.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

return InventoryUI
