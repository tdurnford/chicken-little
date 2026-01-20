--[[
	PlayerDataService
	Knit service that wraps ProfileManager and exposes player data to clients.
	
	Provides:
	- Client access to player data via Knit
	- Data change signals for reactive UI updates
	- Safe wrappers around ProfileManager methods
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))

-- ProfileManager is required lazily to avoid circular dependency at load time
local ProfileManager

-- Create the service
local PlayerDataService = Knit.CreateService({
  Name = "PlayerDataService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to specific clients
    DataChanged = Knit.CreateSignal(), -- Fires full data on change
    MoneyChanged = Knit.CreateSignal(), -- Fires (newMoney: number)
    InventoryChanged = Knit.CreateSignal(), -- Fires (inventory: table)
    LevelChanged = Knit.CreateSignal(), -- Fires (level: number, xp: number)
  },
})

-- Server-side signals (for other services to listen to)
PlayerDataService.DataUpdated = GoodSignal.new() -- (userId: number, data: PlayerDataSchema)
PlayerDataService.PlayerLoaded = GoodSignal.new() -- (userId: number, data: PlayerDataSchema, isNewPlayer: boolean)
PlayerDataService.PlayerUnloading = GoodSignal.new() -- (userId: number)

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function PlayerDataService:KnitInit()
  -- Require ProfileManager here to avoid load-time issues
  ProfileManager = require(ServerScriptService:WaitForChild("ProfileManager"))

  print("[PlayerDataService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function PlayerDataService:KnitStart()
  -- Setup player connections for load/unload notifications
  Players.PlayerAdded:Connect(function(player)
    -- ProfileManager handles the actual loading via its own PlayerAdded connection
    -- We just need to wait for the data to be available and fire our signal
    task.spawn(function()
      -- Wait for profile to be loaded (max 10 seconds)
      local maxWait = 10
      local waited = 0
      while waited < maxWait do
        local data = ProfileManager.getData(player.UserId)
        if data then
          -- Check if this is a new player and auto-activate shield
          local isNewPlayer = data.totalPlayTime == 0
          if isNewPlayer and data.shieldState then
            local currentTime = os.time()
            -- Only activate if shield is not already active
            if not AreaShield.isActive(data.shieldState, currentTime) then
              local result = AreaShield.activate(data.shieldState, currentTime)
              if result.success then
                print(string.format("[PlayerDataService] Auto-activated 2-minute shield for new player %s", player.Name))
                ProfileManager.updateData(player.UserId, data)
              end
            end
          end

          -- Fire the loaded signal
          self.PlayerLoaded:Fire(player.UserId, data, isNewPlayer)

          -- Send initial data to client
          self.Client.DataChanged:Fire(player, data)
          break
        end
        task.wait(0.1)
        waited += 0.1
      end
    end)
  end)

  Players.PlayerRemoving:Connect(function(player)
    -- Fire unloading signal before ProfileManager releases
    self.PlayerUnloading:Fire(player.UserId)
  end)

  print("[PlayerDataService] Started")
end

--[[
	Gets the player's current data.
	Returns nil if player has no loaded profile.
	
	@param player Player - The player requesting data
	@return PlayerDataSchema? - The player's data or nil
]]
function PlayerDataService.Client:GetData(player: Player): PlayerData.PlayerDataSchema?
  return ProfileManager.getData(player.UserId)
end

--[[
	Gets the player's current money.
	
	@param player Player - The player requesting data
	@return number - The player's money (0 if no profile)
]]
function PlayerDataService.Client:GetMoney(player: Player): number
  local data = ProfileManager.getData(player.UserId)
  if data then
    return data.money
  end
  return 0
end

--[[
	Gets the player's inventory.
	
	@param player Player - The player requesting data
	@return InventoryData? - The player's inventory or nil
]]
function PlayerDataService.Client:GetInventory(player: Player): PlayerData.InventoryData?
  local data = ProfileManager.getData(player.UserId)
  if data then
    return data.inventory
  end
  return nil
end

--[[
	Gets the player's placed chickens.
	
	@param player Player - The player requesting data
	@return {ChickenData} - Array of placed chickens
]]
function PlayerDataService.Client:GetPlacedChickens(player: Player): { PlayerData.ChickenData }
  local data = ProfileManager.getData(player.UserId)
  if data then
    return data.placedChickens
  end
  return {}
end

--[[
	Gets the player's level and XP.
	
	@param player Player - The player requesting data
	@return number, number - Level and XP
]]
function PlayerDataService.Client:GetLevelInfo(player: Player): (number, number)
  local data = ProfileManager.getData(player.UserId)
  if data then
    return PlayerData.getLevel(data), PlayerData.getXP(data)
  end
  return 1, 0
end

--[[
	Marks the tutorial as completed for the player.
	Called when player completes or skips the tutorial.
	
	@param player Player - The player completing the tutorial
	@return boolean - Whether the update succeeded
]]
function PlayerDataService.Client:CompleteTutorial(player: Player): boolean
  local data = ProfileManager.getData(player.UserId)
  if not data then
    return false
  end

  data.tutorialComplete = true
  return PlayerDataService:UpdateData(player.UserId, data)
end

--[[
	SERVER-ONLY: Gets data for any player by userId.
	
	@param userId number - The user ID
	@return PlayerDataSchema? - The player's data or nil
]]
function PlayerDataService:GetData(userId: number): PlayerData.PlayerDataSchema?
  return ProfileManager.getData(userId)
end

--[[
	SERVER-ONLY: Updates a player's data and notifies clients.
	
	@param userId number - The user ID
	@param data PlayerDataSchema - The new data
	@return boolean - Whether the update succeeded
]]
function PlayerDataService:UpdateData(userId: number, data: PlayerData.PlayerDataSchema): boolean
  local previousData = ProfileManager.getData(userId)
  local success = ProfileManager.updateData(userId, data)

  if success then
    -- Fire server-side signal
    self.DataUpdated:Fire(userId, data)

    -- Find the player and notify client
    local player = Players:GetPlayerByUserId(userId)
    if player then
      -- Fire DataChanged with full data
      self.Client.DataChanged:Fire(player, data)

      -- Fire specific change signals if relevant fields changed
      if previousData then
        if previousData.money ~= data.money then
          self.Client.MoneyChanged:Fire(player, data.money)
        end

        -- Check inventory changes (simple reference check - may need deep comparison)
        if previousData.inventory ~= data.inventory then
          self.Client.InventoryChanged:Fire(player, data.inventory)
        end

        -- Check level/XP changes
        local prevLevel = PlayerData.getLevel(previousData)
        local newLevel = PlayerData.getLevel(data)
        local prevXP = PlayerData.getXP(previousData)
        local newXP = PlayerData.getXP(data)

        if prevLevel ~= newLevel or prevXP ~= newXP then
          self.Client.LevelChanged:Fire(player, newLevel, newXP)
        end
      end
    end
  end

  return success
end

--[[
	SERVER-ONLY: Checks if a player has a loaded profile.
	
	@param userId number - The user ID
	@return boolean - Whether the player has a loaded profile
]]
function PlayerDataService:HasProfile(userId: number): boolean
  return ProfileManager.hasProfile(userId)
end

--[[
	SERVER-ONLY: Updates just the money field and notifies client.
	Convenience method for common money operations.
	
	@param userId number - The user ID
	@param newMoney number - The new money amount
	@return boolean - Whether the update succeeded
]]
function PlayerDataService:SetMoney(userId: number, newMoney: number): boolean
  local data = ProfileManager.getData(userId)
  if not data then
    return false
  end

  data.money = newMoney
  return self:UpdateData(userId, data)
end

--[[
	SERVER-ONLY: Adds money to a player's balance.
	
	@param userId number - The user ID
	@param amount number - Amount to add (can be negative)
	@return boolean, number? - Success and new balance
]]
function PlayerDataService:AddMoney(userId: number, amount: number): (boolean, number?)
  local data = ProfileManager.getData(userId)
  if not data then
    return false, nil
  end

  local newMoney = data.money + amount
  if newMoney < 0 then
    return false, nil -- Would go negative
  end

  data.money = newMoney
  local success = self:UpdateData(userId, data)
  return success, success and newMoney or nil
end

--[[
	SERVER-ONLY: Adds XP and handles level-up notifications.
	
	@param userId number - The user ID
	@param amount number - XP amount to add
	@return boolean, number? - Success and new level if leveled up
]]
function PlayerDataService:AddXP(userId: number, amount: number): (boolean, number?)
  local data = ProfileManager.getData(userId)
  if not data then
    return false, nil
  end

  local newLevel = PlayerData.addXP(data, amount)
  local success = self:UpdateData(userId, data)

  return success, newLevel
end

--[[
	SERVER-ONLY: Gets global chicken counts across all loaded profiles.
	
	@return {[string]: number} - Map of chicken type to count
]]
function PlayerDataService:GetGlobalChickenCounts(): { [string]: number }
  return ProfileManager.getGlobalChickenCounts()
end

--[[
	SERVER-ONLY: Gets the count of loaded profiles.
	
	@return number - Number of loaded profiles
]]
function PlayerDataService:GetLoadedProfileCount(): number
  return ProfileManager.getLoadedProfileCount()
end

return PlayerDataService
