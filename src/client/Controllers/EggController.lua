--[[
	EggController
	Client-side Knit controller for managing egg interactions.
	
	Provides:
	- Local cache of world eggs
	- GoodSignal events for reactive UI updates
	- Connection to EggService via Knit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Create the controller
local EggController = Knit.CreateController({
  Name = "EggController",
})

-- Local cache of world eggs (eggs visible in the game world)
local worldEggs: { [string]: any } = {}

-- GoodSignal events for reactive UI
EggController.EggHatched = GoodSignal.new() -- Fires (data: {chickenType, chickenRarity, chickenId, isRareHatch, celebrationTier})
EggController.EggSpawned = GoodSignal.new() -- Fires (data: WorldEggData)
EggController.EggCollected = GoodSignal.new() -- Fires (data: {eggId, eggType, rarity})
EggController.EggDespawned = GoodSignal.new() -- Fires (data: {eggId})
EggController.EggPurchased = GoodSignal.new() -- Fires (data: {success, message, newBalance})
EggController.EggSold = GoodSignal.new() -- Fires (data: {eggId, message})
EggController.StockUpdated = GoodSignal.new() -- Fires (data: {itemType, itemId, newStock})

-- Reference to the server service
local eggService = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function EggController:KnitInit()
  print("[EggController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function EggController:KnitStart()
  -- Get reference to server service
  eggService = Knit.GetService("EggService")

  -- Connect to server signals
  eggService.EggHatched:Connect(function(data)
    self.EggHatched:Fire(data)
  end)

  eggService.EggSpawned:Connect(function(data)
    -- Cache world egg
    if data and data.id then
      worldEggs[data.id] = data
    end
    self.EggSpawned:Fire(data)
  end)

  eggService.EggCollected:Connect(function(data)
    -- Remove from cache
    if data and data.eggId then
      worldEggs[data.eggId] = nil
    end
    self.EggCollected:Fire(data)
  end)

  eggService.EggDespawned:Connect(function(data)
    -- Remove from cache
    if data and data.eggId then
      worldEggs[data.eggId] = nil
    end
    self.EggDespawned:Fire(data)
  end)

  eggService.EggPurchased:Connect(function(data)
    self.EggPurchased:Fire(data)
  end)

  eggService.EggSold:Connect(function(data)
    self.EggSold:Fire(data)
  end)

  eggService.StockUpdated:Connect(function(data)
    self.StockUpdated:Fire(data)
  end)

  print("[EggController] Started")
end

--[[
	Hatch an egg from inventory.
	
	@param eggId string - The egg's ID
	@return Promise<HatchResult>
]]
function EggController:HatchEgg(eggId: string)
  if not eggService then
    return Promise.resolve({
      success = false,
      message = "Service not available",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    })
  end
  return eggService:HatchEgg(eggId)
    :catch(function(err)
      warn("[EggController] HatchEgg failed:", tostring(err))
      return {
        success = false,
        message = tostring(err),
        chickenType = nil,
        chickenRarity = nil,
        chickenId = nil,
        isRareHatch = false,
        celebrationTier = 0,
      }
    end)
end

--[[
	Collect a world egg.
	
	@param eggId string - The world egg's ID
	@return Promise<CollectResult>
]]
function EggController:CollectWorldEgg(eggId: string)
  if not eggService then
    return Promise.resolve({ success = false, message = "Service not available", egg = nil })
  end
  return eggService:CollectWorldEgg(eggId)
    :catch(function(err)
      warn("[EggController] CollectWorldEgg failed:", tostring(err))
      return { success = false, message = tostring(err), egg = nil }
    end)
end

--[[
	Buy an egg from the store.
	
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return Promise<PurchaseResult>
]]
function EggController:BuyEgg(eggType: string, quantity: number?)
  if not eggService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return eggService:BuyEgg(eggType, quantity)
    :catch(function(err)
      warn("[EggController] BuyEgg failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell an egg from inventory.
	
	@param eggId string - The egg's ID
	@return Promise<SellResult>
]]
function EggController:SellEgg(eggId: string)
  if not eggService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return eggService:SellEgg(eggId)
    :catch(function(err)
      warn("[EggController] SellEgg failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Get all cached world eggs.
	
	@return { [string]: WorldEggData } - Map of egg ID to world egg data
]]
function EggController:GetWorldEggs(): { [string]: any }
  return worldEggs
end

--[[
	Get a specific world egg from cache.
	
	@param eggId string - The egg's ID
	@return WorldEggData? - The world egg data or nil
]]
function EggController:GetWorldEgg(eggId: string): any?
  return worldEggs[eggId]
end

--[[
	Get the count of world eggs.
	
	@return number - Number of world eggs
]]
function EggController:GetWorldEggCount(): number
  local count = 0
  for _ in pairs(worldEggs) do
    count = count + 1
  end
  return count
end

return EggController
