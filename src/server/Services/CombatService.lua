--[[
	CombatService - Knit Service
	
	Handles all combat-related operations including:
	- Weapon swings and attacks
	- Predator combat
	- Player knockback
	- Shield activation
	- Trap placement
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))
local CombatHealth = require(Shared:WaitForChild("CombatHealth"))
local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
local PredatorAI = require(Shared:WaitForChild("PredatorAI"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))
local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))
local WeaponTool = require(Shared:WaitForChild("WeaponTool"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))

local CombatService = Knit.CreateService({
	Name = "CombatService",
	
	-- Client-exposed API
	Client = {
		-- Signals
		PlayerDamaged = Knit.Signal.new(),
		PlayerKnockback = Knit.Signal.new(),
		PlayerHealthChanged = Knit.Signal.new(),
		PlayerIncapacitated = Knit.Signal.new(),
		MoneyLost = Knit.Signal.new(),
		TrapPlaced = Knit.Signal.new(),
		TrapCaught = Knit.Signal.new(),
		ShieldActivated = Knit.Signal.new(),
		ShieldDeactivated = Knit.Signal.new(),
		BatEquipped = Knit.Signal.new(),
		WeaponEquipped = Knit.Signal.new(),
	},
	
	-- Server state
	_playerService = nil,
	_gameStateService = nil,
})

--[[
	Client Methods - Exposed via Knit remotes
]]

function CombatService.Client:SwingBat(player: Player, action: string, targetType: string?, targetId: string?)
	return self.Server:SwingBat(player, action, targetType, targetId)
end

function CombatService.Client:EquipWeapon(player: Player, weaponType: string?)
	return self.Server:EquipWeapon(player, weaponType)
end

function CombatService.Client:ActivateShield(player: Player)
	return self.Server:ActivateShield(player)
end

function CombatService.Client:PlaceTrap(player: Player, trapId: string, spotIndex: number)
	return self.Server:PlaceTrap(player, trapId, spotIndex)
end

--[[
	Server Methods
]]

function CombatService:SwingBat(player: Player, action: string, targetType: string?, targetId: string?)
	local userId = player.UserId
	local gameState = self._gameStateService:GetPlayerGameState(userId)
	local batState = gameState.batState
	local currentTime = os.clock()
	
	-- Only handle swing action - equip/unequip is handled by Roblox Tool system
	if action ~= "swing" then
		return { success = false, message = "Invalid action" }
	end
	
	-- Check if player has a weapon Tool equipped
	local equippedTool = WeaponTool.getEquippedWeapon(player)
	if not equippedTool then
		return { success = false, message = "No weapon equipped" }
	end
	
	-- Get weapon type from the equipped tool
	local weaponType = WeaponTool.getWeaponType(equippedTool)
	if not weaponType then
		return { success = false, message = "Invalid weapon" }
	end
	
	-- Sync batState.isEquipped with Tool state for BaseballBat module compatibility
	batState.isEquipped = true
	
	-- Handle predator swing
	if targetType == "predator" and targetId then
		local playerData = self._playerService:GetPlayerData(userId)
		if not playerData then
			return { success = false, message = "Player data not found" }
		end
		
		local result = BaseballBat.hitPredator(batState, gameState.spawnState, targetId, currentTime)
		if result.success then
			-- Broadcast health update to ALL clients
			local predator = PredatorSpawning.findPredator(gameState.spawnState, targetId)
			local maxHealth = predator and PredatorConfig.getBatHitsRequired(predator.predatorType) or 1
			
			-- Use GameStateService signals to fire to all clients
			local gameStateService = Knit.GetService("GameStateService")
			gameStateService.Client.PredatorHealthUpdated:FireAll(targetId, result.remainingHealth, maxHealth, result.damage)
			
			if result.defeated then
				-- Award money for defeating predator
				playerData.money = (playerData.money or 0) + result.rewardMoney
				
				-- Award XP for defeating predator
				local defeatedPredator = PredatorSpawning.findPredator(gameState.spawnState, targetId)
				if defeatedPredator then
					local xpAmount = XPConfig.calculatePredatorKillXP(defeatedPredator.predatorType)
					self._playerService:AwardXP(player, playerData, xpAmount, "Defeated " .. defeatedPredator.predatorType)
				end
				
				-- Unregister from predator AI
				PredatorAI.unregisterPredator(gameState.predatorAIState, targetId)
				
				-- Fire PredatorDefeated signal to ALL clients
				gameStateService.Client.PredatorDefeated:FireAll(targetId, true)
				
				self._playerService:SyncPlayerData(player, playerData, true)
			end
		end
		return result
	
	-- Handle player swing (knockback)
	elseif targetType == "player" and targetId then
		local result = BaseballBat.hitPlayer(batState, targetId, currentTime)
		
		if result.success then
			-- Find target player and incapacitate them
			local targetUserId = tonumber(targetId)
			local targetPlayer: Player? = nil
			if targetUserId then
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == targetUserId then
						targetPlayer = p
						break
					end
				end
			end
			
			if targetPlayer then
				-- Get target's combat state and incapacitate them
				local targetGameState = self._gameStateService:GetPlayerGameState(targetUserId :: number)
				local incapResult = CombatHealth.incapacitate(targetGameState.combatState, tostring(userId), currentTime)
				
				if incapResult.success then
					-- Fire incapacitation signal to target player
					self.Client.PlayerIncapacitated:FireClient(targetPlayer, {
						duration = incapResult.duration,
						attackerId = tostring(userId),
						attackerName = player.Name,
					})
				end
			end
		end
		
		return result
	
	-- Handle miss (swing at nothing)
	else
		local result = BaseballBat.swingMiss(batState, currentTime)
		return result
	end
end

function CombatService:EquipWeapon(player: Player, weaponType: string?)
	-- Weapon equipping is now handled by Roblox's native Tool system
	-- This method can be used for validation or custom logic
	return { success = true, message = "Weapon system uses native Tools" }
end

function CombatService:ActivateShield(player: Player)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- Initialize shield state if not present
	if not playerData.shieldState then
		playerData.shieldState = AreaShield.createDefaultState()
	end
	
	local currentTime = os.time()
	local result = AreaShield.activate(playerData.shieldState, currentTime)
	
	if result.success then
		-- Sync player data
		self._playerService:SyncPlayerData(player, playerData, true)
		
		-- Fire ShieldActivated signal to all clients
		self.Client.ShieldActivated:FireAll(userId, playerData.sectionIndex or 1, {
			isActive = true,
			expiresAt = playerData.shieldState.expiresAt,
			durationTotal = AreaShield.getConstants().shieldDuration,
		})
	end
	
	return result
end

function CombatService:PlaceTrap(player: Player, trapId: string, spotIndex: number)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = TrapPlacement.placeTrapFromInventory(playerData, trapId, spotIndex)
	if result.success then
		-- Calculate trap position for visual feedback
		local sectionIndex = playerData.sectionIndex
		local trapPosition = nil
		if sectionIndex then
			local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
			if sectionCenter then
				local spotPos = PlayerSection.getTrapSpotPosition(spotIndex, sectionCenter)
				if spotPos then
					trapPosition = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
				end
			end
		end
		
		-- Fire TrapPlaced signal to all clients
		if result.trap then
			self.Client.TrapPlaced:FireAll(result.trap.id, result.trap.trapType, trapPosition or Vector3.new(0, 0, 0), result.trap.spotIndex)
		end
		
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

--[[
	Lifecycle Methods
]]

function CombatService:KnitInit()
	print("[CombatService] Initializing...")
end

function CombatService:KnitStart()
	-- Get references to other services
	self._playerService = Knit.GetService("PlayerService")
	self._gameStateService = Knit.GetService("GameStateService")
	
	print("[CombatService] Started")
end

return CombatService
