--[[
	Store Module
	Implements the store where players can buy eggs and sell eggs, chickens,
	and trapped predators.
]]

local Store = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local EggConfig = require(script.Parent.EggConfig)
local ChickenConfig = require(script.Parent.ChickenConfig)
local TrapConfig = require(script.Parent.TrapConfig)

-- Type definitions
export type TransactionResult = {
  success: boolean,
  message: string,
  newBalance: number?,
  itemId: string?,
}

export type StoreItem = {
  itemType: "egg" | "chicken" | "predator",
  id: string,
  name: string,
  displayName: string,
  rarity: string,
  price: number,
  sellPrice: number,
}

-- Inventory item with stock count
export type InventoryItem = {
  itemType: "egg" | "chicken",
  id: string,
  name: string,
  displayName: string,
  rarity: string,
  price: number,
  sellPrice: number,
  stock: number,
  maxStock: number,
  robuxPrice: number,
}

-- Store inventory state
export type StoreInventory = {
  eggs: { [string]: InventoryItem },
  chickens: { [string]: InventoryItem },
  lastReplenishTime: number,
}

-- Sell price multiplier for chickens (percentage of equivalent value)
local CHICKEN_SELL_MULTIPLIER = 0.5

-- Base price per money-per-second for chicken value calculation
local CHICKEN_VALUE_PER_MPS = 60

-- Chicken purchase price multiplier
-- Set to 1.5 so basic chickens ($90) are cheaper than eggs ($100)
-- This makes eggs a "gamble" with upside potential for better chickens
local CHICKEN_PURCHASE_MULTIPLIER = 1.5

-- Predator sell prices by tier (placeholder until PredatorConfig exists)
local PREDATOR_SELL_PRICES: { [string]: number } = {
  Fox = 500,
  Wolf = 2000,
  Bear = 10000,
  Dragon = 100000,
}

-- Stock quantities per rarity tier
local RARITY_STOCK_QUANTITIES: { [string]: number } = {
  Common = 10,
  Uncommon = 5,
  Rare = 3,
  Epic = 2,
  Legendary = 1,
  Mythic = 0, -- Mythic items may not always be in stock
}

-- Store replenishment interval in seconds (5 minutes)
local REPLENISH_INTERVAL = 300

-- Rarity weights for weighted random selection (higher = more common)
local RARITY_WEIGHTS: { [string]: number } = {
  Common = 100,
  Uncommon = 50,
  Rare = 20,
  Epic = 8,
  Legendary = 3,
  Mythic = 1,
}

-- Robux prices per rarity tier (for buying items with Robux)
local RARITY_ROBUX_PRICES: { [string]: number } = {
  Common = 5,
  Uncommon = 15,
  Rare = 50,
  Epic = 150,
  Legendary = 500,
  Mythic = 1500,
}

-- Global store inventory state (server-side)
local storeInventory: StoreInventory? = nil

-- Buy an egg from the store
function Store.buyEgg(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string,
  quantity: number?
): TransactionResult
  local amount = quantity or 1

  -- Validate egg type
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return {
      success = false,
      message = "Invalid egg type: " .. tostring(eggType),
      newBalance = playerData.money,
    }
  end

  -- Validate quantity
  if amount < 1 then
    return {
      success = false,
      message = "Quantity must be at least 1",
      newBalance = playerData.money,
    }
  end

  -- Calculate total cost
  local totalCost = eggConfig.purchasePrice * amount

  -- Check if player can afford
  if playerData.money < totalCost then
    return {
      success = false,
      message = string.format(
        "Insufficient funds. Need $%d but only have $%d",
        totalCost,
        playerData.money
      ),
      newBalance = playerData.money,
    }
  end

  -- Deduct money
  playerData.money = playerData.money - totalCost

  -- Add eggs to inventory
  local firstEggId: string? = nil
  for i = 1, amount do
    local eggId = PlayerData.generateId()
    if i == 1 then
      firstEggId = eggId
    end
    table.insert(playerData.inventory.eggs, {
      id = eggId,
      eggType = eggType,
      rarity = eggConfig.rarity,
    })
  end

  local message = amount == 1
      and string.format("Purchased %s for $%d", eggConfig.displayName, totalCost)
    or string.format("Purchased %dx %s for $%d", amount, eggConfig.displayName, totalCost)

  return {
    success = true,
    message = message,
    newBalance = playerData.money,
    itemId = firstEggId,
  }
end

-- Find an egg in inventory by ID
local function findEggById(playerData: PlayerData.PlayerDataSchema, eggId: string): (number?, any?)
  for i, egg in ipairs(playerData.inventory.eggs) do
    if egg.id == eggId then
      return i, egg
    end
  end
  return nil, nil
end

-- Find a chicken in inventory by ID
local function findChickenInInventoryById(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): (number?, any?)
  for i, chicken in ipairs(playerData.inventory.chickens) do
    if chicken.id == chickenId then
      return i, chicken
    end
  end
  return nil, nil
end

-- Find a placed chicken by ID
local function findPlacedChickenById(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): (number?, any?)
  for i, chicken in ipairs(playerData.placedChickens) do
    if chicken.id == chickenId then
      return i, chicken
    end
  end
  return nil, nil
end

-- Calculate sell value for a chicken based on its type
function Store.getChickenValue(chickenType: string): number
  local config = ChickenConfig.get(chickenType)
  if not config then
    return 0
  end
  -- Value based on money per second * multiplier
  return math.floor(config.moneyPerSecond * CHICKEN_VALUE_PER_MPS * CHICKEN_SELL_MULTIPLIER)
end

-- Calculate purchase price for a chicken based on its type
function Store.getChickenPrice(chickenType: string): number
  local config = ChickenConfig.get(chickenType)
  if not config then
    return 0
  end
  -- Price based on money per second * multiplier (higher than sell value)
  return math.floor(config.moneyPerSecond * CHICKEN_VALUE_PER_MPS * CHICKEN_PURCHASE_MULTIPLIER)
end

-- Buy a chicken from the store
function Store.buyChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenType: string,
  quantity: number?
): TransactionResult
  local amount = quantity or 1

  -- Validate chicken type
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return {
      success = false,
      message = "Invalid chicken type: " .. tostring(chickenType),
      newBalance = playerData.money,
    }
  end

  -- Validate quantity
  if amount < 1 then
    return {
      success = false,
      message = "Quantity must be at least 1",
      newBalance = playerData.money,
    }
  end

  -- Calculate total cost
  local unitPrice = Store.getChickenPrice(chickenType)
  local totalCost = unitPrice * amount

  -- Check if player can afford
  if playerData.money < totalCost then
    return {
      success = false,
      message = string.format(
        "Insufficient funds. Need $%d but only have $%d",
        totalCost,
        math.floor(playerData.money)
      ),
      newBalance = playerData.money,
    }
  end

  -- Deduct money
  playerData.money = playerData.money - totalCost

  -- Add chickens to inventory
  local firstChickenId: string? = nil
  for i = 1, amount do
    local chickenId = PlayerData.generateId()
    if i == 1 then
      firstChickenId = chickenId
    end
    table.insert(playerData.inventory.chickens, {
      id = chickenId,
      chickenType = chickenType,
      rarity = chickenConfig.rarity,
      accumulatedMoney = 0,
    })
  end

  local message = amount == 1
      and string.format("Purchased %s for $%d", chickenConfig.displayName, totalCost)
    or string.format("Purchased %dx %s for $%d", amount, chickenConfig.displayName, totalCost)

  return {
    success = true,
    message = message,
    newBalance = playerData.money,
    itemId = firstChickenId,
  }
end

-- Check if player can afford a chicken
function Store.canAffordChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenType: string
): boolean
  local price = Store.getChickenPrice(chickenType)
  if price == 0 then
    return false
  end
  return playerData.money >= price
end

-- Sell an egg from inventory
function Store.sellEgg(playerData: PlayerData.PlayerDataSchema, eggId: string): TransactionResult
  -- Find egg in inventory
  local eggIndex, egg = findEggById(playerData, eggId)
  if not eggIndex or not egg then
    return {
      success = false,
      message = "Egg not found in inventory",
      newBalance = playerData.money,
    }
  end

  -- Get egg config for sell price
  local eggConfig = EggConfig.get(egg.eggType)
  if not eggConfig then
    return {
      success = false,
      message = "Invalid egg type in inventory",
      newBalance = playerData.money,
    }
  end

  local sellPrice = eggConfig.sellPrice

  -- Remove egg from inventory
  table.remove(playerData.inventory.eggs, eggIndex)

  -- Add money
  playerData.money = playerData.money + sellPrice

  return {
    success = true,
    message = string.format("Sold %s for $%d", eggConfig.displayName, sellPrice),
    newBalance = playerData.money,
    itemId = eggId,
  }
end

-- Sell a chicken (from inventory or placed)
function Store.sellChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): TransactionResult
  -- Try to find in inventory first
  local chickenIndex, chicken = findChickenInInventoryById(playerData, chickenId)
  local isPlaced = false

  if not chickenIndex or not chicken then
    -- Try placed chickens
    chickenIndex, chicken = findPlacedChickenById(playerData, chickenId)
    isPlaced = true
  end

  if not chickenIndex or not chicken then
    return {
      success = false,
      message = "Chicken not found",
      newBalance = playerData.money,
    }
  end

  -- Get chicken config for value calculation
  local chickenConfig = ChickenConfig.get(chicken.chickenType)
  if not chickenConfig then
    return {
      success = false,
      message = "Invalid chicken type",
      newBalance = playerData.money,
    }
  end

  local sellPrice = Store.getChickenValue(chicken.chickenType)

  -- Also add any accumulated money from the chicken
  local accumulatedMoney = chicken.accumulatedMoney or 0
  local totalValue = sellPrice + math.floor(accumulatedMoney)

  -- Remove chicken from appropriate list
  if isPlaced then
    table.remove(playerData.placedChickens, chickenIndex)
  else
    table.remove(playerData.inventory.chickens, chickenIndex)
  end

  -- Add money
  playerData.money = playerData.money + totalValue

  local message = accumulatedMoney > 0
      and string.format(
        "Sold %s for $%d (+$%d accumulated)",
        chickenConfig.displayName,
        sellPrice,
        math.floor(accumulatedMoney)
      )
    or string.format("Sold %s for $%d", chickenConfig.displayName, sellPrice)

  return {
    success = true,
    message = message,
    newBalance = playerData.money,
    itemId = chickenId,
  }
end

-- Find a trapped predator by ID
local function findTrappedPredator(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): (number?, any?)
  for i, trap in ipairs(playerData.traps) do
    if trap.id == trapId and trap.caughtPredator then
      return i, trap
    end
  end
  return nil, nil
end

-- Get sell price for a predator type
function Store.getPredatorValue(predatorType: string): number
  return PREDATOR_SELL_PRICES[predatorType] or 100
end

-- Sell a trapped predator
function Store.sellPredator(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): TransactionResult
  -- Find trap with caught predator
  local trapIndex, trap = findTrappedPredator(playerData, trapId)
  if not trapIndex or not trap then
    return {
      success = false,
      message = "No trapped predator found at this trap",
      newBalance = playerData.money,
    }
  end

  local predatorType = trap.caughtPredator
  local sellPrice = Store.getPredatorValue(predatorType)

  -- Clear the caught predator from the trap (trap remains)
  trap.caughtPredator = nil

  -- Add money
  playerData.money = playerData.money + sellPrice

  return {
    success = true,
    message = string.format("Sold trapped %s for $%d", predatorType, sellPrice),
    newBalance = playerData.money,
    itemId = trapId,
  }
end

-- Get all available eggs for purchase
function Store.getAvailableEggs(): { StoreItem }
  local items = {}
  for eggType, config in pairs(EggConfig.getAll()) do
    table.insert(items, {
      itemType = "egg",
      id = eggType,
      name = config.name,
      displayName = config.displayName,
      rarity = config.rarity,
      price = config.purchasePrice,
      sellPrice = config.sellPrice,
    })
  end
  -- Sort by price
  table.sort(items, function(a, b)
    return a.price < b.price
  end)
  return items
end

-- Get all available chickens for purchase
function Store.getAvailableChickens(): { StoreItem }
  local items = {}
  for chickenType, config in pairs(ChickenConfig.getAll()) do
    local price = Store.getChickenPrice(chickenType)
    local sellPrice = Store.getChickenValue(chickenType)
    table.insert(items, {
      itemType = "chicken",
      id = chickenType,
      name = config.name,
      displayName = config.displayName,
      rarity = config.rarity,
      price = price,
      sellPrice = sellPrice,
    })
  end
  -- Sort by price
  table.sort(items, function(a, b)
    return a.price < b.price
  end)
  return items
end

-- Check if player can afford an egg
function Store.canAffordEgg(playerData: PlayerData.PlayerDataSchema, eggType: string): boolean
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return false
  end
  return playerData.money >= eggConfig.purchasePrice
end

-- Get the price of an egg type
function Store.getEggPrice(eggType: string): number?
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return nil
  end
  return eggConfig.purchasePrice
end

-- Get the sell price of an egg type
function Store.getEggSellPrice(eggType: string): number?
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return nil
  end
  return eggConfig.sellPrice
end

-- Sell multiple eggs of the same type
function Store.sellEggsByType(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string,
  quantity: number?
): TransactionResult
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return {
      success = false,
      message = "Invalid egg type: " .. tostring(eggType),
      newBalance = playerData.money,
    }
  end

  -- Find matching eggs
  local matchingEggs = {}
  for i, egg in ipairs(playerData.inventory.eggs) do
    if egg.eggType == eggType then
      table.insert(matchingEggs, { index = i, egg = egg })
    end
  end

  if #matchingEggs == 0 then
    return {
      success = false,
      message = "No eggs of type " .. eggConfig.displayName .. " in inventory",
      newBalance = playerData.money,
    }
  end

  -- Determine how many to sell
  local toSell = quantity or #matchingEggs
  if toSell > #matchingEggs then
    toSell = #matchingEggs
  end
  if toSell < 1 then
    return {
      success = false,
      message = "Quantity must be at least 1",
      newBalance = playerData.money,
    }
  end

  local sellPrice = eggConfig.sellPrice
  local totalValue = sellPrice * toSell

  -- Remove eggs from inventory (in reverse order to preserve indices)
  local eggsToRemove = {}
  for i = 1, toSell do
    table.insert(eggsToRemove, matchingEggs[i].index)
  end
  table.sort(eggsToRemove, function(a, b)
    return a > b
  end)
  for _, idx in ipairs(eggsToRemove) do
    table.remove(playerData.inventory.eggs, idx)
  end

  -- Add money
  playerData.money = playerData.money + totalValue

  local message = toSell == 1
      and string.format("Sold %s for $%d", eggConfig.displayName, totalValue)
    or string.format("Sold %dx %s for $%d", toSell, eggConfig.displayName, totalValue)

  return {
    success = true,
    message = message,
    newBalance = playerData.money,
  }
end

-- Get inventory value summary
function Store.getInventoryValue(playerData: PlayerData.PlayerDataSchema): {
  eggsValue: number,
  chickensValue: number,
  totalValue: number,
}
  local eggsValue = 0
  local chickensValue = 0

  -- Calculate egg values
  for _, egg in ipairs(playerData.inventory.eggs) do
    local config = EggConfig.get(egg.eggType)
    if config then
      eggsValue = eggsValue + config.sellPrice
    end
  end

  -- Calculate inventory chicken values
  for _, chicken in ipairs(playerData.inventory.chickens) do
    chickensValue = chickensValue + Store.getChickenValue(chicken.chickenType)
    chickensValue = chickensValue + math.floor(chicken.accumulatedMoney or 0)
  end

  -- Calculate placed chicken values
  for _, chicken in ipairs(playerData.placedChickens) do
    chickensValue = chickensValue + Store.getChickenValue(chicken.chickenType)
    chickensValue = chickensValue + math.floor(chicken.accumulatedMoney or 0)
  end

  return {
    eggsValue = eggsValue,
    chickensValue = chickensValue,
    totalValue = eggsValue + chickensValue,
  }
end

-- Initialize store inventory with stock based on rarity
function Store.initializeInventory(): StoreInventory
  local inventory: StoreInventory = {
    eggs = {},
    chickens = {},
    lastReplenishTime = os.time(),
  }

  -- Add all egg types with stock based on rarity
  for eggType, config in pairs(EggConfig.getAll()) do
    local stockQuantity = RARITY_STOCK_QUANTITIES[config.rarity] or 0
    local robuxPrice = RARITY_ROBUX_PRICES[config.rarity] or 5
    inventory.eggs[eggType] = {
      itemType = "egg",
      id = eggType,
      name = config.name,
      displayName = config.displayName,
      rarity = config.rarity,
      price = config.purchasePrice,
      sellPrice = config.sellPrice,
      stock = stockQuantity,
      maxStock = stockQuantity,
      robuxPrice = robuxPrice,
    }
  end

  -- Add all chicken types with stock based on rarity
  for chickenType, config in pairs(ChickenConfig.getAll()) do
    local stockQuantity = RARITY_STOCK_QUANTITIES[config.rarity] or 0
    local price = Store.getChickenPrice(chickenType)
    local sellPrice = Store.getChickenValue(chickenType)
    local robuxPrice = RARITY_ROBUX_PRICES[config.rarity] or 5
    inventory.chickens[chickenType] = {
      itemType = "chicken",
      id = chickenType,
      name = config.name,
      displayName = config.displayName,
      rarity = config.rarity,
      price = price,
      sellPrice = sellPrice,
      stock = stockQuantity,
      maxStock = stockQuantity,
      robuxPrice = robuxPrice,
    }
  end

  storeInventory = inventory
  return inventory
end

-- Get the current store inventory (initializes if needed)
function Store.getStoreInventory(): StoreInventory
  if not storeInventory then
    storeInventory = Store.initializeInventory()
  end
  return storeInventory
end

-- Set store inventory (for server sync)
function Store.setStoreInventory(inventory: StoreInventory)
  storeInventory = inventory
end

-- Check if an item is in stock
function Store.isInStock(itemType: "egg" | "chicken", itemId: string): boolean
  local inventory = Store.getStoreInventory()
  if itemType == "egg" then
    local item = inventory.eggs[itemId]
    return item ~= nil and item.stock > 0
  else
    local item = inventory.chickens[itemId]
    return item ~= nil and item.stock > 0
  end
end

-- Get remaining stock for an item
function Store.getStock(itemType: "egg" | "chicken", itemId: string): number
  local inventory = Store.getStoreInventory()
  if itemType == "egg" then
    local item = inventory.eggs[itemId]
    return item and item.stock or 0
  else
    local item = inventory.chickens[itemId]
    return item and item.stock or 0
  end
end

-- Purchase an egg from inventory (decrements stock)
function Store.purchaseEggFromInventory(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string,
  quantity: number?
): TransactionResult
  local amount = quantity or 1

  -- Check if in stock
  if not Store.isInStock("egg", eggType) then
    return {
      success = false,
      message = "Item is sold out",
      newBalance = playerData.money,
    }
  end

  local inventory = Store.getStoreInventory()
  local item = inventory.eggs[eggType]

  -- Check sufficient stock
  if item.stock < amount then
    return {
      success = false,
      message = string.format("Only %d in stock", item.stock),
      newBalance = playerData.money,
    }
  end

  -- Attempt purchase using existing buyEgg function
  local result = Store.buyEgg(playerData, eggType, amount)

  -- Decrement stock on success
  if result.success then
    item.stock = item.stock - amount
    -- Ensure Common eggs never sell out completely
    -- Basic egg should always be available for new players
    if item.rarity == "Common" and item.stock < 1 then
      item.stock = 1
    end
  end

  return result
end

-- Purchase a chicken from inventory (decrements stock)
function Store.purchaseChickenFromInventory(
  playerData: PlayerData.PlayerDataSchema,
  chickenType: string,
  quantity: number?
): TransactionResult
  local amount = quantity or 1

  -- Check if in stock
  if not Store.isInStock("chicken", chickenType) then
    return {
      success = false,
      message = "Item is sold out",
      newBalance = playerData.money,
    }
  end

  local inventory = Store.getStoreInventory()
  local item = inventory.chickens[chickenType]

  -- Check sufficient stock
  if item.stock < amount then
    return {
      success = false,
      message = string.format("Only %d in stock", item.stock),
      newBalance = playerData.money,
    }
  end

  -- Attempt purchase using existing buyChicken function
  local result = Store.buyChicken(playerData, chickenType, amount)

  -- Decrement stock on success
  if result.success then
    item.stock = item.stock - amount
  end

  return result
end

-- Purchase an egg with Robux (bypasses money check, adds directly to inventory)
function Store.purchaseEggWithRobux(
  playerData: PlayerData.PlayerDataSchema,
  eggType: string
): TransactionResult
  -- Validate egg type
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return {
      success = false,
      message = "Invalid egg type: " .. tostring(eggType),
      newBalance = playerData.money,
    }
  end

  -- Add egg to inventory (no money deduction for Robux purchase)
  local eggId = PlayerData.generateId()
  table.insert(playerData.inventory.eggs, {
    id = eggId,
    eggType = eggType,
    rarity = eggConfig.rarity,
  })

  return {
    success = true,
    message = string.format("Purchased %s with Robux", eggConfig.displayName),
    newBalance = playerData.money,
    itemId = eggId,
  }
end

-- Purchase a chicken with Robux (bypasses money check, adds directly to inventory)
function Store.purchaseChickenWithRobux(
  playerData: PlayerData.PlayerDataSchema,
  chickenType: string
): TransactionResult
  -- Validate chicken type
  local chickenConfig = ChickenConfig.get(chickenType)
  if not chickenConfig then
    return {
      success = false,
      message = "Invalid chicken type: " .. tostring(chickenType),
      newBalance = playerData.money,
    }
  end

  -- Add chicken to inventory (no money deduction for Robux purchase)
  local chickenId = PlayerData.generateId()
  table.insert(playerData.inventory.chickens, {
    id = chickenId,
    chickenType = chickenType,
    rarity = chickenConfig.rarity,
    accumulatedMoney = 0,
  })

  return {
    success = true,
    message = string.format("Purchased %s with Robux", chickenConfig.displayName),
    newBalance = playerData.money,
    itemId = chickenId,
  }
end

-- Get available eggs with stock info
function Store.getAvailableEggsWithStock(): { InventoryItem }
  local inventory = Store.getStoreInventory()
  local items = {}
  for _, item in pairs(inventory.eggs) do
    table.insert(items, item)
  end
  -- Sort by price
  table.sort(items, function(a, b)
    return a.price < b.price
  end)
  return items
end

-- Get available chickens with stock info
function Store.getAvailableChickensWithStock(): { InventoryItem }
  local inventory = Store.getStoreInventory()
  local items = {}
  for _, item in pairs(inventory.chickens) do
    table.insert(items, item)
  end
  -- Sort by price
  table.sort(items, function(a, b)
    return a.price < b.price
  end)
  return items
end

-- Get stock quantity for a rarity
function Store.getStockForRarity(rarity: string): number
  return RARITY_STOCK_QUANTITIES[rarity] or 0
end

-- Get Robux price for a rarity
function Store.getRobuxPriceForRarity(rarity: string): number
  return RARITY_ROBUX_PRICES[rarity] or 5
end

-- Get the replenish interval in seconds
function Store.getReplenishInterval(): number
  return REPLENISH_INTERVAL
end

-- Check if store needs replenishing
function Store.needsReplenish(): boolean
  local inventory = Store.getStoreInventory()
  local currentTime = os.time()
  return (currentTime - inventory.lastReplenishTime) >= REPLENISH_INTERVAL
end

-- Get time until next replenish in seconds
function Store.getTimeUntilReplenish(): number
  local inventory = Store.getStoreInventory()
  local currentTime = os.time()
  local elapsed = currentTime - inventory.lastReplenishTime
  local remaining = REPLENISH_INTERVAL - elapsed
  return math.max(0, remaining)
end

-- Weighted random selection helper
local function selectWeightedRarity(): string
  local totalWeight = 0
  for _, weight in pairs(RARITY_WEIGHTS) do
    totalWeight = totalWeight + weight
  end

  local roll = math.random() * totalWeight
  local cumulative = 0

  for rarity, weight in pairs(RARITY_WEIGHTS) do
    cumulative = cumulative + weight
    if roll <= cumulative then
      return rarity
    end
  end

  return "Common" -- Fallback
end

-- Replenish store inventory with new stock
-- Resets all items to their max stock based on rarity weights
function Store.replenishStore(): StoreInventory
  local inventory = Store.getStoreInventory()
  local currentTime = os.time()

  -- Replenish eggs - restore stock based on rarity
  for eggType, item in pairs(inventory.eggs) do
    local baseStock = RARITY_STOCK_QUANTITIES[item.rarity] or 0
    -- Add some randomness: 50% to 100% of base stock
    local minStock = math.max(1, math.floor(baseStock * 0.5))
    local newStock = math.random(minStock, baseStock)
    -- Mythic has chance to get 0-1
    if item.rarity == "Mythic" then
      newStock = math.random(0, 1)
    end
    item.stock = newStock
    item.maxStock = baseStock
  end

  -- Replenish chickens - restore stock based on rarity
  for chickenType, item in pairs(inventory.chickens) do
    local baseStock = RARITY_STOCK_QUANTITIES[item.rarity] or 0
    -- Add some randomness: 50% to 100% of base stock
    local minStock = math.max(1, math.floor(baseStock * 0.5))
    local newStock = math.random(minStock, baseStock)
    -- Mythic has chance to get 0-1
    if item.rarity == "Mythic" then
      newStock = math.random(0, 1)
    end
    item.stock = newStock
    item.maxStock = baseStock
  end

  -- Update timestamp
  inventory.lastReplenishTime = currentTime

  return inventory
end

-- Force replenish (for Robux purchase or testing)
function Store.forceReplenish(): StoreInventory
  return Store.replenishStore()
end

-- Trap/Supply store functions

-- Supply item type for store display
export type SupplyItem = {
  itemType: "trap",
  id: string,
  name: string,
  displayName: string,
  tier: string,
  price: number,
  sellPrice: number,
  description: string,
  robuxPrice: number,
}

-- Robux prices for traps by tier
local TRAP_TIER_ROBUX_PRICES: { [string]: number } = {
  Basic = 10,
  Improved = 25,
  Advanced = 75,
  Expert = 200,
  Master = 600,
  Ultimate = 1500,
}

-- Get all available traps for purchase (sorted by tier then price)
function Store.getAvailableTraps(): { SupplyItem }
  local items: { SupplyItem } = {}
  for trapType, config in pairs(TrapConfig.getAll()) do
    local robuxPrice = TRAP_TIER_ROBUX_PRICES[config.tier] or 10
    table.insert(items, {
      itemType = "trap",
      id = trapType,
      name = config.name,
      displayName = config.displayName,
      tier = config.tier,
      price = config.price,
      sellPrice = config.sellPrice,
      description = config.description,
      robuxPrice = robuxPrice,
    })
  end
  -- Sort by tier level then price
  table.sort(items, function(a, b)
    local aTier = TrapConfig.getTierLevel(a.tier :: TrapConfig.TrapTier)
    local bTier = TrapConfig.getTierLevel(b.tier :: TrapConfig.TrapTier)
    if aTier ~= bTier then
      return aTier < bTier
    end
    return a.price < b.price
  end)
  return items
end

-- Buy a trap from the store
function Store.buyTrap(playerData: PlayerData.PlayerDataSchema, trapType: string): TransactionResult
  -- Validate trap type
  local trapConfig = TrapConfig.get(trapType)
  if not trapConfig then
    return {
      success = false,
      message = "Invalid trap type: " .. tostring(trapType),
      newBalance = playerData.money,
    }
  end

  local price = trapConfig.price

  -- Check if player can afford
  if playerData.money < price then
    return {
      success = false,
      message = string.format(
        "Insufficient funds. Need $%d but only have $%d",
        price,
        math.floor(playerData.money)
      ),
      newBalance = playerData.money,
    }
  end

  -- Check placement limit (player can't have more than maxPlacement of this type)
  local currentCount = 0
  for _, trap in ipairs(playerData.traps) do
    if trap.trapType == trapType then
      currentCount = currentCount + 1
    end
  end

  if currentCount >= trapConfig.maxPlacement then
    return {
      success = false,
      message = string.format(
        "Maximum placement limit reached (%d/%d)",
        currentCount,
        trapConfig.maxPlacement
      ),
      newBalance = playerData.money,
    }
  end

  -- Deduct money
  playerData.money = playerData.money - price

  -- Add trap to player's traps list (unplaced, spotIndex = -1)
  local trapId = PlayerData.generateId()
  table.insert(playerData.traps, {
    id = trapId,
    trapType = trapType,
    tier = trapConfig.tierLevel,
    spotIndex = -1, -- Not placed yet
    cooldownEndTime = nil,
    caughtPredator = nil,
  })

  return {
    success = true,
    message = string.format("Purchased %s for $%d", trapConfig.displayName, price),
    newBalance = playerData.money,
    itemId = trapId,
  }
end

-- Buy a trap with Robux (bypasses money check)
function Store.buyTrapWithRobux(
  playerData: PlayerData.PlayerDataSchema,
  trapType: string
): TransactionResult
  -- Validate trap type
  local trapConfig = TrapConfig.get(trapType)
  if not trapConfig then
    return {
      success = false,
      message = "Invalid trap type: " .. tostring(trapType),
      newBalance = playerData.money,
    }
  end

  -- Check placement limit
  local currentCount = 0
  for _, trap in ipairs(playerData.traps) do
    if trap.trapType == trapType then
      currentCount = currentCount + 1
    end
  end

  if currentCount >= trapConfig.maxPlacement then
    return {
      success = false,
      message = string.format(
        "Maximum placement limit reached (%d/%d)",
        currentCount,
        trapConfig.maxPlacement
      ),
      newBalance = playerData.money,
    }
  end

  -- Add trap to player's traps list (unplaced)
  local trapId = PlayerData.generateId()
  table.insert(playerData.traps, {
    id = trapId,
    trapType = trapType,
    tier = trapConfig.tierLevel,
    spotIndex = -1,
    cooldownEndTime = nil,
    caughtPredator = nil,
  })

  return {
    success = true,
    message = string.format("Purchased %s with Robux", trapConfig.displayName),
    newBalance = playerData.money,
    itemId = trapId,
  }
end

-- Sell a trap
function Store.sellTrap(playerData: PlayerData.PlayerDataSchema, trapId: string): TransactionResult
  -- Find trap in player's traps
  local trapIndex: number? = nil
  local trap: PlayerData.TrapData? = nil
  for i, t in ipairs(playerData.traps) do
    if t.id == trapId then
      trapIndex = i
      trap = t
      break
    end
  end

  if not trapIndex or not trap then
    return {
      success = false,
      message = "Trap not found",
      newBalance = playerData.money,
    }
  end

  -- Can't sell trap with caught predator
  if trap.caughtPredator then
    return {
      success = false,
      message = "Cannot sell trap with caught predator. Sell the predator first.",
      newBalance = playerData.money,
    }
  end

  -- Get trap config for sell price
  local trapConfig = TrapConfig.get(trap.trapType)
  if not trapConfig then
    return {
      success = false,
      message = "Invalid trap type",
      newBalance = playerData.money,
    }
  end

  local sellPrice = trapConfig.sellPrice

  -- Remove trap
  table.remove(playerData.traps, trapIndex)

  -- Add money
  playerData.money = playerData.money + sellPrice

  return {
    success = true,
    message = string.format("Sold %s for $%d", trapConfig.displayName, sellPrice),
    newBalance = playerData.money,
    itemId = trapId,
  }
end

-- Get Robux price for a trap tier
function Store.getTrapRobuxPrice(tier: string): number
  return TRAP_TIER_ROBUX_PRICES[tier] or 10
end

-- Check if player can afford a trap
function Store.canAffordTrap(playerData: PlayerData.PlayerDataSchema, trapType: string): boolean
  local trapConfig = TrapConfig.get(trapType)
  if not trapConfig then
    return false
  end
  return playerData.money >= trapConfig.price
end

return Store
