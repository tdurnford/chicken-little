--[[
	StoreUI Component (Fusion)
	Displays the store where players can browse and purchase eggs, traps, power-ups, and weapons.
	Uses reactive Fusion state for automatic UI updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local Store = require(Shared:WaitForChild("Store"))
local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
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
local ForValues = Fusion.ForValues
local Cleanup = Fusion.Cleanup

-- Types
export type TabType = "eggs" | "supplies" | "powerups" | "weapons"

export type StoreUIProps = {
  onEggPurchase: ((eggType: string, quantity: number) -> ())?,
  onTrapPurchase: ((trapType: string) -> ())?,
  onPowerUpPurchase: ((powerUpId: string) -> ())?,
  onWeaponPurchase: ((weaponType: string) -> ())?,
  onRobuxPurchase: ((itemType: string, itemId: string) -> ())?,
  onReplenish: (() -> ())?,
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

-- Tier colors for supplies/traps and weapons
local TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Improved = Color3.fromRGB(100, 200, 100),
  Advanced = Color3.fromRGB(100, 150, 255),
  Expert = Color3.fromRGB(180, 100, 255),
  Master = Color3.fromRGB(255, 180, 50),
  Ultimate = Color3.fromRGB(255, 100, 150),
  Standard = Color3.fromRGB(100, 150, 255),
  Premium = Color3.fromRGB(255, 180, 50),
}

-- Constants
local CARD_HEIGHT = 90
local CARD_PADDING = 8

-- Module state
local StoreUI = {}
local screenGui: ScreenGui? = nil
local storeScope: Fusion.Scope? = nil
local currentTab: Fusion.Value<TabType>? = nil
local isVisible: Fusion.Value<boolean>? = nil
local restockTime: Fusion.Value<number>? = nil
local cachedCallbacks: StoreUIProps = {}
local timerConnection: RBXScriptConnection? = nil

-- Cached data for display
local cachedOwnedWeapons: Fusion.Value<{ [string]: boolean }>? = nil
local cachedActivePowerUps: Fusion.Value<{ [string]: number }>? = nil

-- Helper: Format restock time
local function formatRestockTime(seconds: number): string
  if seconds <= 0 then
    return "Restocking..."
  end
  local minutes = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("Restocks in %d:%02d", minutes, secs)
end

-- Helper: Get egg description
local function getEggDescription(eggType: string): string
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return "Contains mysterious chickens"
  end

  local rarestOutcome = eggConfig.hatchOutcomes[1]
  for _, outcome in ipairs(eggConfig.hatchOutcomes) do
    if outcome.probability < rarestOutcome.probability then
      rarestOutcome = outcome
    end
  end

  local chickenConfig = ChickenConfig.get(rarestOutcome.chickenType)
  local rarestName = chickenConfig and chickenConfig.displayName or rarestOutcome.chickenType

  return "Contains "
    .. eggConfig.rarity:lower()
    .. " chickens • "
    .. rarestOutcome.probability
    .. "% "
    .. rarestName
end

-- Helper: Get border color based on item type
local function getBorderColor(itemType: string, rarity: string?, tier: string?): Color3
  if tier then
    return TIER_COLORS[tier] or TIER_COLORS.Basic
  end
  return RARITY_COLORS[rarity or "Common"] or RARITY_COLORS.Common
end

-- Create a buy button (cash)
local function createCashButton(
  scope: Fusion.Scope,
  price: number,
  isSoldOut: Fusion.Computed<boolean>,
  canAfford: Fusion.Computed<boolean>,
  onClick: () -> ()
)
  local bgColor = Computed(scope, function(use)
    if use(isSoldOut) then
      return Color3.fromRGB(80, 80, 80)
    elseif use(canAfford) then
      return Color3.fromRGB(50, 180, 50)
    else
      return Color3.fromRGB(80, 80, 80)
    end
  end)

  local textTransparency = Computed(scope, function(use)
    return (use(isSoldOut) or not use(canAfford)) and 0.5 or 0
  end)

  return New(scope, "TextButton")({
    Name = "BuyButton",
    Size = UDim2.new(0, 80, 0, 34),
    BackgroundColor3 = bgColor,
    Text = "",
    AutoButtonColor = false,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 6),
      }),
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 20, 1, 0),
        Position = UDim2.new(0, 4, 0, 0),
        BackgroundTransparency = 1,
        Text = "💵",
        TextSize = 14,
        TextTransparency = textTransparency,
      }),
      New(scope, "TextLabel")({
        Name = "Price",
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.new(0, 24, 0, 0),
        BackgroundTransparency = 1,
        Text = MoneyScaling.formatCleanCurrency(price),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = textTransparency,
      }),
    },

    [OnEvent("MouseButton1Click")] = function()
      if not (isSoldOut :: any):get() and (canAfford :: any):get() then
        onClick()
      end
    end,
  })
end

-- Create a Robux buy button
local function createRobuxButton(scope: Fusion.Scope, robuxPrice: number, onClick: () -> ())
  return New(scope, "TextButton")({
    Name = "RobuxButton",
    Size = UDim2.new(0, 80, 0, 34),
    BackgroundColor3 = Color3.fromRGB(0, 120, 215),
    Text = "",
    AutoButtonColor = false,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 6),
      }),
      New(scope, "UIStroke")({
        Color = Color3.fromRGB(100, 200, 255),
        Thickness = 2,
      }),
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 20, 1, 0),
        Position = UDim2.new(0, 4, 0, 0),
        BackgroundTransparency = 1,
        Text = "💎",
        TextSize = 14,
      }),
      New(scope, "TextLabel")({
        Name = "Price",
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.new(0, 24, 0, 0),
        BackgroundTransparency = 1,
        Text = tostring(robuxPrice),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),
    },

    [OnEvent("MouseButton1Click")] = onClick,
  })
end

-- Create an egg card
local function createEggCard(
  scope: Fusion.Scope,
  item: Store.InventoryItem,
  layoutOrder: number,
  onBuy: () -> (),
  onRobuxBuy: () -> ()
)
  local borderColor = getBorderColor("egg", item.rarity, nil)

  local isSoldOut = Computed(scope, function(use)
    return item.stock <= 0
  end)

  local canAfford = Computed(scope, function(use)
    local money = use(State.Player.Money)
    return money >= item.price
  end)

  return New(scope, "Frame")({
    Name = item.id,
    Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
    LayoutOrder = layoutOrder,
    BackgroundColor3 = Color3.fromRGB(45, 45, 60),

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIStroke")({
        Color = borderColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Rarity bar (left edge)
      New(scope, "Frame")({
        Name = "RarityBar",
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = borderColor,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 4),
          }),
        },
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 12, 0.5, -20),
        BackgroundTransparency = 1,
        Text = "🥚",
        TextSize = 32,
        TextColor3 = borderColor,
      }),

      -- Name
      New(scope, "TextLabel")({
        Name = "Name",
        Size = UDim2.new(0.4, -60, 0, 22),
        Position = UDim2.new(0, 58, 0, 8),
        BackgroundTransparency = 1,
        Text = item.displayName,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 16,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Description
      New(scope, "TextLabel")({
        Name = "Description",
        Size = UDim2.new(0.45, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 32),
        BackgroundTransparency = 1,
        Text = getEggDescription(item.id),
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 11,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Rarity + Stock
      New(scope, "TextLabel")({
        Name = "RarityStock",
        Size = UDim2.new(0.35, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 52),
        BackgroundTransparency = 1,
        Text = item.rarity .. " • " .. (item.stock > 0 and ("x" .. item.stock) or "SOLD OUT"),
        TextColor3 = item.stock > 0 and Theme.Colors.TextMuted or Color3.fromRGB(255, 100, 100),
        TextSize = 12,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Buttons container
      New(scope, "Frame")({
        Name = "Buttons",
        Size = UDim2.new(0, 80, 0, 76),
        Position = UDim2.new(1, -88, 0.5, -38),
        BackgroundTransparency = 1,

        [Children] = {
          New(scope, "UIListLayout")({
            FillDirection = Enum.FillDirection.Vertical,
            Padding = UDim.new(0, 4),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
          }),
          createCashButton(scope, item.price, isSoldOut, canAfford, onBuy),
          createRobuxButton(scope, item.robuxPrice, onRobuxBuy),
        },
      }),
    },
  })
end

-- Create a supply/trap card
local function createSupplyCard(
  scope: Fusion.Scope,
  item: Store.SupplyItem,
  layoutOrder: number,
  onBuy: () -> (),
  onRobuxBuy: () -> ()
)
  local borderColor = getBorderColor("trap", nil, item.tier)

  local isSoldOut = Computed(scope, function()
    return false -- Traps don't have stock limits
  end)

  local canAfford = Computed(scope, function(use)
    local money = use(State.Player.Money)
    return money >= item.price
  end)

  local config = TrapConfig.get(item.id)
  local effectiveness = config and config.effectiveness or 0

  return New(scope, "Frame")({
    Name = item.id,
    Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
    LayoutOrder = layoutOrder,
    BackgroundColor3 = Color3.fromRGB(45, 45, 60),

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIStroke")({
        Color = borderColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Tier bar
      New(scope, "Frame")({
        Name = "TierBar",
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = borderColor,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 4),
          }),
        },
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 12, 0.5, -20),
        BackgroundTransparency = 1,
        Text = item.icon,
        TextSize = 32,
      }),

      -- Name
      New(scope, "TextLabel")({
        Name = "Name",
        Size = UDim2.new(0.4, -60, 0, 22),
        Position = UDim2.new(0, 58, 0, 8),
        BackgroundTransparency = 1,
        Text = item.displayName,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 16,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Description
      New(scope, "TextLabel")({
        Name = "Description",
        Size = UDim2.new(0.45, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 32),
        BackgroundTransparency = 1,
        Text = item.description,
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 11,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Tier + Effectiveness
      New(scope, "TextLabel")({
        Name = "TierInfo",
        Size = UDim2.new(0.35, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 52),
        BackgroundTransparency = 1,
        Text = item.tier .. " • +" .. tostring(math.floor(effectiveness * 100)) .. "% catch rate",
        TextColor3 = Theme.Colors.TextMuted,
        TextSize = 12,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Buttons container
      New(scope, "Frame")({
        Name = "Buttons",
        Size = UDim2.new(0, 80, 0, 76),
        Position = UDim2.new(1, -88, 0.5, -38),
        BackgroundTransparency = 1,

        [Children] = {
          New(scope, "UIListLayout")({
            FillDirection = Enum.FillDirection.Vertical,
            Padding = UDim.new(0, 4),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
          }),
          createCashButton(scope, item.price, isSoldOut, canAfford, onBuy),
          createRobuxButton(scope, item.robuxPrice, onRobuxBuy),
        },
      }),
    },
  })
end

-- Create a power-up card
local function createPowerUpCard(
  scope: Fusion.Scope,
  config: PowerUpConfig.PowerUpConfig,
  layoutOrder: number,
  onBuy: () -> ()
)
  local isLuck = string.find(config.id, "HatchLuck") ~= nil
  local barColor = isLuck and Color3.fromRGB(50, 205, 50) or Color3.fromRGB(255, 215, 0)

  local isActive = Computed(scope, function(use)
    if not cachedActivePowerUps then
      return false
    end
    local powerUps = use(cachedActivePowerUps)
    local powerUpType = PowerUpConfig.getPowerUpType(config.id)
    local expiresAt = powerUpType and powerUps[powerUpType]
    return expiresAt and os.time() < expiresAt
  end)

  local statusText = Computed(scope, function(use)
    if use(isActive) then
      return "✓ ACTIVE"
    end
    return "Duration: " .. PowerUpConfig.formatRemainingTime(config.durationSeconds)
  end)

  local statusColor = Computed(scope, function(use)
    return if use(isActive) then Color3.fromRGB(100, 200, 100) else Theme.Colors.TextMuted
  end)

  return New(scope, "Frame")({
    Name = config.id,
    Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
    LayoutOrder = layoutOrder,
    BackgroundColor3 = Color3.fromRGB(45, 45, 60),

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIStroke")({
        Color = barColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Color bar
      New(scope, "Frame")({
        Name = "ColorBar",
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = barColor,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 4),
          }),
        },
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 12, 0.5, -20),
        BackgroundTransparency = 1,
        Text = config.icon,
        TextSize = 32,
      }),

      -- Name
      New(scope, "TextLabel")({
        Name = "Name",
        Size = UDim2.new(0.4, -60, 0, 22),
        Position = UDim2.new(0, 58, 0, 8),
        BackgroundTransparency = 1,
        Text = config.displayName,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 16,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Description
      New(scope, "TextLabel")({
        Name = "Description",
        Size = UDim2.new(0.45, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 32),
        BackgroundTransparency = 1,
        Text = config.description,
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 11,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Status
      New(scope, "TextLabel")({
        Name = "Status",
        Size = UDim2.new(0.35, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 52),
        BackgroundTransparency = 1,
        Text = statusText,
        TextColor3 = statusColor,
        TextSize = 12,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Buy button (Robux only)
      New(scope, "Frame")({
        Name = "Buttons",
        Size = UDim2.new(0, 80, 0, 38),
        Position = UDim2.new(1, -88, 0.5, -19),
        BackgroundTransparency = 1,

        [Children] = {
          createRobuxButton(scope, config.robuxPrice, onBuy),
        },
      }),
    },
  })
end

-- Create a weapon card
local function createWeaponCard(
  scope: Fusion.Scope,
  item: Store.WeaponItem,
  layoutOrder: number,
  onBuy: () -> (),
  onRobuxBuy: () -> ()
)
  local borderColor = getBorderColor("weapon", nil, item.tier)

  local isOwned = Computed(scope, function(use)
    if not cachedOwnedWeapons then
      return false
    end
    local owned = use(cachedOwnedWeapons)
    return owned[item.id] == true
  end)

  local isFree = item.price == 0

  local canAfford = Computed(scope, function(use)
    local money = use(State.Player.Money)
    return money >= item.price
  end)

  local isSoldOut = Computed(scope, function(use)
    return use(isOwned) or isFree
  end)

  local statusText = Computed(scope, function(use)
    if use(isOwned) then
      return "✓ OWNED"
    elseif isFree then
      return "★ STARTER"
    end
    return ""
  end)

  local statusColor = Computed(scope, function(use)
    if use(isOwned) then
      return Color3.fromRGB(100, 200, 100)
    end
    return Theme.Colors.TextMuted
  end)

  local showButtons = Computed(scope, function(use)
    return not use(isOwned) and not isFree
  end)

  return New(scope, "Frame")({
    Name = item.id,
    Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
    LayoutOrder = layoutOrder,
    BackgroundColor3 = Color3.fromRGB(45, 45, 60),

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIStroke")({
        Color = borderColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Tier bar
      New(scope, "Frame")({
        Name = "TierBar",
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = borderColor,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 4),
          }),
        },
      }),

      -- Icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 12, 0.5, -20),
        BackgroundTransparency = 1,
        Text = item.icon,
        TextSize = 32,
      }),

      -- Name
      New(scope, "TextLabel")({
        Name = "Name",
        Size = UDim2.new(0.4, -60, 0, 22),
        Position = UDim2.new(0, 58, 0, 8),
        BackgroundTransparency = 1,
        Text = item.displayName,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 16,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Description
      New(scope, "TextLabel")({
        Name = "Description",
        Size = UDim2.new(0.45, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 32),
        BackgroundTransparency = 1,
        Text = item.description,
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 11,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
      }),

      -- Tier + Damage + Status
      New(scope, "TextLabel")({
        Name = "TierInfo",
        Size = UDim2.new(0.35, 0, 0, 16),
        Position = UDim2.new(0, 58, 0, 52),
        BackgroundTransparency = 1,
        Text = Computed(scope, function(use)
          local status = use(statusText)
          local base = item.tier .. " • " .. item.damage .. " DMG"
          return status ~= "" and (base .. " • " .. status) or base
        end),
        TextColor3 = statusColor,
        TextSize = 12,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Buttons container (only shown if not owned and not free)
      Computed(scope, function(use)
        if not use(showButtons) then
          return nil
        end
        return New(scope, "Frame")({
          Name = "Buttons",
          Size = UDim2.new(0, 80, 0, 76),
          Position = UDim2.new(1, -88, 0.5, -38),
          BackgroundTransparency = 1,

          [Children] = {
            New(scope, "UIListLayout")({
              FillDirection = Enum.FillDirection.Vertical,
              Padding = UDim.new(0, 4),
              HorizontalAlignment = Enum.HorizontalAlignment.Center,
            }),
            createCashButton(scope, item.price, isSoldOut, canAfford, onBuy),
            createRobuxButton(scope, item.robuxPrice, onRobuxBuy),
          },
        })
      end),
    },
  })
end

-- Create content based on tab
local function createContentFrame(
  scope: Fusion.Scope,
  activeTab: Fusion.Value<TabType>,
  callbacks: StoreUIProps
)
  return New(scope, "ScrollingFrame")({
    Name = "ContentScroll",
    Size = UDim2.new(1, -16, 1, -100),
    Position = UDim2.new(0, 8, 0, 52),
    BackgroundColor3 = Color3.fromRGB(30, 30, 40),
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 8),
      }),
      New(scope, "UIListLayout")({
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, CARD_PADDING),
        SortOrder = Enum.SortOrder.LayoutOrder,
      }),
      New(scope, "UIPadding")({
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
      }),

      -- Dynamic content based on tab
      Computed(scope, function(use)
        local tab = use(activeTab)
        local children = {}

        if tab == "eggs" then
          local eggs = Store.getAvailableEggsWithStock()
          for i, item in ipairs(eggs) do
            table.insert(
              children,
              createEggCard(scope, item, i, function()
                if callbacks.onEggPurchase then
                  callbacks.onEggPurchase(item.id, 1)
                end
              end, function()
                if callbacks.onRobuxPurchase then
                  callbacks.onRobuxPurchase("egg", item.id)
                end
              end)
            )
          end
        elseif tab == "supplies" then
          local traps = Store.getAvailableTraps()
          for i, item in ipairs(traps) do
            table.insert(
              children,
              createSupplyCard(scope, item, i, function()
                if callbacks.onTrapPurchase then
                  callbacks.onTrapPurchase(item.id)
                end
              end, function()
                if callbacks.onRobuxPurchase then
                  callbacks.onRobuxPurchase("trap", item.id)
                end
              end)
            )
          end
        elseif tab == "powerups" then
          local powerUps = PowerUpConfig.getAllSorted()
          for i, config in ipairs(powerUps) do
            table.insert(
              children,
              createPowerUpCard(scope, config, i, function()
                if callbacks.onPowerUpPurchase then
                  callbacks.onPowerUpPurchase(config.id)
                end
              end)
            )
          end
        elseif tab == "weapons" then
          local weapons = Store.getAvailableWeapons()
          for i, item in ipairs(weapons) do
            table.insert(
              children,
              createWeaponCard(scope, item, i, function()
                if callbacks.onWeaponPurchase then
                  callbacks.onWeaponPurchase(item.id)
                end
              end, function()
                if callbacks.onRobuxPurchase then
                  callbacks.onRobuxPurchase("weapon", item.id)
                end
              end)
            )
          end
        end

        return children
      end),
    },
  })
end

-- Create tab button
local function createTabButton(
  scope: Fusion.Scope,
  label: string,
  tabKey: TabType,
  position: UDim2,
  activeTab: Fusion.Value<TabType>,
  onTabClick: (TabType) -> ()
)
  local isActive = Computed(scope, function(use)
    return use(activeTab) == tabKey
  end)

  local bgColor = Computed(scope, function(use)
    return if use(isActive) then Color3.fromRGB(60, 60, 80) else Color3.fromRGB(40, 40, 55)
  end)

  local textColor = Computed(scope, function(use)
    return if use(isActive) then Theme.Colors.TextPrimary else Theme.Colors.TextMuted
  end)

  return New(scope, "TextButton")({
    Name = tabKey .. "Tab",
    Size = UDim2.new(0.25, -3, 1, 0),
    Position = position,
    BackgroundColor3 = bgColor,
    Text = label,
    TextColor3 = textColor,
    TextSize = 12,
    FontFace = Theme.Typography.PrimarySemiBold,
    AutoButtonColor = false,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 6),
      }),
    },

    [OnEvent("MouseButton1Click")] = function()
      onTabClick(tabKey)
    end,
  })
end

-- Create main store frame
local function createStoreFrame(
  scope: Fusion.Scope,
  activeTab: Fusion.Value<TabType>,
  restockTimeValue: Fusion.Value<number>,
  onClose: () -> (),
  onTabClick: (TabType) -> (),
  callbacks: StoreUIProps
)
  local restockText = Computed(scope, function(use)
    return formatRestockTime(use(restockTimeValue))
  end)

  return New(scope, "Frame")({
    Name = "MainFrame",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.new(0, 400, 0, 500),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = Color3.fromRGB(35, 35, 50),

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = UDim.new(0, 12),
      }),
      New(scope, "UIStroke")({
        Color = Color3.fromRGB(80, 80, 100),
        Thickness = 2,
      }),

      -- Header
      New(scope, "Frame")({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Color3.fromRGB(45, 45, 65),

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 12),
          }),
          New(scope, "Frame")({
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 1, -12),
            BackgroundColor3 = Color3.fromRGB(45, 45, 65),
            BorderSizePixel = 0,
          }),
          New(scope, "TextLabel")({
            Name = "Title",
            Size = UDim2.new(1, -80, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Text = "🐔 The Roost",
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 18,
            FontFace = Theme.Typography.PrimaryBold,
            TextXAlignment = Enum.TextXAlignment.Left,
          }),
          New(scope, "TextLabel")({
            Name = "RestockTimer",
            Size = UDim2.new(0, 120, 1, 0),
            Position = UDim2.new(1, -160, 0, 0),
            BackgroundTransparency = 1,
            Text = restockText,
            TextColor3 = Theme.Colors.TextMuted,
            TextSize = 12,
            FontFace = Theme.Typography.Primary,
            TextXAlignment = Enum.TextXAlignment.Right,
          }),
          New(scope, "TextButton")({
            Name = "CloseButton",
            Size = UDim2.new(0, 28, 0, 28),
            Position = UDim2.new(1, -34, 0, 6),
            BackgroundColor3 = Color3.fromRGB(200, 80, 80),
            Text = "X",
            TextColor3 = Theme.Colors.TextPrimary,
            TextSize = 14,
            FontFace = Theme.Typography.PrimaryBold,

            [Children] = {
              New(scope, "UICorner")({
                CornerRadius = UDim.new(0, 6),
              }),
            },

            [OnEvent("MouseButton1Click")] = onClose,
          }),
        },
      }),

      -- Tab frame
      New(scope, "Frame")({
        Name = "TabFrame",
        Size = UDim2.new(1, -16, 0, 36),
        Position = UDim2.new(0, 8, 0, 48),
        BackgroundTransparency = 1,

        [Children] = {
          createTabButton(scope, "🥚 Eggs", "eggs", UDim2.new(0, 0, 0, 0), activeTab, onTabClick),
          createTabButton(
            scope,
            "🪤 Traps",
            "supplies",
            UDim2.new(0.25, 1, 0, 0),
            activeTab,
            onTabClick
          ),
          createTabButton(
            scope,
            "⚡ Boosts",
            "powerups",
            UDim2.new(0.5, 2, 0, 0),
            activeTab,
            onTabClick
          ),
          createTabButton(
            scope,
            "⚔️ Weapons",
            "weapons",
            UDim2.new(0.75, 3, 0, 0),
            activeTab,
            onTabClick
          ),
        },
      }),

      -- Content
      createContentFrame(scope, activeTab, callbacks),
    },
  })
end

--[[
	Create the StoreUI.
	
	@param props StoreUIProps - Configuration props
	@return boolean - Success
]]
function StoreUI.create(props: StoreUIProps?): boolean
  if screenGui then
    warn("[StoreUI] Already created")
    return false
  end

  props = props or {}
  cachedCallbacks = props

  local player = Players.LocalPlayer
  if not player then
    warn("[StoreUI] No local player")
    return false
  end

  -- Create Fusion scope
  storeScope = Fusion.scoped({})
  local scope = storeScope :: Fusion.Scope

  -- State values
  currentTab = Value(scope, "eggs" :: TabType)
  isVisible = Value(scope, false)
  restockTime = Value(scope, Store.getTimeUntilReplenish())
  cachedOwnedWeapons = Value(scope, {} :: { [string]: boolean })
  cachedActivePowerUps = Value(scope, {} :: { [string]: number })

  -- Handlers
  local function onClose()
    StoreUI.close()
  end

  local function onTabClick(tab: TabType)
    if currentTab then
      (currentTab :: Fusion.Value<TabType>):set(tab)
    end
  end

  -- Create ScreenGui
  screenGui = New(scope, "ScreenGui")({
    Name = "StoreUI",
    ResetOnSpawn = false,
    Enabled = false,
    Parent = player:WaitForChild("PlayerGui"),

    [Children] = {
      createStoreFrame(
        scope,
        currentTab :: Fusion.Value<TabType>,
        restockTime :: Fusion.Value<number>,
        onClose,
        onTabClick,
        cachedCallbacks
      ),
    },
  })

  print("[StoreUI] Created")
  return true
end

--[[
	Destroy the StoreUI and cleanup resources.
]]
function StoreUI.destroy()
  if timerConnection then
    timerConnection:Disconnect()
    timerConnection = nil
  end

  if storeScope then
    Fusion.doCleanup(storeScope)
    storeScope = nil
  end

  screenGui = nil
  currentTab = nil
  isVisible = nil
  restockTime = nil
  cachedOwnedWeapons = nil
  cachedActivePowerUps = nil
  cachedCallbacks = {}

  print("[StoreUI] Destroyed")
end

--[[
	Check if the StoreUI is created.
	
	@return boolean
]]
function StoreUI.isCreated(): boolean
  return screenGui ~= nil
end

--[[
	Open the store UI.
]]
function StoreUI.open()
  if not screenGui then
    return
  end

  screenGui.Enabled = true
  if isVisible then
    (isVisible :: Fusion.Value<boolean>):set(true)
  end

  -- Start timer update loop
  if timerConnection then
    timerConnection:Disconnect()
  end
  timerConnection = RunService.Heartbeat:Connect(function()
    if restockTime then
      (restockTime :: Fusion.Value<number>):set(Store.getTimeUntilReplenish())
    end
  end)

  if cachedCallbacks.onVisibilityChanged then
    cachedCallbacks.onVisibilityChanged(true)
  end

  print("[StoreUI] Opened")
end

--[[
	Close the store UI.
]]
function StoreUI.close()
  if not screenGui then
    return
  end

  screenGui.Enabled = false
  if isVisible then
    (isVisible :: Fusion.Value<boolean>):set(false)
  end

  -- Stop timer update loop
  if timerConnection then
    timerConnection:Disconnect()
    timerConnection = nil
  end

  if cachedCallbacks.onVisibilityChanged then
    cachedCallbacks.onVisibilityChanged(false)
  end

  print("[StoreUI] Closed")
end

--[[
	Toggle the store UI.
]]
function StoreUI.toggle()
  if StoreUI.isOpen() then
    StoreUI.close()
  else
    StoreUI.open()
  end
end

--[[
	Check if the store UI is currently open.
	
	@return boolean
]]
function StoreUI.isOpen(): boolean
  return screenGui ~= nil and screenGui.Enabled
end

--[[
	Check if the store UI is visible.
	
	@return boolean
]]
function StoreUI.isVisible(): boolean
  return StoreUI.isOpen()
end

--[[
	Set the visibility of the store UI.
	
	@param visible boolean
]]
function StoreUI.setVisible(visible: boolean)
  if visible then
    StoreUI.open()
  else
    StoreUI.close()
  end
end

--[[
	Get the current tab.
	
	@return TabType
]]
function StoreUI.getCurrentTab(): TabType
  if currentTab then
    return (currentTab :: Fusion.Value<TabType>):get()
  end
  return "eggs"
end

--[[
	Set the current tab.
	
	@param tab TabType
]]
function StoreUI.setTab(tab: TabType)
  if currentTab then
    (currentTab :: Fusion.Value<TabType>):set(tab)
  end
end

--[[
	Update the cached player money.
	No-op in Fusion version (uses reactive State.Player.Money).
	
	@param money number
]]
function StoreUI.updateMoney(_money: number)
  -- No-op: Fusion uses reactive State.Player.Money
end

--[[
	Update the cached owned weapons for display.
	
	@param ownedWeapons { string }?
]]
function StoreUI.updateOwnedWeapons(ownedWeapons: { string }?)
  if not cachedOwnedWeapons then
    return
  end

  local owned: { [string]: boolean } = {}
  if ownedWeapons then
    for _, weaponType in ipairs(ownedWeapons) do
      owned[weaponType] = true
    end
  end
  (cachedOwnedWeapons :: Fusion.Value<{ [string]: boolean }>):set(owned)
end

--[[
	Update the cached active power-ups for display.
	
	@param activePowerUps { [string]: number }?
]]
function StoreUI.updateActivePowerUps(activePowerUps: { [string]: number }?)
  if not cachedActivePowerUps then
    return
  end
  (cachedActivePowerUps :: Fusion.Value<{ [string]: number }>):set(activePowerUps or {})
end

--[[
	Refresh the store inventory display.
	In Fusion version, this triggers a re-render by toggling a refresh value.
]]
function StoreUI.refreshInventory()
  -- Force tab switch to refresh content
  if currentTab then
    local tab = (currentTab :: Fusion.Value<TabType>)
      :get()
      -- Toggle to force re-render
      (currentTab :: Fusion.Value<TabType>)
      :set("eggs" :: TabType)
    task.defer(function()
      (currentTab :: Fusion.Value<TabType>):set(tab)
    end)
  end
end

--[[
	Update stock display for a specific item.
	In Fusion version, this triggers a refresh.
	
	@param itemType string
	@param itemId string
	@param newStock number
]]
function StoreUI.updateItemStock(_itemType: string, _itemId: string, _newStock: number)
  StoreUI.refreshInventory()
end

-- Legacy callback setters for API compatibility

--[[
	Sets the callback for egg purchases.
	
	@param callback function
]]
function StoreUI.onPurchase(callback: (eggType: string, quantity: number) -> any)
  cachedCallbacks.onEggPurchase = callback
end

--[[
	Sets the callback for replenish.
	
	@param callback function
]]
function StoreUI.onReplenish(callback: () -> any)
  cachedCallbacks.onReplenish = callback
end

--[[
	Sets the callback for Robux purchases.
	
	@param callback function
]]
function StoreUI.onRobuxPurchase(callback: (itemType: string, itemId: string) -> any)
  cachedCallbacks.onRobuxPurchase = callback
end

--[[
	Sets the callback for power-up purchases.
	
	@param callback function
]]
function StoreUI.onPowerUpPurchase(callback: (powerUpId: string) -> any)
  cachedCallbacks.onPowerUpPurchase = callback
end

--[[
	Sets the callback for trap purchases.
	
	@param callback function
]]
function StoreUI.onTrapPurchase(callback: (trapType: string) -> any)
  cachedCallbacks.onTrapPurchase = callback
end

--[[
	Sets the callback for weapon purchases.
	
	@param callback function
]]
function StoreUI.onWeaponPurchase(callback: (weaponType: string) -> any)
  cachedCallbacks.onWeaponPurchase = callback
end

return StoreUI
