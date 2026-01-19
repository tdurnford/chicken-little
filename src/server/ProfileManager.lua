--[[
	ProfileManager Module
	Wrapper for ProfileService that handles player profile loading, saving, and session management.
	Implements session locking to prevent data duplication across servers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local ProfileService = require(Packages:WaitForChild("ProfileService"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

local ProfileManager = {}

-- Configuration
local PROFILE_STORE_NAME = "ChickenCoopTycoon_PlayerProfiles_v1"
local PROFILE_KEY_PREFIX = "Player_"

-- Type definitions
export type ProfileLoadResult = {
  success: boolean,
  message: string,
  data: PlayerData.PlayerDataSchema?,
  isNewPlayer: boolean,
  offlineEarnings: number?,
  offlineEggs: number?,
  offlineSeconds: number?,
}

export type ProfileSaveResult = {
  success: boolean,
  message: string,
  timestamp: number?,
}

-- Data template matching PlayerData schema
local DataTemplate = PlayerData.createDefault()

-- Private state
local profileStore: any = nil
local loadedProfiles: { [number]: any } = {} -- userId -> Profile
local profileData: { [number]: PlayerData.PlayerDataSchema } = {} -- userId -> cached data

-- Initialize ProfileService store
function ProfileManager.init(): boolean
  local success, store = pcall(function()
    return ProfileService.GetProfileStore(PROFILE_STORE_NAME, DataTemplate)
  end)

  if success and store then
    profileStore = store
    print("[ProfileManager] ProfileService initialized successfully")
    return true
  end

  warn("[ProfileManager] Failed to initialize ProfileService:", store)
  return false
end

-- Get the profile key for a player
local function getProfileKey(userId: number): string
  return PROFILE_KEY_PREFIX .. tostring(userId)
end

-- Calculate and apply offline earnings
local function processOfflineEarnings(
  data: PlayerData.PlayerDataSchema,
  currentTime: number
): (PlayerData.PlayerDataSchema, number?, number?, number?)
  local offlineEarnings: number? = nil
  local offlineEggs: number? = nil
  local offlineSeconds: number? = nil

  if data.lastLogoutTime then
    local offlineResult = OfflineEarnings.calculate(data, currentTime)

    if offlineResult.cappedMoney > 0 or #offlineResult.eggsEarned > 0 then
      local applyResult = OfflineEarnings.apply(data, offlineResult)
      if applyResult.updatedData then
        data = applyResult.updatedData
      end
      offlineEarnings = offlineResult.cappedMoney
      offlineEggs = #offlineResult.eggsEarned
      offlineSeconds = offlineResult.cappedSeconds
    end
  end

  return data, offlineEarnings, offlineEggs, offlineSeconds
end

-- Load a player's profile
function ProfileManager.loadProfile(player: Player): ProfileLoadResult
  if not profileStore then
    if not ProfileManager.init() then
      -- ProfileService not available - create default data
      warn("[ProfileManager] ProfileService not initialized, using default data")
      local defaultData = PlayerData.createDefault()
      profileData[player.UserId] = defaultData

      return {
        success = true,
        message = "Offline mode - created default data",
        data = defaultData,
        isNewPlayer = true,
      }
    end
  end

  local profileKey = getProfileKey(player.UserId)

  -- Load profile with session locking
  local profile = profileStore:LoadProfileAsync(profileKey)

  if not profile then
    -- Profile failed to load (session locked elsewhere or error)
    warn("[ProfileManager] Failed to load profile for", player.Name, "- session may be locked")
    return {
      success = false,
      message = "Failed to load profile - session may be locked on another server",
      isNewPlayer = false,
    }
  end

  -- Handle profile release (player leaves or profile kicked)
  profile:AddUserId(player.UserId) -- GDPR compliance
  profile:Reconcile() -- Fill in missing template fields

  profile:ListenToRelease(function()
    loadedProfiles[player.UserId] = nil
    profileData[player.UserId] = nil

    -- Kick player if profile released while playing (e.g., same account joined elsewhere)
    if player.Parent then
      player:Kick("Profile session ended - you may have joined from another server")
    end
  end)

  -- Check if player left while loading
  if not player.Parent then
    profile:Release()
    return {
      success = false,
      message = "Player left during loading",
      isNewPlayer = false,
    }
  end

  -- Store references
  loadedProfiles[player.UserId] = profile

  -- Get the data and determine if new player
  local data = profile.Data :: PlayerData.PlayerDataSchema
  local isNewPlayer = data.totalPlayTime == 0

  -- Process offline earnings for returning players
  local currentTime = os.time()
  local offlineEarnings, offlineEggs, offlineSeconds

  if not isNewPlayer then
    data, offlineEarnings, offlineEggs, offlineSeconds = processOfflineEarnings(data, currentTime)
    -- Update profile data after offline earnings
    profile.Data = data
  end

  -- Cache the data
  profileData[player.UserId] = data

  print(
    string.format(
      "[ProfileManager] Loaded profile for %s (new: %s)",
      player.Name,
      tostring(isNewPlayer)
    )
  )

  return {
    success = true,
    message = isNewPlayer and "New player created" or "Profile loaded successfully",
    data = data,
    isNewPlayer = isNewPlayer,
    offlineEarnings = offlineEarnings,
    offlineEggs = offlineEggs,
    offlineSeconds = offlineSeconds,
  }
end

-- Release a player's profile (on leave)
function ProfileManager.releaseProfile(player: Player): ProfileSaveResult
  local profile = loadedProfiles[player.UserId]

  if not profile then
    return {
      success = true,
      message = "No profile to release",
    }
  end

  -- Update logout time before release
  local currentTime = os.time()
  profile.Data.lastLogoutTime = currentTime

  -- Release the profile (ProfileService auto-saves on release)
  profile:Release()

  loadedProfiles[player.UserId] = nil
  profileData[player.UserId] = nil

  print(string.format("[ProfileManager] Released profile for %s", player.Name))

  return {
    success = true,
    message = "Profile released successfully",
    timestamp = currentTime,
  }
end

-- Get cached profile data for a player
function ProfileManager.getData(userId: number): PlayerData.PlayerDataSchema?
  return profileData[userId]
end

-- Update cached profile data
function ProfileManager.updateData(userId: number, data: PlayerData.PlayerDataSchema): boolean
  local profile = loadedProfiles[userId]
  if not profile then
    return false
  end

  if not PlayerData.validate(data) then
    warn("[ProfileManager] Invalid data rejected for user", userId)
    return false
  end

  -- Update both profile and cache
  profile.Data = data
  profileData[userId] = data
  return true
end

-- Check if a player has a loaded profile
function ProfileManager.hasProfile(userId: number): boolean
  return loadedProfiles[userId] ~= nil
end

-- Get count of loaded profiles
function ProfileManager.getLoadedProfileCount(): number
  local count = 0
  for _ in pairs(loadedProfiles) do
    count += 1
  end
  return count
end

-- Get global chicken counts across all loaded profiles
function ProfileManager.getGlobalChickenCounts(): { [string]: number }
  local counts: { [string]: number } = {}

  for _, data in pairs(profileData) do
    -- Count placed chickens
    if data.placedChickens then
      for _, chicken in ipairs(data.placedChickens) do
        local chickenType = chicken.chickenType
        counts[chickenType] = (counts[chickenType] or 0) + 1
      end
    end

    -- Count inventory chickens
    if data.inventory and data.inventory.chickens then
      for _, chicken in ipairs(data.inventory.chickens) do
        local chickenType = chicken.chickenType
        counts[chickenType] = (counts[chickenType] or 0) + 1
      end
    end
  end

  return counts
end

-- Setup player connections
function ProfileManager.setupPlayerConnections(): ()
  -- Handle player joining
  Players.PlayerAdded:Connect(function(player)
    local result = ProfileManager.loadProfile(player)
    if result.success and result.data then
      if
        (result.offlineEarnings and result.offlineEarnings > 0)
        or (result.offlineEggs and result.offlineEggs > 0)
      then
        print(
          string.format(
            "[ProfileManager] %s earned $%.2f and %d eggs while offline (%d seconds)",
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
          "[ProfileManager] Failed to load profile for %s: %s",
          player.Name,
          result.message
        )
      )
    end
  end)

  -- Handle player leaving
  Players.PlayerRemoving:Connect(function(player)
    ProfileManager.releaseProfile(player)
  end)
end

-- Graceful shutdown handling
function ProfileManager.setupShutdown(): ()
  game:BindToClose(function()
    print("[ProfileManager] Server shutting down, releasing all profiles...")

    -- Release all loaded profiles
    for userId, profile in pairs(loadedProfiles) do
      local currentTime = os.time()
      profile.Data.lastLogoutTime = currentTime
      profile:Release()
    end

    -- Clear state
    loadedProfiles = {}
    profileData = {}

    -- Small wait to ensure ProfileService finishes saving
    task.wait(1)
    print("[ProfileManager] All profiles released")
  end)
end

-- Initialize and start the profile system
function ProfileManager.start(): boolean
  local initSuccess = ProfileManager.init()

  ProfileManager.setupPlayerConnections()
  ProfileManager.setupShutdown()

  print("[ProfileManager] Profile management system started")
  return initSuccess
end

return ProfileManager
