--[[
	StoreUI Module
	Implements the store UI where players can browse and purchase eggs and chickens.
	Opens when player interacts with the central store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
  index: number
): Frame
  local card = Instance.new("Frame")
  card.Name = itemId
  card.Size = UDim2.new(1, -10, 0, 80)
  card.Position = UDim2.new(0, 5, 0, (index - 1) * 85 + 5)
  card.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Rarity indicator bar
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

  -- Item icon
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 30, 0, 30)
  iconLabel.Position = UDim2.new(0, 12, 0.5, -15)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = itemType == "egg" and "🥚" or "🐔"
  iconLabel.TextSize = 24
  iconLabel.Parent = card

  -- Item name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.35, -20, 0, 25)
  nameLabel.Position = UDim2.new(0, 45, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = displayName
  nameLabel.TextColor3 = RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.Parent = card

  -- Rarity label
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "Rarity"
  rarityLabel.Size = UDim2.new(0.35, -20, 0, 18)
  rarityLabel.Position = UDim2.new(0, 45, 0, 33)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.Text = rarity
  rarityLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
  rarityLabel.TextScaled = true
  rarityLabel.Font = Enum.Font.Gotham
  rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
  rarityLabel.Parent = card

  -- Stock label
  local stockLabel = Instance.new("TextLabel")
  stockLabel.Name = "StockLabel"
  stockLabel.Size = UDim2.new(0, 50, 0, 18)
  stockLabel.Position = UDim2.new(0, 45, 0, 53)
  stockLabel.BackgroundTransparency = 1
  stockLabel.Text = stock > 0 and ("x" .. tostring(stock)) or "SOLD OUT"
  stockLabel.TextColor3 = stock > 0 and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 80, 80)
  stockLabel.TextScaled = true
  stockLabel.Font = Enum.Font.Gotham
  stockLabel.TextXAlignment = Enum.TextXAlignment.Left
  stockLabel.Parent = card

  -- Buy button (with in-game money) - shows price directly on button
  local isSoldOut = stock <= 0
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 80, 0, 30)
  buyButton.Position = UDim2.new(1, -165, 0.5, -15)
  buyButton.BackgroundColor3 = isSoldOut and Color3.fromRGB(80, 80, 80)
    or Color3.fromRGB(50, 180, 50)
  buyButton.Text = isSoldOut and "SOLD OUT" or ("$" .. tostring(price))
  buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  buyButton.TextTransparency = isSoldOut and 0.5 or 0
  buyButton.TextScaled = true
  buyButton.Font = Enum.Font.GothamBold
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 6)
  buyButtonCorner.Parent = buyButton

  -- Robux buy button (always available for Robux purchase)
  local robuxButton = Instance.new("TextButton")
  robuxButton.Name = "RobuxButton"
  robuxButton.Size = UDim2.new(0, 80, 0, 30)
  robuxButton.Position = UDim2.new(1, -80, 0.5, -15)
  robuxButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255) -- Robux blue
  robuxButton.Text = "" -- Text handled by child labels
  robuxButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxButton.TextScaled = true
  robuxButton.Font = Enum.Font.GothamBold
  robuxButton.Parent = card

  local robuxButtonCorner = Instance.new("UICorner")
  robuxButtonCorner.CornerRadius = UDim.new(0, 6)
  robuxButtonCorner.Parent = robuxButton

  -- Robux icon (using Roblox's official Robux icon)
  local robuxIcon = Instance.new("ImageLabel")
  robuxIcon.Name = "RobuxIcon"
  robuxIcon.Size = UDim2.new(0, 16, 0, 16)
  robuxIcon.Position = UDim2.new(0, 8, 0.5, -8)
  robuxIcon.BackgroundTransparency = 1
  robuxIcon.Image = "rbxassetid://4915439044" -- Robux icon asset
  robuxIcon.Parent = robuxButton

  -- Robux price text
  local robuxPriceLabel = Instance.new("TextLabel")
  robuxPriceLabel.Name = "RobuxPriceLabel"
  robuxPriceLabel.Size = UDim2.new(1, -28, 1, 0)
  robuxPriceLabel.Position = UDim2.new(0, 26, 0, 0)
  robuxPriceLabel.BackgroundTransparency = 1
  robuxPriceLabel.Text = tostring(robuxPrice)
  robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxPriceLabel.TextScaled = true
  robuxPriceLabel.Font = Enum.Font.GothamBold
  robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  robuxPriceLabel.Parent = robuxButton

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

  -- Update affordability - shows price on button
  local function updateAffordability()
    local cardPrice = card:GetAttribute("Price") or price
    local cardStock = card:GetAttribute("Stock") or stock
    local canAfford = cachedPlayerMoney >= cardPrice
    local soldOut = cardStock <= 0
    local priceText = "$" .. tostring(cardPrice)
    if soldOut then
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
      buyButton.Text = "SOLD OUT"
      buyButton.TextTransparency = 0.5
    elseif canAfford then
      buyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
      buyButton.Text = priceText
      buyButton.TextTransparency = 0
    else
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
      buyButton.Text = priceText
      buyButton.TextTransparency = 0.5
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
  card.Size = UDim2.new(1, -10, 0, 90)
  card.Position = UDim2.new(0, 5, 0, (index - 1) * 95 + 5)
  card.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Power-up type indicator bar
  local isLuck = string.find(powerUpId, "HatchLuck") ~= nil
  local barColor = isLuck and Color3.fromRGB(50, 205, 50) or Color3.fromRGB(255, 215, 0)

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

  -- Icon
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 30, 0, 30)
  iconLabel.Position = UDim2.new(0, 12, 0, 10)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = config.icon
  iconLabel.TextSize = 24
  iconLabel.Parent = card

  -- Power-up name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.5, -20, 0, 22)
  nameLabel.Position = UDim2.new(0, 45, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = config.displayName
  nameLabel.TextColor3 = barColor
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.Parent = card

  -- Description
  local descLabel = Instance.new("TextLabel")
  descLabel.Name = "Description"
  descLabel.Size = UDim2.new(0.6, -20, 0, 18)
  descLabel.Position = UDim2.new(0, 45, 0, 30)
  descLabel.BackgroundTransparency = 1
  descLabel.Text = config.description
  descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
  descLabel.TextScaled = true
  descLabel.Font = Enum.Font.Gotham
  descLabel.TextXAlignment = Enum.TextXAlignment.Left
  descLabel.Parent = card

  -- Duration info
  local durationText = PowerUpConfig.formatRemainingTime(config.durationSeconds)
  local durationLabel = Instance.new("TextLabel")
  durationLabel.Name = "Duration"
  durationLabel.Size = UDim2.new(0.5, -20, 0, 16)
  durationLabel.Position = UDim2.new(0, 45, 0, 50)
  durationLabel.BackgroundTransparency = 1
  durationLabel.Text = "Duration: " .. durationText
  durationLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
  durationLabel.TextScaled = true
  durationLabel.Font = Enum.Font.Gotham
  durationLabel.TextXAlignment = Enum.TextXAlignment.Left
  durationLabel.Parent = card

  -- Active status (if power-up is currently active)
  local powerUpType = PowerUpConfig.getPowerUpType(powerUpId)
  local activeExpiresAt = cachedActivePowerUps and powerUpType and cachedActivePowerUps[powerUpType]
  local isActive = activeExpiresAt and os.time() < activeExpiresAt

  local statusLabel = Instance.new("TextLabel")
  statusLabel.Name = "Status"
  statusLabel.Size = UDim2.new(0.5, -20, 0, 16)
  statusLabel.Position = UDim2.new(0, 45, 0, 68)
  statusLabel.BackgroundTransparency = 1
  if isActive then
    local remaining = activeExpiresAt - os.time()
    statusLabel.Text = "✓ ACTIVE (" .. PowerUpConfig.formatRemainingTime(remaining) .. " left)"
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
  else
    statusLabel.Text = ""
  end
  statusLabel.TextScaled = true
  statusLabel.Font = Enum.Font.GothamBold
  statusLabel.TextXAlignment = Enum.TextXAlignment.Left
  statusLabel.Parent = card

  -- Buy button (Robux only)
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 80, 0, 35)
  buyButton.Position = UDim2.new(1, -90, 0.5, -17)
  buyButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255) -- Robux blue
  buyButton.Text = ""
  buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  buyButton.TextScaled = true
  buyButton.Font = Enum.Font.GothamBold
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 6)
  buyButtonCorner.Parent = buyButton

  -- Robux icon
  local robuxIcon = Instance.new("ImageLabel")
  robuxIcon.Name = "RobuxIcon"
  robuxIcon.Size = UDim2.new(0, 16, 0, 16)
  robuxIcon.Position = UDim2.new(0, 8, 0.5, -8)
  robuxIcon.BackgroundTransparency = 1
  robuxIcon.Image = "rbxassetid://4915439044"
  robuxIcon.Parent = buyButton

  -- Price label
  local priceLabel = Instance.new("TextLabel")
  priceLabel.Name = "PriceLabel"
  priceLabel.Size = UDim2.new(1, -28, 1, 0)
  priceLabel.Position = UDim2.new(0, 26, 0, 0)
  priceLabel.BackgroundTransparency = 1
  priceLabel.Text = tostring(config.robuxPrice)
  priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  priceLabel.TextScaled = true
  priceLabel.Font = Enum.Font.GothamBold
  priceLabel.TextXAlignment = Enum.TextXAlignment.Left
  priceLabel.Parent = buyButton

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
	Creates a supply/trap card for the store.
	@param supplyItem Store.SupplyItem - The supply item data
	@param parent Frame - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createSupplyCard(supplyItem: Store.SupplyItem, parent: Frame, index: number): Frame
  local card = Instance.new("Frame")
  card.Name = supplyItem.id
  card.Size = UDim2.new(1, -10, 0, 90)
  card.Position = UDim2.new(0, 5, 0, (index - 1) * 95 + 5)
  card.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Tier color bar on left
  local tierBar = Instance.new("Frame")
  tierBar.Name = "TierBar"
  tierBar.Size = UDim2.new(0, 4, 1, -8)
  tierBar.Position = UDim2.new(0, 4, 0, 4)
  tierBar.BackgroundColor3 = TIER_COLORS[supplyItem.tier] or Color3.fromRGB(128, 128, 128)
  tierBar.BorderSizePixel = 0
  tierBar.Parent = card

  local tierBarCorner = Instance.new("UICorner")
  tierBarCorner.CornerRadius = UDim.new(0, 2)
  tierBarCorner.Parent = tierBar

  -- Icon (trap emoji)
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 40, 0, 40)
  iconLabel.Position = UDim2.new(0, 15, 0, 8)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = "🪤"
  iconLabel.TextScaled = true
  iconLabel.Font = Enum.Font.Gotham
  iconLabel.Parent = card

  -- Name label
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.5, -60, 0, 22)
  nameLabel.Position = UDim2.new(0, 60, 0, 6)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = supplyItem.displayName
  nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.Parent = card

  -- Tier label
  local tierLabel = Instance.new("TextLabel")
  tierLabel.Name = "Tier"
  tierLabel.Size = UDim2.new(0.5, -60, 0, 16)
  tierLabel.Position = UDim2.new(0, 60, 0, 28)
  tierLabel.BackgroundTransparency = 1
  tierLabel.Text = supplyItem.tier
  tierLabel.TextColor3 = TIER_COLORS[supplyItem.tier] or Color3.fromRGB(180, 180, 180)
  tierLabel.TextScaled = true
  tierLabel.Font = Enum.Font.Gotham
  tierLabel.TextXAlignment = Enum.TextXAlignment.Left
  tierLabel.Parent = card

  -- Description label
  local descLabel = Instance.new("TextLabel")
  descLabel.Name = "Description"
  descLabel.Size = UDim2.new(0.9, -60, 0, 28)
  descLabel.Position = UDim2.new(0, 60, 0, 46)
  descLabel.BackgroundTransparency = 1
  descLabel.Text = supplyItem.description
  descLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
  descLabel.TextScaled = true
  descLabel.Font = Enum.Font.Gotham
  descLabel.TextXAlignment = Enum.TextXAlignment.Left
  descLabel.TextWrapped = true
  descLabel.Parent = card

  -- Cash buy button
  local canAfford = cachedPlayerMoney >= supplyItem.price
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 80, 0, 30)
  buyButton.Position = UDim2.new(1, -170, 0, 8)
  buyButton.BackgroundColor3 = canAfford and Color3.fromRGB(50, 180, 50)
    or Color3.fromRGB(80, 80, 80)
  buyButton.Text = "$" .. tostring(supplyItem.price)
  buyButton.TextColor3 = canAfford and Color3.fromRGB(255, 255, 255)
    or Color3.fromRGB(150, 150, 150)
  buyButton.TextScaled = true
  buyButton.Font = Enum.Font.GothamBold
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 6)
  buyButtonCorner.Parent = buyButton

  -- Connect cash buy button
  buyButton.MouseButton1Click:Connect(function()
    if canAfford and onTrapPurchaseCallback then
      onTrapPurchaseCallback(supplyItem.id)
    end
  end)

  -- Robux buy button
  local robuxButton = Instance.new("TextButton")
  robuxButton.Name = "RobuxButton"
  robuxButton.Size = UDim2.new(0, 70, 0, 30)
  robuxButton.Position = UDim2.new(1, -85, 0, 8)
  robuxButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
  robuxButton.Text = ""
  robuxButton.Parent = card

  local robuxButtonCorner = Instance.new("UICorner")
  robuxButtonCorner.CornerRadius = UDim.new(0, 6)
  robuxButtonCorner.Parent = robuxButton

  -- Robux icon
  local robuxIcon = Instance.new("ImageLabel")
  robuxIcon.Name = "RobuxIcon"
  robuxIcon.Size = UDim2.new(0, 14, 0, 14)
  robuxIcon.Position = UDim2.new(0, 6, 0.5, -7)
  robuxIcon.BackgroundTransparency = 1
  robuxIcon.Image = "rbxassetid://4915439044"
  robuxIcon.Parent = robuxButton

  -- Robux price label
  local robuxPriceLabel = Instance.new("TextLabel")
  robuxPriceLabel.Name = "Price"
  robuxPriceLabel.Size = UDim2.new(1, -24, 1, 0)
  robuxPriceLabel.Position = UDim2.new(0, 22, 0, 0)
  robuxPriceLabel.BackgroundTransparency = 1
  robuxPriceLabel.Text = tostring(supplyItem.robuxPrice)
  robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  robuxPriceLabel.TextScaled = true
  robuxPriceLabel.Font = Enum.Font.GothamBold
  robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
  robuxPriceLabel.Parent = robuxButton

  -- Connect Robux button
  robuxButton.MouseButton1Click:Connect(function()
    if onRobuxPurchaseCallback then
      onRobuxPurchaseCallback("trap", supplyItem.id)
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
	Creates a weapon card for the store.
	@param weaponItem Store.WeaponItem - The weapon item data
	@param parent Frame - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createWeaponCard(weaponItem: Store.WeaponItem, parent: Frame, index: number): Frame
  local card = Instance.new("Frame")
  card.Name = weaponItem.id
  card.Size = UDim2.new(1, -10, 0, 90)
  card.Position = UDim2.new(0, 5, 0, (index - 1) * 95 + 5)
  card.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  card.BorderSizePixel = 0
  card.Parent = parent

  local cardCorner = Instance.new("UICorner")
  cardCorner.CornerRadius = UDim.new(0, 8)
  cardCorner.Parent = card

  -- Tier color bar on left
  local tierBar = Instance.new("Frame")
  tierBar.Name = "TierBar"
  tierBar.Size = UDim2.new(0, 4, 1, -8)
  tierBar.Position = UDim2.new(0, 4, 0, 4)
  tierBar.BackgroundColor3 = WEAPON_TIER_COLORS[weaponItem.tier] or Color3.fromRGB(128, 128, 128)
  tierBar.BorderSizePixel = 0
  tierBar.Parent = card

  local tierBarCorner = Instance.new("UICorner")
  tierBarCorner.CornerRadius = UDim.new(0, 2)
  tierBarCorner.Parent = tierBar

  -- Weapon icon
  local iconLabel = Instance.new("TextLabel")
  iconLabel.Name = "Icon"
  iconLabel.Size = UDim2.new(0, 30, 0, 30)
  iconLabel.Position = UDim2.new(0, 15, 0, 10)
  iconLabel.BackgroundTransparency = 1
  iconLabel.Text = weaponItem.icon
  iconLabel.TextSize = 24
  iconLabel.Parent = card

  -- Weapon name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.4, -20, 0, 22)
  nameLabel.Position = UDim2.new(0, 50, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = weaponItem.displayName
  nameLabel.TextColor3 = WEAPON_TIER_COLORS[weaponItem.tier] or Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.Parent = card

  -- Tier and damage label
  local tierLabel = Instance.new("TextLabel")
  tierLabel.Name = "Tier"
  tierLabel.Size = UDim2.new(0.4, -20, 0, 16)
  tierLabel.Position = UDim2.new(0, 50, 0, 30)
  tierLabel.BackgroundTransparency = 1
  tierLabel.Text = weaponItem.tier .. " • " .. weaponItem.damage .. " DMG"
  tierLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
  tierLabel.TextScaled = true
  tierLabel.Font = Enum.Font.Gotham
  tierLabel.TextXAlignment = Enum.TextXAlignment.Left
  tierLabel.Parent = card

  -- Description
  local descLabel = Instance.new("TextLabel")
  descLabel.Name = "Description"
  descLabel.Size = UDim2.new(0.5, -20, 0, 16)
  descLabel.Position = UDim2.new(0, 50, 0, 48)
  descLabel.BackgroundTransparency = 1
  descLabel.Text = weaponItem.description
  descLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
  descLabel.TextScaled = true
  descLabel.Font = Enum.Font.Gotham
  descLabel.TextXAlignment = Enum.TextXAlignment.Left
  descLabel.Parent = card

  -- Owned status
  local isOwned = cachedOwnedWeapons and cachedOwnedWeapons[weaponItem.id]
  local isFree = weaponItem.price == 0

  local statusLabel = Instance.new("TextLabel")
  statusLabel.Name = "Status"
  statusLabel.Size = UDim2.new(0.4, 0, 0, 16)
  statusLabel.Position = UDim2.new(0, 50, 0, 66)
  statusLabel.BackgroundTransparency = 1
  if isOwned then
    statusLabel.Text = "✓ OWNED"
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
  elseif isFree then
    statusLabel.Text = "★ STARTER"
    statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
  else
    statusLabel.Text = ""
  end
  statusLabel.TextScaled = true
  statusLabel.Font = Enum.Font.GothamBold
  statusLabel.TextXAlignment = Enum.TextXAlignment.Left
  statusLabel.Parent = card

  -- Buy button (cash) - only show for non-free, non-owned weapons
  if not isOwned and not isFree then
    local canAfford = cachedPlayerMoney >= weaponItem.price
    local buyButton = Instance.new("TextButton")
    buyButton.Name = "BuyButton"
    buyButton.Size = UDim2.new(0, 70, 0, 28)
    buyButton.Position = UDim2.new(1, -155, 0.5, -14)
    buyButton.BackgroundColor3 = canAfford and Color3.fromRGB(50, 180, 50)
      or Color3.fromRGB(80, 80, 80)
    buyButton.Text = "$" .. tostring(weaponItem.price)
    buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    buyButton.TextTransparency = canAfford and 0 or 0.5
    buyButton.TextScaled = true
    buyButton.Font = Enum.Font.GothamBold
    buyButton.Parent = card

    local buyButtonCorner = Instance.new("UICorner")
    buyButtonCorner.CornerRadius = UDim.new(0, 6)
    buyButtonCorner.Parent = buyButton

    buyButton.MouseButton1Click:Connect(function()
      if onWeaponPurchaseCallback and canAfford then
        onWeaponPurchaseCallback(weaponItem.id)
      end
    end)

    -- Robux button
    local robuxButton = Instance.new("TextButton")
    robuxButton.Name = "RobuxButton"
    robuxButton.Size = UDim2.new(0, 70, 0, 28)
    robuxButton.Position = UDim2.new(1, -80, 0.5, -14)
    robuxButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
    robuxButton.Text = ""
    robuxButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    robuxButton.Parent = card

    local robuxButtonCorner = Instance.new("UICorner")
    robuxButtonCorner.CornerRadius = UDim.new(0, 6)
    robuxButtonCorner.Parent = robuxButton

    local robuxIcon = Instance.new("ImageLabel")
    robuxIcon.Name = "RobuxIcon"
    robuxIcon.Size = UDim2.new(0, 14, 0, 14)
    robuxIcon.Position = UDim2.new(0, 6, 0.5, -7)
    robuxIcon.BackgroundTransparency = 1
    robuxIcon.Image = "rbxassetid://4915439044"
    robuxIcon.Parent = robuxButton

    local robuxPriceLabel = Instance.new("TextLabel")
    robuxPriceLabel.Name = "Price"
    robuxPriceLabel.Size = UDim2.new(1, -24, 1, 0)
    robuxPriceLabel.Position = UDim2.new(0, 22, 0, 0)
    robuxPriceLabel.BackgroundTransparency = 1
    robuxPriceLabel.Text = tostring(weaponItem.robuxPrice)
    robuxPriceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    robuxPriceLabel.TextScaled = true
    robuxPriceLabel.Font = Enum.Font.GothamBold
    robuxPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
    robuxPriceLabel.Parent = robuxButton

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
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #availableEggs * 85 + 10)
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
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #availableChickens * 85 + 10)
  elseif currentTab == "supplies" then
    local availableTraps = Store.getAvailableTraps()
    for index, item in ipairs(availableTraps) do
      createSupplyCard(item, scrollFrame, index)
    end
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #availableTraps * 95 + 10)
  elseif currentTab == "powerups" then
    local powerUps = PowerUpConfig.getAllSorted()
    for index, config in ipairs(powerUps) do
      createPowerUpCard(config.id, config, scrollFrame, index)
    end
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #powerUps * 95 + 10)
  elseif currentTab == "weapons" then
    local availableWeapons = Store.getAvailableWeapons()
    for index, item in ipairs(availableWeapons) do
      createWeaponCard(item, scrollFrame, index)
    end
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #availableWeapons * 95 + 10)
  end
end

--[[
	Updates tab button appearance based on current selection.
]]
local function updateTabAppearance()
  if not tabFrame then
    return
  end

  local eggsTab = tabFrame:FindFirstChild("EggsTab")
  local chickensTab = tabFrame:FindFirstChild("ChickensTab")
  local suppliesTab = tabFrame:FindFirstChild("SuppliesTab")
  local powerupsTab = tabFrame:FindFirstChild("PowerupsTab")
  local weaponsTab = tabFrame:FindFirstChild("WeaponsTab")

  if eggsTab and eggsTab:IsA("TextButton") then
    if currentTab == "eggs" then
      eggsTab.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
      eggsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
      eggsTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      eggsTab.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
  end

  if chickensTab and chickensTab:IsA("TextButton") then
    if currentTab == "chickens" then
      chickensTab.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
      chickensTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
      chickensTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      chickensTab.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
  end

  if suppliesTab and suppliesTab:IsA("TextButton") then
    if currentTab == "supplies" then
      suppliesTab.BackgroundColor3 = Color3.fromRGB(200, 120, 50) -- Orange for supplies
      suppliesTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
      suppliesTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      suppliesTab.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
  end

  if powerupsTab and powerupsTab:IsA("TextButton") then
    if currentTab == "powerups" then
      powerupsTab.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
      powerupsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
      powerupsTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      powerupsTab.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
  end

  if weaponsTab and weaponsTab:IsA("TextButton") then
    if currentTab == "weapons" then
      weaponsTab.BackgroundColor3 = Color3.fromRGB(220, 50, 50) -- Red for weapons
      weaponsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
      weaponsTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      weaponsTab.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
  end
end

--[[
	Switches to the specified tab.
	@param tab "eggs" | "chickens" | "supplies" | "powerups" | "weapons" - The tab to switch to
]]
local function switchTab(tab: "eggs" | "chickens" | "supplies" | "powerups" | "weapons")
  currentTab = tab
  updateTabAppearance()
  populateItems()
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

  -- Main frame (centered panel)
  mainFrame = Instance.new("Frame")
  mainFrame.Name = "MainFrame"
  mainFrame.Size = UDim2.new(0, 420, 0, 550)
  mainFrame.Position = UDim2.new(0.5, -210, 0.5, -275)
  mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
  mainFrame.BorderSizePixel = 0
  mainFrame.Parent = screenGui

  local mainCorner = Instance.new("UICorner")
  mainCorner.CornerRadius = UDim.new(0, 12)
  mainCorner.Parent = mainFrame

  -- Title bar
  local titleBar = Instance.new("Frame")
  titleBar.Name = "TitleBar"
  titleBar.Size = UDim2.new(1, 0, 0, 45)
  titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
  titleBar.BorderSizePixel = 0
  titleBar.Parent = mainFrame

  local titleCorner = Instance.new("UICorner")
  titleCorner.CornerRadius = UDim.new(0, 12)
  titleCorner.Parent = titleBar

  -- Fix bottom corners of title bar
  local titleCornerFix = Instance.new("Frame")
  titleCornerFix.Name = "CornerFix"
  titleCornerFix.Size = UDim2.new(1, 0, 0, 12)
  titleCornerFix.Position = UDim2.new(0, 0, 1, -12)
  titleCornerFix.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
  titleCornerFix.BorderSizePixel = 0
  titleCornerFix.Parent = titleBar

  -- Title text
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Name = "Title"
  titleLabel.Size = UDim2.new(1, -50, 1, 0)
  titleLabel.Position = UDim2.new(0, 15, 0, 0)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Text = "🏪 STORE"
  titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  titleLabel.TextScaled = true
  titleLabel.Font = Enum.Font.GothamBold
  titleLabel.TextXAlignment = Enum.TextXAlignment.Left
  titleLabel.Parent = titleBar

  -- Close button
  local closeButton = Instance.new("TextButton")
  closeButton.Name = "CloseButton"
  closeButton.Size = UDim2.new(0, 35, 0, 35)
  closeButton.Position = UDim2.new(1, -40, 0, 5)
  closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
  closeButton.Text = "X"
  closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  closeButton.TextScaled = true
  closeButton.Font = Enum.Font.GothamBold
  closeButton.Parent = titleBar

  local closeCorner = Instance.new("UICorner")
  closeCorner.CornerRadius = UDim.new(0, 6)
  closeCorner.Parent = closeButton

  closeButton.MouseButton1Click:Connect(function()
    StoreUI.close()
  end)

  -- Money display
  local moneyFrame = Instance.new("Frame")
  moneyFrame.Name = "MoneyFrame"
  moneyFrame.Size = UDim2.new(1, -20, 0, 35)
  moneyFrame.Position = UDim2.new(0, 10, 0, 50)
  moneyFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
  moneyFrame.BorderSizePixel = 0
  moneyFrame.Parent = mainFrame

  local moneyCorner = Instance.new("UICorner")
  moneyCorner.CornerRadius = UDim.new(0, 6)
  moneyCorner.Parent = moneyFrame

  local moneyLabel = Instance.new("TextLabel")
  moneyLabel.Name = "MoneyLabel"
  moneyLabel.Size = UDim2.new(0.55, -10, 1, 0)
  moneyLabel.Position = UDim2.new(0, 5, 0, 0)
  moneyLabel.BackgroundTransparency = 1
  moneyLabel.Text = "Your Balance: $0"
  moneyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
  moneyLabel.TextScaled = true
  moneyLabel.Font = Enum.Font.GothamBold
  moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
  moneyLabel.Parent = moneyFrame

  -- Restock timer display
  restockTimerLabel = Instance.new("TextLabel")
  restockTimerLabel.Name = "RestockTimerLabel"
  restockTimerLabel.Size = UDim2.new(0.45, -5, 1, 0)
  restockTimerLabel.Position = UDim2.new(0.55, 0, 0, 0)
  restockTimerLabel.BackgroundTransparency = 1
  restockTimerLabel.Text = "Restocks in 0:00"
  restockTimerLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
  restockTimerLabel.TextScaled = true
  restockTimerLabel.Font = Enum.Font.Gotham
  restockTimerLabel.TextXAlignment = Enum.TextXAlignment.Right
  restockTimerLabel.Parent = moneyFrame

  -- Initialize timer display
  updateRestockTimer()

  -- Tab frame for Eggs/Chickens/Supplies/Power-ups/Weapons tabs
  tabFrame = Instance.new("Frame")
  tabFrame.Name = "TabFrame"
  tabFrame.Size = UDim2.new(1, -20, 0, 35)
  tabFrame.Position = UDim2.new(0, 10, 0, 90)
  tabFrame.BackgroundTransparency = 1
  tabFrame.Parent = mainFrame

  -- Eggs tab button
  local eggsTab = Instance.new("TextButton")
  eggsTab.Name = "EggsTab"
  eggsTab.Size = UDim2.new(0.2, -2, 1, 0)
  eggsTab.Position = UDim2.new(0, 0, 0, 0)
  eggsTab.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
  eggsTab.Text = "🥚"
  eggsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
  eggsTab.TextScaled = true
  eggsTab.Font = Enum.Font.GothamBold
  eggsTab.Parent = tabFrame

  local eggsTabCorner = Instance.new("UICorner")
  eggsTabCorner.CornerRadius = UDim.new(0, 6)
  eggsTabCorner.Parent = eggsTab

  eggsTab.MouseButton1Click:Connect(function()
    switchTab("eggs")
  end)

  -- Chickens tab button
  local chickensTab = Instance.new("TextButton")
  chickensTab.Name = "ChickensTab"
  chickensTab.Size = UDim2.new(0.2, -2, 1, 0)
  chickensTab.Position = UDim2.new(0.2, 1, 0, 0)
  chickensTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  chickensTab.Text = "🐔"
  chickensTab.TextColor3 = Color3.fromRGB(180, 180, 180)
  chickensTab.TextScaled = true
  chickensTab.Font = Enum.Font.GothamBold
  chickensTab.Parent = tabFrame

  local chickensTabCorner = Instance.new("UICorner")
  chickensTabCorner.CornerRadius = UDim.new(0, 6)
  chickensTabCorner.Parent = chickensTab

  chickensTab.MouseButton1Click:Connect(function()
    switchTab("chickens")
  end)

  -- Supplies tab button
  local suppliesTab = Instance.new("TextButton")
  suppliesTab.Name = "SuppliesTab"
  suppliesTab.Size = UDim2.new(0.2, -2, 1, 0)
  suppliesTab.Position = UDim2.new(0.4, 2, 0, 0)
  suppliesTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  suppliesTab.Text = "🪤"
  suppliesTab.TextColor3 = Color3.fromRGB(180, 180, 180)
  suppliesTab.TextScaled = true
  suppliesTab.Font = Enum.Font.GothamBold
  suppliesTab.Parent = tabFrame

  local suppliesTabCorner = Instance.new("UICorner")
  suppliesTabCorner.CornerRadius = UDim.new(0, 6)
  suppliesTabCorner.Parent = suppliesTab

  suppliesTab.MouseButton1Click:Connect(function()
    switchTab("supplies")
  end)

  -- Power-ups tab button
  local powerupsTab = Instance.new("TextButton")
  powerupsTab.Name = "PowerupsTab"
  powerupsTab.Size = UDim2.new(0.2, -2, 1, 0)
  powerupsTab.Position = UDim2.new(0.6, 3, 0, 0)
  powerupsTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  powerupsTab.Text = "⚡"
  powerupsTab.TextColor3 = Color3.fromRGB(180, 180, 180)
  powerupsTab.TextScaled = true
  powerupsTab.Font = Enum.Font.GothamBold
  powerupsTab.Parent = tabFrame

  local powerupsTabCorner = Instance.new("UICorner")
  powerupsTabCorner.CornerRadius = UDim.new(0, 6)
  powerupsTabCorner.Parent = powerupsTab

  powerupsTab.MouseButton1Click:Connect(function()
    switchTab("powerups")
  end)

  -- Weapons tab button
  local weaponsTab = Instance.new("TextButton")
  weaponsTab.Name = "WeaponsTab"
  weaponsTab.Size = UDim2.new(0.2, -2, 1, 0)
  weaponsTab.Position = UDim2.new(0.8, 4, 0, 0)
  weaponsTab.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  weaponsTab.Text = "⚔️"
  weaponsTab.TextColor3 = Color3.fromRGB(180, 180, 180)
  weaponsTab.TextScaled = true
  weaponsTab.Font = Enum.Font.GothamBold
  weaponsTab.Parent = tabFrame

  local weaponsTabCorner = Instance.new("UICorner")
  weaponsTabCorner.CornerRadius = UDim.new(0, 6)
  weaponsTabCorner.Parent = weaponsTab

  weaponsTab.MouseButton1Click:Connect(function()
    switchTab("weapons")
  end)

  -- Scroll frame for items
  scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "ItemsScroll"
  scrollFrame.Size = UDim2.new(1, -20, 1, -195) -- Reduced height to make room for replenish button
  scrollFrame.Position = UDim2.new(0, 10, 0, 130)
  scrollFrame.BackgroundTransparency = 1
  scrollFrame.ScrollBarThickness = 6
  scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
  scrollFrame.Parent = mainFrame

  -- Replenish Now button (Robux purchase)
  replenishButton = Instance.new("TextButton")
  replenishButton.Name = "ReplenishButton"
  replenishButton.Size = UDim2.new(1, -20, 0, 40)
  replenishButton.Position = UDim2.new(0, 10, 1, -50)
  replenishButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255) -- Robux blue
  replenishButton.Text = "⏱ Replenish Now - R$" .. tostring(ROBUX_REPLENISH_PRICE)
  replenishButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  replenishButton.TextScaled = true
  replenishButton.Font = Enum.Font.GothamBold
  replenishButton.Parent = mainFrame

  local replenishCorner = Instance.new("UICorner")
  replenishCorner.CornerRadius = UDim.new(0, 8)
  replenishCorner.Parent = replenishButton

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
	Opens the store UI.
]]
function StoreUI.open()
  if not screenGui then
    return
  end
  screenGui.Enabled = true
  isOpen = true

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
	Closes the store UI.
]]
function StoreUI.close()
  if not screenGui then
    return
  end
  screenGui.Enabled = false
  isOpen = false

  -- Stop timer update loop
  if timerConnection then
    timerConnection:Disconnect()
    timerConnection = nil
  end

  print("[StoreUI] Closed")
end

--[[
	Toggles the store UI open/closed.
]]
function StoreUI.toggle()
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
	Updates the player money display and affordability indicators.
	@param money number - The player's current money balance
]]
function StoreUI.updateMoney(money: number)
  cachedPlayerMoney = money

  if not mainFrame then
    return
  end

  -- Update money label
  local moneyFrame = mainFrame:FindFirstChild("MoneyFrame")
  if moneyFrame then
    local moneyLabel = moneyFrame:FindFirstChild("MoneyLabel")
    if moneyLabel and moneyLabel:IsA("TextLabel") then
      moneyLabel.Text = "Your Balance: $" .. tostring(math.floor(money))
    end
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
