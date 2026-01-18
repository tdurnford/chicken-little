--[[
	ChickenService - Knit Service
	
	Handles all chicken-related operations including:
	- Chicken placement and pickup
	- Egg hatching
	- Egg collection from world
	- Money collection from chickens
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))
local EggHatching = require(Shared:WaitForChild("EggHatching"))
local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
local WorldEgg = require(Shared:WaitForChild("WorldEgg"))
local ChickenAI = require(Shared:WaitForChild("ChickenAI"))
local ChickenHealth = require(Shared:WaitForChild("ChickenHealth"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

local ChickenService = Knit.CreateService({
	Name = "ChickenService",
	
	-- Client-exposed API
	Client = {
		-- Signals
		ChickenPlaced = Knit.Signal.new(),
		ChickenPickedUp = Knit.Signal.new(),
		ChickenMoved = Knit.Signal.new(),
		ChickenDamaged = Knit.Signal.new(),
		ChickenHealthChanged = Knit.Signal.new(),
		ChickenDied = Knit.Signal.new(),
		ChickenPositionUpdated = Knit.Signal.new(),
		EggHatched = Knit.Signal.new(),
		EggSpawned = Knit.Signal.new(),
		EggCollected = Knit.Signal.new(),
		EggDespawned = Knit.Signal.new(),
		MoneyCollected = Knit.Signal.new(),
	},
	
	-- Server state
	_playerService = nil,
	_gameStateService = nil,
})

--[[
	Client Methods - Exposed via Knit remotes
]]

function ChickenService.Client:PlaceChicken(player: Player, chickenId: string, spotIndex: number?)
	return self.Server:PlaceChicken(player, chickenId, spotIndex)
end

function ChickenService.Client:PickupChicken(player: Player, chickenId: string)
	return self.Server:PickupChicken(player, chickenId)
end

function ChickenService.Client:MoveChicken(player: Player, chickenId: string, newSpotIndex: number)
	return self.Server:MoveChicken(player, chickenId, newSpotIndex)
end

function ChickenService.Client:HatchEgg(player: Player, eggId: string, placementHint: number?, playerPosition: { x: number, y: number, z: number }?)
	return self.Server:HatchEgg(player, eggId, placementHint, playerPosition)
end

function ChickenService.Client:CollectWorldEgg(player: Player, eggId: string)
	return self.Server:CollectWorldEgg(player, eggId)
end

function ChickenService.Client:CollectMoney(player: Player, chickenId: string?)
	return self.Server:CollectMoney(player, chickenId)
end

--[[
	Server Methods
]]

function ChickenService:PlaceChicken(player: Player, chickenId: string, _spotIndex: number?)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- Check chicken limit before placing
	if ChickenPlacement.isAtChickenLimit(playerData) then
		local limitInfo = ChickenPlacement.getChickenLimitInfo(playerData)
		return {
			success = false,
			message = "Area full! Maximum " .. limitInfo.max .. " chickens per area.",
			atLimit = true,
		}
	end
	
	-- Use free-roaming placement
	local result = ChickenPlacement.placeChickenFreeRoaming(playerData, chickenId)
	if result.success then
		local gameState = self._gameStateService:GetPlayerGameState(userId)
		
		-- Register chicken with health system
		if result.chicken and result.chicken.chickenType then
			ChickenHealth.register(gameState.chickenHealthRegistry, chickenId, result.chicken.chickenType)
		end
		
		-- Register chicken with AI for free-roaming behavior
		if gameState.playerChickenAIState and result.chicken then
			local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
			if sectionCenter then
				local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
				local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
				ChickenAI.registerChicken(gameState.playerChickenAIState, chickenId, result.chicken.chickenType, spawnPosV3, os.clock())
			end
		end
		
		-- Get initial position from AI
		local initialPosition = nil
		if gameState.playerChickenAIState then
			local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, chickenId)
			if aiPos then
				initialPosition = aiPos.currentPosition
			end
		end
		
		-- Fire ChickenPlaced signal to all clients
		self.Client.ChickenPlaced:FireAll({
			playerId = userId,
			chicken = result.chicken,
			spotIndex = nil,
			position = initialPosition,
		})
		
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function ChickenService:PickupChicken(player: Player, chickenId: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- Get the spot index before pickup
	local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
	local spotIndex = chicken and chicken.spotIndex or nil
	
	local result = ChickenPlacement.pickupChicken(playerData, chickenId)
	if result.success then
		local gameState = self._gameStateService:GetPlayerGameState(userId)
		
		-- Unregister chicken from health system
		ChickenHealth.unregister(gameState.chickenHealthRegistry, chickenId)
		
		-- Unregister chicken from AI
		if gameState.playerChickenAIState then
			ChickenAI.unregisterChicken(gameState.playerChickenAIState, chickenId)
		end
		
		-- Fire ChickenPickedUp signal to all clients
		self.Client.ChickenPickedUp:FireAll({
			playerId = userId,
			chickenId = chickenId,
			spotIndex = spotIndex,
		})
		
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function ChickenService:MoveChicken(player: Player, chickenId: string, newSpotIndex: number)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
	local oldSpotIndex = chicken and chicken.spotIndex or nil
	
	local result = ChickenPlacement.moveChicken(playerData, chickenId, newSpotIndex)
	if result.success then
		-- Fire ChickenMoved signal to all clients
		self.Client.ChickenMoved:FireAll({
			playerId = userId,
			chickenId = chickenId,
			oldSpotIndex = oldSpotIndex,
			newSpotIndex = newSpotIndex,
			chicken = result.chicken,
		})
		
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function ChickenService:HatchEgg(player: Player, eggId: string, placementHint: number?, playerPosition: { x: number, y: number, z: number }?)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- If placement hint provided, check chicken limit before hatching
	if placementHint and ChickenPlacement.isAtChickenLimit(playerData) then
		local limitInfo = ChickenPlacement.getChickenLimitInfo(playerData)
		return {
			success = false,
			message = "Area full! Maximum " .. limitInfo.max .. " chickens per area.",
			atLimit = true,
		}
	end
	
	local result = EggHatching.hatch(playerData, eggId)
	if result.success then
		-- If placement hint provided, move the chicken from inventory to placed
		if placementHint and result.chickenId then
			local chickenIndex = nil
			local chickenData = nil
			for i, chicken in ipairs(playerData.inventory.chickens) do
				if chicken.id == result.chickenId then
					chickenIndex = i
					chickenData = chicken
					break
				end
			end
			
			if chickenIndex and chickenData then
				-- Remove from inventory and add to placed chickens (free-roaming)
				local chicken = table.remove(playerData.inventory.chickens, chickenIndex)
				chicken.spotIndex = nil
				table.insert(playerData.placedChickens, chicken)
				
				local gameState = self._gameStateService:GetPlayerGameState(userId)
				
				-- Register chicken with health system
				ChickenHealth.register(gameState.chickenHealthRegistry, result.chickenId, chicken.chickenType)
				
				-- Register chicken with AI for free-roaming behavior
				if gameState.playerChickenAIState then
					local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
					if sectionCenter then
						local spawnPos
						if playerPosition then
							spawnPos = PlayerSection.getPositionNear(playerPosition, sectionCenter, 3)
						else
							spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
						end
						local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
						ChickenAI.registerChicken(gameState.playerChickenAIState, result.chickenId, chicken.chickenType, spawnPosV3, os.clock())
					end
				end
				
				-- Get initial position from AI
				local initialPosition = nil
				if gameState.playerChickenAIState then
					local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, result.chickenId)
					if aiPos then
						initialPosition = aiPos.currentPosition
					end
				end
				
				-- Fire ChickenPlaced signal
				self.Client.ChickenPlaced:FireClient(player, {
					chicken = chicken,
					spotIndex = nil,
					position = initialPosition,
				})
			end
		end
		
		-- Fire EggHatched signal to player with result
		self.Client.EggHatched:FireClient(player, {
			chickenType = result.chickenType,
			chickenRarity = result.chickenRarity,
			chickenId = result.chickenId,
			isRareHatch = result.isRareHatch,
			celebrationTier = result.celebrationTier,
			message = result.message,
		})
		
		-- Award XP for hatching a chicken
		if result.chickenRarity then
			local xpAmount = XPConfig.calculateChickenHatchXP(result.chickenRarity)
			self._playerService:AwardXP(player, playerData, xpAmount, "Hatched " .. (result.chickenType or "chicken"))
		end
		
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function ChickenService:CollectWorldEgg(player: Player, eggId: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local gameState = self._gameStateService:GetPlayerGameState(userId)
	local success, message, inventoryEgg = WorldEgg.collect(gameState.worldEggRegistry, eggId, userId)
	
	if success and inventoryEgg then
		-- Add egg to player inventory
		table.insert(playerData.inventory.eggs, inventoryEgg)
		
		-- Fire EggCollected signal to player
		self.Client.EggCollected:FireClient(player, {
			eggId = inventoryEgg.id,
			eggType = inventoryEgg.eggType,
			rarity = inventoryEgg.rarity,
		})
		
		-- Award XP for collecting an egg
		local xpAmount = XPConfig.calculateEggCollectedXP(inventoryEgg.rarity)
		self._playerService:AwardXP(player, playerData, xpAmount, "Collected " .. inventoryEgg.eggType)
		
		self._playerService:SyncPlayerData(player, playerData, true)
		return { success = true, message = message, egg = inventoryEgg }
	end
	
	return { success = false, message = message }
end

function ChickenService:CollectMoney(player: Player, chickenId: string?)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result
	if chickenId then
		result = MoneyCollection.collect(playerData, chickenId)
	else
		result = MoneyCollection.collectAll(playerData)
	end
	
	if result.success then
		local amountCollected = result.amountCollected or result.totalCollected or 0
		if amountCollected > 0 then
			-- Fire MoneyCollected signal to update client visuals
			self.Client.MoneyCollected:FireClient(player, amountCollected, nil)
			self._playerService:SyncPlayerData(player, playerData, true)
		end
	end
	return result
end

--[[
	Lifecycle Methods
]]

function ChickenService:KnitInit()
	print("[ChickenService] Initializing...")
end

function ChickenService:KnitStart()
	-- Get references to other services
	self._playerService = Knit.GetService("PlayerService")
	self._gameStateService = Knit.GetService("GameStateService")
	
	print("[ChickenService] Started")
end

return ChickenService
