--[[
	OfflineEarnings Module
	Calculates and awards money and eggs earned while player was offline.
	Includes caps to prevent excessive offline gains.
]]

local OfflineEarnings = {}

-- Import dependencies
local ChickenConfig = require(script.Parent.ChickenConfig)
local EggConfig = require(script.Parent.EggConfig)
local PlayerData = require(script.Parent.PlayerData)

-- Configuration
local MAX_OFFLINE_HOURS = 24
local OFFLINE_EARNINGS_RATE = 0.5 -- 50% of normal earnings while offline
local MAX_OFFLINE_EGGS_PER_CHICKEN = 10 -- Cap eggs per chicken while offline

-- Type definitions
export type EggEarned = {
  eggType: string,
  rarity: string,
  chickenId: string,
  chickenType: string,
}

export type ChickenEarnings = {
  chickenId: string,
  chickenType: string,
  displayName: string,
  rarity: string,
  moneyEarned: number,
  eggsLaid: { EggEarned },
}

export type OfflineEarningsResult = {
  totalMoney: number,
  cappedMoney: number,
  totalEggs: number,
  cappedEggs: number,
  elapsedSeconds: number,
  cappedSeconds: number,
  wasCapped: boolean,
  moneyPerChicken: { ChickenEarnings },
  eggsEarned: { EggEarned },
}

export type ApplyResult = {
  success: boolean,
  message: string,
  moneyAdded: number,
  eggsAdded: number,
  updatedData: PlayerData.PlayerDataSchema?,
}

-- Get configuration values
function OfflineEarnings.getConfig(): {
  maxOfflineHours: number,
  offlineEarningsRate: number,
  maxOfflineEggsPerChicken: number,
}
  return {
    maxOfflineHours = MAX_OFFLINE_HOURS,
    offlineEarningsRate = OFFLINE_EARNINGS_RATE,
    maxOfflineEggsPerChicken = MAX_OFFLINE_EGGS_PER_CHICKEN,
  }
end

-- Calculate offline earnings without applying them
function OfflineEarnings.calculate(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): OfflineEarningsResult
  local lastLogout = data.lastLogoutTime or currentTime
  local elapsedSeconds = math.max(0, currentTime - lastLogout)

  -- Cap offline time
  local maxOfflineSeconds = MAX_OFFLINE_HOURS * 3600
  local cappedSeconds = math.min(elapsedSeconds, maxOfflineSeconds)
  local wasCapped = elapsedSeconds > maxOfflineSeconds

  local totalMoney = 0
  local cappedMoney = 0
  local totalEggs = 0
  local cappedEggs = 0
  local moneyPerChicken: { ChickenEarnings } = {}
  local allEggsEarned: { EggEarned } = {}

  -- Calculate earnings from each placed chicken
  for _, chicken in ipairs(data.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      -- Calculate money for this chicken
      local fullMoney = config.moneyPerSecond * elapsedSeconds * OFFLINE_EARNINGS_RATE
      local capped = config.moneyPerSecond * cappedSeconds * OFFLINE_EARNINGS_RATE
      totalMoney = totalMoney + fullMoney
      cappedMoney = cappedMoney + capped

      -- Calculate eggs laid while offline
      local timeSinceLastEgg = currentTime - (chicken.lastEggTime or lastLogout)
      local eggInterval = config.eggLayIntervalSeconds

      -- Use capped time for egg calculation
      local effectiveTime = math.min(timeSinceLastEgg, cappedSeconds)
      local eggsLaidCount = math.floor(effectiveTime / eggInterval)

      -- Cap eggs per chicken
      local cappedEggsCount = math.min(eggsLaidCount, MAX_OFFLINE_EGGS_PER_CHICKEN)

      local chickenEggs: { EggEarned } = {}
      if cappedEggsCount > 0 and #config.eggsLaid > 0 then
        for _ = 1, cappedEggsCount do
          -- Select egg type from chicken's possible eggs
          local eggType = config.eggsLaid[math.random(1, #config.eggsLaid)]
          local eggConfig = EggConfig.get(eggType)

          local eggData: EggEarned = {
            eggType = eggType,
            rarity = eggConfig and eggConfig.rarity or "Common",
            chickenId = chicken.id,
            chickenType = chicken.chickenType,
          }

          table.insert(chickenEggs, eggData)
          table.insert(allEggsEarned, eggData)
        end
      end

      totalEggs = totalEggs + eggsLaidCount
      cappedEggs = cappedEggs + cappedEggsCount

      table.insert(moneyPerChicken, {
        chickenId = chicken.id,
        chickenType = chicken.chickenType,
        displayName = config.displayName,
        rarity = config.rarity,
        moneyEarned = capped,
        eggsLaid = chickenEggs,
      })
    end
  end

  return {
    totalMoney = totalMoney,
    cappedMoney = cappedMoney,
    totalEggs = totalEggs,
    cappedEggs = cappedEggs,
    elapsedSeconds = elapsedSeconds,
    cappedSeconds = cappedSeconds,
    wasCapped = wasCapped,
    moneyPerChicken = moneyPerChicken,
    eggsEarned = allEggsEarned,
  }
end

-- Apply offline earnings to player data
function OfflineEarnings.apply(
  data: PlayerData.PlayerDataSchema,
  earnings: OfflineEarningsResult
): ApplyResult
  if earnings.cappedMoney <= 0 and #earnings.eggsEarned == 0 then
    return {
      success = true,
      message = "No offline earnings to apply",
      moneyAdded = 0,
      eggsAdded = 0,
      updatedData = data,
    }
  end

  -- Apply money
  data.money = data.money + earnings.cappedMoney

  -- Add eggs to inventory
  local eggsAdded = 0
  for _, egg in ipairs(earnings.eggsEarned) do
    local newEgg: PlayerData.EggData = {
      id = PlayerData.generateId(),
      eggType = egg.eggType,
      rarity = egg.rarity,
    }
    table.insert(data.inventory.eggs, newEgg)
    eggsAdded = eggsAdded + 1
  end

  -- Update chicken last egg times
  local currentTime = os.time()
  for _, chicken in ipairs(data.placedChickens) do
    -- Reset egg timer based on partial time remaining
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      local timeSinceLastEgg = currentTime - (chicken.lastEggTime or 0)
      local eggInterval = config.eggLayIntervalSeconds
      local eggsLaid = math.floor(timeSinceLastEgg / eggInterval)

      if eggsLaid > 0 then
        -- Set last egg time to current time minus remainder
        local remainder = timeSinceLastEgg % eggInterval
        chicken.lastEggTime = currentTime - remainder
      end
    end
  end

  return {
    success = true,
    message = string.format(
      "Applied $%.2f and %d eggs from offline earnings",
      earnings.cappedMoney,
      eggsAdded
    ),
    moneyAdded = earnings.cappedMoney,
    eggsAdded = eggsAdded,
    updatedData = data,
  }
end

-- Calculate and apply offline earnings in one call
function OfflineEarnings.calculateAndApply(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): (OfflineEarningsResult, ApplyResult)
  local earnings = OfflineEarnings.calculate(data, currentTime)
  local applyResult = OfflineEarnings.apply(data, earnings)
  return earnings, applyResult
end

-- Check if player has any offline earnings pending
function OfflineEarnings.hasEarnings(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): boolean
  if not data.lastLogoutTime then
    return false
  end

  local elapsedSeconds = currentTime - data.lastLogoutTime
  if elapsedSeconds < 60 then -- Minimum 1 minute to count
    return false
  end

  -- Check if there are placed chickens
  return #data.placedChickens > 0
end

-- Get a summary of potential offline earnings (for UI preview)
function OfflineEarnings.getPreview(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): {
  hasPendingEarnings: boolean,
  estimatedMoney: number,
  estimatedEggs: number,
  offlineHours: number,
  placedChickenCount: number,
}
  if not OfflineEarnings.hasEarnings(data, currentTime) then
    return {
      hasPendingEarnings = false,
      estimatedMoney = 0,
      estimatedEggs = 0,
      offlineHours = 0,
      placedChickenCount = 0,
    }
  end

  local earnings = OfflineEarnings.calculate(data, currentTime)

  return {
    hasPendingEarnings = earnings.cappedMoney > 0 or #earnings.eggsEarned > 0,
    estimatedMoney = earnings.cappedMoney,
    estimatedEggs = #earnings.eggsEarned,
    offlineHours = earnings.cappedSeconds / 3600,
    placedChickenCount = #data.placedChickens,
  }
end

-- Format offline duration as human-readable string
function OfflineEarnings.formatDuration(seconds: number): string
  if seconds < 60 then
    return string.format("%d seconds", math.floor(seconds))
  elseif seconds < 3600 then
    local minutes = math.floor(seconds / 60)
    return string.format("%d minute%s", minutes, minutes == 1 and "" or "s")
  elseif seconds < 86400 then
    local hours = math.floor(seconds / 3600)
    local remainingMinutes = math.floor((seconds % 3600) / 60)
    if remainingMinutes > 0 then
      return string.format("%dh %dm", hours, remainingMinutes)
    end
    return string.format("%d hour%s", hours, hours == 1 and "" or "s")
  else
    local days = math.floor(seconds / 86400)
    local remainingHours = math.floor((seconds % 86400) / 3600)
    if remainingHours > 0 then
      return string.format("%dd %dh", days, remainingHours)
    end
    return string.format("%d day%s", days, days == 1 and "" or "s")
  end
end

-- Get breakdown of earnings by rarity tier
function OfflineEarnings.getEarningsByRarity(
  earnings: OfflineEarningsResult
): { [string]: { money: number, eggs: number } }
  local byRarity: { [string]: { money: number, eggs: number } } = {}

  -- Initialize all rarities
  for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
    byRarity[rarity] = { money = 0, eggs = 0 }
  end

  -- Sum money by chicken rarity
  for _, chickenEarnings in ipairs(earnings.moneyPerChicken) do
    local rarity = chickenEarnings.rarity
    if byRarity[rarity] then
      byRarity[rarity].money = byRarity[rarity].money + chickenEarnings.moneyEarned
    end
  end

  -- Sum eggs by egg rarity
  for _, egg in ipairs(earnings.eggsEarned) do
    local rarity = egg.rarity
    if byRarity[rarity] then
      byRarity[rarity].eggs = byRarity[rarity].eggs + 1
    end
  end

  return byRarity
end

-- Validate offline earnings result
function OfflineEarnings.validateResult(result: OfflineEarningsResult): boolean
  if result.cappedMoney < 0 then
    return false
  end
  if result.cappedSeconds < 0 then
    return false
  end
  if result.cappedEggs < 0 then
    return false
  end
  if result.cappedSeconds > result.elapsedSeconds then
    return false
  end
  if result.cappedMoney > result.totalMoney then
    return false
  end
  return true
end

-- Get maximum possible offline earnings for a given player data
function OfflineEarnings.getMaxPotential(
  data: PlayerData.PlayerDataSchema
): { maxMoneyPerHour: number, maxEggsPerHour: number }
  local totalMoneyPerSecond = 0
  local totalEggsPerHour = 0

  for _, chicken in ipairs(data.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      totalMoneyPerSecond = totalMoneyPerSecond + config.moneyPerSecond
      totalEggsPerHour = totalEggsPerHour + (3600 / config.eggLayIntervalSeconds)
    end
  end

  return {
    maxMoneyPerHour = totalMoneyPerSecond * 3600 * OFFLINE_EARNINGS_RATE,
    maxEggsPerHour = totalEggsPerHour,
  }
end

return OfflineEarnings
