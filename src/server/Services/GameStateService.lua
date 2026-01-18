--[[
	GameStateService - Knit Service
	
	Manages per-player game state including:
	- Predator spawning and AI state
	- Combat state
	- Chicken health registry
	- World egg registry
	- Day/night cycle
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
local PredatorAI = require(Shared:WaitForChild("PredatorAI"))
local CageLocking = require(Shared:WaitForChild("CageLocking"))
local ChickenStealing = require(Shared:WaitForChild("ChickenStealing"))
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))
local CombatHealth = require(Shared:WaitForChild("CombatHealth"))
local ChickenHealth = require(Shared:WaitForChild("ChickenHealth"))
local ChickenAI = require(Shared:WaitForChild("ChickenAI"))
local WorldEgg = require(Shared:WaitForChild("WorldEgg"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))
local RandomChickenSpawn = require(Shared:WaitForChild("RandomChickenSpawn"))

-- Type definition for player game state
export type PlayerGameState = {
	spawnState: PredatorSpawning.SpawnState,
	lockState: CageLocking.LockState,
	stealState: ChickenStealing.StealState,
	batState: BaseballBat.BatState,
	combatState: CombatHealth.CombatState,
	chickenHealthRegistry: ChickenHealth.ChickenHealthRegistry,
	predatorAIState: PredatorAI.PredatorAIState,
	worldEggRegistry: WorldEgg.WorldEggRegistry,
	playerChickenAIState: ChickenAI.ChickenAIState?,
}

local GameStateService = Knit.CreateService({
	Name = "GameStateService",
	
	-- Client-exposed API
	Client = {
		-- Signals
		PredatorSpawned = Knit.Signal.new(),
		PredatorDefeated = Knit.Signal.new(),
		PredatorPositionUpdated = Knit.Signal.new(),
		PredatorHealthUpdated = Knit.Signal.new(),
		PredatorTargetChanged = Knit.Signal.new(),
		RandomChickenSpawned = Knit.Signal.new(),
		RandomChickenClaimed = Knit.Signal.new(),
		RandomChickenDespawned = Knit.Signal.new(),
		RandomChickenPositionUpdated = Knit.Signal.new(),
		NightfallWarning = Knit.Signal.new(),
		AlertTriggered = Knit.Signal.new(),
		LockActivated = Knit.Signal.new(),
	},
	
	-- Server state
	_playerGameStates = {},
	_mapState = nil,
	_dayNightState = nil,
	_randomChickenSpawnState = nil,
	_chickenAIState = nil,
	
	-- Game loop tracking
	_lastCleanupTime = 0,
	_lastStoreReplenishCheck = 0,
	_previousTimeOfDay = "day",
	_playerNightCycleCount = {},
	_currentNightCycleNumber = 0,
	_wasNight = false,
	
	-- Configuration
	PREDATOR_CLEANUP_INTERVAL = 10,
})

--[[
	Client Methods - Exposed via Knit remotes
]]

function GameStateService.Client:ClaimRandomChicken(player: Player)
	return self.Server:ClaimRandomChicken(player)
end

--[[
	Server Methods
]]

function GameStateService:CreatePlayerGameState(): PlayerGameState
	return {
		spawnState = PredatorSpawning.createSpawnState(),
		lockState = CageLocking.createLockState(),
		stealState = ChickenStealing.createStealState(),
		batState = BaseballBat.createBatState(),
		combatState = CombatHealth.createState(),
		chickenHealthRegistry = ChickenHealth.createRegistry(),
		predatorAIState = PredatorAI.createState(),
		worldEggRegistry = WorldEgg.createRegistry(),
		playerChickenAIState = nil,
	}
end

function GameStateService:GetPlayerGameState(userId: number): PlayerGameState
	if not self._playerGameStates[userId] then
		self._playerGameStates[userId] = self:CreatePlayerGameState()
	end
	return self._playerGameStates[userId]
end

function GameStateService:GetMapState()
	return self._mapState
end

function GameStateService:GetDayNightState()
	return self._dayNightState
end

function GameStateService:GetRandomChickenSpawnState()
	return self._randomChickenSpawnState
end

function GameStateService:GetChickenAIState()
	return self._chickenAIState
end

function GameStateService:InitializePlayerChickenAI(userId: number, sectionIndex: number)
	local gameState = self:GetPlayerGameState(userId)
	local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
	if sectionCenter then
		gameState.playerChickenAIState = ChickenAI.createSectionState(sectionCenter)
	end
end

function GameStateService:ClaimRandomChicken(player: Player)
	local userId = player.UserId
	local playerService = Knit.GetService("PlayerService")
	local playerData = playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- Get player position
	local character = player.Character
	if not character then
		return { success = false, message = "No character" }
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return { success = false, message = "No HumanoidRootPart" }
	end
	
	local position = rootPart.Position
	local playerPosition = {
		x = position.X,
		y = position.Y,
		z = position.Z,
	}
	
	-- Attempt to claim the chicken
	local currentTime = os.time()
	local playerId = tostring(userId)
	local result = RandomChickenSpawn.claimChicken(self._randomChickenSpawnState, playerId, playerPosition, currentTime)
	
	if result.success and result.chicken then
		-- Remove chicken from AI tracking
		ChickenAI.unregisterChicken(self._chickenAIState, result.chicken.id)
		
		-- Add chicken to player's inventory
		local PlayerData = require(Shared:WaitForChild("PlayerData"))
		local chickenData = {
			id = PlayerData.generateId(),
			chickenType = result.chicken.chickenType,
			rarity = result.chicken.rarity,
			accumulatedMoney = 0,
			lastEggTime = currentTime,
			spotIndex = nil,
		}
		table.insert(playerData.inventory.chickens, chickenData)
		
		-- Fire RandomChickenClaimed signal to all clients
		self.Client.RandomChickenClaimed:FireAll(result.chicken.id, player)
		
		-- Award XP for catching a random chicken
		local XPConfig = require(Shared:WaitForChild("XPConfig"))
		local xpAmount = XPConfig.calculateRandomChickenXP(result.chicken.rarity)
		playerService:AwardXP(player, playerData, xpAmount, "Caught " .. result.chicken.chickenType)
		
		-- Sync player data
		playerService:SyncPlayerData(player, playerData, true)
		
		print("[GameStateService] Player", player.Name, "claimed random chicken:", result.chicken.chickenType, result.chicken.rarity)
		
		return {
			success = true,
			chicken = result.chicken,
			message = "Chicken claimed!",
			playerData = playerData,
		}
	else
		return {
			success = false,
			message = result.reason or "Failed to claim chicken",
		}
	end
end

function GameStateService:CleanupPlayerState(userId: number)
	self._playerGameStates[userId] = nil
	self._playerNightCycleCount[userId] = nil
end

--[[
	Lifecycle Methods
]]

function GameStateService:KnitInit()
	-- Initialize map generation
	self._mapState = MapGeneration.createMapState()
	print(string.format("[GameStateService] MapGeneration initialized: %d sections created", #self._mapState.sections))
	
	-- Initialize day/night cycle
	self._dayNightState = DayNightCycle.init()
	print("[GameStateService] Day/Night cycle initialized")
	
	-- Initialize random chicken spawn state
	local initialTime = os.time()
	local mapConfig = MapGeneration.getConfig()
	local sectionSize = PlayerSection.getSectionSize()
	
	-- Create spawn zones for each player section across the map
	local spawnZones = RandomChickenSpawn.createSpawnZonesFromMap({
		gridColumns = mapConfig.gridColumns,
		gridRows = mapConfig.gridRows,
		sectionWidth = sectionSize.x,
		sectionDepth = sectionSize.z,
		sectionGap = mapConfig.sectionGap,
		originPosition = mapConfig.originPosition,
	})
	
	local randomSpawnConfig = {
		spawnIntervalMin = 120,
		spawnIntervalMax = 300,
		despawnTime = 30,
		neutralZoneCenter = { x = 0, y = 0, z = 0 },
		neutralZoneSize = 32,
		claimRange = 8,
		spawnZones = spawnZones,
	}
	
	self._randomChickenSpawnState = RandomChickenSpawn.createSpawnState(randomSpawnConfig, initialTime)
	print(string.format("[GameStateService] RandomChickenSpawn initialized with %d spawn zones", #spawnZones))
	
	-- Initialize global chicken AI state
	local spawnConfig = self._randomChickenSpawnState.config
	self._chickenAIState = ChickenAI.createState(
		Vector3.new(spawnConfig.neutralZoneCenter.x, spawnConfig.neutralZoneCenter.y, spawnConfig.neutralZoneCenter.z),
		spawnConfig.neutralZoneSize
	)
	print("[GameStateService] ChickenAI initialized")
end

function GameStateService:KnitStart()
	-- Handle player cleanup on leave
	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayerState(player.UserId)
	end)
	
	print("[GameStateService] Started")
end

return GameStateService
