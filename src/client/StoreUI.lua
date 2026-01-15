--[[
	StoreUI Module
	Implements the store UI where players can browse and purchase eggs and chickens.
	Opens when player interacts with the central store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local StoreUI = {}

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local Store = require(Shared:WaitForChild("Store"))
local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

-- Rarity colors for visual distinction
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(200, 200, 200),
  Uncommon = Color3.fromRGB(50, 205, 50),
  Rare = Color3.fromRGB(30, 144, 255),
  Epic = Color3.fromRGB(148, 0, 211),
  Legendary = Color3.fromRGB(255, 165, 0),
  Mythic = Color3.fromRGB(255, 0, 100),
}

-- Rarity gradients for card backgrounds (start = top, end = bottom)
local RARITY_GRADIENTS: { [string]: { start: Color3, endColor: Color3 } } = {
  Common = { start = Color3.fromRGB(180, 180, 180), endColor = Color3.fromRGB(255, 255, 255) },
  Uncommon = { start = Color3.fromRGB(144, 238, 144), endColor = Color3.fromRGB(34, 139, 34) },
  Rare = { start = Color3.fromRGB(135, 206, 250), endColor = Color3.fromRGB(30, 90, 180) },
  Epic = { start = Color3.fromRGB(200, 150, 255), endColor = Color3.fromRGB(148, 0, 211) },
  Legendary = { start = Color3.fromRGB(255, 220, 100), endColor = Color3.fromRGB(255, 140, 0) },
  Mythic = { start = Color3.fromRGB(255, 150, 180), endColor = Color3.fromRGB(255, 0, 100) },
}

-- Tier gradients for supplies/traps and weapons (consistent with rarity gradients)
local TIER_GRADIENTS: { [string]: { start: Color3, endColor: Color3 } } = {
  -- Supplies/Traps tiers
  Basic = { start = Color3.fromRGB(200, 200, 200), endColor = Color3.fromRGB(140, 140, 140) },
  Improved = { start = Color3.fromRGB(160, 255, 160), endColor = Color3.fromRGB(50, 180, 50) },
  Advanced = { start = Color3.fromRGB(140, 200, 255), endColor = Color3.fromRGB(30, 120, 220) },
  Expert = { start = Color3.fromRGB(200, 160, 255), endColor = Color3.fromRGB(140, 40, 200) },
  Master = { start = Color3.fromRGB(255, 220, 150), endColor = Color3.fromRGB(255, 140, 0) },
  Ultimate = { start = Color3.fromRGB(255, 180, 200), endColor = Color3.fromRGB(255, 50, 100) },
  -- Weapons tiers
  Standard = { start = Color3.fromRGB(140, 200, 255), endColor = Color3.fromRGB(40, 130, 220) },
  Premium = { start = Color3.fromRGB(255, 220, 150), endColor = Color3.fromRGB(255, 150, 50) },
}

-- Local player reference
local localPlayer = Players.LocalPlayer

-- UI components
local screenGui: ScreenGui? = nil
local mainFrame: Frame? = nil
local tabFrame: Frame? = nil
local scrollFrame: ScrollingFrame? = nil
local replenishButton: TextButton? = nil
local confirmationFrame: Frame? = nil
local restockTimerLabel: TextLabel? = nil
local timerConnection: RBXScriptConnection? = nil
local isOpen = false
local currentTab: "eggs" | "chickens" | "supplies" | "powerups" | "weapons" = "eggs"

-- Cached player money for UI updates
local cachedPlayerMoney = 0

-- Cached active power-ups for display
local cachedActivePowerUps: { [string]: number }? = nil -- powerUpType -> expiresAt

-- Robux price for instant replenish (configurable)
local ROBUX_REPLENISH_PRICE = 50

-- Animation constants
local ANIMATION_DURATION = 0.35
local OPEN_TWEEN_INFO =
  TweenInfo.new(ANIMATION_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN_INFO =
  TweenInfo.new(ANIMATION_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local TARGET_SIZE = UDim2.new(0, 420, 0, 550)
local CLOSED_SIZE = UDim2.new(0, 0, 0, 0)

-- Tab switching animation constants
local TAB_ANIMATION_DURATION = 0.2
local TAB_TWEEN_INFO =
  TweenInfo.new(TAB_ANIMATION_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CONTENT_FADE_DURATION = 0.15
local CONTENT_FADE_INFO =
  TweenInfo.new(CONTENT_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Animation state
local isAnimating = false
local isTabSwitching = false

-- Callbacks
local onEggPurchaseCallback: ((eggType: string, quantity: number) -> any)? = nil
local onChickenPurchaseCallback: ((chickenType: string, quantity: number) -> any)? = nil
local onReplenishCallback: (() -> any)? = nil
local onRobuxPurchaseCallback: ((itemType: string, itemId: string) -> any)? = nil
local onPowerUpPurchaseCallback: ((powerUpId: string) -> any)? = nil
local onTrapPurchaseCallback: ((trapType: string) -> any)? = nil
local onWeaponPurchaseCallback: ((weaponType: string) -> any)? = nil

-- Cached owned weapons for display
local cachedOwnedWeapons: { [string]: boolean }? = nil

--[[
	Formats seconds into M:SS format for the restock timer.
	@param seconds number - Time remaining in seconds
	@return string - Formatted time string
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
	Updates the restock timer display.
]]
local function updateRestockTimer()
  if not restockTimerLabel then
    return
  end
  local timeRemaining = Store.getTimeUntilReplenish()
  restockTimerLabel.Text = formatRestockTime(timeRemaining)
end

--[[
	Generates a description for an egg based on its hatch outcomes.
	Shows what chickens can be hatched from this egg.
	@param eggType string - The egg type identifier
	@return string - Description text for the egg
]]
local function getEggDescription(eggType: string): string
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return "Contains mysterious chickens"
  end

  -- Find the rarest outcome (lowest probability = rarest)
  local rarestOutcome = eggConfig.hatchOutcomes[1]
  for _, outcome in ipairs(eggConfig.hatchOutcomes) do
    if outcome.probability < rarestOutcome.probability then
      rarestOutcome = outcome
    end
  end

  -- Get the display name of the rarest chicken
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
	Generates a description for a chicken based on its config.
	@param chickenType string - The chicken type identifier
	@return string - Description text for the chicken
]]
local function getChickenDescription(chickenType: string): string
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return "A fine feathered friend"
  end

  return "Earns $"
    .. chickenConfig.moneyPerSecond
    .. "/sec • Lays eggs every "
    .. math.floor(chickenConfig.eggLayIntervalSeconds / 60)
    .. "m"
end

--[[
	Creates a single item card for the store (works for both eggs and chickens).
	@param itemType "egg" | "chicken" - The type of item
	@param itemId string - The item type identifier
	@param displayName string - Display name for the item
	@param rarity string - Rarity tier
	@param price number - Purchase price
	@param robuxPrice number - Robux price
	@param stock number - Current stock count
	@param parent Instance - Parent frame to add card to
	@param index number - Index for positioning
	@param description string? - Optional description text (generated if not provided)
]]
local function createItemCard(
  itemType: "egg" | "chicken",
  itemId: string,
  displayName: string,
  rarity: string,
  price: number,
  robuxPrice: number,
  stock: number,
  parent: Frame,
  index: number,
  description: string?
): Frame
  local card = Instance.new("Frame")
  card.Name = itemId
  card.Size = UDim2.new(1, 0, 0, 104) -- Full width, UIListLayout handles spacing
  card.LayoutOrder = index
  card.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Base color for gradient
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Rarity-based gradient background
  local gradientColors = RARITY_GRADIENTS[rarity] or RARITY_GRADIENTS.Common
  local cardGradient = Instance.new("UIGradient")
  cardGradient.Name = "RarityGradient"
  cardGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, gradientColors.start),
    ColorSequenceKeypoint.new(1, gradientColors.endColor),
  })
  cardGradient.Rotation = 90 -- Vertical gradient (light on top)
  cardGradient.Parent = card

  -- Card stroke for definition
  local cardStroke = Instance.new("UIStroke")
  cardStroke.Name = "CardStroke"
  cardStroke.Color = Color3.fromRGB(60, 40, 20) -- Dark brown to match theme
  cardStroke.Thickness = 2
  cardStroke.Transparency = 0.3
  cardStroke.Parent = card

  -- Rarity indicator bar (accent on left edge)
  local rarityBar = Instance.new("Frame")
  rarityBar.Name = "RarityBar"
  rarityBar.Size = UDim2.new(0, 4, 1, 0)
  rarityBar.Position = UDim2.new(0, 0, 0, 0)
  rarityBar.BackgroundColor3 = RARITY_COLORS[rarity] or Color3.fromRGB(128, 128, 128)
  rarityBar.BorderSizePixel = 0
  rarityBar.Parent = card

  local rarityBarCorner = Instance.new("UICorner")
  rarityBarCorner.CornerRadius = UDim.new(0, 4)
  rarityBarCorner.Parent = rarityBar

  -- Item icon (enlarged with pop-out effect)
  -- Drop shadow behind icon for depth
  local iconShadow = Instance.new("TextLabel")
  iconShadow.Name = "IconShadow"
  iconShadow.Size = UDim2.new(0, 60, 0, 60)
  iconShadow.Position = UDim2.new(0, -7, 0.5, -27) -- Offset by 3px for shadow effect
  iconShadow.BackgroundTransparency = 1
  iconShadow.Text = itemType == "egg" and "🥚" or "🐔"
  iconShadow.TextSize = 48
  iconShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
  iconShadow.TextTransparency = 0.6
  iconShadow.ZIndex = 2
  iconShadow.Parent = card

  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 60, 0, 60)
  iconLabel.Position = UDim2.new(0, -10, 0.5, -30) -- Overlaps left edge by 10px
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = itemType == "egg" and "🥚" or "🐔"
  iconLabel.TextSize = 48
  iconLabel.ZIndex = 3 -- Above shadow and card edge
  iconLabel.Parent = card

  -- Item name (white with dark stroke for visibility on gradients)
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.35, -20, 0, 22)
  nameLabel.Position = UDim2.new(0, 55, 0, 8) -- Shifted right for larger icon
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = displayName
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White for visibility
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.FredokaOne -- Cartoony chunky font
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) -- Dark stroke for pop effect
  nameLabel.TextStrokeTransparency = 0
  nameLabel.Parent = card

  -- Subtext description (italicized style, describes egg contents)
  local subtextContent = description
  if not subtextContent then
    subtextContent = itemType == "egg" and getEggDescription(itemId)
      or getChickenDescription(itemId)
  end
  local subtextLabel = Instance.new("TextLabel")
  subtextLabel.Name = "Subtext"
  subtextLabel.Size = UDim2.new(0.5, -20, 0, 14)
  subtextLabel.Position = UDim2.new(0, 55, 0, 30)
  subtextLabel.BackgroundTransparency = 1
  subtextLabel.Text = subtextContent
  subtextLabel.TextColor3 = Color3.fromRGB(80, 60, 40) -- Dark brown, slightly muted
  subtextLabel.TextScaled = true
  subtextLabel.Font = Enum.Font.GothamMedium
  subtextLabel.TextXAlignment = Enum.TextXAlignment.Left
  subtextLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  subtextLabel.TextStrokeTransparency = 0.5
  subtextLabel.TextTransparency = 0.15 -- Slightly faded for subordinate appearance
  subtextLabel.Parent = card

  -- Rarity label (dark text for readability on gradients)
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "Rarity"
  rarityLabel.Size = UDim2.new(0.35, -20, 0, 16)
  rarityLabel.Position = UDim2.new(0, 55, 0, 46)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.Text = rarity
  rarityLabel.TextColor3 = Color3.fromRGB(50, 50, 50) -- Dark grey for readability
  rarityLabel.TextScaled = true
  rarityLabel.Font = Enum.Font.GothamMedium -- Standard body font
  rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
  rarityLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  rarityLabel.TextStrokeTransparency = 0.7
  rarityLabel.Parent = card

  -- Stock label (dark text for readability)
  local stockLabel = Instance.new("TextLabel")
  stockLabel.Name = "StockLabel"
  stockLabel.Size = UDim2.new(0, 60, 0, 16)
  stockLabel.Position = UDim2.new(0, 55, 0, 64)
  stockLabel.BackgroundTransparency = 1
  stockLabel.Text = stock > 0 and ("x" .. tostring(stock)) or "SOLD OUT"
  stockLabel.TextColor3 = stock > 0 and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(180, 30, 30)
  stockLabel.TextScaled = true
  stockLabel.Font = Enum.Font.GothamMedium -- Standard body font
  stockLabel.TextXAlignment = Enum.TextXAlignment.Left
  stockLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  stockLabel.TextStrokeTransparency = stock > 0 and 0.7 or 0.5
  stockLabel.Parent = card

  -- Buy button (with in-game money) - stacked vertically on right
  local isSoldOut = stock <= 0
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 85, 0, 38)
  buyButton.Position = UDim2.new(1, -95, 0, 8) -- Top right, stacked vertically
  buyButton.BackgroundColor3 = isSoldOut and Color3.fromRGB(80, 80, 80)
    or Color3.fromRGB(50, 180, 50)
  buyButton.Text = "" -- Text handled by child labels
  buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  buyButton.TextTransparency = isSoldOut and 0.5 or 0
  buyButton.TextScaled = true
  buyButton.Font = Enum.Font.GothamBold
  buyButton.BackgroundTransparency = 0
  buyButton.ZIndex = 2
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 8)
  buyButtonCorner.Parent = buyButton

  -- Cash button icon and price label
  local cashIcon = Instance.new("TextLabel")
  cashIcon.Name = "CashIcon"
  cashIcon.Size = UDim2.new(0, 24, 1, 0)
  cashIcon.Position = UDim2.new(0, 4, 0, 0)
  cashIcon.BackgroundTransparency = 1
  cashIcon.Text = "💵"
  cashIcon.TextSize = 18
  cashIcon.ZIndex = 3
  cashIcon.Parent = buyButton

  local cashPriceLabel = Instance.new("TextLabel")
  cashPriceLabel.Name = "CashPriceLabel"
  cashPriceLabel.Size = UDim2.new(1, -32, 1, 0)
  cashPriceLabel.Position = UDim2.new(0, 28, 0, 0)
  cashPriceLabel.BackgroundTransparency = 1
  cashPriceLabel.Text = isSoldOut and "SOLD" or ("$" .. tostring(price))
  cashPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  cashPriceLabel.TextStrokeTransparency = 0
  cashPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  cashPriceLabel.TextScaled = true
  cashPriceLabel.Font = Enum.Font.GothamBold
  cashPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  cashPriceLabel.ZIndex = 3
  cashPriceLabel.Parent = buyButton

  -- Shine effect for cash button
  local cashShine = Instance.new("UIGradient")
  cashShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
  })
  cashShine.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.7),
    NumberSequenceKeypoint.new(0.3, 0.9),
    NumberSequenceKeypoint.new(1, 0.85),
  })
  cashShine.Rotation = 45
  cashShine.Parent = buyButton

  -- Hover effect for cash button
  local cashOriginalColor = buyButton.BackgroundColor3
  buyButton.MouseEnter:Connect(function()
    if not isSoldOut then
      buyButton.BackgroundColor3 = Color3.fromRGB(70, 220, 70) -- Brighter green
    end
  end)
  buyButton.MouseLeave:Connect(function()
    -- Restore based on current affordability state
    local canAfford = cachedPlayerMoney >= (card:GetAttribute("Price") or price)
    local soldOut = (card:GetAttribute("Stock") or stock) <= 0
    if soldOut then
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    elseif canAfford then
      buyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
    else
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    end
  end)

  -- Robux buy button (stacked below cash button)
  local robuxButton = Instance.new("TextButton")
  robuxButton.Name = "RobuxButton"
  robuxButton.Size = UDim2.new(0, 85, 0, 38)
  robuxButton.Position = UDim2.new(1, -95, 0, 52) -- Below cash button
  robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215) -- Premium blue
  robuxButton.Text = "" -- Text handled by child labels
  robuxButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxButton.TextScaled = true
  robuxButton.Font = Enum.Font.GothamBold
  robuxButton.BackgroundTransparency = 0
  robuxButton.ZIndex = 2
  robuxButton.Parent = card

  local robuxButtonCorner = Instance.new("UICorner")
  robuxButtonCorner.CornerRadius = UDim.new(0, 8)
  robuxButtonCorner.Parent = robuxButton

  -- UIStroke for premium button 'juicy' look
  local robuxStroke = Instance.new("UIStroke")
  robuxStroke.Color = Color3.fromRGB(100, 200, 255) -- Light blue glow
  robuxStroke.Thickness = 2
  robuxStroke.Parent = robuxButton

  -- Gem icon for premium button
  local gemIcon = Instance.new("TextLabel")
  gemIcon.Name = "GemIcon"
  gemIcon.Size = UDim2.new(0, 24, 1, 0)
  gemIcon.Position = UDim2.new(0, 4, 0, 0)
  gemIcon.BackgroundTransparency = 1
  gemIcon.Text = "💎"
  gemIcon.TextSize = 18
  gemIcon.ZIndex = 3
  gemIcon.Parent = robuxButton

  -- Robux price text
  local robuxPriceLabel = Instance.new("TextLabel")
  robuxPriceLabel.Name = "RobuxPriceLabel"
  robuxPriceLabel.Size = UDim2.new(1, -32, 1, 0)
  robuxPriceLabel.Position = UDim2.new(0, 28, 0, 0)
  robuxPriceLabel.BackgroundTransparency = 1
  robuxPriceLabel.Text = tostring(robuxPrice)
  robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxPriceLabel.TextStrokeTransparency = 0
  robuxPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  robuxPriceLabel.TextScaled = true
  robuxPriceLabel.Font = Enum.Font.GothamBold
  robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  robuxPriceLabel.ZIndex = 3
  robuxPriceLabel.Parent = robuxButton

  -- Shine effect for premium button
  local premiumShine = Instance.new("UIGradient")
  premiumShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
  })
  premiumShine.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.7),
    NumberSequenceKeypoint.new(0.3, 0.9),
    NumberSequenceKeypoint.new(1, 0.85),
  })
  premiumShine.Rotation = 45
  premiumShine.Parent = robuxButton

  -- Hover effect for premium button
  robuxButton.MouseEnter:Connect(function()
    robuxButton.BackgroundColor3 = Color3.fromRGB(30, 150, 255) -- Brighter blue
    robuxStroke.Color = Color3.fromRGB(150, 220, 255)
  end)
  robuxButton.MouseLeave:Connect(function()
    robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    robuxStroke.Color = Color3.fromRGB(100, 200, 255)
  end)

  -- Connect buy button (only if in stock)
  if not isSoldOut then
    buyButton.MouseButton1Click:Connect(function()
      if itemType == "egg" and onEggPurchaseCallback then
        onEggPurchaseCallback(itemId, 1)
      elseif itemType == "chicken" and onChickenPurchaseCallback then
        onChickenPurchaseCallback(itemId, 1)
      end
    end)
  end

  -- Connect Robux button (always available)
  robuxButton.MouseButton1Click:Connect(function()
    if onRobuxPurchaseCallback then
      onRobuxPurchaseCallback(itemType, itemId)
    end
  end)

  -- Store price and stock on card for affordability updates
  card:SetAttribute("Price", price)
  card:SetAttribute("Stock", stock)

  -- Update affordability - shows price on button via cashPriceLabel
  local function updateAffordability()
    local cardPrice = card:GetAttribute("Price") or price
    local cardStock = card:GetAttribute("Stock") or stock
    local canAfford = cachedPlayerMoney >= cardPrice
    local soldOut = cardStock <= 0
    local priceText = "$" .. tostring(cardPrice)
    if soldOut then
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
      cashPriceLabel.Text = "SOLD"
      cashPriceLabel.TextTransparency = 0.5
      cashIcon.TextTransparency = 0.5
    elseif canAfford then
      buyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
      cashPriceLabel.Text = priceText
      cashPriceLabel.TextTransparency = 0
      cashIcon.TextTransparency = 0
    else
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
      cashPriceLabel.Text = priceText
      cashPriceLabel.TextTransparency = 0.5
      cashIcon.TextTransparency = 0.5
    end
  end

  -- Listen for money updates
  card:SetAttribute("UpdateAffordability", true)
  card.AttributeChanged:Connect(function(attributeName)
    if attributeName == "PlayerMoney" or attributeName == "Stock" then
      updateAffordability()
    end
  end)

  updateAffordability()
  return card
end

--[[
	Creates a power-up card for the store.
	@param powerUpId string - The power-up identifier
	@param config table - Power-up configuration
	@param parent Instance - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createPowerUpCard(
  powerUpId: string,
  config: PowerUpConfig.PowerUpConfig,
  parent: Frame,
  index: number
): Frame
  local card = Instance.new("Frame")
  card.Name = powerUpId
  card.Size = UDim2.new(1, 0, 0, 104) -- Full width, UIListLayout handles spacing
  card.LayoutOrder = index
  card.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Base for gradient
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Power-up type colors and gradient
  local isLuck = string.find(powerUpId, "HatchLuck") ~= nil
  local barColor = isLuck and Color3.fromRGB(50, 205, 50) or Color3.fromRGB(255, 215, 0)
  local gradientStart = isLuck and Color3.fromRGB(160, 255, 160) or Color3.fromRGB(255, 240, 180)
  local gradientEnd = isLuck and Color3.fromRGB(50, 180, 50) or Color3.fromRGB(255, 180, 50)

  -- Gradient background
  local cardGradient = Instance.new("UIGradient")
  cardGradient.Name = "PowerUpGradient"
  cardGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, gradientStart),
    ColorSequenceKeypoint.new(1, gradientEnd),
  })
  cardGradient.Rotation = 90
  cardGradient.Parent = card

  -- Card stroke for definition
  local cardStroke = Instance.new("UIStroke")
  cardStroke.Name = "CardStroke"
  cardStroke.Color = Color3.fromRGB(60, 40, 20)
  cardStroke.Thickness = 2
  cardStroke.Transparency = 0.3
  cardStroke.Parent = card

  -- Type bar (accent)
  local typeBar = Instance.new("Frame")
  typeBar.Name = "TypeBar"
  typeBar.Size = UDim2.new(0, 4, 1, 0)
  typeBar.Position = UDim2.new(0, 0, 0, 0)
  typeBar.BackgroundColor3 = barColor
  typeBar.BorderSizePixel = 0
  typeBar.Parent = card

  local typeBarCorner = Instance.new("UICorner")
  typeBarCorner.CornerRadius = UDim.new(0, 4)
  typeBarCorner.Parent = typeBar

  -- Icon shadow for depth
  local iconShadow = Instance.new("TextLabel")
  iconShadow.Name = "IconShadow"
  iconShadow.Size = UDim2.new(0, 60, 0, 60)
  iconShadow.Position = UDim2.new(0, -7, 0.5, -27)
  iconShadow.BackgroundTransparency = 1
  iconShadow.Text = config.icon
  iconShadow.TextSize = 48
  iconShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
  iconShadow.TextTransparency = 0.6
  iconShadow.ZIndex = 2
  iconShadow.Parent = card

  -- Icon (enlarged with pop-out)
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 60, 0, 60)
  iconLabel.Position = UDim2.new(0, -10, 0.5, -30)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = config.icon
  iconLabel.TextSize = 48
  iconLabel.ZIndex = 3
  iconLabel.Parent = card

  -- Power-up name (white with dark stroke)
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.35, -20, 0, 28)
  nameLabel.Position = UDim2.new(0, 55, 0, 12)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = config.displayName
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.FredokaOne -- Cartoony chunky font
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  nameLabel.TextStrokeTransparency = 0
  nameLabel.Parent = card

  -- Description
  local descLabel = Instance.new("TextLabel")
  descLabel.Name = "Description"
  descLabel.Size = UDim2.new(0.4, 0, 0, 20)
  descLabel.Position = UDim2.new(0, 55, 0, 42)
  descLabel.BackgroundTransparency = 1
  descLabel.Text = config.description
  descLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  descLabel.TextScaled = true
  descLabel.Font = Enum.Font.GothamMedium -- Standard body font
  descLabel.TextXAlignment = Enum.TextXAlignment.Left
  descLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  descLabel.TextStrokeTransparency = 0.7
  descLabel.Parent = card

  -- Duration and status info
  local durationText = PowerUpConfig.formatRemainingTime(config.durationSeconds)
  local powerUpType = PowerUpConfig.getPowerUpType(powerUpId)
  local activeExpiresAt = cachedActivePowerUps and powerUpType and cachedActivePowerUps[powerUpType]
  local isActive = activeExpiresAt and os.time() < activeExpiresAt

  local statusLabel = Instance.new("TextLabel")
  statusLabel.Name = "Status"
  statusLabel.Size = UDim2.new(0.4, 0, 0, 20)
  statusLabel.Position = UDim2.new(0, 55, 0, 70)
  statusLabel.BackgroundTransparency = 1
  if isActive then
    local remaining = activeExpiresAt - os.time()
    statusLabel.Text = "✓ ACTIVE (" .. PowerUpConfig.formatRemainingTime(remaining) .. " left)"
    statusLabel.TextColor3 = Color3.fromRGB(20, 120, 20)
  else
    statusLabel.Text = "Duration: " .. durationText
    statusLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  end
  statusLabel.TextScaled = true
  statusLabel.Font = Enum.Font.GothamBold
  statusLabel.TextXAlignment = Enum.TextXAlignment.Left
  statusLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  statusLabel.TextStrokeTransparency = 0.7
  statusLabel.Parent = card

  -- Buy button (Robux only, centered vertically)
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 85, 0, 42)
  buyButton.Position = UDim2.new(1, -95, 0.5, -21)
  buyButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
  buyButton.Text = ""
  buyButton.BackgroundTransparency = 0
  buyButton.ZIndex = 2
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 8)
  buyButtonCorner.Parent = buyButton

  -- UIStroke for premium button
  local buyStroke = Instance.new("UIStroke")
  buyStroke.Color = Color3.fromRGB(100, 200, 255)
  buyStroke.Thickness = 2
  buyStroke.Parent = buyButton

  -- Gem icon
  local gemIcon = Instance.new("TextLabel")
  gemIcon.Name = "GemIcon"
  gemIcon.Size = UDim2.new(0, 24, 1, 0)
  gemIcon.Position = UDim2.new(0, 4, 0, 0)
  gemIcon.BackgroundTransparency = 1
  gemIcon.Text = "💎"
  gemIcon.TextSize = 18
  gemIcon.ZIndex = 3
  gemIcon.Parent = buyButton

  local priceLabel = Instance.new("TextLabel")
  priceLabel.Name = "PriceLabel"
  priceLabel.Size = UDim2.new(1, -32, 1, 0)
  priceLabel.Position = UDim2.new(0, 28, 0, 0)
  priceLabel.BackgroundTransparency = 1
  priceLabel.Text = tostring(config.robuxPrice)
  priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  priceLabel.TextStrokeTransparency = 0
  priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  priceLabel.TextScaled = true
  priceLabel.Font = Enum.Font.GothamBold
  priceLabel.TextXAlignment = Enum.TextXAlignment.Left
  priceLabel.ZIndex = 3
  priceLabel.Parent = buyButton

  -- Shine effect
  local premiumShine = Instance.new("UIGradient")
  premiumShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
  })
  premiumShine.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.7),
    NumberSequenceKeypoint.new(0.3, 0.9),
    NumberSequenceKeypoint.new(1, 0.85),
  })
  premiumShine.Rotation = 45
  premiumShine.Parent = buyButton

  -- Hover effect
  buyButton.MouseEnter:Connect(function()
    buyButton.BackgroundColor3 = Color3.fromRGB(30, 150, 255)
    buyStroke.Color = Color3.fromRGB(150, 220, 255)
  end)
  buyButton.MouseLeave:Connect(function()
    buyButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    buyStroke.Color = Color3.fromRGB(100, 200, 255)
  end)

  -- Connect buy button
  buyButton.MouseButton1Click:Connect(function()
    if onPowerUpPurchaseCallback then
      onPowerUpPurchaseCallback(powerUpId)
    end
  end)

  return card
end

-- Tier colors for supplies/traps
local TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Improved = Color3.fromRGB(50, 200, 50),
  Advanced = Color3.fromRGB(50, 150, 255),
  Expert = Color3.fromRGB(160, 50, 220),
  Master = Color3.fromRGB(255, 165, 0),
  Ultimate = Color3.fromRGB(255, 50, 100),
}

--[[
	Creates a supply/trap card for the store with themed styling.
	@param supplyItem Store.SupplyItem - The supply item data
	@param parent Frame - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createSupplyCard(supplyItem: Store.SupplyItem, parent: Frame, index: number): Frame
  local card = Instance.new("Frame")
  card.Name = supplyItem.id
  card.Size = UDim2.new(1, 0, 0, 104) -- Full width, UIListLayout handles spacing
  card.LayoutOrder = index
  card.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Base for gradient
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Tier-based gradient background
  local gradientColors = TIER_GRADIENTS[supplyItem.tier] or TIER_GRADIENTS.Basic
  local cardGradient = Instance.new("UIGradient")
  cardGradient.Name = "TierGradient"
  cardGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, gradientColors.start),
    ColorSequenceKeypoint.new(1, gradientColors.endColor),
  })
  cardGradient.Rotation = 90
  cardGradient.Parent = card

  -- Card stroke for definition
  local cardStroke = Instance.new("UIStroke")
  cardStroke.Name = "CardStroke"
  cardStroke.Color = Color3.fromRGB(60, 40, 20)
  cardStroke.Thickness = 2
  cardStroke.Transparency = 0.3
  cardStroke.Parent = card

  -- Tier color bar on left (accent)
  local tierBar = Instance.new("Frame")
  tierBar.Name = "TierBar"
  tierBar.Size = UDim2.new(0, 4, 1, 0)
  tierBar.Position = UDim2.new(0, 0, 0, 0)
  tierBar.BackgroundColor3 = TIER_COLORS[supplyItem.tier] or Color3.fromRGB(128, 128, 128)
  tierBar.BorderSizePixel = 0
  tierBar.Parent = card

  local tierBarCorner = Instance.new("UICorner")
  tierBarCorner.CornerRadius = UDim.new(0, 4)
  tierBarCorner.Parent = tierBar

  -- Icon shadow for depth
  local iconShadow = Instance.new("ImageLabel")
  iconShadow.Name = "IconShadow"
  iconShadow.Size = UDim2.new(0, 60, 0, 60)
  iconShadow.Position = UDim2.new(0, -7, 0.5, -27)
  iconShadow.BackgroundTransparency = 1
  iconShadow.Image = "rbxassetid://6022668885"
  iconShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
  iconShadow.ImageTransparency = 0.6
  iconShadow.ScaleType = Enum.ScaleType.Fit
  iconShadow.ZIndex = 2
  iconShadow.Parent = card

  -- Icon (enlarged with pop-out effect)
  local iconImage = Instance.new("ImageLabel")
  iconImage.Name = "Icon"
  iconImage.Size = UDim2.new(0, 60, 0, 60)
  iconImage.Position = UDim2.new(0, -10, 0.5, -30)
  iconImage.BackgroundTransparency = 1
  iconImage.Image = "rbxassetid://6022668885"
  iconImage.ScaleType = Enum.ScaleType.Fit
  iconImage.ZIndex = 3
  iconImage.Parent = card

  -- Name label (white with dark stroke)
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.35, -20, 0, 22)
  nameLabel.Position = UDim2.new(0, 55, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = supplyItem.displayName
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.FredokaOne -- Cartoony chunky font
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  nameLabel.TextStrokeTransparency = 0
  nameLabel.Parent = card

  -- Subtext description (below name, describes trap functionality)
  local subtextLabel = Instance.new("TextLabel")
  subtextLabel.Name = "Subtext"
  subtextLabel.Size = UDim2.new(0.5, -20, 0, 14)
  subtextLabel.Position = UDim2.new(0, 55, 0, 30)
  subtextLabel.BackgroundTransparency = 1
  subtextLabel.Text = supplyItem.description
  subtextLabel.TextColor3 = Color3.fromRGB(80, 60, 40) -- Dark brown, slightly muted
  subtextLabel.TextScaled = true
  subtextLabel.Font = Enum.Font.GothamMedium
  subtextLabel.TextXAlignment = Enum.TextXAlignment.Left
  subtextLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  subtextLabel.TextStrokeTransparency = 0.5
  subtextLabel.TextTransparency = 0.15 -- Slightly faded for subordinate appearance
  subtextLabel.Parent = card

  -- Tier label (dark for readability)
  local tierLabel = Instance.new("TextLabel")
  tierLabel.Name = "Tier"
  tierLabel.Size = UDim2.new(0.35, -20, 0, 16)
  tierLabel.Position = UDim2.new(0, 55, 0, 46)
  tierLabel.BackgroundTransparency = 1
  tierLabel.Text = supplyItem.tier
  tierLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  tierLabel.TextScaled = true
  tierLabel.Font = Enum.Font.GothamMedium -- Standard body font
  tierLabel.TextXAlignment = Enum.TextXAlignment.Left
  tierLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  tierLabel.TextStrokeTransparency = 0.7
  tierLabel.Parent = card

  -- Effectiveness info (catch rate info)
  local effectivenessLabel = Instance.new("TextLabel")
  effectivenessLabel.Name = "Effectiveness"
  effectivenessLabel.Size = UDim2.new(0.4, 0, 0, 16)
  effectivenessLabel.Position = UDim2.new(0, 55, 0, 64)
  effectivenessLabel.BackgroundTransparency = 1
  effectivenessLabel.Text = "+"
    .. tostring(math.floor((supplyItem.effectiveness or 0) * 100))
    .. "% catch rate"
  effectivenessLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  effectivenessLabel.TextScaled = true
  effectivenessLabel.Font = Enum.Font.GothamMedium
  effectivenessLabel.TextXAlignment = Enum.TextXAlignment.Left
  effectivenessLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  effectivenessLabel.TextStrokeTransparency = 0.7
  effectivenessLabel.Parent = card

  -- Cash buy button (stacked vertically)
  local canAfford = cachedPlayerMoney >= supplyItem.price
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 85, 0, 38)
  buyButton.Position = UDim2.new(1, -95, 0, 8)
  buyButton.BackgroundColor3 = canAfford and Color3.fromRGB(50, 180, 50)
    or Color3.fromRGB(80, 80, 80)
  buyButton.Text = ""
  buyButton.BackgroundTransparency = 0
  buyButton.ZIndex = 2
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 8)
  buyButtonCorner.Parent = buyButton

  -- Cash button icon
  local cashIcon = Instance.new("TextLabel")
  cashIcon.Name = "CashIcon"
  cashIcon.Size = UDim2.new(0, 24, 1, 0)
  cashIcon.Position = UDim2.new(0, 4, 0, 0)
  cashIcon.BackgroundTransparency = 1
  cashIcon.Text = "💵"
  cashIcon.TextSize = 18
  cashIcon.ZIndex = 3
  cashIcon.Parent = buyButton

  local cashPriceLabel = Instance.new("TextLabel")
  cashPriceLabel.Name = "CashPriceLabel"
  cashPriceLabel.Size = UDim2.new(1, -32, 1, 0)
  cashPriceLabel.Position = UDim2.new(0, 28, 0, 0)
  cashPriceLabel.BackgroundTransparency = 1
  cashPriceLabel.Text = "$" .. tostring(supplyItem.price)
  cashPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  cashPriceLabel.TextStrokeTransparency = 0
  cashPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  cashPriceLabel.TextScaled = true
  cashPriceLabel.Font = Enum.Font.GothamBold
  cashPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  cashPriceLabel.ZIndex = 3
  cashPriceLabel.Parent = buyButton

  -- Shine effect for cash button
  local cashShine = Instance.new("UIGradient")
  cashShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
  })
  cashShine.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.7),
    NumberSequenceKeypoint.new(0.3, 0.9),
    NumberSequenceKeypoint.new(1, 0.85),
  })
  cashShine.Rotation = 45
  cashShine.Parent = buyButton

  -- Hover effect for cash button
  buyButton.MouseEnter:Connect(function()
    if cachedPlayerMoney >= supplyItem.price then
      buyButton.BackgroundColor3 = Color3.fromRGB(70, 220, 70)
    end
  end)
  buyButton.MouseLeave:Connect(function()
    local currentCanAfford = cachedPlayerMoney >= supplyItem.price
    buyButton.BackgroundColor3 = currentCanAfford and Color3.fromRGB(50, 180, 50)
      or Color3.fromRGB(80, 80, 80)
  end)

  -- Connect cash buy button
  buyButton.MouseButton1Click:Connect(function()
    if onTrapPurchaseCallback then
      onTrapPurchaseCallback(supplyItem.id)
    end
  end)

  -- Robux buy button (stacked below)
  local robuxButton = Instance.new("TextButton")
  robuxButton.Name = "RobuxButton"
  robuxButton.Size = UDim2.new(0, 85, 0, 38)
  robuxButton.Position = UDim2.new(1, -95, 0, 52)
  robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
  robuxButton.Text = ""
  robuxButton.BackgroundTransparency = 0
  robuxButton.ZIndex = 2
  robuxButton.Parent = card

  local robuxButtonCorner = Instance.new("UICorner")
  robuxButtonCorner.CornerRadius = UDim.new(0, 8)
  robuxButtonCorner.Parent = robuxButton

  -- UIStroke for premium button
  local robuxStroke = Instance.new("UIStroke")
  robuxStroke.Color = Color3.fromRGB(100, 200, 255)
  robuxStroke.Thickness = 2
  robuxStroke.Parent = robuxButton

  -- Gem icon
  local gemIcon = Instance.new("TextLabel")
  gemIcon.Name = "GemIcon"
  gemIcon.Size = UDim2.new(0, 24, 1, 0)
  gemIcon.Position = UDim2.new(0, 4, 0, 0)
  gemIcon.BackgroundTransparency = 1
  gemIcon.Text = "💎"
  gemIcon.TextSize = 18
  gemIcon.ZIndex = 3
  gemIcon.Parent = robuxButton

  local robuxPriceLabel = Instance.new("TextLabel")
  robuxPriceLabel.Name = "RobuxPriceLabel"
  robuxPriceLabel.Size = UDim2.new(1, -32, 1, 0)
  robuxPriceLabel.Position = UDim2.new(0, 28, 0, 0)
  robuxPriceLabel.BackgroundTransparency = 1
  robuxPriceLabel.Text = tostring(supplyItem.robuxPrice)
  robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxPriceLabel.TextStrokeTransparency = 0
  robuxPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  robuxPriceLabel.TextScaled = true
  robuxPriceLabel.Font = Enum.Font.GothamBold
  robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  robuxPriceLabel.ZIndex = 3
  robuxPriceLabel.Parent = robuxButton

  -- Shine effect for premium button
  local premiumShine = Instance.new("UIGradient")
  premiumShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
  })
  premiumShine.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.7),
    NumberSequenceKeypoint.new(0.3, 0.9),
    NumberSequenceKeypoint.new(1, 0.85),
  })
  premiumShine.Rotation = 45
  premiumShine.Parent = robuxButton

  -- Hover effect for premium button
  robuxButton.MouseEnter:Connect(function()
    robuxButton.BackgroundColor3 = Color3.fromRGB(30, 150, 255)
    robuxStroke.Color = Color3.fromRGB(150, 220, 255)
  end)
  robuxButton.MouseLeave:Connect(function()
    robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    robuxStroke.Color = Color3.fromRGB(100, 200, 255)
  end)

  -- Connect Robux button
  robuxButton.MouseButton1Click:Connect(function()
    if onRobuxPurchaseCallback then
      onRobuxPurchaseCallback("trap", supplyItem.id)
    end
  end)

  -- Store price on card for affordability updates
  card:SetAttribute("Price", supplyItem.price)

  -- Update affordability
  local function updateAffordability()
    local currentCanAfford = cachedPlayerMoney >= supplyItem.price
    buyButton.BackgroundColor3 = currentCanAfford and Color3.fromRGB(50, 180, 50)
      or Color3.fromRGB(80, 80, 80)
  end

  card.AttributeChanged:Connect(function(attributeName)
    if attributeName == "PlayerMoney" then
      updateAffordability()
    end
  end)

  return card
end

-- Weapon tier colors for UI display
local WEAPON_TIER_COLORS: { [string]: Color3 } = {
  Basic = Color3.fromRGB(180, 180, 180),
  Standard = Color3.fromRGB(50, 150, 255),
  Premium = Color3.fromRGB(255, 165, 0),
}

--[[
	Creates a weapon card for the store with themed styling.
	@param weaponItem Store.WeaponItem - The weapon item data
	@param parent Frame - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createWeaponCard(weaponItem: Store.WeaponItem, parent: Frame, index: number): Frame
  local card = Instance.new("Frame")
  card.Name = weaponItem.id
  card.Size = UDim2.new(1, 0, 0, 104) -- Full width, UIListLayout handles spacing
  card.LayoutOrder = index
  card.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Base for gradient
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Tier-based gradient background
  local gradientColors = TIER_GRADIENTS[weaponItem.tier] or TIER_GRADIENTS.Basic
  local cardGradient = Instance.new("UIGradient")
  cardGradient.Name = "TierGradient"
  cardGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, gradientColors.start),
    ColorSequenceKeypoint.new(1, gradientColors.endColor),
  })
  cardGradient.Rotation = 90
  cardGradient.Parent = card

  -- Card stroke for definition
  local cardStroke = Instance.new("UIStroke")
  cardStroke.Name = "CardStroke"
  cardStroke.Color = Color3.fromRGB(60, 40, 20)
  cardStroke.Thickness = 2
  cardStroke.Transparency = 0.3
  cardStroke.Parent = card

  -- Tier color bar on left (accent)
  local tierBar = Instance.new("Frame")
  tierBar.Name = "TierBar"
  tierBar.Size = UDim2.new(0, 4, 1, 0)
  tierBar.Position = UDim2.new(0, 0, 0, 0)
  tierBar.BackgroundColor3 = WEAPON_TIER_COLORS[weaponItem.tier] or Color3.fromRGB(128, 128, 128)
  tierBar.BorderSizePixel = 0
  tierBar.Parent = card

  local tierBarCorner = Instance.new("UICorner")
  tierBarCorner.CornerRadius = UDim.new(0, 4)
  tierBarCorner.Parent = tierBar

  -- Icon shadow for depth
  local iconShadow = Instance.new("TextLabel")
  iconShadow.Name = "IconShadow"
  iconShadow.Size = UDim2.new(0, 60, 0, 60)
  iconShadow.Position = UDim2.new(0, -7, 0.5, -27)
  iconShadow.BackgroundTransparency = 1
  iconShadow.Text = weaponItem.icon
  iconShadow.TextSize = 48
  iconShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
  iconShadow.TextTransparency = 0.6
  iconShadow.ZIndex = 2
  iconShadow.Parent = card

  -- Weapon icon (enlarged with pop-out)
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 60, 0, 60)
  iconLabel.Position = UDim2.new(0, -10, 0.5, -30)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = weaponItem.icon
  iconLabel.TextSize = 48
  iconLabel.ZIndex = 3
  iconLabel.Parent = card

  -- Weapon name (white with dark stroke)
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.35, -20, 0, 22)
  nameLabel.Position = UDim2.new(0, 55, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = weaponItem.displayName
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.FredokaOne -- Cartoony chunky font
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
  nameLabel.TextStrokeTransparency = 0
  nameLabel.Parent = card

  -- Subtext description (below name, describes weapon)
  local subtextLabel = Instance.new("TextLabel")
  subtextLabel.Name = "Subtext"
  subtextLabel.Size = UDim2.new(0.5, -20, 0, 14)
  subtextLabel.Position = UDim2.new(0, 55, 0, 30)
  subtextLabel.BackgroundTransparency = 1
  subtextLabel.Text = weaponItem.description
  subtextLabel.TextColor3 = Color3.fromRGB(80, 60, 40) -- Dark brown, slightly muted
  subtextLabel.TextScaled = true
  subtextLabel.Font = Enum.Font.GothamMedium
  subtextLabel.TextXAlignment = Enum.TextXAlignment.Left
  subtextLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  subtextLabel.TextStrokeTransparency = 0.5
  subtextLabel.TextTransparency = 0.15 -- Slightly faded for subordinate appearance
  subtextLabel.Parent = card

  -- Tier and damage label (dark for readability)
  local tierLabel = Instance.new("TextLabel")
  tierLabel.Name = "Tier"
  tierLabel.Size = UDim2.new(0.35, -20, 0, 16)
  tierLabel.Position = UDim2.new(0, 55, 0, 46)
  tierLabel.BackgroundTransparency = 1
  tierLabel.Text = weaponItem.tier .. " • " .. weaponItem.damage .. " DMG"
  tierLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  tierLabel.TextScaled = true
  tierLabel.Font = Enum.Font.GothamMedium -- Standard body font
  tierLabel.TextXAlignment = Enum.TextXAlignment.Left
  tierLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  tierLabel.TextStrokeTransparency = 0.7
  tierLabel.Parent = card

  -- Status label (owned/starter)
  local isOwned = cachedOwnedWeapons and cachedOwnedWeapons[weaponItem.id]
  local isFree = weaponItem.price == 0

  local statusLabel = Instance.new("TextLabel")
  statusLabel.Name = "Status"
  statusLabel.Size = UDim2.new(0.35, 0, 0, 16)
  statusLabel.Position = UDim2.new(0, 55, 0, 64)
  statusLabel.BackgroundTransparency = 1
  if isOwned then
    statusLabel.Text = "✓ OWNED"
    statusLabel.TextColor3 = Color3.fromRGB(20, 120, 20)
  elseif isFree then
    statusLabel.Text = "★ STARTER"
    statusLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
  else
    statusLabel.Text = ""
    statusLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
  end
  statusLabel.TextScaled = true
  statusLabel.Font = Enum.Font.GothamBold
  statusLabel.TextXAlignment = Enum.TextXAlignment.Left
  statusLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
  statusLabel.TextStrokeTransparency = 0.7
  statusLabel.Parent = card

  -- Buy buttons - only show for non-free, non-owned weapons
  if not isOwned and not isFree then
    local canAfford = cachedPlayerMoney >= weaponItem.price

    -- Cash buy button (stacked vertically)
    local buyButton = Instance.new("TextButton")
    buyButton.Name = "BuyButton"
    buyButton.Size = UDim2.new(0, 85, 0, 38)
    buyButton.Position = UDim2.new(1, -95, 0, 8)
    buyButton.BackgroundColor3 = canAfford and Color3.fromRGB(50, 180, 50)
      or Color3.fromRGB(80, 80, 80)
    buyButton.Text = ""
    buyButton.BackgroundTransparency = 0
    buyButton.ZIndex = 2
    buyButton.Parent = card

    local buyButtonCorner = Instance.new("UICorner")
    buyButtonCorner.CornerRadius = UDim.new(0, 8)
    buyButtonCorner.Parent = buyButton

    -- Cash button icon
    local cashIcon = Instance.new("TextLabel")
    cashIcon.Name = "CashIcon"
    cashIcon.Size = UDim2.new(0, 24, 1, 0)
    cashIcon.Position = UDim2.new(0, 4, 0, 0)
    cashIcon.BackgroundTransparency = 1
    cashIcon.Text = "💵"
    cashIcon.TextSize = 18
    cashIcon.ZIndex = 3
    cashIcon.Parent = buyButton

    local cashPriceLabel = Instance.new("TextLabel")
    cashPriceLabel.Name = "CashPriceLabel"
    cashPriceLabel.Size = UDim2.new(1, -32, 1, 0)
    cashPriceLabel.Position = UDim2.new(0, 28, 0, 0)
    cashPriceLabel.BackgroundTransparency = 1
    cashPriceLabel.Text = "$" .. tostring(weaponItem.price)
    cashPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    cashPriceLabel.TextStrokeTransparency = 0
    cashPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    cashPriceLabel.TextScaled = true
    cashPriceLabel.Font = Enum.Font.GothamBold
    cashPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
    cashPriceLabel.ZIndex = 3
    cashPriceLabel.Parent = buyButton

    -- Shine effect for cash button
    local cashShine = Instance.new("UIGradient")
    cashShine.Color = ColorSequence.new({
      ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
      ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
      ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
    })
    cashShine.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0.7),
      NumberSequenceKeypoint.new(0.3, 0.9),
      NumberSequenceKeypoint.new(1, 0.85),
    })
    cashShine.Rotation = 45
    cashShine.Parent = buyButton

    -- Hover effect for cash button
    buyButton.MouseEnter:Connect(function()
      if cachedPlayerMoney >= weaponItem.price then
        buyButton.BackgroundColor3 = Color3.fromRGB(70, 220, 70)
      end
    end)
    buyButton.MouseLeave:Connect(function()
      local currentCanAfford = cachedPlayerMoney >= weaponItem.price
      buyButton.BackgroundColor3 = currentCanAfford and Color3.fromRGB(50, 180, 50)
        or Color3.fromRGB(80, 80, 80)
    end)

    buyButton.MouseButton1Click:Connect(function()
      if onWeaponPurchaseCallback and cachedPlayerMoney >= weaponItem.price then
        onWeaponPurchaseCallback(weaponItem.id)
      end
    end)

    -- Robux button (stacked below)
    local robuxButton = Instance.new("TextButton")
    robuxButton.Name = "RobuxButton"
    robuxButton.Size = UDim2.new(0, 85, 0, 38)
    robuxButton.Position = UDim2.new(1, -95, 0, 52)
    robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    robuxButton.Text = ""
    robuxButton.BackgroundTransparency = 0
    robuxButton.ZIndex = 2
    robuxButton.Parent = card

    local robuxButtonCorner = Instance.new("UICorner")
    robuxButtonCorner.CornerRadius = UDim.new(0, 8)
    robuxButtonCorner.Parent = robuxButton

    -- UIStroke for premium button
    local robuxStroke = Instance.new("UIStroke")
    robuxStroke.Color = Color3.fromRGB(100, 200, 255)
    robuxStroke.Thickness = 2
    robuxStroke.Parent = robuxButton

    -- Gem icon
    local gemIcon = Instance.new("TextLabel")
    gemIcon.Name = "GemIcon"
    gemIcon.Size = UDim2.new(0, 24, 1, 0)
    gemIcon.Position = UDim2.new(0, 4, 0, 0)
    gemIcon.BackgroundTransparency = 1
    gemIcon.Text = "💎"
    gemIcon.TextSize = 18
    gemIcon.ZIndex = 3
    gemIcon.Parent = robuxButton

    local robuxPriceLabel = Instance.new("TextLabel")
    robuxPriceLabel.Name = "RobuxPriceLabel"
    robuxPriceLabel.Size = UDim2.new(1, -32, 1, 0)
    robuxPriceLabel.Position = UDim2.new(0, 28, 0, 0)
    robuxPriceLabel.BackgroundTransparency = 1
    robuxPriceLabel.Text = tostring(weaponItem.robuxPrice)
    robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    robuxPriceLabel.TextStrokeTransparency = 0
    robuxPriceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    robuxPriceLabel.TextScaled = true
    robuxPriceLabel.Font = Enum.Font.GothamBold
    robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
    robuxPriceLabel.ZIndex = 3
    robuxPriceLabel.Parent = robuxButton

    -- Shine effect for premium button
    local premiumShine = Instance.new("UIGradient")
    premiumShine.Color = ColorSequence.new({
      ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
      ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
      ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
    })
    premiumShine.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0.7),
      NumberSequenceKeypoint.new(0.3, 0.9),
      NumberSequenceKeypoint.new(1, 0.85),
    })
    premiumShine.Rotation = 45
    premiumShine.Parent = robuxButton

    -- Hover effect for premium button
    robuxButton.MouseEnter:Connect(function()
      robuxButton.BackgroundColor3 = Color3.fromRGB(30, 150, 255)
      robuxStroke.Color = Color3.fromRGB(150, 220, 255)
    end)
    robuxButton.MouseLeave:Connect(function()
      robuxButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
      robuxStroke.Color = Color3.fromRGB(100, 200, 255)
    end)

    robuxButton.MouseButton1Click:Connect(function()
      if onRobuxPurchaseCallback then
        onRobuxPurchaseCallback("weapon", weaponItem.id)
      end
    end)
  end

  return card
end

--[[
	Populates the scroll frame with items based on current tab.
]]
local function populateItems()
  if not scrollFrame then
    return
  end

  -- Clear existing items
  for _, child in ipairs(scrollFrame:GetChildren()) do
    if child:IsA("Frame") then
      child:Destroy()
    end
  end

  if currentTab == "eggs" then
    local availableEggs = Store.getAvailableEggsWithStock()
    for index, item in ipairs(availableEggs) do
      createItemCard(
        "egg",
        item.id,
        item.displayName,
        item.rarity,
        item.price,
        item.robuxPrice or 5,
        item.stock,
        scrollFrame,
        index
      )
    end
    scrollFrame.CanvasSize =
      UDim2.new(0, 0, 0, #availableEggs * 104 + math.max(0, #availableEggs - 1) * 8 + 20)
  elseif currentTab == "chickens" then
    local availableChickens = Store.getAvailableChickensWithStock()
    for index, item in ipairs(availableChickens) do
      createItemCard(
        "chicken",
        item.id,
        item.displayName,
        item.rarity,
        item.price,
        item.robuxPrice or 5,
        item.stock,
        scrollFrame,
        index
      )
    end
    scrollFrame.CanvasSize =
      UDim2.new(0, 0, 0, #availableChickens * 104 + math.max(0, #availableChickens - 1) * 8 + 20)
  elseif currentTab == "supplies" then
    local availableTraps = Store.getAvailableTraps()
    for index, item in ipairs(availableTraps) do
      createSupplyCard(item, scrollFrame, index)
    end
    scrollFrame.CanvasSize =
      UDim2.new(0, 0, 0, #availableTraps * 104 + math.max(0, #availableTraps - 1) * 8 + 20)
  elseif currentTab == "powerups" then
    local powerUps = PowerUpConfig.getAllSorted()
    for index, config in ipairs(powerUps) do
      createPowerUpCard(config.id, config, scrollFrame, index)
    end
    scrollFrame.CanvasSize =
      UDim2.new(0, 0, 0, #powerUps * 104 + math.max(0, #powerUps - 1) * 8 + 20)
  elseif currentTab == "weapons" then
    local availableWeapons = Store.getAvailableWeapons()
    for index, item in ipairs(availableWeapons) do
      createWeaponCard(item, scrollFrame, index)
    end
    scrollFrame.CanvasSize =
      UDim2.new(0, 0, 0, #availableWeapons * 104 + math.max(0, #availableWeapons - 1) * 8 + 20)
  end
end

--[[
	Updates tab button appearance based on current selection.
	Active tabs appear brighter, larger, and connected to content area.
	Inactive tabs are muted and smaller.
]]
local function updateTabAppearance(animate: boolean?)
  if not tabFrame then
    return
  end

  -- Tab configuration: tabName -> { activeColor, zIndex when active }
  local tabConfigs: { [string]: { activeColor: Color3, tabKey: string } } = {
    EggsTab = { activeColor = Color3.fromRGB(255, 220, 150), tabKey = "eggs" },
    ChickensTab = { activeColor = Color3.fromRGB(255, 220, 150), tabKey = "chickens" },
    SuppliesTab = { activeColor = Color3.fromRGB(255, 200, 130), tabKey = "supplies" },
    PowerupsTab = { activeColor = Color3.fromRGB(200, 230, 255), tabKey = "powerups" },
    WeaponsTab = { activeColor = Color3.fromRGB(255, 180, 180), tabKey = "weapons" },
  }

  -- Inactive tab styling
  local inactiveColor = Color3.fromRGB(180, 140, 90) -- Muted brown
  local inactiveSize = UDim2.new(0.2, -4, 0, 38)
  local inactivePosition = 4 -- Y offset from top

  -- Active tab styling (larger, connected to content)
  local activeSize = UDim2.new(0.2, -4, 0, 44) -- 6px taller
  local activePosition = 0 -- Flush with content area

  for tabName, config in pairs(tabConfigs) do
    local tab = tabFrame:FindFirstChild(tabName)
    if tab and tab:IsA("TextButton") then
      local isActive = currentTab == config.tabKey
      local iconLabel = tab:FindFirstChild("IconLabel")
      local tabStroke = tab:FindFirstChild("TabStroke")

      -- Target properties based on active state
      local targetColor = if isActive then config.activeColor else inactiveColor
      local targetSize = if isActive then activeSize else inactiveSize
      local targetPosY = if isActive then activePosition else inactivePosition
      local targetPosition = UDim2.new(tab.Position.X.Scale, tab.Position.X.Offset, 0, targetPosY)
      local targetZIndex = if isActive then 5 else 3
      local targetIconTransparency = if isActive then 0 else 0.2
      local targetIconZIndex = if isActive then 6 else 4
      local targetStrokeColor = if isActive
        then Color3.fromRGB(80, 50, 25)
        else Color3.fromRGB(101, 67, 33)
      local targetStrokeThickness = if isActive then 3 else 2

      if animate then
        -- Animate tab properties with tweens
        local tabTween = TweenService:Create(tab, TAB_TWEEN_INFO, {
          BackgroundColor3 = targetColor,
          Size = targetSize,
          Position = targetPosition,
        })
        tabTween:Play()

        -- ZIndex doesn't tween, set immediately for active, delay for inactive
        if isActive then
          tab.ZIndex = targetZIndex
        else
          task.delay(TAB_ANIMATION_DURATION, function()
            tab.ZIndex = targetZIndex
          end)
        end

        if iconLabel and iconLabel:IsA("TextLabel") then
          local iconTween = TweenService:Create(iconLabel, TAB_TWEEN_INFO, {
            TextTransparency = targetIconTransparency,
          })
          iconTween:Play()
          if isActive then
            iconLabel.ZIndex = targetIconZIndex
          else
            task.delay(TAB_ANIMATION_DURATION, function()
              iconLabel.ZIndex = targetIconZIndex
            end)
          end
        end

        if tabStroke and tabStroke:IsA("UIStroke") then
          local strokeTween = TweenService:Create(tabStroke, TAB_TWEEN_INFO, {
            Color = targetStrokeColor,
            Thickness = targetStrokeThickness,
          })
          strokeTween:Play()
        end
      else
        -- Instant property changes (no animation)
        tab.BackgroundColor3 = targetColor
        tab.Size = targetSize
        tab.Position = targetPosition
        tab.ZIndex = targetZIndex

        if iconLabel and iconLabel:IsA("TextLabel") then
          iconLabel.TextTransparency = targetIconTransparency
          iconLabel.ZIndex = targetIconZIndex
        end

        if tabStroke and tabStroke:IsA("UIStroke") then
          tabStroke.Color = targetStrokeColor
          tabStroke.Thickness = targetStrokeThickness
        end
      end
    end
  end
end

--[[
	Fades scroll content out, populates new items, then fades back in.
	Used for animated tab switching.
]]
local function animateContentTransition()
  if not scrollFrame then
    return
  end

  -- Fade out all current item cards
  local fadeOutTweens = {}
  for _, child in ipairs(scrollFrame:GetChildren()) do
    if child:IsA("Frame") then
      local tween = TweenService:Create(child, CONTENT_FADE_INFO, {
        BackgroundTransparency = 1,
      })
      tween:Play()
      table.insert(fadeOutTweens, tween)

      -- Also fade out all descendant elements
      for _, descendant in ipairs(child:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
          local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
            TextTransparency = 1,
            BackgroundTransparency = 1,
          })
          descTween:Play()
        elseif descendant:IsA("Frame") or descendant:IsA("ImageLabel") then
          local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
            BackgroundTransparency = 1,
          })
          descTween:Play()
        end
      end
    end
  end

  -- Wait for fade out to complete, then populate new items
  task.delay(CONTENT_FADE_DURATION, function()
    populateItems()

    -- Fade in new content
    if scrollFrame then
      for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") then
          -- Start transparent
          child.BackgroundTransparency = 1
          for _, descendant in ipairs(child:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
              descendant.TextTransparency = 1
              descendant.BackgroundTransparency = 1
            elseif descendant:IsA("Frame") or descendant:IsA("ImageLabel") then
              descendant.BackgroundTransparency = 1
            end
          end

          -- Tween to visible
          local tween = TweenService:Create(child, CONTENT_FADE_INFO, {
            BackgroundTransparency = 0,
          })
          tween:Play()

          for _, descendant in ipairs(child:GetDescendants()) do
            if descendant:IsA("TextLabel") then
              local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
                TextTransparency = 0,
                BackgroundTransparency = 1, -- Labels typically have transparent background
              })
              descTween:Play()
            elseif descendant:IsA("TextButton") then
              local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
                TextTransparency = 0,
                BackgroundTransparency = 0,
              })
              descTween:Play()
            elseif descendant:IsA("Frame") then
              local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
                BackgroundTransparency = 0,
              })
              descTween:Play()
            elseif descendant:IsA("ImageLabel") then
              local descTween = TweenService:Create(descendant, CONTENT_FADE_INFO, {
                BackgroundTransparency = 1, -- ImageLabels often have transparent background
              })
              descTween:Play()
            end
          end
        end
      end
    end

    isTabSwitching = false
  end)
end

--[[
	Switches to the specified tab.
	@param tab "eggs" | "chickens" | "supplies" | "powerups" | "weapons" - The tab to switch to
]]
local function switchTab(tab: "eggs" | "chickens" | "supplies" | "powerups" | "weapons")
  -- Guard against switching to same tab or during animation
  if currentTab == tab or isTabSwitching then
    return
  end

  isTabSwitching = true
  currentTab = tab

  -- Animate tab appearance change
  updateTabAppearance(true)

  -- Animate content transition (fade out, repopulate, fade in)
  animateContentTransition()
end

--[[
	Creates the store UI structure.
	Called once when the client loads.
]]
function StoreUI.create()
  if screenGui then
    return
  end

  screenGui = Instance.new("ScreenGui")
  screenGui.Name = "StoreUI"
  screenGui.ResetOnSpawn = false
  screenGui.Enabled = false
  screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

  -- Main frame (centered panel) - "The Supply Shack" wooden theme
  mainFrame = Instance.new("Frame")
  mainFrame.Name = "MainFrame"
  mainFrame.AnchorPoint = Vector2.new(0.5, 0.5) -- Center anchor for scale animation
  mainFrame.Size = UDim2.new(0, 420, 0, 550)
  mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0) -- Centered with anchor point
  mainFrame.BackgroundColor3 = Color3.fromRGB(255, 248, 220) -- Warm off-white/cream
  mainFrame.BorderSizePixel = 0
  mainFrame.Parent = screenGui

  local mainCorner = Instance.new("UICorner")
  mainCorner.CornerRadius = UDim.new(0, 20) -- Bubbly rounded corners
  mainCorner.Parent = mainFrame

  -- Wood border effect
  local mainStroke = Instance.new("UIStroke")
  mainStroke.Color = Color3.fromRGB(101, 67, 33) -- Dark brown wood
  mainStroke.Thickness = 4
  mainStroke.Parent = mainFrame

  -- Title bar - wooden header
  local titleBar = Instance.new("Frame")
  titleBar.Name = "TitleBar"
  titleBar.Size = UDim2.new(1, 0, 0, 45)
  titleBar.BackgroundColor3 = Color3.fromRGB(139, 90, 43) -- Medium brown wood
  titleBar.BorderSizePixel = 0
  titleBar.Parent = mainFrame

  local titleCorner = Instance.new("UICorner")
  titleCorner.CornerRadius = UDim.new(0, 20) -- Match main frame corners
  titleCorner.Parent = titleBar

  -- Wooden sign border stroke
  local titleStroke = Instance.new("UIStroke")
  titleStroke.Color = Color3.fromRGB(80, 50, 25) -- Darker brown for sign border
  titleStroke.Thickness = 3
  titleStroke.Parent = titleBar

  -- Fix bottom corners of title bar
  local titleCornerFix = Instance.new("Frame")
  titleCornerFix.Name = "CornerFix"
  titleCornerFix.Size = UDim2.new(1, 0, 0, 20)
  titleCornerFix.Position = UDim2.new(0, 0, 1, -20)
  titleCornerFix.BackgroundColor3 = Color3.fromRGB(139, 90, 43) -- Match header
  titleCornerFix.BorderSizePixel = 0
  titleCornerFix.Parent = titleBar

  -- Title text - wooden sign style with cartoony font and text stroke
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "Title"
  titleLabel.Size = UDim2.new(1, -50, 1, 0)
  titleLabel.Position = UDim2.new(0, 15, 0, 0)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "🐔 The Roost"
  titleLabel.TextColor3 = Color3.fromRGB(255, 248, 220) -- Warm cream to match frame
  titleLabel.TextScaled = true
  titleLabel.Font = Enum.Font.FredokaOne -- Cartoony chunky font
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.TextStrokeColor3 = Color3.fromRGB(60, 30, 10) -- Dark brown stroke
  titleLabel.TextStrokeTransparency = 0 -- Fully visible stroke
  titleLabel.Parent = titleBar

  -- Close button (red wooden square with white painted X)
  local closeButton = Instance.new("TextButton")
  closeButton.Name = "CloseButton"
  closeButton.Size = UDim2.new(0, 35, 0, 35)
  closeButton.Position = UDim2.new(1, -40, 0, 5)
  closeButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Red wood color
  closeButton.Text = "X"
  closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  closeButton.TextScaled = true
  closeButton.Font = Enum.Font.FredokaOne -- Cartoony font for X
  closeButton.TextStrokeColor3 = Color3.fromRGB(80, 20, 20) -- Dark red stroke
  closeButton.TextStrokeTransparency = 0 -- Fully visible stroke
  closeButton.Parent = titleBar

  local closeCorner = Instance.new("UICorner")
  closeCorner.CornerRadius = UDim.new(0, 6) -- Slight rounding for wooden look
  closeCorner.Parent = closeButton

  -- UIStroke for depth (darker red border)
  local closeStroke = Instance.new("UIStroke")
  closeStroke.Color = Color3.fromRGB(120, 30, 30) -- Darker red for depth
  closeStroke.Thickness = 2
  closeStroke.Parent = closeButton

  -- Store original colors for hover effect
  local closeDefaultBg = Color3.fromRGB(180, 50, 50)
  local closeHoverBg = Color3.fromRGB(220, 70, 70) -- Brighter red on hover
  local closeDefaultStroke = Color3.fromRGB(120, 30, 30)
  local closeHoverStroke = Color3.fromRGB(160, 50, 50)

  -- Hover effect: slightly brighter red on MouseEnter
  closeButton.MouseEnter:Connect(function()
    closeButton.BackgroundColor3 = closeHoverBg
    closeStroke.Color = closeHoverStroke
  end)

  closeButton.MouseLeave:Connect(function()
    closeButton.BackgroundColor3 = closeDefaultBg
    closeStroke.Color = closeDefaultStroke
  end)

  closeButton.MouseButton1Click:Connect(function()
    StoreUI.close()
  end)

  -- Restock timer frame (balance removed - shown in main HUD)
  local restockFrame = Instance.new("Frame")
  restockFrame.Name = "RestockFrame"
  restockFrame.Size = UDim2.new(1, -20, 0, 35)
  restockFrame.Position = UDim2.new(0, 10, 0, 50)
  restockFrame.BackgroundColor3 = Color3.fromRGB(255, 100, 50) -- Orange-red base for urgency
  restockFrame.BorderSizePixel = 0
  restockFrame.Parent = mainFrame

  local restockCorner = Instance.new("UICorner")
  restockCorner.CornerRadius = UDim.new(0, 8)
  restockCorner.Parent = restockFrame

  -- Urgency gradient (Red to Orange) for restock timer
  local restockGradient = Instance.new("UIGradient")
  restockGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 60, 60)), -- Red on left
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 50)), -- Orange on right
  })
  restockGradient.Rotation = 0 -- Horizontal gradient
  restockGradient.Parent = restockFrame

  -- Restock timer display
  restockTimerLabel = Instance.new("TextLabel")
  restockTimerLabel.Name = "RestockTimerLabel"
  restockTimerLabel.Size = UDim2.new(1, -10, 1, 0)
  restockTimerLabel.Position = UDim2.new(0, 5, 0, 0)
  restockTimerLabel.BackgroundTransparency = 1
  restockTimerLabel.Text = "Restocks in 0:00"
  restockTimerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White text for contrast
  restockTimerLabel.TextScaled = true
  restockTimerLabel.Font = Enum.Font.GothamBold
  restockTimerLabel.TextXAlignment = Enum.TextXAlignment.Center
  restockTimerLabel.TextStrokeColor3 = Color3.fromRGB(80, 20, 10) -- Dark red stroke
  restockTimerLabel.TextStrokeTransparency = 0.3 -- Visible stroke for readability
  restockTimerLabel.Parent = restockFrame

  -- Initialize timer display
  updateRestockTimer()

  -- Tab frame for Eggs/Chickens/Supplies/Power-ups/Weapons tabs (hanging folder tabs)
  tabFrame = Instance.new("Frame")
  tabFrame.Name = "TabFrame"
  tabFrame.Size = UDim2.new(1, -20, 0, 42) -- Slightly taller for folder tab effect
  tabFrame.Position = UDim2.new(0, 10, 0, 85) -- Positioned to overlap scroll frame top
  tabFrame.BackgroundTransparency = 1
  tabFrame.ZIndex = 3 -- Above scroll frame
  tabFrame.Parent = mainFrame

  -- Helper to create folder-style tab with icon shadow and rotation
  local function createFolderTab(
    name: string,
    icon: string,
    positionX: number,
    tabName: "eggs" | "chickens" | "supplies" | "powerups" | "weapons",
    rotation: number
  ): TextButton
    local tab = Instance.new("TextButton")
    tab.Name = name
    tab.Size = UDim2.new(0.2, -4, 0, 38) -- Default inactive size
    tab.Position = UDim2.new(positionX, 2, 0, 4) -- Slightly raised inactive position
    tab.BackgroundColor3 = Color3.fromRGB(180, 140, 90) -- Inactive: muted brown
    tab.Text = ""
    tab.AutoButtonColor = false
    tab.ZIndex = 3
    tab.Parent = tabFrame

    -- Folder tab corner (rounded top only effect via larger radius)
    local tabCorner = Instance.new("UICorner")
    tabCorner.Name = "TabCorner"
    tabCorner.CornerRadius = UDim.new(0, 10)
    tabCorner.Parent = tab

    -- Border stroke for depth
    local tabStroke = Instance.new("UIStroke")
    tabStroke.Name = "TabStroke"
    tabStroke.Color = Color3.fromRGB(101, 67, 33) -- Dark brown wood border
    tabStroke.Thickness = 2
    tabStroke.Parent = tab

    -- Icon shadow for drop shadow effect
    local iconShadow = Instance.new("TextLabel")
    iconShadow.Name = "IconShadow"
    iconShadow.Size = UDim2.new(1, 0, 1, 0)
    iconShadow.Position = UDim2.new(0, 2, 0, 2) -- Offset for shadow effect
    iconShadow.BackgroundTransparency = 1
    iconShadow.Text = icon
    iconShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    iconShadow.TextTransparency = 0.6
    iconShadow.TextScaled = true
    iconShadow.Font = Enum.Font.GothamBold
    iconShadow.Rotation = rotation -- Slight tilt for dynamic feel
    iconShadow.ZIndex = 3
    iconShadow.Parent = tab

    -- Main icon label
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Name = "IconLabel"
    iconLabel.Size = UDim2.new(1, 0, 1, 0)
    iconLabel.Position = UDim2.new(0, 0, 0, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = icon
    iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconLabel.TextScaled = true
    iconLabel.Font = Enum.Font.GothamBold
    iconLabel.Rotation = rotation -- Slight tilt for dynamic feel
    iconLabel.ZIndex = 4
    iconLabel.Parent = tab

    -- Text stroke for icon pop
    iconLabel.TextStrokeColor3 = Color3.fromRGB(60, 30, 10)
    iconLabel.TextStrokeTransparency = 0.3

    tab.MouseButton1Click:Connect(function()
      switchTab(tabName)
    end)

    return tab
  end

  -- Create folder tabs with slight icon rotations for dynamic feel
  createFolderTab("EggsTab", "🥚", 0, "eggs", -2)
  createFolderTab("ChickensTab", "🐔", 0.2, "chickens", 2)
  createFolderTab("SuppliesTab", "🪤", 0.4, "supplies", -1)
  createFolderTab("PowerupsTab", "⚡", 0.6, "powerups", 2)
  createFolderTab("WeaponsTab", "⚔️", 0.8, "weapons", -2)

  -- Set initial tab appearance (eggs is active by default, no animation)
  updateTabAppearance(false)

  -- Scroll frame for items
  scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "ItemsScroll"
  scrollFrame.Size = UDim2.new(1, -20, 1, -195) -- Reduced height to make room for replenish button
  scrollFrame.Position = UDim2.new(0, 10, 0, 130)
  scrollFrame.BackgroundTransparency = 1
  scrollFrame.ScrollBarThickness = 6
  scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(139, 90, 43) -- Brown to match theme
  scrollFrame.Parent = mainFrame

  -- Add UIPadding for consistent spacing from edges
  local scrollPadding = Instance.new("UIPadding")
  scrollPadding.PaddingLeft = UDim.new(0, 10)
  scrollPadding.PaddingRight = UDim.new(0, 10)
  scrollPadding.PaddingTop = UDim.new(0, 10)
  scrollPadding.PaddingBottom = UDim.new(0, 10)
  scrollPadding.Parent = scrollFrame

  -- Add UIListLayout for consistent spacing between cards
  local scrollListLayout = Instance.new("UIListLayout")
  scrollListLayout.Padding = UDim.new(0, 8)
  scrollListLayout.SortOrder = Enum.SortOrder.LayoutOrder
  scrollListLayout.FillDirection = Enum.FillDirection.Vertical
  scrollListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  scrollListLayout.Parent = scrollFrame

  -- Replenish Now button (Robux purchase) - Gold "Restock Now" themed button
  replenishButton = Instance.new("TextButton")
  replenishButton.Name = "ReplenishButton"
  replenishButton.Size = UDim2.new(1, -20, 0, 40)
  replenishButton.Position = UDim2.new(0, 10, 1, -50)
  replenishButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold color
  replenishButton.Text = "⚡ Restock Now! - R$" .. tostring(ROBUX_REPLENISH_PRICE)
  replenishButton.TextColor3 = Color3.fromRGB(80, 50, 0) -- Dark brown for contrast
  replenishButton.TextScaled = true
  replenishButton.Font = Enum.Font.FredokaOne
  replenishButton.TextStrokeColor3 = Color3.fromRGB(255, 255, 255) -- White stroke
  replenishButton.TextStrokeTransparency = 0.2 -- Visible stroke for pop effect
  replenishButton.Parent = mainFrame

  local replenishCorner = Instance.new("UICorner")
  replenishCorner.CornerRadius = UDim.new(0, 8)
  replenishCorner.Parent = replenishButton

  -- UIStroke for button definition (dark gold/orange border)
  local replenishStroke = Instance.new("UIStroke")
  replenishStroke.Color = Color3.fromRGB(200, 150, 0) -- Dark gold
  replenishStroke.Thickness = 2
  replenishStroke.Parent = replenishButton

  -- UIGradient for metallic shine effect (light gold to gold)
  local replenishGradient = Instance.new("UIGradient")
  replenishGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)), -- Light gold at top
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 215, 0)), -- Gold in middle
    ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 180, 0)), -- Darker gold at bottom
  })
  replenishGradient.Rotation = 90 -- Vertical gradient
  replenishGradient.Parent = replenishButton

  -- Hover effect for replenish button
  local defaultGoldColor = Color3.fromRGB(255, 215, 0)
  local hoverGoldColor = Color3.fromRGB(255, 235, 100) -- Brighter gold on hover
  local defaultStrokeColor = Color3.fromRGB(200, 150, 0)
  local hoverStrokeColor = Color3.fromRGB(255, 200, 50) -- Brighter stroke on hover

  replenishButton.MouseEnter:Connect(function()
    replenishButton.BackgroundColor3 = hoverGoldColor
    replenishStroke.Color = hoverStrokeColor
  end)

  replenishButton.MouseLeave:Connect(function()
    replenishButton.BackgroundColor3 = defaultGoldColor
    replenishStroke.Color = defaultStrokeColor
  end)

  -- Confirmation dialog (hidden by default)
  confirmationFrame = Instance.new("Frame")
  confirmationFrame.Name = "ConfirmationFrame"
  confirmationFrame.Size = UDim2.new(0, 300, 0, 150)
  confirmationFrame.Position = UDim2.new(0.5, -150, 0.5, -75)
  confirmationFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
  confirmationFrame.BorderSizePixel = 0
  confirmationFrame.Visible = false
  confirmationFrame.ZIndex = 10
  confirmationFrame.Parent = screenGui

  local confirmCorner = Instance.new("UICorner")
  confirmCorner.CornerRadius = UDim.new(0, 12)
  confirmCorner.Parent = confirmationFrame

  -- Confirmation title
  local confirmTitle = Instance.new("TextLabel")
  confirmTitle.Name = "Title"
  confirmTitle.Size = UDim2.new(1, 0, 0, 35)
  confirmTitle.Position = UDim2.new(0, 0, 0, 10)
  confirmTitle.BackgroundTransparency = 1
  confirmTitle.Text = "Confirm Purchase"
  confirmTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
  confirmTitle.TextScaled = true
  confirmTitle.Font = Enum.Font.GothamBold
  confirmTitle.ZIndex = 11
  confirmTitle.Parent = confirmationFrame

  -- Confirmation message
  local confirmMessage = Instance.new("TextLabel")
  confirmMessage.Name = "Message"
  confirmMessage.Size = UDim2.new(1, -20, 0, 40)
  confirmMessage.Position = UDim2.new(0, 10, 0, 45)
  confirmMessage.BackgroundTransparency = 1
  confirmMessage.Text = "Instantly replenish store stock for R$"
    .. tostring(ROBUX_REPLENISH_PRICE)
    .. "?"
  confirmMessage.TextColor3 = Color3.fromRGB(200, 200, 200)
  confirmMessage.TextScaled = true
  confirmMessage.Font = Enum.Font.Gotham
  confirmMessage.TextWrapped = true
  confirmMessage.ZIndex = 11
  confirmMessage.Parent = confirmationFrame

  -- Confirm button
  local confirmButton = Instance.new("TextButton")
  confirmButton.Name = "ConfirmButton"
  confirmButton.Size = UDim2.new(0, 100, 0, 35)
  confirmButton.Position = UDim2.new(0.5, -110, 1, -50)
  confirmButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
  confirmButton.Text = "Confirm"
  confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  confirmButton.TextScaled = true
  confirmButton.Font = Enum.Font.GothamBold
  confirmButton.ZIndex = 11
  confirmButton.Parent = confirmationFrame

  local confirmBtnCorner = Instance.new("UICorner")
  confirmBtnCorner.CornerRadius = UDim.new(0, 6)
  confirmBtnCorner.Parent = confirmButton

  -- Cancel button
  local cancelButton = Instance.new("TextButton")
  cancelButton.Name = "CancelButton"
  cancelButton.Size = UDim2.new(0, 100, 0, 35)
  cancelButton.Position = UDim2.new(0.5, 10, 1, -50)
  cancelButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
  cancelButton.Text = "Cancel"
  cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  cancelButton.TextScaled = true
  cancelButton.Font = Enum.Font.GothamBold
  cancelButton.ZIndex = 11
  cancelButton.Parent = confirmationFrame

  local cancelBtnCorner = Instance.new("UICorner")
  cancelBtnCorner.CornerRadius = UDim.new(0, 6)
  cancelBtnCorner.Parent = cancelButton

  -- Replenish button opens confirmation
  replenishButton.MouseButton1Click:Connect(function()
    if confirmationFrame then
      confirmationFrame.Visible = true
    end
  end)

  -- Confirm button triggers replenish
  confirmButton.MouseButton1Click:Connect(function()
    if confirmationFrame then
      confirmationFrame.Visible = false
    end
    if onReplenishCallback then
      onReplenishCallback()
    end
  end)

  -- Cancel button closes confirmation
  cancelButton.MouseButton1Click:Connect(function()
    if confirmationFrame then
      confirmationFrame.Visible = false
    end
  end)

  -- Populate with eggs by default
  populateItems()

  -- Escape key to close
  UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
      return
    end
    if input.KeyCode == Enum.KeyCode.Escape and isOpen then
      StoreUI.close()
    end
  end)

  print("[StoreUI] Created with tabs")
end

--[[
	Opens the store UI with animation.
]]
function StoreUI.open()
  if not screenGui or not mainFrame then
    return
  end
  if isAnimating or isOpen then
    return
  end

  isAnimating = true
  isOpen = true

  -- Set initial state for animation
  mainFrame.Size = CLOSED_SIZE
  screenGui.Enabled = true

  -- Animate scale in with Back easing for bouncy feel
  local tween = TweenService:Create(mainFrame, OPEN_TWEEN_INFO, {
    Size = TARGET_SIZE,
  })
  tween:Play()
  tween.Completed:Connect(function()
    isAnimating = false
  end)

  -- Start timer update loop (updates every second, not every frame)
  updateRestockTimer()
  if timerConnection then
    timerConnection:Disconnect()
  end
  local lastUpdate = 0
  timerConnection = RunService.Heartbeat:Connect(function(deltaTime)
    lastUpdate = lastUpdate + deltaTime
    if lastUpdate >= 1 then
      lastUpdate = 0
      updateRestockTimer()
    end
  end)

  print("[StoreUI] Opened")
end

--[[
	Closes the store UI with animation.
]]
function StoreUI.close()
  if not screenGui or not mainFrame then
    return
  end
  if isAnimating or not isOpen then
    return
  end

  isAnimating = true
  isOpen = false

  -- Stop timer update loop
  if timerConnection then
    timerConnection:Disconnect()
    timerConnection = nil
  end

  -- Animate scale out with Back easing
  local tween = TweenService:Create(mainFrame, CLOSE_TWEEN_INFO, {
    Size = CLOSED_SIZE,
  })
  tween:Play()
  tween.Completed:Connect(function()
    screenGui.Enabled = false
    isAnimating = false
  end)

  print("[StoreUI] Closed")
end

--[[
	Toggles the store UI open/closed.
]]
function StoreUI.toggle()
  if isAnimating then
    return
  end
  if isOpen then
    StoreUI.close()
  else
    StoreUI.open()
  end
end

--[[
	Returns whether the store UI is currently open.
	@return boolean
]]
function StoreUI.isOpen(): boolean
  return isOpen
end

--[[
	Updates the cached player money and affordability indicators.
	@param money number - The player's current money balance
]]
function StoreUI.updateMoney(money: number)
  cachedPlayerMoney = money

  if not mainFrame then
    return
  end

  -- Update affordability of all cards
  if scrollFrame then
    for _, child in ipairs(scrollFrame:GetChildren()) do
      if child:IsA("Frame") then
        child:SetAttribute("PlayerMoney", money)
      end
    end
  end
end

--[[
	Sets the callback for when an egg purchase is attempted.
	@param callback function - Function to call with (eggType, quantity)
]]
function StoreUI.onPurchase(callback: (eggType: string, quantity: number) -> any)
  onEggPurchaseCallback = callback
end

--[[
	Sets the callback for when a chicken purchase is attempted.
	@param callback function - Function to call with (chickenType, quantity)
]]
function StoreUI.onChickenPurchase(callback: (chickenType: string, quantity: number) -> any)
  onChickenPurchaseCallback = callback
end

--[[
	Sets the callback for when Robux replenish is attempted.
	@param callback function - Function to call when replenish is confirmed
]]
function StoreUI.onReplenish(callback: () -> any)
  onReplenishCallback = callback
end

--[[
	Sets the callback for when Robux item purchase is attempted.
	@param callback function - Function to call with (itemType, itemId)
]]
function StoreUI.onRobuxPurchase(callback: (itemType: string, itemId: string) -> any)
  onRobuxPurchaseCallback = callback
end

--[[
	Sets the callback for when a power-up purchase is attempted.
	@param callback function - Function to call with (powerUpId)
]]
function StoreUI.onPowerUpPurchase(callback: (powerUpId: string) -> any)
  onPowerUpPurchaseCallback = callback
end

--[[
	Sets the callback for when a trap/supply purchase is attempted.
	@param callback function - Function to call with (trapType)
]]
function StoreUI.onTrapPurchase(callback: (trapType: string) -> any)
  onTrapPurchaseCallback = callback
end

--[[
	Registers a callback for weapon purchase events.
	@param callback function(weaponType: string) - Called when player clicks buy on a weapon
]]
function StoreUI.onWeaponPurchase(callback: (weaponType: string) -> any)
  onWeaponPurchaseCallback = callback
end

--[[
	Returns the current tab.
	@return "eggs" | "chickens" | "supplies" | "powerups" | "weapons"
]]
function StoreUI.getCurrentTab(): string
  return currentTab
end

--[[
	Refreshes the store inventory display.
	Call this when inventory changes (e.g., after purchase or replenish).
]]
function StoreUI.refreshInventory()
  if isOpen then
    populateItems()
  end
end

--[[
	Updates the cached owned weapons for display.
	@param ownedWeapons table - List of weapon type strings the player owns
]]
function StoreUI.updateOwnedWeapons(ownedWeapons: { string }?)
  cachedOwnedWeapons = {}
  if ownedWeapons then
    for _, weaponType in ipairs(ownedWeapons) do
      cachedOwnedWeapons[weaponType] = true
    end
  end
  -- Refresh display if on weapons tab
  if isOpen and currentTab == "weapons" then
    populateItems()
  end
end

--[[
	Updates the cached active power-ups for display.
	@param activePowerUps table - Map of power-up type to expires at time
]]
function StoreUI.updateActivePowerUps(activePowerUps: { [string]: number }?)
  cachedActivePowerUps = activePowerUps
  -- Refresh display if on power-ups tab
  if isOpen and currentTab == "powerups" then
    populateItems()
  end
end

--[[
	Updates the stock display for a specific item.
	@param itemType "egg" | "chicken" - The type of item
	@param itemId string - The item identifier
	@param newStock number - The new stock count
]]
function StoreUI.updateItemStock(itemType: string, itemId: string, newStock: number)
  if not scrollFrame then
    return
  end

  -- Only update if we're on the matching tab
  if
    (itemType == "egg" and currentTab ~= "eggs")
    or (itemType == "chicken" and currentTab ~= "chickens")
  then
    return
  end

  local card = scrollFrame:FindFirstChild(itemId)
  if card and card:IsA("Frame") then
    card:SetAttribute("Stock", newStock)

    -- Update stock label
    local stockLabel = card:FindFirstChild("StockLabel")
    if stockLabel and stockLabel:IsA("TextLabel") then
      stockLabel.Text = newStock > 0 and ("x" .. tostring(newStock)) or "SOLD OUT"
      stockLabel.TextColor3 = newStock > 0 and Color3.fromRGB(150, 150, 150)
        or Color3.fromRGB(255, 80, 80)
    end
  end
end

return StoreUI
