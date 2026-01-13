--[[
	DataPersistence Module
	Handles saving and loading player data using Roblox DataStore.
	Includes auto-save, offline earnings calculation, and error handling.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

local DataPersistence = {}

-- Configuration
local DATA_STORE_NAME = "ChickenCoopTycoon_PlayerData_v1"
local AUTO_SAVE_INTERVAL = 300 -- 5 minutes
local MAX_OFFLINE_HOURS = 24 -- Maximum hours of offline earnings
local OFFLINE_EARNINGS_RATE = 0.5 -- 50% of normal earnings while offline
local MAX_RETRY_ATTEMPTS = 3
local RETRY_DELAY = 1

-- Type definitions
export type SaveResult = {
  success: boolean,
  message: string,
  timestamp: number?,
}

export type LoadResult = {
  success: boolean,
  message: string,
  data: PlayerData.PlayerDataSchema?,
  isNewPlayer: boolean,
  offlineEarnings: number?,
  offlineSeconds: number?,
}

export type OfflineEarningsResult = {
  totalEarnings: number,
  cappedEarnings: number,
  elapsedSeconds: number,
  cappedSeconds: number,
  wasCapped: boolean,
}

-- Private state
local dataStore: DataStore? = nil
local playerDataCache: { [number]: PlayerData.PlayerDataSchema } = {}
local saveInProgress: { [number]: boolean } = {}
local autoSaveConnection: RBXScriptConnection? = nil

-- Initialize the DataStore
function DataPersistence.init(): boolean
  local success, store = pcall(function()
    return DataStoreService:GetDataStore(DATA_STORE_NAME)
  end)

  if success and store then
    dataStore = store
    return true
  end

  warn("[DataPersistence] Failed to initialize DataStore:", store)
  return false
end

-- Get the data key for a player
local function getDataKey(userId: number): string
  return "Player_" .. tostring(userId)
end

-- Retry wrapper for DataStore operations
local function retryOperation<T>(operation: () -> T, maxAttempts: number?): (boolean, T | string)
  local attempts = maxAttempts or MAX_RETRY_ATTEMPTS

  for attempt = 1, attempts do
    local success, result = pcall(operation)
    if success then
      return true, result
    end

    if attempt < attempts then
      task.wait(RETRY_DELAY * attempt)
    else
      return false, result :: string
    end
  end

  return false, "Max retry attempts exceeded"
end

-- Calculate offline earnings for a player's placed chickens
function DataPersistence.calculateOfflineEarnings(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): OfflineEarningsResult
  local lastLogout = data.lastLogoutTime or currentTime
  local elapsedSeconds = math.max(0, currentTime - lastLogout)

  -- Cap offline time
  local maxOfflineSeconds = MAX_OFFLINE_HOURS * 3600
  local cappedSeconds = math.min(elapsedSeconds, maxOfflineSeconds)
  local wasCapped = elapsedSeconds > maxOfflineSeconds

  -- Calculate earnings from placed chickens
  local totalMoneyPerSecond = 0
  for _, chicken in ipairs(data.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      totalMoneyPerSecond = totalMoneyPerSecond + config.moneyPerSecond
    end
  end

  local totalEarnings = totalMoneyPerSecond * elapsedSeconds * OFFLINE_EARNINGS_RATE
  local cappedEarnings = totalMoneyPerSecond * cappedSeconds * OFFLINE_EARNINGS_RATE

  return {
    totalEarnings = totalEarnings,
    cappedEarnings = cappedEarnings,
    elapsedSeconds = elapsedSeconds,
    cappedSeconds = cappedSeconds,
    wasCapped = wasCapped,
  }
end

-- Apply offline earnings to player data
local function applyOfflineEarnings(
  data: PlayerData.PlayerDataSchema,
  offlineResult: OfflineEarningsResult
): PlayerData.PlayerDataSchema
  data.money = data.money + offlineResult.cappedEarnings

  -- Update chicken accumulated money based on offline time
  local currentTime = os.time()
  for _, chicken in ipairs(data.placedChickens) do
    local config = ChickenConfig.get(chicken.chickenType)
    if config then
      local offlineGenerated = config.moneyPerSecond
        * offlineResult.cappedSeconds
        * OFFLINE_EARNINGS_RATE
      chicken.accumulatedMoney = chicken.accumulatedMoney + offlineGenerated
      chicken.lastEggTime = currentTime -- Reset egg timers
    end
  end

  return data
end

-- Load player data from DataStore
function DataPersistence.load(userId: number): LoadResult
  if not dataStore then
    if not DataPersistence.init() then
      return {
        success = false,
        message = "DataStore not initialized",
        data = nil,
        isNewPlayer = false,
      }
    end
  end

  local dataKey = getDataKey(userId)
  local success, result = retryOperation(function()
    return dataStore:GetAsync(dataKey)
  end)

  if not success then
    return {
      success = false,
      message = "Failed to load data: " .. tostring(result),
      data = nil,
      isNewPlayer = false,
    }
  end

  local currentTime = os.time()
  local isNewPlayer = result == nil
  local playerDataValue: PlayerData.PlayerDataSchema

  if isNewPlayer then
    playerDataValue = PlayerData.createDefault()
    playerDataValue.lastLogoutTime = currentTime
  else
    -- Validate loaded data
    if not PlayerData.validate(result) then
      warn("[DataPersistence] Invalid data for user " .. tostring(userId) .. ", creating new data")
      playerDataValue = PlayerData.createDefault()
      playerDataValue.lastLogoutTime = currentTime
      isNewPlayer = true
    else
      playerDataValue = result :: PlayerData.PlayerDataSchema
    end
  end

  -- Calculate and apply offline earnings for returning players
  local offlineEarnings: number? = nil
  local offlineSeconds: number? = nil

  if not isNewPlayer and playerDataValue.lastLogoutTime then
    local offlineResult = DataPersistence.calculateOfflineEarnings(playerDataValue, currentTime)

    if offlineResult.cappedEarnings > 0 then
      playerDataValue = applyOfflineEarnings(playerDataValue, offlineResult)
      offlineEarnings = offlineResult.cappedEarnings
      offlineSeconds = offlineResult.cappedSeconds
    end
  end

  -- Cache the data
  playerDataCache[userId] = playerDataValue

  return {
    success = true,
    message = isNewPlayer and "New player created" or "Data loaded successfully",
    data = playerDataValue,
    isNewPlayer = isNewPlayer,
    offlineEarnings = offlineEarnings,
    offlineSeconds = offlineSeconds,
  }
end

-- Save player data to DataStore
function DataPersistence.save(userId: number, data: PlayerData.PlayerDataSchema?): SaveResult
  if not dataStore then
    if not DataPersistence.init() then
      return {
        success = false,
        message = "DataStore not initialized",
      }
    end
  end

  -- Use cached data if not provided
  local saveData = data or playerDataCache[userId]
  if not saveData then
    return {
      success = false,
      message = "No data to save",
    }
  end

  -- Prevent concurrent saves
  if saveInProgress[userId] then
    return {
      success = false,
      message = "Save already in progress",
    }
  end

  -- Validate data before saving
  if not PlayerData.validate(saveData) then
    return {
      success = false,
      message = "Invalid data, cannot save",
    }
  end

  saveInProgress[userId] = true

  -- Update logout time and play time
  local currentTime = os.time()
  saveData.lastLogoutTime = currentTime

  local dataKey = getDataKey(userId)
  local success, result = retryOperation(function()
    dataStore:SetAsync(dataKey, saveData)
    return true
  end)

  saveInProgress[userId] = false

  if not success then
    return {
      success = false,
      message = "Failed to save data: " .. tostring(result),
    }
  end

  -- Update cache
  playerDataCache[userId] = saveData

  return {
    success = true,
    message = "Data saved successfully",
    timestamp = currentTime,
  }
end

-- Get cached player data
function DataPersistence.getData(userId: number): PlayerData.PlayerDataSchema?
  return playerDataCache[userId]
end

-- Update cached player data
function DataPersistence.updateData(userId: number, data: PlayerData.PlayerDataSchema): boolean
  if not PlayerData.validate(data) then
    return false
  end
  playerDataCache[userId] = data
  return true
end

-- Remove player data from cache
function DataPersistence.clearCache(userId: number): boolean
  if playerDataCache[userId] then
    playerDataCache[userId] = nil
    return true
  end
  return false
end

-- Handle player leaving - save and clear cache
function DataPersistence.onPlayerLeave(player: Player): SaveResult
  local userId = player.UserId
  local data = playerDataCache[userId]

  if not data then
    return {
      success = true,
      message = "No data to save",
    }
  end

  local result = DataPersistence.save(userId, data)
  DataPersistence.clearCache(userId)

  return result
end

-- Handle player joining - load data
function DataPersistence.onPlayerJoin(player: Player): LoadResult
  return DataPersistence.load(player.UserId)
end

-- Save all cached player data
function DataPersistence.saveAll(): { [number]: SaveResult }
  local results: { [number]: SaveResult } = {}

  for userId, data in pairs(playerDataCache) do
    results[userId] = DataPersistence.save(userId, data)
  end

  return results
end

-- Start auto-save system
function DataPersistence.startAutoSave(): boolean
  if autoSaveConnection then
    return false -- Already running
  end

  local lastSaveTime = os.time()

  autoSaveConnection = RunService.Heartbeat:Connect(function()
    local currentTime = os.time()
    if currentTime - lastSaveTime >= AUTO_SAVE_INTERVAL then
      lastSaveTime = currentTime
      task.spawn(function()
        local results = DataPersistence.saveAll()
        local successCount = 0
        local failCount = 0

        for _, result in pairs(results) do
          if result.success then
            successCount += 1
          else
            failCount += 1
          end
        end

        if successCount > 0 or failCount > 0 then
          print(
            string.format(
              "[DataPersistence] Auto-save completed: %d success, %d failed",
              successCount,
              failCount
            )
          )
        end
      end)
    end
  end)

  return true
end

-- Stop auto-save system
function DataPersistence.stopAutoSave(): boolean
  if autoSaveConnection then
    autoSaveConnection:Disconnect()
    autoSaveConnection = nil
    return true
  end
  return false
end

-- Setup player connections
function DataPersistence.setupPlayerConnections(): ()
  -- Handle player joining
  Players.PlayerAdded:Connect(function(player)
    local result = DataPersistence.onPlayerJoin(player)
    if result.success then
      print(string.format("[DataPersistence] Loaded data for %s", player.Name))
      if result.offlineEarnings and result.offlineEarnings > 0 then
        print(
          string.format(
            "[DataPersistence] %s earned $%.2f while offline (%d seconds)",
            player.Name,
            result.offlineEarnings,
            result.offlineSeconds or 0
          )
        )
      end
    else
      warn(
        string.format(
          "[DataPersistence] Failed to load data for %s: %s",
          player.Name,
          result.message
        )
      )
    end
  end)

  -- Handle player leaving
  Players.PlayerRemoving:Connect(function(player)
    local result = DataPersistence.onPlayerLeave(player)
    if result.success then
      print(string.format("[DataPersistence] Saved data for %s", player.Name))
    else
      warn(
        string.format(
          "[DataPersistence] Failed to save data for %s: %s",
          player.Name,
          result.message
        )
      )
    end
  end)

  -- Handle server shutdown
  game:BindToClose(function()
    print("[DataPersistence] Server shutting down, saving all player data...")
    DataPersistence.saveAll()
    task.wait(2) -- Give time for saves to complete
  end)
end

-- Initialize everything and start the persistence system
function DataPersistence.start(): boolean
  local initSuccess = DataPersistence.init()
  if not initSuccess then
    warn("[DataPersistence] Failed to initialize, running in offline mode")
  end

  DataPersistence.setupPlayerConnections()
  DataPersistence.startAutoSave()

  print("[DataPersistence] Data persistence system started")
  return initSuccess
end

-- Get configuration values (for testing/UI)
function DataPersistence.getConfig(): {
  autoSaveInterval: number,
  maxOfflineHours: number,
  offlineEarningsRate: number,
  maxRetryAttempts: number,
}
  return {
    autoSaveInterval = AUTO_SAVE_INTERVAL,
    maxOfflineHours = MAX_OFFLINE_HOURS,
    offlineEarningsRate = OFFLINE_EARNINGS_RATE,
    maxRetryAttempts = MAX_RETRY_ATTEMPTS,
  }
end

-- Check if a player has cached data
function DataPersistence.hasData(userId: number): boolean
  return playerDataCache[userId] ~= nil
end

-- Get count of cached players
function DataPersistence.getCachedPlayerCount(): number
  local count = 0
  for _ in pairs(playerDataCache) do
    count += 1
  end
  return count
end

-- Check if auto-save is running
function DataPersistence.isAutoSaveRunning(): boolean
  return autoSaveConnection ~= nil
end

return DataPersistence
