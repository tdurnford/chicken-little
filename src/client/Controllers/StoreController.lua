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
local Promise = require(Packages:WaitForChild("Promise"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))

-- Create the controller
local StoreController = Knit.CreateController({
  Name = "StoreController",
})

-- GoodSignal events for reactive UI
StoreController.StoreReplenished = GoodSignal.new() -- Fires (data: {timeUntilNext: number, inventory: StoreInventory})
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
    -- Sync local Store module with server inventory (updates lastReplenishTime)
    if data.inventory then
      Store.setStoreInventory(data.inventory)
    end
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
	@return Promise<StoreInventory>
]]
function StoreController:GetStoreInventory(forceRefresh: boolean?)
  if not storeService then
    return Promise.resolve({})
  end

  if forceRefresh or cachedInventory == nil then
    return storeService:GetStoreInventory()
      :andThen(function(inventory)
        cachedInventory = inventory
        return inventory
      end)
      :catch(function(err)
        warn("[StoreController] GetStoreInventory failed:", tostring(err))
        return {}
      end)
  end

  return Promise.resolve(cachedInventory)
end

--[[
	Get available items with stock info.
	
	@param forceRefresh boolean? - Force refresh from server
	@return Promise<{ eggs: {}, chickens: {}, traps: {}, weapons: {} }>
]]
function StoreController:GetAvailableItems(forceRefresh: boolean?)
  if not storeService then
    return Promise.resolve({ eggs = {}, chickens = {}, traps = {}, weapons = {} })
  end

  if forceRefresh or cachedAvailableItems == nil then
    return storeService:GetAvailableItems()
      :andThen(function(items)
        cachedAvailableItems = items
        return items
      end)
      :catch(function(err)
        warn("[StoreController] GetAvailableItems failed:", tostring(err))
        return { eggs = {}, chickens = {}, traps = {}, weapons = {} }
      end)
  end

  return Promise.resolve(cachedAvailableItems)
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
	
	@return Promise<number> - Seconds until replenish
]]
function StoreController:GetTimeUntilReplenish()
  if not storeService then
    return Promise.resolve(0)
  end
  return storeService:GetTimeUntilReplenish()
    :catch(function(err)
      warn("[StoreController] GetTimeUntilReplenish failed:", tostring(err))
      return 0
    end)
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
	@return Promise<TransactionResult>
]]
function StoreController:BuyEgg(eggType: string, quantity: number?)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:BuyEgg(eggType, quantity)
    :catch(function(err)
      warn("[StoreController] BuyEgg failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Buy a chicken from the store.
	
	@param chickenType string - The chicken type to buy
	@param quantity number? - Optional quantity (default 1)
	@return Promise<TransactionResult>
]]
function StoreController:BuyChicken(chickenType: string, quantity: number?)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:BuyChicken(chickenType, quantity)
    :catch(function(err)
      warn("[StoreController] BuyChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Buy a trap from the store.
	
	@param trapType string - The trap type to buy
	@return Promise<TransactionResult>
]]
function StoreController:BuyTrap(trapType: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:BuyTrap(trapType)
    :catch(function(err)
      warn("[StoreController] BuyTrap failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Buy a weapon from the store.
	
	@param weaponType string - The weapon type to buy
	@return Promise<TransactionResult>
]]
function StoreController:BuyWeapon(weaponType: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:BuyWeapon(weaponType)
    :catch(function(err)
      warn("[StoreController] BuyWeapon failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

-- ============================================================================
-- Sell Methods
-- ============================================================================

--[[
	Sell an egg from inventory.
	
	@param eggId string - The egg's ID
	@return Promise<TransactionResult>
]]
function StoreController:SellEgg(eggId: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:SellEgg(eggId)
    :catch(function(err)
      warn("[StoreController] SellEgg failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell a chicken from inventory or placed.
	
	@param chickenId string - The chicken's ID
	@return Promise<TransactionResult>
]]
function StoreController:SellChicken(chickenId: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:SellChicken(chickenId)
    :catch(function(err)
      warn("[StoreController] SellChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell a trapped predator.
	
	@param trapId string - The trap's ID containing the predator
	@return Promise<TransactionResult>
]]
function StoreController:SellPredator(trapId: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:SellPredator(trapId)
    :catch(function(err)
      warn("[StoreController] SellPredator failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell a trap.
	
	@param trapId string - The trap's ID
	@return Promise<TransactionResult>
]]
function StoreController:SellTrap(trapId: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:SellTrap(trapId)
    :catch(function(err)
      warn("[StoreController] SellTrap failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell a weapon.
	
	@param weaponType string - The weapon type to sell
	@return Promise<TransactionResult>
]]
function StoreController:SellWeapon(weaponType: string)
  if not storeService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return storeService:SellWeapon(weaponType)
    :catch(function(err)
      warn("[StoreController] SellWeapon failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

return StoreController
