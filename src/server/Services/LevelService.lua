--[[
	LevelService
	Knit service that handles XP, leveling, and level-based unlocks.
	
	Provides:
	- XP awarding for various game actions
	- Level-up detection and notifications
	- Threat level unlock tracking
	- Level-based gameplay scaling
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))

-- PlayerDataService is required lazily to avoid circular dependency
local PlayerDataService

-- Create the service
local LevelService = Knit.CreateService({
  Name = "LevelService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to specific clients
    XPGained = Knit.CreateSignal(), -- Fires (amount: number, reason: string, newTotal: number)
    LevelUp = Knit.CreateSignal(), -- Fires (newLevel: number, unlocks: {string})
  },
})

-- Server-side signals (for other services to listen to)
LevelService.XPAwardedSignal = GoodSignal.new() -- (userId: number, amount: number, reason: string)
LevelService.LevelUpSignal = GoodSignal.new() -- (userId: number, newLevel: number, unlocks: {string})
LevelService.ThreatUnlockedSignal = GoodSignal.new() -- (userId: number, threatLevel: string)

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function LevelService:KnitInit()
  print("[LevelService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function LevelService:KnitStart()
  -- Require PlayerDataService here to avoid load-time circular dependency
  PlayerDataService = Knit.GetService("PlayerDataService")

  print("[LevelService] Started")
end

--[[
	Gets the player's current level and XP.
	
	@param player Player - The player requesting data
	@return number, number - Level and XP
]]
function LevelService.Client:GetLevelInfo(player: Player): (number, number)
  local data = PlayerDataService:GetData(player.UserId)
  if data then
    return LevelConfig.getLevelFromXP(data.xp), data.xp
  end
  return 1, 0
end

--[[
	Gets the player's level progress (0-1 progress to next level).
	
	@param player Player - The player requesting data
	@return number - Progress percentage (0-1)
]]
function LevelService.Client:GetLevelProgress(player: Player): number
  local data = PlayerDataService:GetData(player.UserId)
  if data then
    return LevelConfig.getLevelProgress(data.xp)
  end
  return 0
end

--[[
	Gets XP needed to reach the next level.
	
	@param player Player - The player requesting data
	@return number? - XP needed (nil if at max level)
]]
function LevelService.Client:GetXPToNextLevel(player: Player): number?
  local data = PlayerDataService:GetData(player.UserId)
  if data then
    return LevelConfig.getXPToNextLevel(data.xp)
  end
  return nil
end

--[[
	Gets the player's level data (full summary).
	
	@param player Player - The player requesting data
	@return LevelConfig.LevelData - Level data including unlocks
]]
function LevelService.Client:GetLevelData(player: Player): LevelConfig.LevelData
  local data = PlayerDataService:GetData(player.UserId)
  if data then
    return LevelConfig.getLevelDataFromXP(data.xp)
  end
  return LevelConfig.getLevelData(1)
end

--[[
	Gets the highest threat level unlocked for the player.
	
	@param player Player - The player requesting data
	@return string - Highest unlocked threat level
]]
function LevelService.Client:GetMaxThreatLevel(player: Player): string
  local data = PlayerDataService:GetData(player.UserId)
  if data then
    local level = LevelConfig.getLevelFromXP(data.xp)
    return LevelConfig.getMaxThreatLevel(level)
  end
  return "Minor"
end

--[[
	Gets all unlocked threat levels for the player.
	
	@param player Player - The player requesting data
	@return {string} - List of unlocked threat levels
]]
function LevelService.Client:GetUnlockedThreatLevels(player: Player): { string }
  local data = PlayerDataService:GetData(player.UserId)
  local unlocked = {}

  local level = 1
  if data then
    level = LevelConfig.getLevelFromXP(data.xp)
  end

  local threatLevels = LevelConfig.getThreatUnlockLevels()
  for threatLevel, requiredLevel in pairs(threatLevels) do
    if level >= requiredLevel then
      table.insert(unlocked, threatLevel)
    end
  end

  return unlocked
end

--[[
	SERVER-ONLY: Awards XP to a player for a specific action.
	Handles level-up detection and broadcasts to client.
	
	@param userId number - The user ID
	@param amount number - XP amount to award
	@param reason string - Reason for XP (for display/logging)
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardXP(userId: number, amount: number, reason: string): (boolean, number?)
  if amount <= 0 then
    return false, nil
  end

  local data = PlayerDataService:GetData(userId)
  if not data then
    return false, nil
  end

  local oldLevel = LevelConfig.getLevelFromXP(data.xp)
  local success, newLevel = PlayerDataService:AddXP(userId, amount)

  if success then
    -- Fire server signal
    self.XPAwardedSignal:Fire(userId, amount, reason)

    -- Notify client
    local player = Players:GetPlayerByUserId(userId)
    if player then
      local newXP = data.xp + amount
      self.Client.XPGained:Fire(player, amount, reason, newXP)

      -- Handle level up
      if newLevel and newLevel > oldLevel then
        local unlocks = self:_getNewUnlocks(oldLevel, newLevel)
        self.Client.LevelUp:Fire(player, newLevel, unlocks)
        self.LevelUpSignal:Fire(userId, newLevel, unlocks)

        -- Fire individual threat unlock signals
        for _, unlock in ipairs(unlocks) do
          if unlock:match("Threat:") then
            local threatLevel = unlock:gsub("Threat: ", "")
            self.ThreatUnlockedSignal:Fire(userId, threatLevel)
          end
        end
      end
    end

    return true, newLevel
  end

  return false, nil
end

--[[
	SERVER-ONLY: Awards XP for killing a predator.
	
	@param userId number - The user ID
	@param predatorType string - Type of predator killed
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardPredatorKillXP(userId: number, predatorType: string): (boolean, number?)
  local xp = XPConfig.calculatePredatorKillXP(predatorType)
  return self:AwardXP(userId, xp, "Defeated " .. predatorType)
end

--[[
	SERVER-ONLY: Awards XP for hatching a chicken.
	
	@param userId number - The user ID
	@param chickenRarity string - Rarity of hatched chicken
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardChickenHatchXP(userId: number, chickenRarity: string): (boolean, number?)
  local xp = XPConfig.calculateChickenHatchXP(chickenRarity)
  return self:AwardXP(userId, xp, "Hatched " .. chickenRarity .. " chicken")
end

--[[
	SERVER-ONLY: Awards XP for catching a random chicken.
	
	@param userId number - The user ID
	@param chickenRarity string - Rarity of caught chicken
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardRandomChickenXP(
  userId: number,
  chickenRarity: string
): (boolean, number?)
  local xp = XPConfig.calculateRandomChickenXP(chickenRarity)
  return self:AwardXP(userId, xp, "Caught wild " .. chickenRarity .. " chicken")
end

--[[
	SERVER-ONLY: Awards XP for collecting an egg.
	
	@param userId number - The user ID
	@param eggRarity string - Rarity of collected egg
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardEggCollectedXP(userId: number, eggRarity: string): (boolean, number?)
  local xp = XPConfig.calculateEggCollectedXP(eggRarity)
  return self:AwardXP(userId, xp, "Collected " .. eggRarity .. " egg")
end

--[[
	SERVER-ONLY: Awards XP for catching a predator in a trap.
	
	@param userId number - The user ID
	@param predatorType string - Type of predator caught
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardTrapCatchXP(userId: number, predatorType: string): (boolean, number?)
  local xp = XPConfig.calculateTrapCatchXP(predatorType)
  return self:AwardXP(userId, xp, "Trapped " .. predatorType)
end

--[[
	SERVER-ONLY: Awards XP for surviving a day/night cycle.
	
	@param userId number - The user ID
	@return boolean, number? - Success and new level if leveled up
]]
function LevelService:AwardDayNightCycleXP(userId: number): (boolean, number?)
  local xp = XPConfig.calculateDayNightCycleXP()
  return self:AwardXP(userId, xp, "Survived night cycle")
end

--[[
	SERVER-ONLY: Gets the player's current level.
	
	@param userId number - The user ID
	@return number - Player's level
]]
function LevelService:GetLevel(userId: number): number
  local data = PlayerDataService:GetData(userId)
  if data then
    return LevelConfig.getLevelFromXP(data.xp)
  end
  return 1
end

--[[
	SERVER-ONLY: Gets the max simultaneous predators for a player's level.
	
	@param userId number - The user ID
	@return number - Max predators allowed
]]
function LevelService:GetMaxPredators(userId: number): number
  local level = self:GetLevel(userId)
  return LevelConfig.getMaxPredatorsForLevel(level)
end

--[[
	SERVER-ONLY: Gets the threat multiplier for a player's level.
	
	@param userId number - The user ID
	@return number - Threat multiplier (1.0 - 2.0)
]]
function LevelService:GetThreatMultiplier(userId: number): number
  local level = self:GetLevel(userId)
  return LevelConfig.getThreatMultiplierForLevel(level)
end

--[[
	SERVER-ONLY: Checks if a threat level is unlocked for a player.
	
	@param userId number - The user ID
	@param threatLevel string - Threat level to check
	@return boolean - Whether threat level is unlocked
]]
function LevelService:IsThreatUnlocked(userId: number, threatLevel: string): boolean
  local level = self:GetLevel(userId)
  return LevelConfig.isThreatLevelUnlocked(level, threatLevel)
end

--[[
	SERVER-ONLY: Gets the max threat level for a player.
	
	@param userId number - The user ID
	@return string - Highest unlocked threat level
]]
function LevelService:GetMaxThreatLevel(userId: number): string
  local level = self:GetLevel(userId)
  return LevelConfig.getMaxThreatLevel(level)
end

--[[
	PRIVATE: Gets new unlocks between two levels.
	
	@param oldLevel number - Previous level
	@param newLevel number - New level
	@return {string} - List of unlock descriptions
]]
function LevelService:_getNewUnlocks(oldLevel: number, newLevel: number): { string }
  local unlocks = {}

  -- Check for threat level unlocks
  local threatLevels = LevelConfig.getThreatUnlockLevels()
  for threatLevel, requiredLevel in pairs(threatLevels) do
    if oldLevel < requiredLevel and newLevel >= requiredLevel then
      table.insert(unlocks, "Threat: " .. threatLevel)
    end
  end

  -- Check for max predator increases
  local oldMaxPredators = LevelConfig.getMaxPredatorsForLevel(oldLevel)
  local newMaxPredators = LevelConfig.getMaxPredatorsForLevel(newLevel)
  if newMaxPredators > oldMaxPredators then
    table.insert(unlocks, "Max Predators: " .. newMaxPredators)
  end

  -- Check for milestone bonuses
  local bonus = LevelConfig.getLevelUpBonusXP(newLevel)
  if bonus > 0 then
    table.insert(unlocks, "Milestone Bonus: " .. bonus .. " XP")
  end

  return unlocks
end

return LevelService
