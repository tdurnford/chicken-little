--[[
	StoreService - Knit Service
	
	Handles all store operations including:
	- Buying eggs, chickens, traps, weapons
	- Selling items
	- Store inventory management
	- Power-up purchases
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local WeaponTool = require(Shared:WaitForChild("WeaponTool"))
local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

local StoreService = Knit.CreateService({
	Name = "StoreService",
	
	-- Client-exposed API
	Client = {
		-- Signals
		StoreReplenished = Knit.Signal.new(),
		StoreInventoryUpdated = Knit.Signal.new(),
		ChickenSold = Knit.Signal.new(),
		PowerUpActivated = Knit.Signal.new(),
	},
	
	-- Server state
	_playerService = nil,
	
	-- Configuration
	STORE_REPLENISH_CHECK_INTERVAL = 10,
	STORE_REPLENISH_PRODUCT_ID = 0, -- TODO: Set actual product ID
	
	-- Robux product IDs
	ITEM_ROBUX_PRODUCT_IDS = {
		Common = 0,
		Uncommon = 0,
		Rare = 0,
		Epic = 0,
		Legendary = 0,
		Mythic = 0,
	},
	POWERUP_ROBUX_PRODUCT_IDS = {
		HatchLuck15 = 0,
		HatchLuck60 = 0,
		HatchLuck240 = 0,
		EggQuality15 = 0,
		EggQuality60 = 0,
		EggQuality240 = 0,
	},
	
	-- Pending purchases tracking
	_pendingReplenishPurchases = {},
	_pendingItemPurchases = {},
	_pendingPowerUpPurchases = {},
})

--[[
	Client Methods - Exposed via Knit remotes
]]

function StoreService.Client:BuyEgg(player: Player, eggType: string, quantity: number?)
	return self.Server:BuyEgg(player, eggType, quantity)
end

function StoreService.Client:BuyChicken(player: Player, chickenType: string, quantity: number?)
	return self.Server:BuyChicken(player, chickenType, quantity)
end

function StoreService.Client:BuyTrap(player: Player, trapType: string)
	return self.Server:BuyTrap(player, trapType)
end

function StoreService.Client:BuyWeapon(player: Player, weaponType: string)
	return self.Server:BuyWeapon(player, weaponType)
end

function StoreService.Client:SellChicken(player: Player, chickenId: string)
	return self.Server:SellChicken(player, chickenId)
end

function StoreService.Client:SellEgg(player: Player, eggId: string)
	return self.Server:SellEgg(player, eggId)
end

function StoreService.Client:SellPredator(player: Player, trapId: string)
	return self.Server:SellPredator(player, trapId)
end

function StoreService.Client:GetStoreInventory(player: Player)
	return self.Server:GetStoreInventory()
end

function StoreService.Client:BuyPowerUp(player: Player, powerUpId: string)
	return self.Server:BuyPowerUp(player, powerUpId)
end

function StoreService.Client:ReplenishStoreWithRobux(player: Player)
	return self.Server:ReplenishStoreWithRobux(player)
end

function StoreService.Client:BuyItemWithRobux(player: Player, itemType: string, itemId: string)
	return self.Server:BuyItemWithRobux(player, itemType, itemId)
end

--[[
	Server Methods
]]

function StoreService:BuyEgg(player: Player, eggType: string, quantity: number?)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.purchaseEggFromInventory(playerData, eggType, quantity)
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
		
		-- Notify all clients about stock update
		local newStock = Store.getStock("egg", eggType)
		self.Client.StoreInventoryUpdated:FireAll({
			itemType = "egg",
			itemId = eggType,
			newStock = newStock,
		})
	end
	return result
end

function StoreService:BuyChicken(player: Player, chickenType: string, quantity: number?)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.purchaseChickenFromInventory(playerData, chickenType, quantity)
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
		
		-- Notify all clients about stock update
		local newStock = Store.getStock("chicken", chickenType)
		self.Client.StoreInventoryUpdated:FireAll({
			itemType = "chicken",
			itemId = chickenType,
			newStock = newStock,
		})
	end
	return result
end

function StoreService:BuyTrap(player: Player, trapType: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.buyTrap(playerData, trapType)
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function StoreService:BuyWeapon(player: Player, weaponType: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.buyWeapon(playerData, weaponType)
	if result.success then
		-- Give the weapon Tool to player's Backpack
		WeaponTool.giveToPlayer(player, weaponType)
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function StoreService:SellChicken(player: Player, chickenId: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.sellChicken(playerData, chickenId)
	if result.success then
		self.Client.ChickenSold:FireClient(player, { chickenId = chickenId, message = result.message })
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function StoreService:SellEgg(player: Player, eggId: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.sellEgg(playerData, eggId)
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function StoreService:SellPredator(player: Player, trapId: string)
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	local result = Store.sellPredator(playerData, trapId)
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	return result
end

function StoreService:GetStoreInventory()
	return Store.getStoreInventory()
end

function StoreService:BuyPowerUp(player: Player, powerUpId: string)
	-- Validate power-up ID
	local powerUpConfigData = PowerUpConfig.get(powerUpId)
	if not powerUpConfigData then
		return {
			success = false,
			message = "Invalid power-up: " .. tostring(powerUpId),
		}
	end
	
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- For development mode (product ID not configured), give power-up for free
	local productId = self.POWERUP_ROBUX_PRODUCT_IDS[powerUpId]
	if not productId or productId == 0 then
		-- Add power-up to player data
		PlayerData.addPowerUp(playerData, powerUpId, powerUpConfigData.durationSeconds)
		self._playerService:SyncPlayerData(player, playerData, true)
		
		-- Fire power-up activated signal
		self.Client.PowerUpActivated:FireClient(player, {
			powerUpId = powerUpId,
			expiresAt = os.time() + powerUpConfigData.durationSeconds,
		})
		
		print("[StoreService] Power-up activated (free/dev mode):", powerUpId, "for", player.Name)
		
		return {
			success = true,
			message = "Power-up activated! " .. powerUpConfigData.displayName,
			powerUpId = powerUpId,
		}
	end
	
	-- Store pending purchase info
	self._pendingPowerUpPurchases[userId] = powerUpId
	
	-- Prompt player to purchase the developer product
	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	
	if success then
		return {
			success = true,
			message = "Purchase prompt opened",
			productId = productId,
		}
	else
		self._pendingPowerUpPurchases[userId] = nil
		return {
			success = false,
			message = "Failed to open purchase prompt: " .. tostring(errorMessage),
		}
	end
end

function StoreService:ReplenishStoreWithRobux(player: Player)
	if self.STORE_REPLENISH_PRODUCT_ID == 0 then
		-- For testing: perform free replenish when product ID not set
		local newInventory = Store.forceReplenish()
		print("[StoreService] Free store replenish (product ID not configured) for", player.Name)
		
		-- Notify all connected players about replenish
		for _, p in ipairs(Players:GetPlayers()) do
			self.Client.StoreReplenished:FireClient(p, newInventory)
		end
		
		return {
			success = true,
			message = "Store replenished! (Free - product not configured)",
			productId = 0,
			robuxPrice = 0,
		}
	end
	
	-- Prompt player to purchase the developer product
	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, self.STORE_REPLENISH_PRODUCT_ID)
	end)
	
	if success then
		self._pendingReplenishPurchases[player.UserId] = true
		return {
			success = true,
			message = "Purchase prompt opened",
			productId = self.STORE_REPLENISH_PRODUCT_ID,
		}
	else
		return {
			success = false,
			message = "Failed to open purchase prompt: " .. tostring(errorMessage),
		}
	end
end

function StoreService:BuyItemWithRobux(player: Player, itemType: string, itemId: string)
	if itemType ~= "egg" and itemType ~= "chicken" and itemType ~= "trap" and itemType ~= "weapon" then
		return { success = false, message = "Invalid item type" }
	end
	
	local userId = player.UserId
	local playerData = self._playerService:GetPlayerData(userId)
	if not playerData then
		return { success = false, message = "Player data not found" }
	end
	
	-- Handle weapon purchases
	if itemType == "weapon" then
		local weaponConfigData = WeaponConfig.get(itemId)
		if not weaponConfigData then
			return { success = false, message = "Weapon type not found" }
		end
		
		local result = Store.buyWeaponWithRobux(playerData, itemId)
		if result.success then
			WeaponTool.giveToPlayer(player, itemId)
			self._playerService:SyncPlayerData(player, playerData, true)
		end
		return result
	end
	
	-- Handle trap purchases
	if itemType == "trap" then
		local trapConfigData = TrapConfig.get(itemId)
		if not trapConfigData then
			return { success = false, message = "Trap type not found" }
		end
		
		local result = Store.buyTrapWithRobux(playerData, itemId)
		if result.success then
			self._playerService:SyncPlayerData(player, playerData, true)
		end
		return result
	end
	
	-- Handle egg/chicken purchases (free in dev mode)
	local result
	if itemType == "egg" then
		result = Store.purchaseEggWithRobux(playerData, itemId)
	else
		result = Store.purchaseChickenWithRobux(playerData, itemId)
	end
	
	if result.success then
		self._playerService:SyncPlayerData(player, playerData, true)
	end
	
	return result
end

function StoreService:CheckStoreReplenish()
	if Store.needsReplenish() then
		local newInventory = Store.replenishStore()
		print("[StoreService] Store inventory replenished")
		
		-- Notify all connected players
		for _, player in ipairs(Players:GetPlayers()) do
			self.Client.StoreReplenished:FireClient(player, newInventory)
		end
	end
end

--[[
	Lifecycle Methods
]]

function StoreService:KnitInit()
	-- Initialize store inventory
	Store.initializeInventory()
	print("[StoreService] Initialized")
end

function StoreService:KnitStart()
	-- Get reference to PlayerService
	self._playerService = Knit.GetService("PlayerService")
	
	print("[StoreService] Started")
end

return StoreService
