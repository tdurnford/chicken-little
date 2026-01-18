--[[
	ChickenController - Knit Controller
	
	Handles client-side chicken operations including:
	- Chicken visual management
	- Egg visual management
	- Chicken/egg interaction prompts
	- Sell confirmation flow
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

-- Get client modules
local ClientModules = script.Parent.Parent

local ChickenController = Knit.CreateController({
	Name = "ChickenController",
	
	-- State
	_localPlayer = Players.LocalPlayer,
	_worldEggVisuals = {},
	
	-- Module references
	_chickenVisuals = nil,
	_eggVisuals = nil,
	_chickenHealthBar = nil,
	_soundEffects = nil,
	_hatchPreviewUI = nil,
	_chickenSelling = nil,
	
	-- Placed egg tracking for hatching flow
	_placedEggData = nil,
})

function ChickenController:KnitInit()
	print("[ChickenController] Initializing...")
	
	-- Load modules
	self._chickenVisuals = require(ClientModules:WaitForChild("ChickenVisuals"))
	self._eggVisuals = require(ClientModules:WaitForChild("EggVisuals"))
	self._chickenHealthBar = require(ClientModules:WaitForChild("ChickenHealthBar"))
	self._soundEffects = require(ClientModules:WaitForChild("SoundEffects"))
	self._hatchPreviewUI = require(ClientModules:WaitForChild("HatchPreviewUI"))
	self._chickenSelling = require(ClientModules:WaitForChild("ChickenSelling"))
	
	-- Create Hatch Preview UI
	self._hatchPreviewUI.create()
	print("[ChickenController] HatchPreviewUI created")
	
	-- Initialize ChickenSelling
	self._chickenSelling.create()
	print("[ChickenController] ChickenSelling initialized")
end

function ChickenController:KnitStart()
	print("[ChickenController] Starting...")
	
	-- Get services
	local ChickenService = Knit.GetService("ChickenService")
	local MainController = Knit.GetController("MainController")
	
	-- Wire ChickenSelling callbacks
	self._chickenSelling.setGetNearbyChicken(function(position)
		return self:FindNearbyPlacedChicken(position)
	end)
	
	self._chickenSelling.setGetPlayerData(function()
		return MainController:GetPlayerData()
	end)
	
	-- Wire up server-side sale via ChickenService
	self._chickenSelling.setPerformServerSale(function(chickenId)
		local StoreService = Knit.GetService("StoreService")
		local result = StoreService:SellChicken(chickenId)
		if result and result.success then
			self._soundEffects.playMoneyCollect(result.sellPrice or 0)
			return {
				success = true,
				message = result.message,
				sellPrice = result.sellPrice,
			}
		else
			self._soundEffects.play("uiError")
			return {
				success = false,
				error = result and result.message or "Unknown error",
			}
		end
	end)
	
	-- Wire up ChickenVisuals sell prompt
	self._chickenVisuals.setOnSellPromptTriggered(function(chickenId)
		local visualState = self._chickenVisuals.get(chickenId)
		if visualState then
			self._chickenSelling.startSell(chickenId, visualState.chickenType, visualState.rarity, visualState.accumulatedMoney)
		end
	end)
	
	-- Wire up ChickenVisuals claim prompt for random chickens
	self._chickenVisuals.setOnClaimPromptTriggered(function(chickenId)
		local GameStateService = Knit.GetService("GameStateService")
		task.spawn(function()
			local result = GameStateService:ClaimRandomChicken()
			if result and result.success then
				self._soundEffects.play("chickenClaim")
				self._chickenVisuals.destroy(chickenId)
				
				-- Update local cache and UI with returned player data
				if result.playerData then
					MainController:UpdatePlayerData(result.playerData)
				end
				
				print("[ChickenController] Claimed random chicken:", result.chicken and result.chicken.chickenType)
			else
				self._soundEffects.play("uiError")
				warn("[ChickenController] Failed to claim random chicken:", result and result.message)
			end
		end)
	end)
	
	-- Wire up HatchPreviewUI callbacks
	self._hatchPreviewUI.onHatch(function(eggId, eggType)
		self:OnHatchConfirmed(eggId, eggType)
	end)
	
	self._hatchPreviewUI.onCancel(function()
		self._placedEggData = nil
	end)
	
	-- Connect to ChickenService signals
	ChickenService.ChickenPlaced:Connect(function(eventData)
		self:OnChickenPlaced(eventData)
	end)
	
	ChickenService.ChickenPickedUp:Connect(function(data)
		self:OnChickenPickedUp(data)
	end)
	
	ChickenService.ChickenDamaged:Connect(function(eventData)
		self:OnChickenDamaged(eventData)
	end)
	
	ChickenService.ChickenHealthChanged:Connect(function(eventData)
		self:OnChickenHealthChanged(eventData)
	end)
	
	ChickenService.ChickenDied:Connect(function(eventData)
		self:OnChickenDied(eventData)
	end)
	
	ChickenService.ChickenPositionUpdated:Connect(function(data)
		self:OnChickenPositionUpdated(data)
	end)
	
	ChickenService.EggHatched:Connect(function(eggId, chickenType, rarity)
		self:OnEggHatched(eggId, chickenType, rarity)
	end)
	
	ChickenService.EggSpawned:Connect(function(eggData)
		self:OnEggSpawned(eggData)
	end)
	
	ChickenService.EggCollected:Connect(function(eventData)
		self:OnEggCollected(eventData)
	end)
	
	ChickenService.EggDespawned:Connect(function(eventData)
		self:OnEggDespawned(eventData)
	end)
	
	ChickenService.MoneyCollected:Connect(function(amount, position)
		self:OnMoneyCollected(amount, position)
	end)
	
	print("[ChickenController] Started")
end

function ChickenController:FindNearbyPlacedChicken(playerPosition)
	local MainController = Knit.GetController("MainController")
	local playerDataCache = MainController:GetPlayerData()
	
	if not playerDataCache or not playerDataCache.placedChickens then
		return nil, nil, nil, nil
	end
	
	local CHICKEN_INTERACTION_RANGE = 10
	local nearestDistance = CHICKEN_INTERACTION_RANGE
	local nearestChicken = nil
	
	for _, chicken in ipairs(playerDataCache.placedChickens) do
		local visualState = self._chickenVisuals.get(chicken.id)
		if visualState and visualState.position then
			local distance = (playerPosition - visualState.position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestChicken = chicken
			end
		end
	end
	
	if nearestChicken then
		local realTimeAccumulatedMoney = self._chickenVisuals.getAccumulatedMoney(nearestChicken.id)
		return nearestChicken.id, nil, nearestChicken.chickenType, nearestChicken.rarity, realTimeAccumulatedMoney
	end
	
	return nil, nil, nil, nil
end

function ChickenController:OnHatchConfirmed(eggId, eggType)
	if not self._placedEggData or self._placedEggData.id ~= eggId then
		warn("[ChickenController] Placed egg data mismatch")
		return
	end
	
	-- Get player's current position for spawning chicken nearby
	local playerPosition = nil
	local character = self._localPlayer.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local pos = humanoidRootPart.Position
			playerPosition = { x = pos.X, y = pos.Y, z = pos.Z }
		end
	end
	
	-- Hatch egg via server
	local ChickenService = Knit.GetService("ChickenService")
	local result = ChickenService:HatchEgg(eggId, 1, playerPosition)
	
	if result and result.success then
		self._soundEffects.playEggHatch(result.rarity or "Common")
		print("[ChickenController] Egg hatched successfully:", result.chickenType, result.rarity)
		
		-- Show the result screen
		self._hatchPreviewUI.showResult(result.chickenType, result.rarity)
	elseif result and result.atLimit then
		self._soundEffects.play("uiError")
		warn("[ChickenController] Cannot hatch egg:", result.message)
	else
		self._soundEffects.play("uiError")
		warn("[ChickenController] Hatch failed:", result and result.message or "Unknown error")
	end
	
	-- Clear placed egg data
	self._placedEggData = nil
end

-- Event handlers
function ChickenController:OnChickenPlaced(eventData)
	local chicken = eventData.chicken
	if not chicken then
		warn("[ChickenController] ChickenPlaced: Invalid event data - missing chicken")
		return
	end
	
	local position
	if eventData.position then
		local pos = eventData.position
		position = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
	else
		local MainController = Knit.GetController("MainController")
		local playerDataCache = MainController:GetPlayerData()
		local sectionIndex = playerDataCache.sectionIndex or 1
		local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
		position = sectionCenter or Vector3.new(0, 5, 0)
	end
	
	local visualState = self._chickenVisuals.create(chicken.id, chicken.chickenType, position, true)
	self._soundEffects.play("chickenPlace")
	
	-- Create health bar for the chicken
	if visualState and visualState.model then
		self._chickenHealthBar.create(chicken.id, chicken.chickenType, visualState.model)
	end
	
	print("[ChickenController] Chicken placed:", chicken.id)
end

function ChickenController:OnChickenPickedUp(data)
	local chickenId
	if type(data) == "string" then
		chickenId = data
	elseif type(data) == "table" then
		chickenId = data.chickenId
	else
		warn("[ChickenController] ChickenPickedUp: Invalid data format")
		return
	end
	
	self._chickenVisuals.destroy(chickenId)
	self._chickenHealthBar.destroy(chickenId)
	self._soundEffects.play("chickenPickup")
	print("[ChickenController] Chicken picked up:", chickenId)
end

function ChickenController:OnChickenDamaged(eventData)
	local chickenId = eventData.chickenId
	local newHealth = eventData.newHealth
	local maxHealth = eventData.maxHealth
	
	if chickenId and newHealth then
		self._chickenHealthBar.updateHealth(chickenId, newHealth)
		
		if maxHealth and maxHealth > 0 then
			local healthPercent = newHealth / maxHealth
			self._chickenVisuals.updateHealthState(chickenId, healthPercent)
		end
	end
end

function ChickenController:OnChickenHealthChanged(eventData)
	local chickenId = eventData.chickenId
	local newHealth = eventData.newHealth
	local maxHealth = eventData.maxHealth
	
	if chickenId and newHealth then
		self._chickenHealthBar.updateHealth(chickenId, newHealth)
		
		if maxHealth and maxHealth > 0 then
			local healthPercent = newHealth / maxHealth
			self._chickenVisuals.updateHealthState(chickenId, healthPercent)
		end
	end
end

function ChickenController:OnChickenDied(eventData)
	local chickenId = eventData.chickenId
	local killedBy = eventData.killedBy
	
	if chickenId then
		self._chickenVisuals.destroy(chickenId)
		self._chickenHealthBar.destroy(chickenId)
		self._soundEffects.play("chickenPickup")
		print("[ChickenController] Chicken killed by", killedBy or "predator", ":", chickenId)
	end
end

function ChickenController:OnChickenPositionUpdated(data)
	if not data or not data.chickens then
		return
	end
	
	for _, chickenData in ipairs(data.chickens) do
		if chickenData.chickenId and chickenData.position and chickenData.facingDirection then
			local position = Vector3.new(chickenData.position.X, chickenData.position.Y, chickenData.position.Z)
			local targetPosition = chickenData.targetPosition and Vector3.new(chickenData.targetPosition.X, chickenData.targetPosition.Y, chickenData.targetPosition.Z) or nil
			local facingDirection = Vector3.new(chickenData.facingDirection.X, chickenData.facingDirection.Y, chickenData.facingDirection.Z)
			
			self._chickenVisuals.updatePosition(chickenData.chickenId, position, targetPosition, facingDirection, chickenData.walkSpeed, chickenData.isIdle)
		end
	end
end

function ChickenController:OnEggHatched(eggId, chickenType, rarity)
	self._eggVisuals.playHatchAnimation(eggId)
	self._soundEffects.playEggHatch(rarity)
	print("[ChickenController] Egg hatched:", eggId, "->", chickenType, rarity)
end

function ChickenController:OnEggSpawned(eggData)
	local eggId = eggData.id
	local eggType = eggData.eggType
	local chickenId = eggData.chickenId
	local position = eggData.position
	
	-- Play laying animation on the chicken
	if chickenId then
		self._chickenVisuals.playLayingAnimation(chickenId)
	end
	
	-- Create egg visual in world
	local eggPosition = Vector3.new(position.x, position.y, position.z)
	local eggVisualState = self._eggVisuals.create(eggId, eggType, eggPosition)
	
	if eggVisualState and eggVisualState.model then
		-- Add proximity prompt for collection
		local primaryPart = eggVisualState.model.PrimaryPart
		if primaryPart then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = "Egg"
			prompt.ActionText = "Collect"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = primaryPart
			
			-- Handle collection
			prompt.Triggered:Connect(function(playerWhoTriggered)
				if playerWhoTriggered == self._localPlayer then
					local ChickenService = Knit.GetService("ChickenService")
					local result = ChickenService:CollectWorldEgg(eggId)
					if result and result.success then
						self._soundEffects.play("eggCollect")
						print("[ChickenController] Collected egg:", eggId)
					else
						warn("[ChickenController] Failed to collect egg:", result and result.message or "Unknown error")
					end
				end
			end)
			
			-- Store reference for cleanup
			self._worldEggVisuals[eggId] = {
				model = eggVisualState.model,
				prompt = prompt,
			}
		end
	end
	
	self._soundEffects.play("eggPlace")
	print("[ChickenController] Egg spawned:", eggId, "from chicken", chickenId)
end

function ChickenController:OnEggCollected(eventData)
	local eggId = eventData.eggId
	
	-- Remove egg visual
	local eggVisual = self._worldEggVisuals[eggId]
	if eggVisual then
		if eggVisual.prompt then
			eggVisual.prompt:Destroy()
		end
		self._eggVisuals.destroy(eggId)
		self._worldEggVisuals[eggId] = nil
	end
	
	print("[ChickenController] Egg collected and added to inventory:", eggId)
end

function ChickenController:OnEggDespawned(eventData)
	local eggId = eventData.eggId
	local reason = eventData.reason
	
	-- Remove egg visual
	local eggVisual = self._worldEggVisuals[eggId]
	if eggVisual then
		if eggVisual.prompt then
			eggVisual.prompt:Destroy()
		end
		self._eggVisuals.destroy(eggId)
		self._worldEggVisuals[eggId] = nil
	end
	
	print("[ChickenController] Egg despawned:", eggId, "reason:", reason)
end

function ChickenController:OnMoneyCollected(amount, position)
	self._soundEffects.playMoneyCollect(amount)
	if position then
		self._chickenVisuals.createMoneyPopEffect({
			amount = amount,
			position = position,
			isLarge = amount >= 1000,
		})
	end
	print("[ChickenController] Money collected:", amount)
end

return ChickenController
