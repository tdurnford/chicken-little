--[[
	ChickenController
	Client-side Knit controller for managing chicken interactions.
	
	Provides:
	- Local cache of placed chickens
	- GoodSignal events for reactive UI updates
	- Connection to ChickenService via Knit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Create the controller
local ChickenController = Knit.CreateController({
  Name = "ChickenController",
})

-- GoodSignal events for reactive UI
ChickenController.ChickenPlaced = GoodSignal.new() -- Fires (data: {playerId, chicken, position})
ChickenController.ChickenPickedUp = GoodSignal.new() -- Fires (data: {playerId, chickenId, spotIndex})
ChickenController.ChickenMoved = GoodSignal.new() -- Fires (data: {playerId, chickenId, oldSpotIndex, newSpotIndex, chicken})
ChickenController.ChickenSold = GoodSignal.new() -- Fires (data: {chickenId, message})
ChickenController.MoneyCollected = GoodSignal.new() -- Fires (amount: number)

-- Reference to the server service
local chickenService = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function ChickenController:KnitInit()
  print("[ChickenController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function ChickenController:KnitStart()
  -- Get reference to server service
  chickenService = Knit.GetService("ChickenService")

  -- Connect to server signals
  chickenService.ChickenPlaced:Connect(function(data)
    self.ChickenPlaced:Fire(data)
  end)

  chickenService.ChickenPickedUp:Connect(function(data)
    self.ChickenPickedUp:Fire(data)
  end)

  chickenService.ChickenMoved:Connect(function(data)
    self.ChickenMoved:Fire(data)
  end)

  chickenService.ChickenSold:Connect(function(data)
    self.ChickenSold:Fire(data)
  end)

  chickenService.MoneyCollected:Connect(function(amount)
    self.MoneyCollected:Fire(amount)
  end)

  print("[ChickenController] Started")
end

--[[
	Place a chicken from inventory into the world.
	
	@param chickenId string - The chicken's ID
	@return Promise<PlacementResult>
]]
function ChickenController:PlaceChicken(chickenId: string)
  if not chickenService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return chickenService:PlaceChicken(chickenId)
    :catch(function(err)
      warn("[ChickenController] PlaceChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Pick up a placed chicken back to inventory.
	
	@param chickenId string - The chicken's ID
	@return Promise<PlacementResult>
]]
function ChickenController:PickupChicken(chickenId: string)
  if not chickenService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return chickenService:PickupChicken(chickenId)
    :catch(function(err)
      warn("[ChickenController] PickupChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Move a chicken to a different spot.
	
	@param chickenId string - The chicken's ID
	@param newSpotIndex number - The new spot index
	@return Promise<PlacementResult>
]]
function ChickenController:MoveChicken(chickenId: string, newSpotIndex: number)
  if not chickenService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return chickenService:MoveChicken(chickenId, newSpotIndex)
    :catch(function(err)
      warn("[ChickenController] MoveChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Sell a chicken for money.
	
	@param chickenId string - The chicken's ID
	@return Promise<SellResult>
]]
function ChickenController:SellChicken(chickenId: string)
  if not chickenService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return chickenService:SellChicken(chickenId)
    :catch(function(err)
      warn("[ChickenController] SellChicken failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Collect accumulated money from chickens.
	
	@param chickenId string? - Optional specific chicken ID (nil = collect all)
	@return Promise<CollectionResult>
]]
function ChickenController:CollectMoney(chickenId: string?)
  if not chickenService then
    return Promise.resolve({ success = false, message = "Service not available" })
  end
  return chickenService:CollectMoney(chickenId)
    :catch(function(err)
      warn("[ChickenController] CollectMoney failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

return ChickenController
