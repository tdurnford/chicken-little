--[[
	StoreService
	Knit service that handles all store-related server logic.
	
	Provides:
	- Store inventory management
	- Buy/sell operations for eggs, chickens, traps, and weapons
	- Store restocking logic
	- Event broadcasting for store updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

-- Services will be retrieved after Knit starts
local PlayerDataService

-- Create the service
local StoreService = Knit.CreateService({
  Name = "StoreService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    StoreReplenished = Knit.CreateSignal(), -- Fires to all when store restocks
    ItemPurchased = Knit.CreateSignal(), -- Fires to owner when item purchased
    ItemSold = Knit.CreateSignal(), -- Fires to owner when item sold
    StockUpdated = Knit.CreateSignal(), -- Fires to owner when stock changes
  },
})

-- Server-side signals (for other services to listen to)
StoreService.PurchaseCompleted = GoodSignal.new() -- (userId: number, itemType: string, itemId: string)
StoreService.SaleCompleted = GoodSignal.new() -- (userId: number, itemType: string, itemId: string, amount: number)
StoreService.StoreRestocked = GoodSignal.new() -- ()

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function StoreService:KnitInit()
  -- Initialize store inventory
  Store.initializeInventory()
  print("[StoreService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function StoreService:KnitStart()
  -- Get reference to PlayerDataService
  PlayerDataService = Knit.GetService("PlayerDataService")

  print("[StoreService] Started")
end

-- ============================================================================
-- Client Methods
-- ============================================================================

--[[
	CLIENT: Get the current store inventory.
	
	@param player Player - The requesting player
	@return StoreInventory
]]
function StoreService.Client:GetStoreInventory(player: Player)
  return StoreService:GetStoreInventory()
end

--[[
	CLIENT: Buy an egg from the store.
	
	@param player Player - The player buying
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreService.Client:BuyEgg(player: Player, eggType: string, quantity: number?)
  return StoreService:BuyEgg(player.UserId, eggType, quantity)
end

--[[
	CLIENT: Buy a chicken from the store.
	
	@param player Player - The player buying
	@param chickenType string - The chicken type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreService.Client:BuyChicken(player: Player, chickenType: string, quantity: number?)
  return StoreService:BuyChicken(player.UserId, chickenType, quantity)
end

--[[
	CLIENT: Buy a trap from the store.
	
	@param player Player - The player buying
	@param trapType string - The trap type to buy
	@return TransactionResult
]]
function StoreService.Client:BuyTrap(player: Player, trapType: string)
  return StoreService:BuyTrap(player.UserId, trapType)
end

--[[
	CLIENT: Buy a weapon from the store.
	
	@param player Player - The player buying
	@param weaponType string - The weapon type to buy
	@return TransactionResult
]]
function StoreService.Client:BuyWeapon(player: Player, weaponType: string)
  return StoreService:BuyWeapon(player.UserId, weaponType)
end

--[[
	CLIENT: Sell an egg from inventory.
	
	@param player Player - The player selling
	@param eggId string - The egg's ID
	@return TransactionResult
]]
function StoreService.Client:SellEgg(player: Player, eggId: string)
  return StoreService:SellEgg(player.UserId, eggId)
end

--[[
	CLIENT: Sell a chicken from inventory or placed.
	
	@param player Player - The player selling
	@param chickenId string - The chicken's ID
	@return TransactionResult
]]
function StoreService.Client:SellChicken(player: Player, chickenId: string)
  return StoreService:SellChicken(player.UserId, chickenId)
end

--[[
	CLIENT: Sell a trapped predator.
	
	@param player Player - The player selling
	@param trapId string - The trap's ID containing the predator
	@return TransactionResult
]]
function StoreService.Client:SellPredator(player: Player, trapId: string)
  return StoreService:SellPredator(player.UserId, trapId)
end

--[[
	CLIENT: Sell a trap.
	
	@param player Player - The player selling
	@param trapId string - The trap's ID
	@return TransactionResult
]]
function StoreService.Client:SellTrap(player: Player, trapId: string)
  return StoreService:SellTrap(player.UserId, trapId)
end

--[[
	CLIENT: Sell a weapon.
	
	@param player Player - The player selling
	@param weaponType string - The weapon type to sell
	@return TransactionResult
]]
function StoreService.Client:SellWeapon(player: Player, weaponType: string)
  return StoreService:SellWeapon(player.UserId, weaponType)
end

--[[
	CLIENT: Get available items with stock info.
	
	@param player Player - The requesting player
	@return { eggs: { InventoryItem }, chickens: { InventoryItem }, traps: { SupplyItem }, weapons: { WeaponItem } }
]]
function StoreService.Client:GetAvailableItems(player: Player)
  return StoreService:GetAvailableItems()
end

--[[
	CLIENT: Get time until next store replenish.
	
	@param player Player - The requesting player
	@return number - Seconds until replenish
]]
function StoreService.Client:GetTimeUntilReplenish(player: Player)
  return StoreService:GetTimeUntilReplenish()
end

-- ============================================================================
-- Server Methods
-- ============================================================================

--[[
	SERVER: Get the current store inventory.
	
	@return StoreInventory
]]
function StoreService:GetStoreInventory(): Store.StoreInventory
  return Store.getStoreInventory()
end

--[[
	SERVER: Buy an egg from the store.
	
	@param userId number - The user ID
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreService:BuyEgg(
  userId: number,
  eggType: string,
  quantity: number?
): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.purchaseEggFromInventory(playerData, eggType, quantity or 1)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemPurchased:Fire(player, {
        itemType = "egg",
        itemId = eggType,
        quantity = quantity or 1,
        newBalance = result.newBalance,
      })

      -- Notify stock update
      local newStock = Store.getStock("egg", eggType)
      self.Client.StockUpdated:Fire(player, {
        itemType = "egg",
        itemId = eggType,
        newStock = newStock,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.PurchaseCompleted:Fire(userId, "egg", eggType)
  end

  return result
end

--[[
	SERVER: Buy a chicken from the store.
	
	@param userId number - The user ID
	@param chickenType string - The chicken type to buy
	@param quantity number? - Optional quantity (default 1)
	@return TransactionResult
]]
function StoreService:BuyChicken(
  userId: number,
  chickenType: string,
  quantity: number?
): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.purchaseChickenFromInventory(playerData, chickenType, quantity or 1)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemPurchased:Fire(player, {
        itemType = "chicken",
        itemId = chickenType,
        quantity = quantity or 1,
        newBalance = result.newBalance,
      })

      -- Notify stock update
      local newStock = Store.getStock("chicken", chickenType)
      self.Client.StockUpdated:Fire(player, {
        itemType = "chicken",
        itemId = chickenType,
        newStock = newStock,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.PurchaseCompleted:Fire(userId, "chicken", chickenType)
  end

  return result
end

--[[
	SERVER: Buy a trap from the store.
	
	@param userId number - The user ID
	@param trapType string - The trap type to buy
	@return TransactionResult
]]
function StoreService:BuyTrap(userId: number, trapType: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.buyTrap(playerData, trapType)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemPurchased:Fire(player, {
        itemType = "trap",
        itemId = trapType,
        trapId = result.itemId,
        newBalance = result.newBalance,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.PurchaseCompleted:Fire(userId, "trap", trapType)
  end

  return result
end

--[[
	SERVER: Buy a weapon from the store.
	
	@param userId number - The user ID
	@param weaponType string - The weapon type to buy
	@return TransactionResult
]]
function StoreService:BuyWeapon(userId: number, weaponType: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.buyWeapon(playerData, weaponType)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemPurchased:Fire(player, {
        itemType = "weapon",
        itemId = weaponType,
        newBalance = result.newBalance,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.PurchaseCompleted:Fire(userId, "weapon", weaponType)
  end

  return result
end

--[[
	SERVER: Sell an egg from inventory.
	
	@param userId number - The user ID
	@param eggId string - The egg's ID
	@return TransactionResult
]]
function StoreService:SellEgg(userId: number, eggId: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellEgg(playerData, eggId)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemSold:Fire(player, {
        itemType = "egg",
        itemId = eggId,
        newBalance = result.newBalance,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.SaleCompleted:Fire(userId, "egg", eggId, result.newBalance or 0)
  end

  return result
end

--[[
	SERVER: Sell a chicken from inventory or placed.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@return TransactionResult
]]
function StoreService:SellChicken(userId: number, chickenId: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellChicken(playerData, chickenId)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemSold:Fire(player, {
        itemType = "chicken",
        itemId = chickenId,
        newBalance = result.newBalance,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.SaleCompleted:Fire(userId, "chicken", chickenId, result.newBalance or 0)
  end

  return result
end

--[[
	SERVER: Sell a trapped predator.
	
	@param userId number - The user ID
	@param trapId string - The trap's ID containing the predator
	@return TransactionResult
]]
function StoreService:SellPredator(userId: number, trapId: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellPredator(playerData, trapId)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemSold:Fire(player, {
        itemType = "predator",
        itemId = trapId,
        newBalance = result.newBalance,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.SaleCompleted:Fire(userId, "predator", trapId, result.newBalance or 0)
  end

  return result
end

--[[
	SERVER: Sell a trap.
	
	@param userId number - The user ID
	@param trapId string - The trap's ID
	@return TransactionResult
]]
function StoreService:SellTrap(userId: number, trapId: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellTrap(playerData, trapId)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemSold:Fire(player, {
        itemType = "trap",
        itemId = trapId,
        newBalance = result.newBalance,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.SaleCompleted:Fire(userId, "trap", trapId, result.newBalance or 0)
  end

  return result
end

--[[
	SERVER: Sell a weapon.
	
	@param userId number - The user ID
	@param weaponType string - The weapon type to sell
	@return TransactionResult
]]
function StoreService:SellWeapon(userId: number, weaponType: string): Store.TransactionResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellWeapon(playerData, weaponType)

  if result.success then
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client events
    if player then
      self.Client.ItemSold:Fire(player, {
        itemType = "weapon",
        itemId = weaponType,
        newBalance = result.newBalance,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.SaleCompleted:Fire(userId, "weapon", weaponType, result.newBalance or 0)
  end

  return result
end

--[[
	SERVER: Get available items with stock info.
	
	@return { eggs: { InventoryItem }, chickens: { InventoryItem }, traps: { SupplyItem }, weapons: { WeaponItem } }
]]
function StoreService:GetAvailableItems()
  return {
    eggs = Store.getAvailableEggsWithStock(),
    chickens = Store.getAvailableChickensWithStock(),
    traps = Store.getAvailableTraps(),
    weapons = Store.getAvailableWeapons(),
  }
end

--[[
	SERVER: Check if store needs replenishing.
	
	@return boolean
]]
function StoreService:NeedsReplenish(): boolean
  return Store.needsReplenish()
end

--[[
	SERVER: Get time until next store replenish.
	
	@return number - Seconds until replenish
]]
function StoreService:GetTimeUntilReplenish(): number
  return Store.getTimeUntilReplenish()
end

--[[
	SERVER: Replenish the store inventory.
	Called by the game loop periodically.
	
	@return StoreInventory
]]
function StoreService:ReplenishStore(): Store.StoreInventory
  local inventory = Store.replenishStore()

  -- Notify all players
  for _, player in ipairs(Players:GetPlayers()) do
    self.Client.StoreReplenished:Fire(player, {
      timeUntilNext = Store.getReplenishInterval(),
    })
  end

  -- Fire server signal
  self.StoreRestocked:Fire()

  print("[StoreService] Store replenished")

  return inventory
end

--[[
	SERVER: Force replenish the store (for Robux purchase or admin).
	
	@return StoreInventory
]]
function StoreService:ForceReplenish(): Store.StoreInventory
  return self:ReplenishStore()
end

--[[
	SERVER: Check store and replenish if needed.
	Call this periodically from the game loop.
	
	@return boolean - True if replenished
]]
function StoreService:UpdateStore(): boolean
  if self:NeedsReplenish() then
    self:ReplenishStore()
    return true
  end
  return false
end

--[[
	SERVER: Get stock for an item.
	
	@param itemType "egg" | "chicken" - The item type
	@param itemId string - The item ID
	@return number
]]
function StoreService:GetStock(itemType: "egg" | "chicken", itemId: string): number
  return Store.getStock(itemType, itemId)
end

--[[
	SERVER: Check if an item is in stock.
	
	@param itemType "egg" | "chicken" - The item type
	@param itemId string - The item ID
	@return boolean
]]
function StoreService:IsInStock(itemType: "egg" | "chicken", itemId: string): boolean
  return Store.isInStock(itemType, itemId)
end

--[[
	SERVER: Get player's inventory value.
	
	@param userId number - The user ID
	@return { eggsValue: number, chickensValue: number, totalValue: number }?
]]
function StoreService:GetInventoryValue(userId: number): {
  eggsValue: number,
  chickensValue: number,
  totalValue: number,
}?
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return nil
  end

  return Store.getInventoryValue(playerData)
end

--[[
	SERVER: Get egg price.
	
	@param eggType string - The egg type
	@return number?
]]
function StoreService:GetEggPrice(eggType: string): number?
  return Store.getEggPrice(eggType)
end

--[[
	SERVER: Get chicken price.
	
	@param chickenType string - The chicken type
	@return number
]]
function StoreService:GetChickenPrice(chickenType: string): number
  return Store.getChickenPrice(chickenType)
end

--[[
	SERVER: Get chicken sell value.
	
	@param chickenType string - The chicken type
	@return number
]]
function StoreService:GetChickenValue(chickenType: string): number
  return Store.getChickenValue(chickenType)
end

--[[
	SERVER: Get predator sell value.
	
	@param predatorType string - The predator type
	@return number
]]
function StoreService:GetPredatorValue(predatorType: string): number
  return Store.getPredatorValue(predatorType)
end

return StoreService
