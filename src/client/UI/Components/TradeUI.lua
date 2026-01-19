--[[
	TradeUI Component (Fusion)
	Creates and manages the trading UI for players to initiate and manage trades.
	Supports trade requests, offer management, and confirmation flow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local ForPairs = Fusion.ForPairs
local ForValues = Fusion.ForValues
local Cleanup = Fusion.Cleanup

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

export type TradeUIProps = {
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

-- Animation settings
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Module state
local TradeUI = {}
local screenGui: ScreenGui? = nil
local tradeScope: Fusion.Scope? = nil
local tradeVisible: Fusion.Value<boolean>? = nil
local requestVisible: Fusion.Value<boolean>? = nil
local tradeFrameSize: Fusion.Value<UDim2>? = nil

-- Trade state values
local tradeActive: Fusion.Value<boolean>? = nil
local partnerId: Fusion.Value<number?>? = nil
local partnerName: Fusion.Value<string?>? = nil
local localOfferItems: Fusion.Value<{ TradeItem }>? = nil
local localOfferConfirmed: Fusion.Value<boolean>? = nil
local partnerOfferItems: Fusion.Value<{ TradeItem }>? = nil
local partnerOfferConfirmed: Fusion.Value<boolean>? = nil
local tradeStatus: Fusion.Value<string>? = nil

-- Request state
local pendingRequests: Fusion.Value<{ TradeRequest }>? = nil
local currentRequest: Fusion.Value<TradeRequest?>? = nil

-- Callbacks
local cachedCallbacks: TradeUIProps = {}

-- Helper: Get display name for item
local function getItemDisplayName(item: TradeItem): string
  if item.itemType == "egg" then
    local config = EggConfig.get(item.itemData.eggType)
    return config and config.displayName or item.itemData.eggType
  else
    local config = ChickenConfig.get(item.itemData.chickenType)
    return config and config.displayName or item.itemData.chickenType
  end
end

-- Helper: Get rarity color for item
local function getItemRarityColor(item: TradeItem): Color3
  local rarity = item.itemData.rarity or "Common"
  return RARITY_COLORS[rarity] or RARITY_COLORS.Common
end

-- Create a trade item slot component
local function createTradeItemSlot(
  scope: Fusion.Scope,
  item: TradeItem,
  isLocal: boolean,
  layoutOrder: number
): Frame
  local rarity = item.itemData.rarity or "Common"
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  local displayName = getItemDisplayName(item)

  return New(scope, "Frame")({
    Name = "TradeSlot_" .. item.itemId,
    Size = UDim2.new(1, -8, 0, 50),
    BackgroundColor3 = Theme.Colors.Surface,
    BorderSizePixel = 0,
    LayoutOrder = layoutOrder,

    [Children] = {
      New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
      New(scope, "UIStroke")({
        Color = rarityColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 5, 0.5, -20),
        BackgroundTransparency = 1,
        Text = item.itemType == "egg" and "🥚" or "🐔",
        TextSize = 24,
        TextColor3 = rarityColor,
      }),

      -- Item name
      New(scope, "TextLabel")({
        Name = "NameLabel",
        Size = UDim2.new(1, -90, 0, 20),
        Position = UDim2.new(0, 50, 0, 5),
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 13,
        FontFace = Theme.Typography.PrimaryBold,
        Text = displayName,
      }),

      -- Rarity label
      New(scope, "TextLabel")({
        Name = "RarityLabel",
        Size = UDim2.new(1, -90, 0, 16),
        Position = UDim2.new(0, 50, 0, 26),
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = rarityColor,
        TextSize = 11,
        FontFace = Theme.Typography.PrimarySemiBold,
        Text = rarity,
      }),

      -- Remove button (only for local items)
      if isLocal
        then New(scope, "TextButton")({
          Name = "RemoveButton",
          Size = UDim2.new(0, 28, 0, 28),
          Position = UDim2.new(1, -34, 0.5, -14),
          BackgroundColor3 = Color3.fromRGB(180, 60, 60),
          Text = "X",
          TextColor3 = Theme.Colors.TextPrimary,
          TextSize = 14,
          FontFace = Theme.Typography.PrimaryBold,
          BorderSizePixel = 0,
          AutoButtonColor = true,

          [Children] = {
            New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
          },

          [OnEvent("MouseButton1Click")] = function()
            if cachedCallbacks.onRemoveItem then
              cachedCallbacks.onRemoveItem(item.itemId)
            end
          end,
        })
        else nil,
    },
  })
end

-- Create offer panel component
local function createOfferPanel(
  scope: Fusion.Scope,
  title: string,
  isLocal: boolean,
  items: Fusion.Value<{ TradeItem }>,
  confirmed: Fusion.Value<boolean>,
  position: UDim2
): Frame
  -- Create computed status color
  local statusColor = Computed(scope, function(use)
    return use(confirmed) and Color3.fromRGB(80, 200, 80) or Theme.Colors.TextMuted
  end)

  -- Create item slots dynamically
  local itemSlots = Computed(scope, function(use)
    local currentItems = use(items)
    local slots = {}
    for i, item in ipairs(currentItems) do
      table.insert(slots, createTradeItemSlot(scope, item, isLocal, i))
    end
    return slots
  end)

  return New(scope, "Frame")({
    Name = isLocal and "LocalOfferPanel" or "PartnerOfferPanel",
    Size = UDim2.new(0.5, -12, 1, -60),
    Position = position,
    BackgroundColor3 = Theme.Colors.BackgroundDark,
    BorderSizePixel = 0,

    [Children] = {
      New(scope, "UICorner")({ CornerRadius = UDim.new(0, 8) }),

      -- Title
      New(scope, "TextLabel")({
        Name = "Title",
        Size = UDim2.new(1, -12, 0, 30),
        Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 14,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Status indicator
      New(scope, "Frame")({
        Name = "StatusIndicator",
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(1, -18, 0, 12),
        BackgroundColor3 = statusColor,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(1, 0) }),
        },
      }),

      -- Scrolling content
      New(scope, "ScrollingFrame")({
        Name = "ItemsFrame",
        Size = UDim2.new(1, -12, 1, -44),
        Position = UDim2.new(0, 6, 0, 38),
        BackgroundColor3 = Theme.Colors.BackgroundDark,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Colors.TextMuted,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
          New(scope, "UIListLayout")({
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4),
          }),
          New(scope, "UIPadding")({
            PaddingTop = UDim.new(0, 4),
            PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 4),
            PaddingRight = UDim.new(0, 4),
          }),

          -- Item slots or empty message
          Computed(scope, function(use)
            local currentItems = use(items)
            if #currentItems == 0 then
              return New(scope, "TextLabel")({
                Name = "EmptyLabel",
                Size = UDim2.new(1, -8, 0, 40),
                BackgroundTransparency = 1,
                Text = isLocal and "Add items to trade" or "Waiting for items...",
                TextColor3 = Theme.Colors.TextMuted,
                TextSize = 12,
                TextWrapped = true,
                FontFace = Theme.Typography.Primary,
              })
            end
            return nil
          end),

          itemSlots,
        },
      }),
    },
  })
end

-- Create the main trade frame
local function createTradeFrame(scope: Fusion.Scope): Frame
  local computedTitle = Computed(scope, function(use)
    local name = use(partnerName)
    return name and ("🤝 Trade with " .. name) or "🤝 Trade"
  end)

  local partnerPanelTitle = Computed(scope, function(use)
    local name = use(partnerName)
    return name and (name .. "'s Offer") or "Partner's Offer"
  end)

  local confirmButtonText = Computed(scope, function(use)
    return use(localOfferConfirmed) and "✓ Confirmed" or "✓ Confirm"
  end)

  local confirmButtonColor = Computed(scope, function(use)
    return use(localOfferConfirmed) and Color3.fromRGB(60, 120, 60) or Color3.fromRGB(80, 160, 80)
  end)

  return New(scope, "Frame")({
    Name = "TradeFrame",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = tradeFrameSize,
    BackgroundColor3 = Theme.Colors.Background,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    Visible = tradeVisible,

    [Children] = {
      New(scope, "UICorner")({ CornerRadius = UDim.new(0, 12) }),
      New(scope, "UIStroke")({
        Color = Theme.Colors.Borders.ColorLight,
        Thickness = 2,
      }),

      -- Title bar
      New(scope, "Frame")({
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Colors.Surface,
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 12) }),
          -- Cover bottom corners
          New(scope, "Frame")({
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 1, -12),
            BackgroundColor3 = Theme.Colors.Surface,
            BorderSizePixel = 0,
          }),
          New(scope, "TextLabel")({
            Name = "Title",
            Size = UDim2.new(1, -20, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Text = computedTitle,
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 16,
            FontFace = Theme.Typography.PrimaryBold,
            TextXAlignment = Enum.TextXAlignment.Left,
          }),
        },
      }),

      -- Content container
      New(scope, "Frame")({
        Name = "ContentContainer",
        Size = UDim2.new(1, -16, 1, -100),
        Position = UDim2.new(0, 8, 0, 48),
        BackgroundTransparency = 1,

        [Children] = {
          createOfferPanel(
            scope,
            "Your Offer",
            true,
            localOfferItems,
            localOfferConfirmed,
            UDim2.new(0, 0, 0, 0)
          ),
          createOfferPanel(
            scope,
            partnerPanelTitle,
            false,
            partnerOfferItems,
            partnerOfferConfirmed,
            UDim2.new(0.5, 8, 0, 0)
          ),
        },
      }),

      -- Button frame
      New(scope, "Frame")({
        Name = "ButtonFrame",
        Size = UDim2.new(1, -16, 0, 44),
        Position = UDim2.new(0, 8, 1, -52),
        BackgroundTransparency = 1,

        [Children] = {
          -- Confirm button
          New(scope, "TextButton")({
            Name = "ConfirmButton",
            Size = UDim2.new(0.5, -4, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = confirmButtonColor,
            Text = confirmButtonText,
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 14,
            FontFace = Theme.Typography.PrimaryBold,
            BorderSizePixel = 0,
            AutoButtonColor = true,

            [Children] = {
              New(scope, "UICorner")({ CornerRadius = UDim.new(0, 8) }),
            },

            [OnEvent("MouseButton1Click")] = function()
              if cachedCallbacks.onConfirm then
                cachedCallbacks.onConfirm()
              end
            end,
          }),

          -- Cancel button
          New(scope, "TextButton")({
            Name = "CancelButton",
            Size = UDim2.new(0.5, -4, 1, 0),
            Position = UDim2.new(0.5, 4, 0, 0),
            BackgroundColor3 = Color3.fromRGB(180, 80, 80),
            Text = "X Cancel",
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 14,
            FontFace = Theme.Typography.PrimaryBold,
            BorderSizePixel = 0,
            AutoButtonColor = true,

            [Children] = {
              New(scope, "UICorner")({ CornerRadius = UDim.new(0, 8) }),
            },

            [OnEvent("MouseButton1Click")] = function()
              if cachedCallbacks.onCancel then
                cachedCallbacks.onCancel()
              end
            end,
          }),
        },
      }),
    },
  })
end

-- Create request notification frame
local function createRequestFrame(scope: Fusion.Scope): Frame
  local requestText = Computed(scope, function(use)
    local request = use(currentRequest)
    if request then
      return "🤝 Trade request from " .. request.fromPlayerName
    end
    return "🤝 Trade request"
  end)

  return New(scope, "Frame")({
    Name = "RequestFrame",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 60),
    Size = UDim2.new(0, 300, 0, 80),
    BackgroundColor3 = Theme.Colors.Surface,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    Visible = requestVisible,

    [Children] = {
      New(scope, "UICorner")({ CornerRadius = UDim.new(0, 10) }),
      New(scope, "UIStroke")({
        Color = Theme.Colors.Info,
        Thickness = 2,
      }),

      -- Request text
      New(scope, "TextLabel")({
        Name = "RequestText",
        Size = UDim2.new(1, -16, 0, 30),
        Position = UDim2.new(0, 8, 0, 8),
        BackgroundTransparency = 1,
        Text = requestText,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 14,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),

      -- Accept button
      New(scope, "TextButton")({
        Name = "AcceptButton",
        Size = UDim2.new(0.5, -12, 0, 32),
        Position = UDim2.new(0, 8, 1, -40),
        BackgroundColor3 = Color3.fromRGB(80, 160, 80),
        Text = "✓ Accept",
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 13,
        FontFace = Theme.Typography.PrimaryBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
        },

        [OnEvent("MouseButton1Click")] = function()
          local request = currentRequest and Fusion.peek(currentRequest)
          if request and cachedCallbacks.onTradeAccept then
            cachedCallbacks.onTradeAccept(request.fromPlayerId)
          end
          TradeUI.hideTradeRequest()
        end,
      }),

      -- Decline button
      New(scope, "TextButton")({
        Name = "DeclineButton",
        Size = UDim2.new(0.5, -12, 0, 32),
        Position = UDim2.new(0.5, 4, 1, -40),
        BackgroundColor3 = Color3.fromRGB(180, 80, 80),
        Text = "X Decline",
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 13,
        FontFace = Theme.Typography.PrimaryBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
        },

        [OnEvent("MouseButton1Click")] = function()
          local request = currentRequest and Fusion.peek(currentRequest)
          if request and cachedCallbacks.onTradeDecline then
            cachedCallbacks.onTradeDecline(request.fromPlayerId)
          end
          TradeUI.hideTradeRequest()
        end,
      }),
    },
  })
end

-- Initialize the Trade UI
function TradeUI.create(props: TradeUIProps?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("TradeUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  TradeUI.destroy()

  -- Store callbacks
  if props then
    cachedCallbacks = props
  end

  -- Create Fusion scope
  tradeScope = Fusion.scoped({})

  -- Create reactive state
  tradeVisible = Value(tradeScope, false)
  requestVisible = Value(tradeScope, false)
  tradeFrameSize = Value(tradeScope, UDim2.new(0, 500, 0, 400))

  tradeActive = Value(tradeScope, false)
  partnerId = Value(tradeScope, nil :: number?)
  partnerName = Value(tradeScope, nil :: string?)
  localOfferItems = Value(tradeScope, {} :: { TradeItem })
  localOfferConfirmed = Value(tradeScope, false)
  partnerOfferItems = Value(tradeScope, {} :: { TradeItem })
  partnerOfferConfirmed = Value(tradeScope, false)
  tradeStatus = Value(tradeScope, "pending")

  pendingRequests = Value(tradeScope, {} :: { TradeRequest })
  currentRequest = Value(tradeScope, nil :: TradeRequest?)

  -- Create screen GUI with Fusion
  screenGui = New(tradeScope, "ScreenGui")({
    Name = "TradeUI",
    Parent = player:WaitForChild("PlayerGui"),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,

    [Children] = {
      createTradeFrame(tradeScope),
      createRequestFrame(tradeScope),
    },
  })

  return true
end

-- Destroy the Trade UI
function TradeUI.destroy()
  if tradeScope then
    Fusion.doCleanup(tradeScope)
    tradeScope = nil
  end

  screenGui = nil
  tradeVisible = nil
  requestVisible = nil
  tradeFrameSize = nil
  tradeActive = nil
  partnerId = nil
  partnerName = nil
  localOfferItems = nil
  localOfferConfirmed = nil
  partnerOfferItems = nil
  partnerOfferConfirmed = nil
  tradeStatus = nil
  pendingRequests = nil
  currentRequest = nil
  cachedCallbacks = {}
end

-- Reset trade state
function TradeUI.resetTradeState()
  if tradeActive then
    tradeActive:set(false)
  end
  if partnerId then
    partnerId:set(nil)
  end
  if partnerName then
    partnerName:set(nil)
  end
  if localOfferItems then
    localOfferItems:set({})
  end
  if localOfferConfirmed then
    localOfferConfirmed:set(false)
  end
  if partnerOfferItems then
    partnerOfferItems:set({})
  end
  if partnerOfferConfirmed then
    partnerOfferConfirmed:set(false)
  end
  if tradeStatus then
    tradeStatus:set("pending")
  end
end

-- Show trade request notification
function TradeUI.showTradeRequest(fromPlayerId: number, fromPlayerName: string)
  local request: TradeRequest = {
    fromPlayerId = fromPlayerId,
    fromPlayerName = fromPlayerName,
    timestamp = os.time(),
  }

  -- Add to pending requests
  if pendingRequests then
    local requests = Fusion.peek(pendingRequests)
    local newRequests = table.clone(requests)
    table.insert(newRequests, request)
    pendingRequests:set(newRequests)
  end

  -- Show current request
  if currentRequest then
    currentRequest:set(request)
  end
  if requestVisible then
    requestVisible:set(true)
  end
end

-- Hide trade request notification
function TradeUI.hideTradeRequest()
  if requestVisible then
    requestVisible:set(false)
  end

  -- Remove oldest request
  if pendingRequests then
    local requests = Fusion.peek(pendingRequests)
    if #requests > 0 then
      local newRequests = table.clone(requests)
      table.remove(newRequests, 1)
      pendingRequests:set(newRequests)

      -- Show next request if any
      if #newRequests > 0 and currentRequest then
        currentRequest:set(newRequests[1])
        if requestVisible then
          requestVisible:set(true)
        end
      end
    end
  end
end

-- Start a trade with a player
function TradeUI.startTrade(targetPartnerId: number, targetPartnerName: string)
  if tradeActive then
    tradeActive:set(true)
  end
  if partnerId then
    partnerId:set(targetPartnerId)
  end
  if partnerName then
    partnerName:set(targetPartnerName)
  end
  if tradeStatus then
    tradeStatus:set("negotiating")
  end
  if localOfferItems then
    localOfferItems:set({})
  end
  if localOfferConfirmed then
    localOfferConfirmed:set(false)
  end
  if partnerOfferItems then
    partnerOfferItems:set({})
  end
  if partnerOfferConfirmed then
    partnerOfferConfirmed:set(false)
  end

  TradeUI.show()
end

-- Add item to local offer
function TradeUI.addItemToOffer(item: TradeItem): boolean
  if not localOfferItems then
    return false
  end

  local items = Fusion.peek(localOfferItems)

  -- Check if item already in offer
  for _, existingItem in ipairs(items) do
    if existingItem.itemId == item.itemId then
      return false
    end
  end

  -- Reset confirmation when offer changes
  if localOfferConfirmed then
    localOfferConfirmed:set(false)
  end

  local newItems = table.clone(items)
  table.insert(newItems, item)
  localOfferItems:set(newItems)

  if cachedCallbacks.onAddItem then
    cachedCallbacks.onAddItem(item)
  end

  return true
end

-- Remove item from local offer
function TradeUI.removeItemFromOffer(itemId: string): boolean
  if not localOfferItems then
    return false
  end

  local items = Fusion.peek(localOfferItems)

  for i, item in ipairs(items) do
    if item.itemId == itemId then
      local newItems = table.clone(items)
      table.remove(newItems, i)
      localOfferItems:set(newItems)

      -- Reset confirmation when offer changes
      if localOfferConfirmed then
        localOfferConfirmed:set(false)
      end

      return true
    end
  end

  return false
end

-- Update partner's offer (called from network)
function TradeUI.updatePartnerOffer(items: { TradeItem }, confirmed: boolean)
  if partnerOfferItems then
    partnerOfferItems:set(items)
  end
  if partnerOfferConfirmed then
    partnerOfferConfirmed:set(confirmed)
  end
end

-- Confirm local offer
function TradeUI.confirmOffer()
  if localOfferConfirmed then
    localOfferConfirmed:set(true)
  end
end

-- Unconfirm local offer
function TradeUI.unconfirmOffer()
  if localOfferConfirmed then
    localOfferConfirmed:set(false)
  end
end

-- Check if both parties confirmed
function TradeUI.areBothConfirmed(): boolean
  local localConfirmed = localOfferConfirmed and Fusion.peek(localOfferConfirmed) or false
  local partnerConfirmed = partnerOfferConfirmed and Fusion.peek(partnerOfferConfirmed) or false
  return localConfirmed and partnerConfirmed
end

-- Update display (no-op for Fusion - reactive updates)
function TradeUI.updateDisplay()
  -- Fusion handles this automatically via reactive state
end

-- End trade
function TradeUI.endTrade(status: "completed" | "cancelled")
  if tradeStatus then
    tradeStatus:set(status)
  end
  TradeUI.hide()
  TradeUI.resetTradeState()
end

-- Show the trade UI
function TradeUI.show()
  if tradeVisible then
    tradeVisible:set(true)
  end

  -- Animate in
  if tradeFrameSize then
    tradeFrameSize:set(UDim2.new(0, 500, 0, 0))
    task.spawn(function()
      for i = 1, 20 do
        if not tradeFrameSize then
          break
        end
        local t = i / 20
        -- Back ease out
        local overshoot = 1.70158
        local scale = 1 + overshoot * ((t - 1) ^ 3) + overshoot * ((t - 1) ^ 2)
        local height = 400 * math.max(0, math.min(1.1, scale))
        tradeFrameSize:set(UDim2.new(0, 500, 0, height))
        task.wait(0.2 / 20)
      end
      if tradeFrameSize then
        tradeFrameSize:set(UDim2.new(0, 500, 0, 400))
      end
    end)
  end
end

-- Hide the trade UI
function TradeUI.hide()
  if tradeVisible then
    tradeVisible:set(false)
  end
end

-- Toggle visibility
function TradeUI.toggle()
  if tradeVisible then
    tradeVisible:set(not Fusion.peek(tradeVisible))
  end
end

-- Check if visible
function TradeUI.isVisible(): boolean
  return tradeVisible ~= nil and Fusion.peek(tradeVisible) == true
end

-- Check if created
function TradeUI.isCreated(): boolean
  return screenGui ~= nil and tradeScope ~= nil
end

-- Check if trade is active
function TradeUI.isTradeActive(): boolean
  return tradeActive ~= nil and Fusion.peek(tradeActive) == true
end

-- Get current trade state
function TradeUI.getTradeState(): TradeState
  return {
    isActive = tradeActive and Fusion.peek(tradeActive) or false,
    partnerId = partnerId and Fusion.peek(partnerId),
    partnerName = partnerName and Fusion.peek(partnerName),
    localOffer = {
      items = localOfferItems and Fusion.peek(localOfferItems) or {},
      confirmed = localOfferConfirmed and Fusion.peek(localOfferConfirmed) or false,
    },
    partnerOffer = {
      items = partnerOfferItems and Fusion.peek(partnerOfferItems) or {},
      confirmed = partnerOfferConfirmed and Fusion.peek(partnerOfferConfirmed) or false,
    },
    status = tradeStatus and Fusion.peek(tradeStatus) or "pending",
  }
end

-- Get local offer
function TradeUI.getLocalOffer(): TradeOffer
  return {
    items = localOfferItems and Fusion.peek(localOfferItems) or {},
    confirmed = localOfferConfirmed and Fusion.peek(localOfferConfirmed) or false,
  }
end

-- Get partner offer
function TradeUI.getPartnerOffer(): TradeOffer
  return {
    items = partnerOfferItems and Fusion.peek(partnerOfferItems) or {},
    confirmed = partnerOfferConfirmed and Fusion.peek(partnerOfferConfirmed) or false,
  }
end

-- Get partner info
function TradeUI.getPartnerInfo(): (number?, string?)
  local id = partnerId and Fusion.peek(partnerId)
  local name = partnerName and Fusion.peek(partnerName)
  return id, name
end

-- Set callback setters for legacy API compatibility
function TradeUI.setOnTradeRequest(callback: (number) -> ())
  cachedCallbacks.onTradeRequest = callback
end

function TradeUI.setOnTradeAccept(callback: (number) -> ())
  cachedCallbacks.onTradeAccept = callback
end

function TradeUI.setOnTradeDecline(callback: (number) -> ())
  cachedCallbacks.onTradeDecline = callback
end

function TradeUI.setOnAddItem(callback: (TradeItem) -> ())
  cachedCallbacks.onAddItem = callback
end

function TradeUI.setOnRemoveItem(callback: (string) -> ())
  cachedCallbacks.onRemoveItem = callback
end

function TradeUI.setOnConfirm(callback: () -> ())
  cachedCallbacks.onConfirm = callback
end

function TradeUI.setOnCancel(callback: () -> ())
  cachedCallbacks.onCancel = callback
end

-- Get pending requests
function TradeUI.getPendingRequests(): { TradeRequest }
  return pendingRequests and Fusion.peek(pendingRequests) or {}
end

-- Clear pending requests
function TradeUI.clearPendingRequests()
  if pendingRequests then
    pendingRequests:set({})
  end
  if currentRequest then
    currentRequest:set(nil)
  end
  TradeUI.hideTradeRequest()
end

-- Get the screen GUI
function TradeUI.getScreenGui(): ScreenGui?
  return screenGui
end

return TradeUI
