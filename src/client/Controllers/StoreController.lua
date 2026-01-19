--[[
	StoreController
	Client-side Knit controller for managing store interactions.
	
	Provides:
	- Buy/sell operations via StoreService
	- GoodSignal events for reactive UI updates
	- Store inventory caching
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Create the controller
local StoreController = Knit.CreateController({
  Name = "StoreController",
})

-- GoodSignal events for reactive UI
StoreController.StoreReplenished = GoodSignal.new() -- Fires (data: {timeUntilNext: number})
StoreController.ItemPurchased = GoodSignal.new() -- Fires (data: {itemType, itemId, quantity?, newBalance})
StoreController.ItemSold = GoodSignal.new() -- Fires (data: {itemType, itemId, newBalance, message})
StoreController.StockUpdated = GoodSignal.new() -- Fires (data: {itemType, itemId, newStock})

-- Reference to the server service
local storeService = nil

-- Cached store inventory
local cachedInventory = nil
local cachedAvailableItems = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function StoreController:KnitInit()
  print("[StoreController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function StoreController:KnitStart()
  -- Get reference to server service
  storeService = Knit.GetService("StoreService")

  -- Connect to server signals
  storeService.StoreReplenished:Connect(function(data)
    -- Invalidate cache on replenish
    cachedInventory = nil
    cachedAvailableItems = nil
    self.StoreReplenished:Fire(data)
  end)

  storeService.ItemPurchased:Connect(function(data)
    self.ItemPurchased:Fire(data)
  end)

  storeService.ItemSold:Connect(function(data)
    self.ItemSold:Fire(data)
  end)

  storeService.StockUpdated:Connect(function(data)
    -- Invalidate cache on stock update
    cachedInventory = nil
    cachedAvailableItems = nil
    self.StockUpdated:Fire(data)
  end)

  print("[StoreController] Started")
end

-- ============================================================================
-- Store Query Methods
-- ============================================================================

--[[
	Get the current store inventory.
	
	@param forceRefresh boolean? - Force refresh from server
	@return StoreInventory
]]
function StoreController:GetStoreInventory(forceRefresh: boolean?)
  if not storeService then
    return {}
  end

  if forceRefresh or cachedInventory == nil then
    cachedInventory = storeService:GetStoreInventory()
  end

  return cachedInventory
end

--[[
	Get available items with stock info.
	
	@param forceRefresh boolean? - Force refresh from server
	@return { eggs: {}, chickens: {}, traps: {}, weapons: {} }
]]
function StoreController:GetAvailableItems(forceRefresh: boolean?)
  if not storeService then
    return { eggs = {}, chickens = {}, traps = {}, weapons = {} }
  end

  if forceRefresh or cachedAvailableItems == nil then
    cachedAvailableItems = storeService:GetAvailableItems()
  end

  return cachedAvailableItems
end

--[[
	Get cached store inventory (synchronous).
	
	@return StoreInventory?
]]
function StoreController:GetCachedInventory()
  return cachedInventory
end

--[[
	Get cached available items (synchronous).
	
	@return { eggs: {}, chickens: {}, traps: {}, weapons: {} }?
]]
function StoreController:GetCachedAvailableItems()
  return cachedAvailableItems
end

--[[
	Get time until next store replenish.
	
	@return number - Seconds until replenish
]]
function StoreController:GetTimeUntilReplenish(): number
  if not storeService then
    return 0
  end
  return storeService:GetTimeUntilReplenish()
end

--[[
	Invalidate local cache (call when player inventory changes).
]]
function StoreController:InvalidateCache()
  cachedInventory = nil
  cachedAvailableItems = nil
end

-- ============================================================================
-- Buy Methods
-- ============================================================================

--[[
	Buy an egg from the store.
	
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreController:BuyEgg(eggType: string, quantity: number?)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:BuyEgg(eggType, quantity)
end

--[[
	Buy a chicken from the store.
	
	@param chickenType string - The chicken type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreController:BuyChicken(chickenType: string, quantity: number?)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:BuyChicken(chickenType, quantity)
end

--[[
	Buy a trap from the store.
	
	@param trapType string - The trap type to buy
	@return TransactionResult
]]
function StoreController:BuyTrap(trapType: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:BuyTrap(trapType)
end

--[[
	Buy a weapon from the store.
	
	@param weaponType string - The weapon type to buy
	@return TransactionResult
]]
function StoreController:BuyWeapon(weaponType: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:BuyWeapon(weaponType)
end

-- ============================================================================
-- Sell Methods
-- ============================================================================

--[[
	Sell an egg from inventory.
	
	@param eggId string - The egg's ID
	@return TransactionResult
]]
function StoreController:SellEgg(eggId: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:SellEgg(eggId)
end

--[[
	Sell a chicken from inventory or placed.
	
	@param chickenId string - The chicken's ID
	@return TransactionResult
]]
function StoreController:SellChicken(chickenId: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:SellChicken(chickenId)
end

--[[
	Sell a trapped predator.
	
	@param trapId string - The trap's ID containing the predator
	@return TransactionResult
]]
function StoreController:SellPredator(trapId: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:SellPredator(trapId)
end

--[[
	Sell a trap.
	
	@param trapId string - The trap's ID
	@return TransactionResult
]]
function StoreController:SellTrap(trapId: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:SellTrap(trapId)
end

--[[
	Sell a weapon.
	
	@param weaponType string - The weapon type to sell
	@return TransactionResult
]]
function StoreController:SellWeapon(weaponType: string)
  if not storeService then
    return { success = false, message = "Service not available" }
  end
  return storeService:SellWeapon(weaponType)
end

return StoreController
