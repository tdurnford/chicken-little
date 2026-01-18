--[[
	PlayerService - Knit Service
	
	Handles all player data operations including:
	- Player data persistence
	- Player data synchronization
	- Money transactions
	- XP and leveling
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

local PlayerService = Knit.CreateService({
	Name = "PlayerService",
	
	-- Client-exposed API
	Client = {
		-- Signals
		PlayerDataChanged = Knit.Signal.new(),
		XPGained = Knit.Signal.new(),
		LevelUp = Knit.Signal.new(),
		BankruptcyAssistance = Knit.Signal.new(),
		ProtectionStatusChanged = Knit.Signal.new(),
	},
	
	-- Server state
	_dataPersistence = nil,
	_playerDataCache = {},
	_lastSyncTime = {},
	_playerJoinTimes = {},
	_lastBankruptcyAssistanceTime = {},
	
	-- Configuration
	DATA_SYNC_THROTTLE_INTERVAL = 0.1,
	NEW_PLAYER_PROTECTION_DURATION = 120,
	BANKRUPTCY_ASSISTANCE_COOLDOWN = 300,
})

--[[
	Client Methods - Exposed via Knit remotes
]]

function PlayerService.Client:GetPlayerData(player: Player)
	return self.Server:GetPlayerData(player.UserId)
end

function PlayerService.Client:GetGlobalChickenCounts(player: Player)
	return self.Server:GetGlobalChickenCounts()
end

--[[
	Server Methods
]]

function PlayerService:GetPlayerData(userId: number)
	if self._dataPersistence then
		return self._dataPersistence.getData(userId)
	end
	return self._playerDataCache[userId]
end

function PlayerService:SetDataPersistence(dataPersistence)
	self._dataPersistence = dataPersistence
end

function PlayerService:GetGlobalChickenCounts()
	if self._dataPersistence and self._dataPersistence.getGlobalChickenCounts then
		return self._dataPersistence.getGlobalChickenCounts()
	end
	return {}
end

function PlayerService:SyncPlayerData(player: Player, data: { [string]: any }?, forceSync: boolean?)
	local userId = player.UserId
	local currentTime = os.clock()
	local lastSync = self._lastSyncTime[userId] or 0
	
	-- Throttle check (skip if forceSync is true)
	if not forceSync and (currentTime - lastSync) < self.DATA_SYNC_THROTTLE_INTERVAL then
		return
	end
	
	-- Get data from cache if not provided
	local syncData = data or self:GetPlayerData(userId)
	if not syncData then
		return
	end
	
	-- Fire the signal to the client
	self.Client.PlayerDataChanged:FireClient(player, syncData)
	self._lastSyncTime[userId] = currentTime
end

function PlayerService:AwardXP(player: Player, playerData: PlayerData.PlayerDataSchema, xpAmount: number, reason: string)
	if xpAmount <= 0 then
		return
	end
	
	-- Award XP and check for level up
	local newLevel = PlayerData.addXP(playerData, xpAmount)
	
	-- Fire XPGained signal to player
	self.Client.XPGained:FireClient(player, xpAmount, reason)
	
	-- If player leveled up, fire LevelUp signal
	if newLevel then
		-- Check what unlocks at this level
		local unlocks = {}
		
		-- Check threat level unlocks
		local threatUnlockLevels = LevelConfig.getThreatUnlockLevels()
		for threatLevel, requiredLevel in pairs(threatUnlockLevels) do
			if requiredLevel == newLevel then
				table.insert(unlocks, threatLevel .. " predators unlocked!")
			end
		end
		
		-- Check max predator increase
		local prevMaxPredators = LevelConfig.getMaxPredatorsForLevel(newLevel - 1)
		local newMaxPredators = LevelConfig.getMaxPredatorsForLevel(newLevel)
		if newMaxPredators > prevMaxPredators then
			table.insert(unlocks, "Max simultaneous predators: " .. newMaxPredators)
		end
		
		-- Fire LevelUp signal to player
		self.Client.LevelUp:FireClient(player, newLevel, unlocks)
		
		print("[PlayerService] Player", player.Name, "leveled up to", newLevel)
	end
end

function PlayerService:IsPlayerProtected(userId: number): boolean
	local joinTime = self._playerJoinTimes[userId]
	if not joinTime then
		return false
	end
	return (os.time() - joinTime) < self.NEW_PLAYER_PROTECTION_DURATION
end

function PlayerService:GetProtectionRemaining(userId: number): number
	local joinTime = self._playerJoinTimes[userId]
	if not joinTime then
		return 0
	end
	return math.max(0, self.NEW_PLAYER_PROTECTION_DURATION - (os.time() - joinTime))
end

function PlayerService:CheckAndApplyBankruptcyAssistance(player: Player)
	local currentTime = os.time()
	local userId = player.UserId
	
	-- Get player data
	local playerData = self:GetPlayerData(userId)
	if not playerData then
		return
	end
	
	-- Check if player is actually bankrupt
	if not PlayerData.isBankrupt(playerData) then
		return
	end
	
	-- Check cooldown to prevent exploitation
	local lastAssistance = self._lastBankruptcyAssistanceTime[userId]
	if lastAssistance and (currentTime - lastAssistance) < self.BANKRUPTCY_ASSISTANCE_COOLDOWN then
		return
	end
	
	-- Apply bankruptcy assistance
	local starterMoney = PlayerData.getBankruptcyStarterMoney()
	local amountNeeded = math.max(0, starterMoney - playerData.money)
	if amountNeeded <= 0 then
		return
	end
	
	playerData.money = playerData.money + amountNeeded
	self._lastBankruptcyAssistanceTime[userId] = currentTime
	
	-- Sync player data
	self:SyncPlayerData(player, playerData, true)
	
	-- Notify client about bankruptcy assistance
	self.Client.BankruptcyAssistance:FireClient(player, {
		moneyAwarded = amountNeeded,
		message = string.format("You've been given $%d to help you get back on your feet!", amountNeeded),
	})
	
	print(string.format("[PlayerService] Awarded $%d bankruptcy assistance to %s", amountNeeded, player.Name))
end

function PlayerService:OnPlayerJoined(player: Player)
	local userId = player.UserId
	self._playerJoinTimes[userId] = os.time()
	
	-- Send initial protection status
	self.Client.ProtectionStatusChanged:FireClient(player, {
		isProtected = true,
		remainingSeconds = self.NEW_PLAYER_PROTECTION_DURATION,
		totalDuration = self.NEW_PLAYER_PROTECTION_DURATION,
	})
end

function PlayerService:OnPlayerLeft(player: Player)
	local userId = player.UserId
	self._lastSyncTime[userId] = nil
	self._playerJoinTimes[userId] = nil
	self._lastBankruptcyAssistanceTime[userId] = nil
end

--[[
	Lifecycle Methods
]]

function PlayerService:KnitInit()
	print("[PlayerService] Initializing...")
end

function PlayerService:KnitStart()
	-- Connect to player events
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerJoined(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerLeft(player)
	end)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerJoined(player)
	end
	
	print("[PlayerService] Started")
end

return PlayerService
