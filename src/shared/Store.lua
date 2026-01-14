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

-- Sell price multiplier for chickens (percentage of equivalent value)
local CHICKEN_SELL_MULTIPLIER = 0.5

-- Base price per money-per-second for chicken value calculation
local CHICKEN_VALUE_PER_MPS = 60

-- Chicken purchase price multiplier (higher than sell value for profit margin)
local CHICKEN_PURCHASE_MULTIPLIER = 2.0

-- Predator sell prices by tier (placeholder until PredatorConfig exists)
local PREDATOR_SELL_PRICES: { [string]: number } = {
  Fox = 500,
  Wolf = 2000,
  Bear = 10000,
  Dragon = 100000,
}

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

return Store
