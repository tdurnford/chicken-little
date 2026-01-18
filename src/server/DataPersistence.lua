--[[
	DataPersistence Module
	Handles saving and loading player data using ProfileService.
	Includes auto-save, offline earnings calculation, session locking, and error handling.
	
	ProfileService provides:
	- Automatic session locking to prevent data corruption
	- Automatic data saving on a regular interval
	- Data reconciliation with templates
	- Safe handling of server crashes and player disconnects
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local ProfileService = require(Packages:WaitForChild("ProfileService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

local DataPersistence = {}

-- Configuration
local DATA_STORE_NAME = "ChickenCoopTycoon_PlayerData_v1"
local MAX_OFFLINE_HOURS = 24 -- Maximum hours of offline earnings
local OFFLINE_EARNINGS_RATE = 0.5 -- 50% of normal earnings while offline

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
  offlineEggs: number?,
  offlineSeconds: number?,
}

export type OfflineEarningsResult = OfflineEarnings.OfflineEarningsResult

-- Profile template - default data structure for new players
local ProfileTemplate = PlayerData.createDefault()

-- ProfileStore instance
local ProfileStore = ProfileService.GetProfileStore(DATA_STORE_NAME, ProfileTemplate)

-- Private state
local profiles: { [number]: any } = {} -- Active profiles keyed by userId
local playerDataCache: { [number]: PlayerData.PlayerDataSchema } = {}
local profileStoreInitialized = false

-- Initialize ProfileService (ProfileService initializes automatically)
function DataPersistence.init(): boolean
  profileStoreInitialized = true
  return true
end

-- Get the profile key for a player
local function getProfileKey(userId: number): string
  return "Player_" .. tostring(userId)
end

-- Calculate offline earnings for a player's placed chickens
-- Delegates to OfflineEarnings module for full calculation including eggs
function DataPersistence.calculateOfflineEarnings(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): OfflineEarningsResult
  return OfflineEarnings.calculate(data, currentTime)
end

-- Apply offline earnings to player data (money and eggs)
local function applyOfflineEarnings(
  data: PlayerData.PlayerDataSchema,
  offlineResult: OfflineEarningsResult
): PlayerData.PlayerDataSchema
  local result = OfflineEarnings.apply(data, offlineResult)
  return result.updatedData or data
end

-- Load player profile using ProfileService
function DataPersistence.load(userId: number): LoadResult
  local profileKey = getProfileKey(userId)

  -- Load the profile with ForceLoad to handle session locking
  local profile = ProfileStore:LoadProfileAsync(profileKey, "ForceLoad")

  if not profile then
    -- Profile failed to load - create default data for offline mode
    warn("[DataPersistence] Failed to load profile for user " .. tostring(userId))
    local currentTime = os.time()
    local defaultData = PlayerData.createDefault()
    defaultData.lastLogoutTime = currentTime
    playerDataCache[userId] = defaultData

    return {
      success = true,
      message = "Profile load failed - created default data",
      data = defaultData,
      isNewPlayer = true,
    }
  end

  -- Add userId to profile (for GDPR compliance)
  profile:AddUserId(userId)

  -- Reconcile profile data with template to add any new fields
  profile:Reconcile()

  -- Store the active profile
  profiles[userId] = profile

  -- Set up profile release listener
  profile:ListenToRelease(function()
    profiles[userId] = nil
    playerDataCache[userId] = nil

    -- Kick the player if they're still in the game (session was stolen)
    local player = Players:GetPlayerByUserId(userId)
    if player then
      player:Kick("Your data was loaded on another server. Please rejoin.")
    end
  end)

  local currentTime = os.time()
  local profileData = profile.Data :: PlayerData.PlayerDataSchema

  -- Determine if this is a new player (check if profile was just created)
  local isNewPlayer = profile.MetaData.SessionLoadCount == 1

  -- Validate loaded data
  if not PlayerData.validate(profileData) then
    warn("[DataPersistence] Invalid data for user " .. tostring(userId) .. ", resetting to default")
    -- Reset to default data
    local defaultData = PlayerData.createDefault()
    for key, value in pairs(defaultData) do
      profileData[key] = value
    end
    isNewPlayer = true
  end

  -- Calculate and apply offline earnings for returning players
  local offlineEarnings: number? = nil
  local offlineEggs: number? = nil
  local offlineSeconds: number? = nil

  if not isNewPlayer and profileData.lastLogoutTime then
    local offlineResult = DataPersistence.calculateOfflineEarnings(profileData, currentTime)

    if offlineResult.cappedMoney > 0 or #offlineResult.eggsEarned > 0 then
      -- Apply offline earnings directly to profile data
      local updatedData = applyOfflineEarnings(profileData, offlineResult)
      for key, value in pairs(updatedData) do
        profileData[key] = value
      end
      offlineEarnings = offlineResult.cappedMoney
      offlineEggs = #offlineResult.eggsEarned
      offlineSeconds = offlineResult.cappedSeconds
    end
  end

  -- Cache the data reference
  playerDataCache[userId] = profileData

  return {
    success = true,
    message = isNewPlayer and "New player created" or "Data loaded successfully",
    data = profileData,
    isNewPlayer = isNewPlayer,
    offlineEarnings = offlineEarnings,
    offlineEggs = offlineEggs,
    offlineSeconds = offlineSeconds,
  }
end

-- Save player data (ProfileService auto-saves, but this allows manual save)
function DataPersistence.save(userId: number, data: PlayerData.PlayerDataSchema?): SaveResult
  local profile = profiles[userId]

  if not profile then
    return {
      success = false,
      message = "No active profile for user",
    }
  end

  -- Use provided data or get from cache
  local saveData = data or playerDataCache[userId]
  if not saveData then
    return {
      success = false,
      message = "No data to save",
    }
  end

  -- Validate data before saving
  if not PlayerData.validate(saveData) then
    return {
      success = false,
      message = "Invalid data, cannot save",
    }
  end

  -- Update logout time
  local currentTime = os.time()
  saveData.lastLogoutTime = currentTime

  -- Copy data to profile (ProfileService handles the actual save)
  for key, value in pairs(saveData) do
    profile.Data[key] = value
  end

  -- Trigger a save
  profile:Save()

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

-- Get player data by player object (convenience method)
function DataPersistence.get(player: Player): PlayerData.PlayerDataSchema?
  return playerDataCache[player.UserId]
end

-- Update cached player data
function DataPersistence.updateData(userId: number, data: PlayerData.PlayerDataSchema): boolean
  if not PlayerData.validate(data) then
    return false
  end

  local profile = profiles[userId]
  if profile then
    -- Update profile data
    for key, value in pairs(data) do
      profile.Data[key] = value
    end
  end

  playerDataCache[userId] = data
  return true
end

-- Remove player data from cache (called internally when profile is released)
function DataPersistence.clearCache(userId: number): boolean
  if playerDataCache[userId] then
    playerDataCache[userId] = nil
    return true
  end
  return false
end

-- Handle player leaving - release profile
function DataPersistence.onPlayerLeave(player: Player): SaveResult
  local userId = player.UserId
  local profile = profiles[userId]

  if not profile then
    return {
      success = true,
      message = "No active profile",
    }
  end

  -- Update logout time before release
  local currentTime = os.time()
  profile.Data.lastLogoutTime = currentTime

  -- Release the profile (ProfileService will save before releasing)
  profile:Release()

  -- Clear local references
  profiles[userId] = nil
  playerDataCache[userId] = nil

  return {
    success = true,
    message = "Profile released successfully",
    timestamp = currentTime,
  }
end

-- Handle player joining - load data
function DataPersistence.onPlayerJoin(player: Player): LoadResult
  return DataPersistence.load(player.UserId)
end

-- Save all cached player data (triggers save on all active profiles)
function DataPersistence.saveAll(): { [number]: SaveResult }
  local results: { [number]: SaveResult } = {}

  for userId, profile in pairs(profiles) do
    if profile:IsActive() then
      profile:Save()
      results[userId] = {
        success = true,
        message = "Save triggered",
        timestamp = os.time(),
      }
    else
      results[userId] = {
        success = false,
        message = "Profile not active",
      }
    end
  end

  return results
end

-- Start auto-save system (ProfileService handles auto-save, but this maintains API compatibility)
function DataPersistence.startAutoSave(): boolean
  -- ProfileService automatically saves profiles every ~30 seconds
  -- This function is kept for API compatibility
  return true
end

-- Stop auto-save system (no-op since ProfileService handles this)
function DataPersistence.stopAutoSave(): boolean
  -- ProfileService manages auto-save internally
  return true
end

-- Setup player connections
function DataPersistence.setupPlayerConnections(): ()
  -- Handle player joining
  Players.PlayerAdded:Connect(function(player)
    local result = DataPersistence.onPlayerJoin(player)
    if result.success then
      print(string.format("[DataPersistence] Loaded profile for %s", player.Name))
      if
        (result.offlineEarnings and result.offlineEarnings > 0)
        or (result.offlineEggs and result.offlineEggs > 0)
      then
        print(
          string.format(
            "[DataPersistence] %s earned $%.2f and %d eggs while offline (%d seconds)",
            player.Name,
            result.offlineEarnings or 0,
            result.offlineEggs or 0,
            result.offlineSeconds or 0
          )
        )
      end
    else
      warn(
        string.format(
          "[DataPersistence] Failed to load profile for %s: %s",
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
      print(string.format("[DataPersistence] Released profile for %s", player.Name))
    else
      warn(
        string.format(
          "[DataPersistence] Failed to release profile for %s: %s",
          player.Name,
          result.message
        )
      )
    end
  end)

  -- Handle server shutdown - release all profiles
  game:BindToClose(function()
    print("[DataPersistence] Server shutting down, releasing all profiles...")
    for userId, profile in pairs(profiles) do
      if profile:IsActive() then
        profile:Release()
      end
    end
    -- Wait for ProfileService to finish saving
    task.wait(2)
  end)
end

-- Initialize everything and start the persistence system
function DataPersistence.start(): boolean
  DataPersistence.init()
  DataPersistence.setupPlayerConnections()

  print("[DataPersistence] ProfileService-based persistence system started")
  return true
end

-- Get configuration values (for testing/UI)
function DataPersistence.getConfig(): {
  autoSaveInterval: number,
  maxOfflineHours: number,
  offlineEarningsRate: number,
  maxRetryAttempts: number,
}
  return {
    autoSaveInterval = 30, -- ProfileService default
    maxOfflineHours = MAX_OFFLINE_HOURS,
    offlineEarningsRate = OFFLINE_EARNINGS_RATE,
    maxRetryAttempts = 3,
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

-- Check if auto-save is running (always true with ProfileService)
function DataPersistence.isAutoSaveRunning(): boolean
  return true
end

-- Get global chicken counts across all players (placed + inventory)
-- Returns a table mapping chickenType to total count
function DataPersistence.getGlobalChickenCounts(): { [string]: number }
  local counts: { [string]: number } = {}

  for _, playerData in pairs(playerDataCache) do
    -- Count placed chickens
    if playerData.placedChickens then
      for _, chicken in ipairs(playerData.placedChickens) do
        local chickenType = chicken.chickenType
        counts[chickenType] = (counts[chickenType] or 0) + 1
      end
    end

    -- Count inventory chickens
    if playerData.inventory and playerData.inventory.chickens then
      for _, chicken in ipairs(playerData.inventory.chickens) do
        local chickenType = chicken.chickenType
        counts[chickenType] = (counts[chickenType] or 0) + 1
      end
    end
  end

  return counts
end

-- Get the active profile for a user (for advanced usage)
function DataPersistence.getProfile(userId: number): any?
  return profiles[userId]
end

-- Check if a profile is active
function DataPersistence.isProfileActive(userId: number): boolean
  local profile = profiles[userId]
  return profile ~= nil and profile:IsActive()
end

return DataPersistence
