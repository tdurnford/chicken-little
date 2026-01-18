--[[
	MainController - Knit Controller
	
	Main client controller that handles:
	- Player data synchronization
	- UI updates from server events
	- Input handling coordination
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))

-- Get client modules (UI, Visuals, etc.)
local ClientModules = script.Parent.Parent

local MainController = Knit.CreateController({
	Name = "MainController",
	
	-- State
	_playerDataCache = {},
	_localPlayer = Players.LocalPlayer,
	
	-- UI Module references
	_mainHUD = nil,
	_inventoryUI = nil,
	_storeUI = nil,
	_soundEffects = nil,
})

function MainController:GetPlayerData()
	return self._playerDataCache
end

function MainController:UpdatePlayerData(data)
	self._playerDataCache = data
	
	-- Update all UI modules with new data
	if self._mainHUD then
		self._mainHUD.updateFromPlayerData(data)
	end
	
	if self._inventoryUI then
		self._inventoryUI.updateFromPlayerData(data)
	end
	
	if self._storeUI then
		self._storeUI.updateMoney(data.money or 0)
	end
	
	-- Update inventory item count badge on MainHUD
	if data.inventory and self._mainHUD then
		local eggCount = data.inventory.eggs and #data.inventory.eggs or 0
		local chickenCount = data.inventory.chickens and #data.inventory.chickens or 0
		self._mainHUD.setInventoryItemCount(eggCount + chickenCount)
	end
	
	-- Update chicken count display on MainHUD
	if data.placedChickens and self._mainHUD then
		self._mainHUD.setChickenCount(#data.placedChickens, 15)
	end
	
	-- Update ShieldUI with current shield state
	if data.shieldState then
		local shieldController = Knit.GetController("ShieldController")
		if shieldController then
			shieldController:UpdateShieldStatus(data.shieldState)
		end
	end
end

function MainController:KnitInit()
	print("[MainController] Initializing...")
	
	-- Load UI modules
	self._soundEffects = require(ClientModules:WaitForChild("SoundEffects"))
	self._mainHUD = require(ClientModules:WaitForChild("MainHUD"))
	self._inventoryUI = require(ClientModules:WaitForChild("InventoryUI"))
	self._storeUI = require(ClientModules:WaitForChild("StoreUI"))
	
	-- Initialize sound effects
	self._soundEffects.initialize()
	print("[MainController] SoundEffects initialized")
	
	-- Create Main HUD
	self._mainHUD.create()
	print("[MainController] MainHUD created")
	
	-- Create Inventory UI
	local inventoryCreated = self._inventoryUI.create()
	if not inventoryCreated then
		warn("[MainController] InventoryUI creation FAILED")
	end
	print("[MainController] InventoryUI created")
	
	-- Create Store UI
	self._storeUI.create()
	print("[MainController] StoreUI created")
end

function MainController:KnitStart()
	print("[MainController] Starting...")
	
	-- Get PlayerService from server
	local PlayerService = Knit.GetService("PlayerService")
	
	-- Request initial player data
	local initialData = PlayerService:GetPlayerData()
	if initialData then
		self:UpdatePlayerData(initialData)
		print("[MainController] Got initial data, sectionIndex =", initialData.sectionIndex)
	end
	
	-- Listen for player data changes
	PlayerService.PlayerDataChanged:Connect(function(data)
		self:UpdatePlayerData(data)
	end)
	
	-- Listen for XP gained
	PlayerService.XPGained:Connect(function(amount, reason)
		if self._mainHUD and self._mainHUD.showXPGain then
			self._mainHUD.showXPGain(amount)
		end
		self._soundEffects.play("xpGain")
		print("[MainController] XP gained:", amount, "for", reason)
	end)
	
	-- Listen for level up
	PlayerService.LevelUp:Connect(function(newLevel, unlocks)
		if self._mainHUD and self._mainHUD.showLevelUp then
			self._mainHUD.showLevelUp(newLevel, unlocks)
		end
		self._soundEffects.play("levelUp")
		print("[MainController] Level up! Now level", newLevel)
	end)
	
	-- Listen for bankruptcy assistance
	PlayerService.BankruptcyAssistance:Connect(function(data)
		self._soundEffects.play("uiNotification")
		print("[MainController] Bankruptcy assistance received: $" .. tostring(data.moneyAwarded))
		if self._mainHUD and self._mainHUD.showBankruptcyAssistance then
			self._mainHUD.showBankruptcyAssistance(data)
		end
	end)
	
	-- Listen for protection status changes
	PlayerService.ProtectionStatusChanged:Connect(function(data)
		if self._mainHUD and self._mainHUD.setProtectionStatus then
			self._mainHUD.setProtectionStatus(data)
		end
	end)
	
	-- Setup keyboard input for inventory toggle (I key)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		
		if input.KeyCode == Enum.KeyCode.I then
			self._inventoryUI.toggle()
		end
	end)
	
	-- Wire up MainHUD inventory button to toggle InventoryUI
	self._mainHUD.onInventoryClick(function()
		self._inventoryUI.toggle()
	end)
	
	print("[MainController] Started")
end

return MainController
