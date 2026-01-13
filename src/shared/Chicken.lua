--[[
	Chicken Module
	Manages chicken entities that generate money over time and lay eggs at intervals.
	This module handles chicken state updates, money accumulation, and egg laying logic.
]]

local Chicken = {}
Chicken.__index = Chicken

-- Import dependencies
local ChickenConfig = require(script.Parent.ChickenConfig)
local PlayerData = require(script.Parent.PlayerData)

-- Type definitions
export type ChickenState = {
  id: string,
  chickenType: string,
  rarity: string,
  accumulatedMoney: number,
  lastEggTime: number,
  lastUpdateTime: number,
  spotIndex: number?,
}

export type ChickenInstance = typeof(setmetatable({} :: ChickenState, Chicken))

-- Create a new chicken instance from player data
function Chicken.new(chickenData: PlayerData.ChickenData): ChickenInstance?
  local config = ChickenConfig.get(chickenData.chickenType)
  if not config then
    return nil
  end

  local self: ChickenState = {
    id = chickenData.id,
    chickenType = chickenData.chickenType,
    rarity = chickenData.rarity,
    accumulatedMoney = chickenData.accumulatedMoney or 0,
    lastEggTime = chickenData.lastEggTime or os.time(),
    lastUpdateTime = os.time(),
    spotIndex = chickenData.spotIndex,
  }

  return setmetatable(self, Chicken)
end

-- Create a new chicken from a type (for hatching)
function Chicken.fromType(chickenType: string, spotIndex: number?): ChickenInstance?
  local config = ChickenConfig.get(chickenType)
  if not config then
    return nil
  end

  local currentTime = os.time()
  local self: ChickenState = {
    id = PlayerData.generateId(),
    chickenType = chickenType,
    rarity = config.rarity,
    accumulatedMoney = 0,
    lastEggTime = currentTime,
    lastUpdateTime = currentTime,
    spotIndex = spotIndex,
  }

  return setmetatable(self, Chicken)
end

-- Get the chicken's configuration
function Chicken:getConfig(): ChickenConfig.ChickenTypeConfig?
  return ChickenConfig.get(self.chickenType)
end

-- Get money per second for this chicken
function Chicken:getMoneyPerSecond(): number
  local config = self:getConfig()
  if not config then
    return 0
  end
  return config.moneyPerSecond
end

-- Get egg laying interval in seconds
function Chicken:getEggLayInterval(): number
  local config = self:getConfig()
  if not config then
    return 60
  end
  return config.eggLayIntervalSeconds
end

-- Get possible egg types this chicken can lay
function Chicken:getEggTypes(): { string }
  local config = self:getConfig()
  if not config then
    return {}
  end
  return config.eggsLaid
end

-- Update the chicken's accumulated money based on elapsed time
-- Returns the amount of money generated since last update
function Chicken:update(currentTime: number?): number
  local now = currentTime or os.time()
  local elapsedSeconds = now - self.lastUpdateTime

  if elapsedSeconds <= 0 then
    return 0
  end

  local moneyGenerated = self:getMoneyPerSecond() * elapsedSeconds
  self.accumulatedMoney = self.accumulatedMoney + moneyGenerated
  self.lastUpdateTime = now

  return moneyGenerated
end

-- Check if the chicken is ready to lay an egg
function Chicken:canLayEgg(currentTime: number?): boolean
  local now = currentTime or os.time()
  local timeSinceLastEgg = now - self.lastEggTime
  return timeSinceLastEgg >= self:getEggLayInterval()
end

-- Get the time remaining until the chicken can lay an egg
function Chicken:getTimeUntilEgg(currentTime: number?): number
  local now = currentTime or os.time()
  local timeSinceLastEgg = now - self.lastEggTime
  local interval = self:getEggLayInterval()

  if timeSinceLastEgg >= interval then
    return 0
  end

  return interval - timeSinceLastEgg
end

-- Lay an egg and return the egg type (or nil if not ready)
-- Resets the egg timer on success
function Chicken:layEgg(currentTime: number?): string?
  if not self:canLayEgg(currentTime) then
    return nil
  end

  local eggTypes = self:getEggTypes()
  if #eggTypes == 0 then
    return nil
  end

  -- Select random egg type from possible types
  local selectedEgg = eggTypes[math.random(1, #eggTypes)]

  -- Reset egg timer
  self.lastEggTime = currentTime or os.time()

  return selectedEgg
end

-- Collect accumulated money and reset to zero
-- Returns the amount collected
function Chicken:collectMoney(): number
  local amount = self.accumulatedMoney
  self.accumulatedMoney = 0
  return amount
end

-- Get the current accumulated money without collecting
function Chicken:getAccumulatedMoney(): number
  return self.accumulatedMoney
end

-- Check if chicken is placed in a coop spot
function Chicken:isPlaced(): boolean
  return self.spotIndex ~= nil
end

-- Place chicken in a coop spot
function Chicken:place(spotIndex: number): boolean
  if spotIndex < 1 or spotIndex > 12 then
    return false
  end
  self.spotIndex = spotIndex
  return true
end

-- Remove chicken from coop spot (back to inventory)
function Chicken:pickup(): boolean
  if not self:isPlaced() then
    return false
  end
  self.spotIndex = nil
  return true
end

-- Convert chicken instance back to PlayerData format
function Chicken:toPlayerData(): PlayerData.ChickenData
  return {
    id = self.id,
    chickenType = self.chickenType,
    rarity = self.rarity,
    accumulatedMoney = self.accumulatedMoney,
    lastEggTime = self.lastEggTime,
    spotIndex = self.spotIndex,
  }
end

-- Calculate earnings for a specific time period
function Chicken:calculateEarningsForPeriod(seconds: number): number
  return self:getMoneyPerSecond() * seconds
end

-- Get display name for the chicken
function Chicken:getDisplayName(): string
  local config = self:getConfig()
  if not config then
    return self.chickenType
  end
  return config.displayName
end

-- Get the chicken's rarity
function Chicken:getRarity(): string
  return self.rarity
end

-- Validate the chicken's state
function Chicken:isValid(): boolean
  local config = self:getConfig()
  if not config then
    return false
  end

  if self.accumulatedMoney < 0 then
    return false
  end

  if self.spotIndex ~= nil and (self.spotIndex < 1 or self.spotIndex > 12) then
    return false
  end

  return true
end

-- Static: Validate a chicken type exists
function Chicken.isValidType(chickenType: string): boolean
  return ChickenConfig.isValidType(chickenType)
end

-- Static: Get all available chicken types
function Chicken.getAllTypes(): { string }
  return ChickenConfig.getAllTypes()
end

-- Static: Calculate offline earnings for a chicken given elapsed time
function Chicken.calculateOfflineEarnings(
  chickenType: string,
  elapsedSeconds: number,
  maxSeconds: number?
): number
  local config = ChickenConfig.get(chickenType)
  if not config then
    return 0
  end

  local cappedSeconds = elapsedSeconds
  if maxSeconds then
    cappedSeconds = math.min(elapsedSeconds, maxSeconds)
  end

  return config.moneyPerSecond * cappedSeconds
end

return Chicken
