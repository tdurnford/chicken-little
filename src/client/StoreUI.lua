--[[
	StoreUI Module
	Implements the store UI where players can browse and purchase eggs.
	Opens when player interacts with the central store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local StoreUI = {}

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local Store = require(Shared:WaitForChild("Store"))

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
local isOpen = false

-- Cached player money for UI updates
local cachedPlayerMoney = 0

-- Callbacks
local onPurchaseCallback: ((eggType: string, quantity: number) -> any)? = nil

--[[
	Creates a single egg item card for the store.
	@param eggType string - The egg type name
	@param config table - The egg configuration
	@param parent Instance - Parent frame to add card to
	@param index number - Index for positioning
]]
local function createEggCard(eggType: string, config: any, parent: Frame, index: number): Frame
  local card = Instance.new("Frame")
  card.Name = eggType
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
  rarityBar.BackgroundColor3 = RARITY_COLORS[config.rarity] or Color3.fromRGB(128, 128, 128)
  rarityBar.BorderSizePixel = 0
  rarityBar.Parent = card

  local rarityBarCorner = Instance.new("UICorner")
  rarityBarCorner.CornerRadius = UDim.new(0, 4)
  rarityBarCorner.Parent = rarityBar

  -- Egg name
  local nameLabel = Instance.new("TextLabel")
  nameLabel.Name = "Name"
  nameLabel.Size = UDim2.new(0.5, -20, 0, 25)
  nameLabel.Position = UDim2.new(0, 15, 0, 8)
  nameLabel.BackgroundTransparency = 1
  nameLabel.Text = config.displayName
  nameLabel.TextColor3 = RARITY_COLORS[config.rarity] or Color3.fromRGB(255, 255, 255)
  nameLabel.TextScaled = true
  nameLabel.Font = Enum.Font.GothamBold
  nameLabel.TextXAlignment = Enum.TextXAlignment.Left
  nameLabel.Parent = card

  -- Rarity label
  local rarityLabel = Instance.new("TextLabel")
  rarityLabel.Name = "Rarity"
  rarityLabel.Size = UDim2.new(0.5, -20, 0, 18)
  rarityLabel.Position = UDim2.new(0, 15, 0, 33)
  rarityLabel.BackgroundTransparency = 1
  rarityLabel.Text = config.rarity
  rarityLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
  rarityLabel.TextScaled = true
  rarityLabel.Font = Enum.Font.Gotham
  rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
  rarityLabel.Parent = card

  -- Price label
  local priceLabel = Instance.new("TextLabel")
  priceLabel.Name = "Price"
  priceLabel.Size = UDim2.new(0, 80, 0, 25)
  priceLabel.Position = UDim2.new(0.5, 0, 0, 8)
  priceLabel.BackgroundTransparency = 1
  priceLabel.Text = "$" .. tostring(config.purchasePrice)
  priceLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
  priceLabel.TextScaled = true
  priceLabel.Font = Enum.Font.GothamBold
  priceLabel.TextXAlignment = Enum.TextXAlignment.Left
  priceLabel.Parent = card

  -- Buy button
  local buyButton = Instance.new("TextButton")
  buyButton.Name = "BuyButton"
  buyButton.Size = UDim2.new(0, 70, 0, 35)
  buyButton.Position = UDim2.new(1, -80, 0.5, -17)
  buyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
  buyButton.Text = "BUY"
  buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  buyButton.TextScaled = true
  buyButton.Font = Enum.Font.GothamBold
  buyButton.Parent = card

  local buyButtonCorner = Instance.new("UICorner")
  buyButtonCorner.CornerRadius = UDim.new(0, 6)
  buyButtonCorner.Parent = buyButton

  -- Connect buy button
  buyButton.MouseButton1Click:Connect(function()
    if onPurchaseCallback then
      onPurchaseCallback(eggType, 1)
    end
  end)

  -- Update affordability
  local function updateAffordability()
    local canAfford = cachedPlayerMoney >= config.purchasePrice
    if canAfford then
      buyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
      buyButton.TextTransparency = 0
    else
      buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
      buyButton.TextTransparency = 0.5
    end
  end

  -- Store update function on card for later updates
  card:SetAttribute("UpdateAffordability", true)
  card.AttributeChanged:Connect(function(attributeName)
    if attributeName == "PlayerMoney" then
      updateAffordability()
    end
  end)

  updateAffordability()
  return card
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
  mainFrame.Size = UDim2.new(0, 400, 0, 500)
  mainFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
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
  titleLabel.Text = "🏪 EGG STORE"
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
  moneyLabel.Size = UDim2.new(1, -10, 1, 0)
  moneyLabel.Position = UDim2.new(0, 5, 0, 0)
  moneyLabel.BackgroundTransparency = 1
  moneyLabel.Text = "Your Balance: $0"
  moneyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
  moneyLabel.TextScaled = true
  moneyLabel.Font = Enum.Font.GothamBold
  moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
  moneyLabel.Parent = moneyFrame

  -- Scroll frame for items
  local scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "ItemsScroll"
  scrollFrame.Size = UDim2.new(1, -20, 1, -100)
  scrollFrame.Position = UDim2.new(0, 10, 0, 90)
  scrollFrame.BackgroundTransparency = 1
  scrollFrame.ScrollBarThickness = 6
  scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
  scrollFrame.Parent = mainFrame

  -- Add egg items
  local availableEggs = Store.getAvailableEggs()
  for index, item in ipairs(availableEggs) do
    local config = EggConfig.get(item.id)
    if config then
      createEggCard(item.id, config, scrollFrame, index)
    end
  end

  -- Set canvas size based on number of items
  scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #availableEggs * 85 + 10)

  -- Escape key to close
  UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
      return
    end
    if input.KeyCode == Enum.KeyCode.Escape and isOpen then
      StoreUI.close()
    end
  end)

  print("[StoreUI] Created")
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
  local scrollFrame = mainFrame:FindFirstChild("ItemsScroll")
  if scrollFrame then
    for _, child in ipairs(scrollFrame:GetChildren()) do
      if child:IsA("Frame") then
        child:SetAttribute("PlayerMoney", money)
      end
    end
  end
end

--[[
	Sets the callback for when a purchase is attempted.
	@param callback function - Function to call with (eggType, quantity)
]]
function StoreUI.onPurchase(callback: (eggType: string, quantity: number) -> any)
  onPurchaseCallback = callback
end

return StoreUI
