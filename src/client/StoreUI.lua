--[[
	StoreUI Module
	Implements the store UI where players can browse and purchase eggs and supplies.
	Opens when player interacts with the central store.
	Built with Fusion and OnyxUI for reactive, component-based UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Get Fusion and OnyxUI from Packages
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))
local OnyxUI = require(Packages:WaitForChild("OnyxUI"))

-- Fusion imports
local scoped = Fusion.scoped
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local peek = Fusion.peek
local Observer = Fusion.Observer
local ForValues = Fusion.ForValues

-- OnyxUI imports
local Themer = OnyxUI.Themer
local OnyxComponents = OnyxUI.Components
local Util = OnyxUI.Util

local StoreUI = {}

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local Store = require(Shared:WaitForChild("Store"))
local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))

-- Rarity colors for visual distinction
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(200, 200, 200),
  Uncommon = Color3.fromRGB(50, 205, 50),
  Rare = Color3.fromRGB(30, 144, 255),
  Epic = Color3.fromRGB(148, 0, 211),
  Legendary = Color3.fromRGB(255, 165, 0),
  Mythic = Color3.fromRGB(255, 0, 100),
}

-- Rarity gradients for card backgrounds
local RARITY_GRADIENTS: { [string]: { start: Color3, endColor: Color3 } } = {
  Common = { start = Color3.fromRGB(180, 180, 180), endColor = Color3.fromRGB(255, 255, 255) },
  Uncommon = { start = Color3.fromRGB(144, 238, 144), endColor = Color3.fromRGB(34, 139, 34) },
  Rare = { start = Color3.fromRGB(135, 206, 250), endColor = Color3.fromRGB(30, 90, 180) },
  Epic = { start = Color3.fromRGB(200, 150, 255), endColor = Color3.fromRGB(148, 0, 211) },
  Legendary = { start = Color3.fromRGB(255, 220, 100), endColor = Color3.fromRGB(255, 140, 0) },
  Mythic = { start = Color3.fromRGB(255, 150, 180), endColor = Color3.fromRGB(255, 0, 100) },
}

-- Tier gradients for supplies/traps and weapons
local TIER_GRADIENTS: { [string]: { start: Color3, endColor: Color3 } } = {
  Basic = { start = Color3.fromRGB(200, 200, 200), endColor = Color3.fromRGB(140, 140, 140) },
  Improved = { start = Color3.fromRGB(160, 255, 160), endColor = Color3.fromRGB(50, 180, 50) },
  Advanced = { start = Color3.fromRGB(140, 200, 255), endColor = Color3.fromRGB(30, 120, 220) },
  Expert = { start = Color3.fromRGB(200, 160, 255), endColor = Color3.fromRGB(140, 40, 200) },
  Master = { start = Color3.fromRGB(255, 220, 150), endColor = Color3.fromRGB(255, 140, 0) },
  Ultimate = { start = Color3.fromRGB(255, 180, 200), endColor = Color3.fromRGB(255, 50, 100) },
  Standard = { start = Color3.fromRGB(140, 200, 255), endColor = Color3.fromRGB(40, 130, 220) },
  Premium = { start = Color3.fromRGB(255, 220, 150), endColor = Color3.fromRGB(255, 150, 50) },
}

-- Tier colors for supplies/traps
local TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Improved = Color3.fromRGB(50, 200, 50),
  Advanced = Color3.fromRGB(50, 150, 255),
  Expert = Color3.fromRGB(160, 50, 220),
  Master = Color3.fromRGB(255, 165, 0),
  Ultimate = Color3.fromRGB(255, 50, 100),
}

-- Weapon tier colors
local WEAPON_TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Standard = Color3.fromRGB(50, 150, 255),
  Premium = Color3.fromRGB(255, 165, 0),
}

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Fusion scope for UI management
local scope: Fusion.Scope<typeof(Fusion) & typeof(OnyxComponents) & typeof(Util)>? = nil

-- Reactive state values (Fusion Values)
local isOpenState: Fusion.Value<boolean>? = nil
local currentTabState: Fusion.Value<string>? = nil
local playerMoneyState: Fusion.Value<number>? = nil
local activePowerUpsState: Fusion.Value<{ [string]: number }>? = nil
local ownedWeaponsState: Fusion.Value<{ [string]: boolean }>? = nil
local restockTimeState: Fusion.Value<string>? = nil
local showConfirmationState: Fusion.Value<boolean>? = nil
local inventoryRefreshState: Fusion.Value<number>? = nil

-- UI references
local screenGui: ScreenGui? = nil
local timerConnection: RBXScriptConnection? = nil

-- Robux price for instant replenish
local ROBUX_REPLENISH_PRICE = 50

-- Callbacks
local onEggPurchaseCallback: ((eggType: string, quantity: number) -> any)? = nil
local onReplenishCallback: (() -> any)? = nil
local onRobuxPurchaseCallback: ((itemType: string, itemId: string) -> any)? = nil
local onPowerUpPurchaseCallback: ((powerUpId: string) -> any)? = nil
local onTrapPurchaseCallback: ((trapType: string) -> any)? = nil
local onWeaponPurchaseCallback: ((weaponType: string) -> any)? = nil

--[[
	Formats seconds into M:SS format for the restock timer.
]]
local function formatRestockTime(seconds: number): string
  if seconds <= 0 then
    return "Restocking..."
  end
  local minutes = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("Restocks in %d:%02d", minutes, secs)
end

--[[
	Generates a description for an egg based on its hatch outcomes.
]]
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

--[[
	Creates an item card component using Fusion/OnyxUI for eggs.
]]
local function createEggCard(cardScope: typeof(scope), item: Store.InventoryItem, index: number)
  local gradientColors = RARITY_GRADIENTS[item.rarity] or RARITY_GRADIENTS.Common
  local rarityColor = RARITY_COLORS[item.rarity] or Color3.fromRGB(128, 128, 128)
  local hovering = cardScope:Value(false)

  local canAfford = cardScope:Computed(function(use)
    return use(playerMoneyState :: any) >= item.price
  end)

  local isSoldOut = cardScope:Computed(function(use)
    -- Force refresh when inventory changes
    local _ = use(inventoryRefreshState :: any)
    return item.stock <= 0
  end)

  return cardScope:Card({
    Name = item.id,
    Size = UDim2.new(1, -20, 0, 104),
    LayoutOrder = index,
    CornerRadius = Util.Fallback(nil, UDim.new(0, 12)),
    Padding = Util.Fallback(nil, UDim.new(0, 0)),
    StrokeEnabled = true,
    StrokeColor = Color3.fromRGB(60, 40, 20),
    StrokeTransparency = 0.3,

    [Children] = {
      -- Gradient background
      cardScope:New("UIGradient")({
        Color = ColorSequence.new({
          ColorSequenceKeypoint.new(0, gradientColors.start),
          ColorSequenceKeypoint.new(1, gradientColors.endColor),
        }),
        Rotation = 90,
      }),

      -- Rarity bar on left
      cardScope:Frame({
        Name = "RarityBar",
        Size = UDim2.new(0, 4, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = rarityColor,
        CornerRadius = Util.Fallback(nil, UDim.new(0, 4)),
      }),

      -- Icon
      cardScope:Text({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, -10, 0.5, -30),
        BackgroundTransparency = 1,
        Text = "🥚",
        TextSize = 48,
        ZIndex = 3,
      }),

      -- Name label
      cardScope:Heading({
        Name = "Name",
        Size = UDim2.new(0.35, -20, 0, 24),
        Position = UDim2.new(0, 55, 0, 6),
        Text = item.displayName,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Description
      cardScope:Text({
        Name = "Description",
        Size = UDim2.new(0.5, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 30),
        Text = getEggDescription(item.id),
        TextColor3 = Color3.fromRGB(80, 60, 40),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 0.15,
      }),

      -- Rarity text
      cardScope:Text({
        Name = "Rarity",
        Size = UDim2.new(0.35, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 48),
        Text = item.rarity,
        TextColor3 = Color3.fromRGB(50, 50, 50),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Stock label
      cardScope:Text({
        Name = "Stock",
        Size = UDim2.new(0, 70, 0, 18),
        Position = UDim2.new(0, 55, 0, 66),
        Text = cardScope:Computed(function(use)
          return if use(isSoldOut) then "SOLD OUT" else ("x" .. tostring(item.stock))
        end),
        TextColor3 = cardScope:Computed(function(use)
          return if use(isSoldOut) then Color3.fromRGB(180, 30, 30) else Color3.fromRGB(50, 50, 50)
        end),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Cash buy button
      cardScope:Button({
        Name = "BuyButton",
        Size = UDim2.new(0, 85, 0, 38),
        Position = UDim2.new(1, -95, 0, 8),
        Color = cardScope:Computed(function(use)
          local soldOut = use(isSoldOut)
          local afford = use(canAfford)
          return if soldOut or not afford
            then Color3.fromRGB(80, 80, 80)
            else Color3.fromRGB(50, 180, 50)
        end),
        Content = { "💵", MoneyScaling.formatCleanCurrency(item.price) },
        Disabled = cardScope:Computed(function(use)
          return use(isSoldOut) or not use(canAfford)
        end),
        [OnEvent("MouseButton1Click")] = function()
          if not peek(isSoldOut) and peek(canAfford) and onEggPurchaseCallback then
            onEggPurchaseCallback(item.id, 1)
          end
        end,
      }),

      -- Robux buy button
      cardScope:Button({
        Name = "RobuxButton",
        Size = UDim2.new(0, 85, 0, 38),
        Position = UDim2.new(1, -95, 0, 52),
        Color = Color3.fromRGB(0, 120, 215),
        Content = { "💎", tostring(item.robuxPrice) },
        [OnEvent("MouseButton1Click")] = function()
          if onRobuxPurchaseCallback then
            onRobuxPurchaseCallback("egg", item.id)
          end
        end,
      }),
    },
  })
end

--[[
	Creates a supply/trap card component using Fusion/OnyxUI.
]]
local function createSupplyCard(
  cardScope: typeof(scope),
  supplyItem: Store.SupplyItem,
  index: number
)
  local gradientColors = TIER_GRADIENTS[supplyItem.tier] or TIER_GRADIENTS.Basic
  local tierColor = TIER_COLORS[supplyItem.tier] or Color3.fromRGB(128, 128, 128)

  local canAfford = cardScope:Computed(function(use)
    return use(playerMoneyState :: any) >= supplyItem.price
  end)

  return cardScope:Card({
    Name = supplyItem.id,
    Size = UDim2.new(1, -20, 0, 104),
    LayoutOrder = index,
    CornerRadius = Util.Fallback(nil, UDim.new(0, 12)),
    StrokeEnabled = true,
    StrokeColor = Color3.fromRGB(60, 40, 20),
    StrokeTransparency = 0.3,

    [Children] = {
      -- Gradient background
      cardScope:New("UIGradient")({
        Color = ColorSequence.new({
          ColorSequenceKeypoint.new(0, gradientColors.start),
          ColorSequenceKeypoint.new(1, gradientColors.endColor),
        }),
        Rotation = 90,
      }),

      -- Tier bar
      cardScope:Frame({
        Name = "TierBar",
        Size = UDim2.new(0, 4, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = tierColor,
        CornerRadius = Util.Fallback(nil, UDim.new(0, 4)),
      }),

      -- Icon
      cardScope:Text({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, -10, 0.5, -30),
        BackgroundTransparency = 1,
        Text = supplyItem.icon,
        TextSize = 48,
        ZIndex = 3,
      }),

      -- Name
      cardScope:Heading({
        Name = "Name",
        Size = UDim2.new(0.35, -20, 0, 24),
        Position = UDim2.new(0, 55, 0, 6),
        Text = supplyItem.displayName,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Description
      cardScope:Text({
        Name = "Description",
        Size = UDim2.new(0.5, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 30),
        Text = supplyItem.description,
        TextColor3 = Color3.fromRGB(80, 60, 40),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 0.15,
      }),

      -- Tier
      cardScope:Text({
        Name = "Tier",
        Size = UDim2.new(0.35, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 48),
        Text = supplyItem.tier,
        TextColor3 = Color3.fromRGB(50, 50, 50),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Effectiveness
      cardScope:Text({
        Name = "Effectiveness",
        Size = UDim2.new(0.4, 0, 0, 18),
        Position = UDim2.new(0, 55, 0, 66),
        Text = "+" .. tostring(math.floor((supplyItem.effectiveness or 0) * 100)) .. "% catch rate",
        TextColor3 = Color3.fromRGB(50, 50, 50),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Cash button
      cardScope:Button({
        Name = "BuyButton",
        Size = UDim2.new(0, 85, 0, 38),
        Position = UDim2.new(1, -95, 0, 8),
        Color = cardScope:Computed(function(use)
          return if use(canAfford) then Color3.fromRGB(50, 180, 50) else Color3.fromRGB(80, 80, 80)
        end),
        Content = { "💵", MoneyScaling.formatCleanCurrency(supplyItem.price) },
        Disabled = cardScope:Computed(function(use)
          return not use(canAfford)
        end),
        [OnEvent("MouseButton1Click")] = function()
          if peek(canAfford) and onTrapPurchaseCallback then
            onTrapPurchaseCallback(supplyItem.id)
          end
        end,
      }),

      -- Robux button
      cardScope:Button({
        Name = "RobuxButton",
        Size = UDim2.new(0, 85, 0, 38),
        Position = UDim2.new(1, -95, 0, 52),
        Color = Color3.fromRGB(0, 120, 215),
        Content = { "💎", tostring(supplyItem.robuxPrice) },
        [OnEvent("MouseButton1Click")] = function()
          if onRobuxPurchaseCallback then
            onRobuxPurchaseCallback("trap", supplyItem.id)
          end
        end,
      }),
    },
  })
end

--[[
	Creates a power-up card component using Fusion/OnyxUI.
]]
local function createPowerUpCard(
  cardScope: typeof(scope),
  powerUpId: string,
  config: PowerUpConfig.PowerUpConfig,
  index: number
)
  local isLuck = string.find(powerUpId, "HatchLuck") ~= nil
  local barColor = isLuck and Color3.fromRGB(50, 205, 50) or Color3.fromRGB(255, 215, 0)
  local gradientStart = isLuck and Color3.fromRGB(160, 255, 160) or Color3.fromRGB(255, 240, 180)
  local gradientEnd = isLuck and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(255, 180, 50)

  local isActive = cardScope:Computed(function(use)
    local activePowerUps = use(activePowerUpsState :: any)
    local powerUpType = PowerUpConfig.getPowerUpType(powerUpId)
    local activeExpiresAt = activePowerUps and powerUpType and activePowerUps[powerUpType]
    return activeExpiresAt and os.time() < activeExpiresAt
  end)

  local statusText = cardScope:Computed(function(use)
    local activePowerUps = use(activePowerUpsState :: any)
    local powerUpType = PowerUpConfig.getPowerUpType(powerUpId)
    local activeExpiresAt = activePowerUps and powerUpType and activePowerUps[powerUpType]
    if activeExpiresAt and os.time() < activeExpiresAt then
      local remaining = activeExpiresAt - os.time()
      return "✓ ACTIVE (" .. PowerUpConfig.formatRemainingTime(remaining) .. " left)"
    else
      return "Duration: " .. PowerUpConfig.formatRemainingTime(config.durationSeconds)
    end
  end)

  return cardScope:Card({
    Name = powerUpId,
    Size = UDim2.new(1, -20, 0, 104),
    LayoutOrder = index,
    CornerRadius = Util.Fallback(nil, UDim.new(0, 12)),
    StrokeEnabled = true,
    StrokeColor = Color3.fromRGB(60, 40, 20),
    StrokeTransparency = 0.3,

    [Children] = {
      -- Gradient
      cardScope:New("UIGradient")({
        Color = ColorSequence.new({
          ColorSequenceKeypoint.new(0, gradientStart),
          ColorSequenceKeypoint.new(1, gradientEnd),
        }),
        Rotation = 90,
      }),

      -- Type bar
      cardScope:Frame({
        Name = "TypeBar",
        Size = UDim2.new(0, 4, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = barColor,
        CornerRadius = Util.Fallback(nil, UDim.new(0, 4)),
      }),

      -- Icon
      cardScope:Text({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, -10, 0.5, -30),
        BackgroundTransparency = 1,
        Text = config.icon,
        TextSize = 48,
        ZIndex = 3,
      }),

      -- Name
      cardScope:Heading({
        Name = "Name",
        Size = UDim2.new(0.35, -20, 0, 28),
        Position = UDim2.new(0, 55, 0, 10),
        Text = config.displayName,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Description
      cardScope:Text({
        Name = "Description",
        Size = UDim2.new(0.4, 0, 0, 22),
        Position = UDim2.new(0, 55, 0, 40),
        Text = config.description,
        TextColor3 = Color3.fromRGB(50, 50, 50),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Status
      cardScope:Text({
        Name = "Status",
        Size = UDim2.new(0.4, 0, 0, 22),
        Position = UDim2.new(0, 55, 0, 68),
        Text = statusText,
        TextColor3 = cardScope:Computed(function(use)
          return if use(isActive) then Color3.fromRGB(20, 120, 20) else Color3.fromRGB(50, 50, 50)
        end),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Buy button (Robux only)
      cardScope:Button({
        Name = "BuyButton",
        Size = UDim2.new(0, 85, 0, 42),
        Position = UDim2.new(1, -95, 0.5, -21),
        Color = Color3.fromRGB(0, 120, 215),
        Content = { "💎", tostring(config.robuxPrice) },
        [OnEvent("MouseButton1Click")] = function()
          if onPowerUpPurchaseCallback then
            onPowerUpPurchaseCallback(powerUpId)
          end
        end,
      }),
    },
  })
end

--[[
	Creates a weapon card component using Fusion/OnyxUI.
]]
local function createWeaponCard(
  cardScope: typeof(scope),
  weaponItem: Store.WeaponItem,
  index: number
)
  local gradientColors = TIER_GRADIENTS[weaponItem.tier] or TIER_GRADIENTS.Basic
  local tierColor = WEAPON_TIER_COLORS[weaponItem.tier] or Color3.fromRGB(128, 128, 128)

  local isOwned = cardScope:Computed(function(use)
    local owned = use(ownedWeaponsState :: any)
    return owned and owned[weaponItem.id]
  end)

  local isFree = weaponItem.price == 0

  local canAfford = cardScope:Computed(function(use)
    return use(playerMoneyState :: any) >= weaponItem.price
  end)

  local statusText = cardScope:Computed(function(use)
    if use(isOwned) then
      return "✓ OWNED"
    elseif isFree then
      return "★ STARTER"
    else
      return ""
    end
  end)

  local statusColor = cardScope:Computed(function(use)
    if use(isOwned) then
      return Color3.fromRGB(20, 120, 20)
    elseif isFree then
      return Color3.fromRGB(80, 80, 80)
    else
      return Color3.fromRGB(50, 50, 50)
    end
  end)

  local showButtons = cardScope:Computed(function(use)
    return not use(isOwned) and not isFree
  end)

  return cardScope:Card({
    Name = weaponItem.id,
    Size = UDim2.new(1, -20, 0, 104),
    LayoutOrder = index,
    CornerRadius = Util.Fallback(nil, UDim.new(0, 12)),
    StrokeEnabled = true,
    StrokeColor = Color3.fromRGB(60, 40, 20),
    StrokeTransparency = 0.3,

    [Children] = {
      -- Gradient
      cardScope:New("UIGradient")({
        Color = ColorSequence.new({
          ColorSequenceKeypoint.new(0, gradientColors.start),
          ColorSequenceKeypoint.new(1, gradientColors.endColor),
        }),
        Rotation = 90,
      }),

      -- Tier bar
      cardScope:Frame({
        Name = "TierBar",
        Size = UDim2.new(0, 4, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = tierColor,
        CornerRadius = Util.Fallback(nil, UDim.new(0, 4)),
      }),

      -- Icon
      cardScope:Text({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, -10, 0.5, -30),
        BackgroundTransparency = 1,
        Text = weaponItem.icon,
        TextSize = 48,
        ZIndex = 3,
      }),

      -- Name
      cardScope:Heading({
        Name = "Name",
        Size = UDim2.new(0.35, -20, 0, 24),
        Position = UDim2.new(0, 55, 0, 6),
        Text = weaponItem.displayName,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Description
      cardScope:Text({
        Name = "Description",
        Size = UDim2.new(0.5, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 30),
        Text = weaponItem.description,
        TextColor3 = Color3.fromRGB(80, 60, 40),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 0.15,
      }),

      -- Tier and damage
      cardScope:Text({
        Name = "Tier",
        Size = UDim2.new(0.35, -20, 0, 18),
        Position = UDim2.new(0, 55, 0, 48),
        Text = weaponItem.tier .. " • " .. weaponItem.damage .. " DMG",
        TextColor3 = Color3.fromRGB(50, 50, 50),
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Status
      cardScope:Text({
        Name = "Status",
        Size = UDim2.new(0.35, 0, 0, 18),
        Position = UDim2.new(0, 55, 0, 66),
        Text = statusText,
        TextColor3 = statusColor,
        TextXAlignment = Enum.TextXAlignment.Left,
      }),

      -- Cash button (only if not owned and not free)
      cardScope:Computed(function(use)
        if not use(showButtons) then
          return nil
        end
        return cardScope:Button({
          Name = "BuyButton",
          Size = UDim2.new(0, 85, 0, 38),
          Position = UDim2.new(1, -95, 0, 8),
          Color = cardScope:Computed(function(use2)
            return if use2(canAfford)
              then Color3.fromRGB(50, 180, 50)
              else Color3.fromRGB(80, 80, 80)
          end),
          Content = { "💵", MoneyScaling.formatCleanCurrency(weaponItem.price) },
          Disabled = cardScope:Computed(function(use2)
            return not use2(canAfford)
          end),
          [OnEvent("MouseButton1Click")] = function()
            if peek(canAfford) and onWeaponPurchaseCallback then
              onWeaponPurchaseCallback(weaponItem.id)
            end
          end,
        })
      end),

      -- Robux button (only if not owned and not free)
      cardScope:Computed(function(use)
        if not use(showButtons) then
          return nil
        end
        return cardScope:Button({
          Name = "RobuxButton",
          Size = UDim2.new(0, 85, 0, 38),
          Position = UDim2.new(1, -95, 0, 52),
          Color = Color3.fromRGB(0, 120, 215),
          Content = { "💎", tostring(weaponItem.robuxPrice) },
          [OnEvent("MouseButton1Click")] = function()
            if onRobuxPurchaseCallback then
              onRobuxPurchaseCallback("weapon", weaponItem.id)
            end
          end,
        })
      end),
    },
  })
end

--[[
	Creates the content list for the current tab.
]]
local function createTabContent(contentScope: typeof(scope))
  return contentScope:Computed(function(use)
    local currentTab = use(currentTabState :: any)
    local _ = use(inventoryRefreshState :: any) -- Force refresh

    local children = {}

    if currentTab == "eggs" then
      local availableEggs = Store.getAvailableEggsWithStock()
      for index, item in ipairs(availableEggs) do
        table.insert(children, createEggCard(contentScope, item, index))
      end
    elseif currentTab == "supplies" then
      local availableTraps = Store.getAvailableTraps()
      for index, item in ipairs(availableTraps) do
        table.insert(children, createSupplyCard(contentScope, item, index))
      end
    elseif currentTab == "powerups" then
      local powerUps = PowerUpConfig.getAllSorted()
      for index, config in ipairs(powerUps) do
        table.insert(children, createPowerUpCard(contentScope, config.id, config, index))
      end
    elseif currentTab == "weapons" then
      local availableWeapons = Store.getAvailableWeapons()
      for index, item in ipairs(availableWeapons) do
        table.insert(children, createWeaponCard(contentScope, item, index))
      end
    end

    return children
  end)
end

--[[
	Creates the tab button component.
]]
local function createTabButton(
  tabScope: typeof(scope),
  icon: string,
  tabKey: string,
  activeColor: Color3
)
  local isActive = tabScope:Computed(function(use)
    return use(currentTabState :: any) == tabKey
  end)

  return tabScope:Button({
    Name = tabKey .. "Tab",
    Size = UDim2.new(0.25, -4, 0, 38),
    Color = tabScope:Computed(function(use)
      return if use(isActive) then activeColor else Color3.fromRGB(180, 140, 90)
    end),
    Content = { icon },
    SizeVariant = "Medium",
    [OnEvent("MouseButton1Click")] = function()
      if currentTabState then
        currentTabState:set(tabKey)
      end
    end,
  })
end

--[[
	Creates the main store UI using Fusion and OnyxUI.
]]
function StoreUI.create()
  if screenGui then
    return
  end

  -- Create Fusion scope with OnyxUI components
  scope = scoped(Fusion, OnyxComponents, Util)

  -- Initialize state values
  isOpenState = scope:Value(false)
  currentTabState = scope:Value("eggs")
  playerMoneyState = scope:Value(0)
  activePowerUpsState = scope:Value({})
  ownedWeaponsState = scope:Value({})
  restockTimeState = scope:Value(formatRestockTime(Store.getTimeUntilReplenish()))
  showConfirmationState = scope:Value(false)
  inventoryRefreshState = scope:Value(0)

  -- Create animated size for open/close animation
  local targetSize = scope:Computed(function(use)
    return if use(isOpenState :: any) then UDim2.new(0, 420, 0, 550) else UDim2.new(0, 0, 0, 0)
  end)

  local animatedSize = scope:Spring(targetSize, 30, 0.8)

  -- Create ScreenGui
  screenGui = scope:New("ScreenGui")({
    Name = "StoreUI",
    Parent = localPlayer:WaitForChild("PlayerGui"),
    ResetOnSpawn = false,
    Enabled = scope:Computed(function(use)
      return use(isOpenState :: any)
    end),

    [Children] = {
      -- Main Frame using OnyxUI Frame component
      scope:Frame({
        Name = "MainFrame",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = animatedSize,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(255, 248, 220),
        CornerRadius = Util.Fallback(nil, UDim.new(0, 20)),
        StrokeEnabled = true,
        StrokeColor = Color3.fromRGB(101, 67, 33),
        StrokeThickness = 4,
        ClipsDescendants = true,

        [Children] = {
          -- Title Bar
          scope:TitleBar({
            Name = "TitleBar",
            Size = UDim2.new(1, 0, 0, 45),
            BackgroundColor3 = Color3.fromRGB(139, 90, 43),
            CornerRadius = Util.Fallback(nil, UDim.new(0, 20)),
            Title = "🐔 The Roost",
            CloseButtonDisabled = false,
            OnClose = function()
              StoreUI.close()
            end,
          }),

          -- Restock timer
          scope:Text({
            Name = "RestockTimer",
            Size = UDim2.new(0.5, 0, 0, 20),
            Position = UDim2.new(1, -10, 0, 55),
            AnchorPoint = Vector2.new(1, 0),
            Text = restockTimeState,
            TextColor3 = Color3.fromRGB(30, 41, 59),
            TextXAlignment = Enum.TextXAlignment.Right,
            BackgroundTransparency = 1,
          }),

          -- Tab Frame
          scope:Group({
            Name = "TabFrame",
            Size = UDim2.new(1, -20, 0, 42),
            Position = UDim2.new(0, 10, 0, 85),
            BackgroundTransparency = 1,
            ListEnabled = true,
            ListFillDirection = Enum.FillDirection.Horizontal,
            ListPadding = UDim.new(0, 4),

            [Children] = {
              createTabButton(scope, "🥚", "eggs", Color3.fromRGB(255, 220, 150)),
              createTabButton(scope, "🪤", "supplies", Color3.fromRGB(255, 200, 130)),
              createTabButton(scope, "⚡", "powerups", Color3.fromRGB(200, 230, 255)),
              createTabButton(scope, "⚔️", "weapons", Color3.fromRGB(255, 180, 180)),
            },
          }),

          -- Scroll Frame for items
          scope:Scroller({
            Name = "ItemsScroll",
            Size = UDim2.new(1, -20, 1, -195),
            Position = UDim2.new(0, 10, 0, 130),
            BackgroundTransparency = 1,
            ListEnabled = true,
            ListPadding = UDim.new(0, 8),
            Padding = Util.Fallback(nil, UDim.new(0, 10)),

            [Children] = createTabContent(scope),
          }),

          -- Replenish Now button
          scope:Button({
            Name = "ReplenishButton",
            Size = UDim2.new(1, -20, 0, 40),
            Position = UDim2.new(0, 10, 1, -50),
            Color = Color3.fromRGB(255, 215, 0),
            Content = { "⚡", "Restock Now! - R$" .. tostring(ROBUX_REPLENISH_PRICE) },
            ContentColor = Color3.fromRGB(80, 50, 0),
            [OnEvent("MouseButton1Click")] = function()
              if showConfirmationState then
                showConfirmationState:set(true)
              end
            end,
          }),
        },
      }),

      -- Confirmation Dialog
      scope:Computed(function(use)
        if not use(showConfirmationState :: any) then
          return nil
        end

        return scope:Card({
          Name = "ConfirmationFrame",
          Size = UDim2.new(0, 300, 0, 150),
          Position = UDim2.new(0.5, 0, 0.5, 0),
          AnchorPoint = Vector2.new(0.5, 0.5),
          BackgroundColor3 = Color3.fromRGB(30, 30, 30),
          CornerRadius = Util.Fallback(nil, UDim.new(0, 12)),
          ZIndex = 10,

          [Children] = {
            scope:Heading({
              Name = "Title",
              Size = UDim2.new(1, 0, 0, 35),
              Position = UDim2.new(0, 0, 0, 10),
              Text = "Confirm Purchase",
              TextColor3 = Color3.fromRGB(255, 255, 255),
              BackgroundTransparency = 1,
            }),

            scope:Text({
              Name = "Message",
              Size = UDim2.new(1, -20, 0, 40),
              Position = UDim2.new(0, 10, 0, 45),
              Text = "Instantly replenish store stock for R$"
                .. tostring(ROBUX_REPLENISH_PRICE)
                .. "?",
              TextColor3 = Color3.fromRGB(200, 200, 200),
              BackgroundTransparency = 1,
              TextWrapped = true,
            }),

            scope:Button({
              Name = "ConfirmButton",
              Size = UDim2.new(0, 100, 0, 35),
              Position = UDim2.new(0.5, -110, 1, -50),
              Color = Color3.fromRGB(0, 162, 255),
              Content = { "Confirm" },
              [OnEvent("MouseButton1Click")] = function()
                if showConfirmationState then
                  showConfirmationState:set(false)
                end
                if onReplenishCallback then
                  onReplenishCallback()
                end
              end,
            }),

            scope:Button({
              Name = "CancelButton",
              Size = UDim2.new(0, 100, 0, 35),
              Position = UDim2.new(0.5, 10, 1, -50),
              Color = Color3.fromRGB(80, 80, 80),
              Content = { "Cancel" },
              [OnEvent("MouseButton1Click")] = function()
                if showConfirmationState then
                  showConfirmationState:set(false)
                end
              end,
            }),
          },
        })
      end),
    },
  }) :: ScreenGui

  -- Escape key to close
  UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
      return
    end
    if input.KeyCode == Enum.KeyCode.Escape and isOpenState and peek(isOpenState) then
      StoreUI.close()
    end
  end)

  print("[StoreUI] Created with Fusion and OnyxUI")
end

--[[
	Opens the store UI with animation.
]]
function StoreUI.open()
  if not screenGui or not isOpenState then
    return
  end
  if peek(isOpenState) then
    return
  end

  isOpenState:set(true)

  -- Start timer update loop
  if restockTimeState then
    restockTimeState:set(formatRestockTime(Store.getTimeUntilReplenish()))
  end

  if timerConnection then
    timerConnection:Disconnect()
  end

  local lastUpdate = 0
  timerConnection = RunService.Heartbeat:Connect(function(deltaTime)
    lastUpdate = lastUpdate + deltaTime
    if lastUpdate >= 1 then
      lastUpdate = 0
      if restockTimeState then
        restockTimeState:set(formatRestockTime(Store.getTimeUntilReplenish()))
      end
    end
  end)

  print("[StoreUI] Opened")
end

--[[
	Closes the store UI with animation.
]]
function StoreUI.close()
  if not screenGui or not isOpenState then
    return
  end
  if not peek(isOpenState) then
    return
  end

  isOpenState:set(false)

  -- Stop timer update loop
  if timerConnection then
    timerConnection:Disconnect()
    timerConnection = nil
  end

  -- Close confirmation if open
  if showConfirmationState then
    showConfirmationState:set(false)
  end

  print("[StoreUI] Closed")
end

--[[
	Toggles the store UI open/closed.
]]
function StoreUI.toggle()
  if isOpenState and peek(isOpenState) then
    StoreUI.close()
  else
    StoreUI.open()
  end
end

--[[
	Returns whether the store UI is currently open.
]]
function StoreUI.isOpen(): boolean
  return isOpenState ~= nil and peek(isOpenState)
end

--[[
	Updates the cached player money and affordability indicators.
]]
function StoreUI.updateMoney(money: number)
  if playerMoneyState then
    playerMoneyState:set(money)
  end
end

--[[
	Sets the callback for when an egg purchase is attempted.
]]
function StoreUI.onPurchase(callback: (eggType: string, quantity: number) -> any)
  onEggPurchaseCallback = callback
end

--[[
	Sets the callback for when Robux replenish is attempted.
]]
function StoreUI.onReplenish(callback: () -> any)
  onReplenishCallback = callback
end

--[[
	Sets the callback for when Robux item purchase is attempted.
]]
function StoreUI.onRobuxPurchase(callback: (itemType: string, itemId: string) -> any)
  onRobuxPurchaseCallback = callback
end

--[[
	Sets the callback for when a power-up purchase is attempted.
]]
function StoreUI.onPowerUpPurchase(callback: (powerUpId: string) -> any)
  onPowerUpPurchaseCallback = callback
end

--[[
	Sets the callback for when a trap/supply purchase is attempted.
]]
function StoreUI.onTrapPurchase(callback: (trapType: string) -> any)
  onTrapPurchaseCallback = callback
end

--[[
	Registers a callback for weapon purchase events.
]]
function StoreUI.onWeaponPurchase(callback: (weaponType: string) -> any)
  onWeaponPurchaseCallback = callback
end

--[[
	Returns the current tab.
]]
function StoreUI.getCurrentTab(): string
  return currentTabState and peek(currentTabState) or "eggs"
end

--[[
	Refreshes the store inventory display.
]]
function StoreUI.refreshInventory()
  if inventoryRefreshState then
    inventoryRefreshState:set(peek(inventoryRefreshState) + 1)
  end
end

--[[
	Updates the cached owned weapons for display.
]]
function StoreUI.updateOwnedWeapons(ownedWeapons: { string }?)
  if not ownedWeaponsState then
    return
  end

  local weaponMap = {}
  if ownedWeapons then
    for _, weaponType in ipairs(ownedWeapons) do
      weaponMap[weaponType] = true
    end
  end
  ownedWeaponsState:set(weaponMap)
end

--[[
	Updates the cached active power-ups for display.
]]
function StoreUI.updateActivePowerUps(activePowerUps: { [string]: number }?)
  if activePowerUpsState then
    activePowerUpsState:set(activePowerUps or {})
  end
end

--[[
	Updates the stock display for a specific item.
]]
function StoreUI.updateItemStock(itemType: string, itemId: string, newStock: number)
  -- Trigger a refresh to update the UI
  StoreUI.refreshInventory()
end

return StoreUI
