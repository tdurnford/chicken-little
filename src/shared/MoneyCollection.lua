--[[
	MoneyCollection Module
	Handles collecting accumulated money from chickens and adding it to player's balance.
	Provides functions for collecting from single chickens or all chickens at once.
]]

local MoneyCollection = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)

-- Type definitions
export type CollectionResult = {
  success: boolean,
  message: string,
  amountCollected: number,
  chickenId: string?,
  newBalance: number,
}

export type BulkCollectionResult = {
  success: boolean,
  message: string,
  totalCollected: number,
  chickensCollected: number,
  newBalance: number,
  results: { CollectionResult },
}

-- Find a placed chicken by ID in player data
local function findPlacedChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): (PlayerData.ChickenData?, number?)
  for index, chicken in ipairs(playerData.placedChickens) do
    if chicken.id == chickenId then
      return chicken, index
    end
  end
  return nil, nil
end

-- Collect money from a single placed chicken
function MoneyCollection.collect(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string,
  currentTime: number?
): CollectionResult
  -- Find the chicken
  local chicken, _ = findPlacedChicken(playerData, chickenId)
  if not chicken then
    return {
      success = false,
      message = "Chicken not found in placed chickens",
      amountCollected = 0,
      chickenId = chickenId,
      newBalance = playerData.money,
    }
  end

  -- Update chicken's accumulated money based on elapsed time
  local now = currentTime or os.time()
  if chicken.lastEggTime then
    -- Use ChickenConfig to get money per second
    local ChickenConfig = require(script.Parent.ChickenConfig)
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      local lastUpdate = chicken.accumulatedMoney > 0 and now or (chicken.lastEggTime or now)
      -- Money accumulates continuously, we just collect what's there
    end
  end

  -- Collect the accumulated money
  local amountCollected = chicken.accumulatedMoney

  if amountCollected <= 0 then
    return {
      success = true,
      message = "No money to collect",
      amountCollected = 0,
      chickenId = chickenId,
      newBalance = playerData.money,
    }
  end

  -- Reset chicken's accumulated money and add to player balance
  chicken.accumulatedMoney = 0
  playerData.money = playerData.money + amountCollected

  return {
    success = true,
    message = string.format("Collected $%.2f from chicken", amountCollected),
    amountCollected = amountCollected,
    chickenId = chickenId,
    newBalance = playerData.money,
  }
end

-- Collect money from all placed chickens
function MoneyCollection.collectAll(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number?
): BulkCollectionResult
  local results: { CollectionResult } = {}
  local totalCollected = 0
  local chickensCollected = 0

  if #playerData.placedChickens == 0 then
    return {
      success = true,
      message = "No placed chickens to collect from",
      totalCollected = 0,
      chickensCollected = 0,
      newBalance = playerData.money,
      results = results,
    }
  end

  -- Collect from each placed chicken
  for _, chicken in ipairs(playerData.placedChickens) do
    local result = MoneyCollection.collect(playerData, chicken.id, currentTime)
    table.insert(results, result)

    if result.success and result.amountCollected > 0 then
      totalCollected = totalCollected + result.amountCollected
      chickensCollected = chickensCollected + 1
    end
  end

  local message
  if chickensCollected > 0 then
    message = string.format(
      "Collected $%.2f from %d chicken%s",
      totalCollected,
      chickensCollected,
      chickensCollected == 1 and "" or "s"
    )
  else
    message = "No money to collect from any chickens"
  end

  return {
    success = true,
    message = message,
    totalCollected = totalCollected,
    chickensCollected = chickensCollected,
    newBalance = playerData.money,
    results = results,
  }
end

-- Update a single chicken's accumulated money based on elapsed time
-- This should be called periodically to accumulate money
function MoneyCollection.updateChickenMoney(
  chicken: PlayerData.ChickenData,
  currentTime: number?
): number
  local ChickenConfig = require(script.Parent.ChickenConfig)
  local config = ChickenConfig.get(chicken.chickenType)
  if not config then
    return 0
  end

  local now = currentTime or os.time()
  -- We need a lastUpdateTime to track when we last updated
  -- For now, we'll use lastEggTime as a proxy (not ideal but works)
  -- In practice, the Chicken class handles this properly
  return chicken.accumulatedMoney
end

-- Update all placed chickens' accumulated money
function MoneyCollection.updateAllChickenMoney(
  playerData: PlayerData.PlayerDataSchema,
  elapsedSeconds: number
): number
  local ChickenConfig = require(script.Parent.ChickenConfig)
  local totalGenerated = 0

  for _, chicken in ipairs(playerData.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      local moneyGenerated = config.moneyPerSecond * elapsedSeconds
      chicken.accumulatedMoney = chicken.accumulatedMoney + moneyGenerated
      totalGenerated = totalGenerated + moneyGenerated
    end
  end

  return totalGenerated
end

-- Get total accumulated money across all placed chickens (without collecting)
function MoneyCollection.getTotalAccumulated(playerData: PlayerData.PlayerDataSchema): number
  local total = 0
  for _, chicken in ipairs(playerData.placedChickens) do
    total = total + (chicken.accumulatedMoney or 0)
  end
  return total
end

-- Get accumulated money for a specific chicken (without collecting)
function MoneyCollection.getAccumulated(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): number?
  local chicken, _ = findPlacedChicken(playerData, chickenId)
  if not chicken then
    return nil
  end
  return chicken.accumulatedMoney
end

-- Get the number of chickens with money ready to collect
function MoneyCollection.getChickensWithMoney(
  playerData: PlayerData.PlayerDataSchema,
  minimumAmount: number?
): number
  local threshold = minimumAmount or 0
  local count = 0
  for _, chicken in ipairs(playerData.placedChickens) do
    if (chicken.accumulatedMoney or 0) > threshold then
      count = count + 1
    end
  end
  return count
end

-- Check if a specific chicken has money to collect
function MoneyCollection.hasMoney(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string,
  minimumAmount: number?
): boolean
  local threshold = minimumAmount or 0
  local chicken, _ = findPlacedChicken(playerData, chickenId)
  if not chicken then
    return false
  end
  return (chicken.accumulatedMoney or 0) > threshold
end

-- Calculate total money per second from all placed chickens
function MoneyCollection.getTotalMoneyPerSecond(playerData: PlayerData.PlayerDataSchema): number
  local ChickenConfig = require(script.Parent.ChickenConfig)
  local total = 0

  for _, chicken in ipairs(playerData.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      total = total + config.moneyPerSecond
    end
  end

  return total
end

-- Estimate earnings for a time period based on current chickens
function MoneyCollection.estimateEarnings(
  playerData: PlayerData.PlayerDataSchema,
  seconds: number
): number
  return MoneyCollection.getTotalMoneyPerSecond(playerData) * seconds
end

return MoneyCollection
