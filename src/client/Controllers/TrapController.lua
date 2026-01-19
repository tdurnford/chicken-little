--[[
	TrapController
	Client-side Knit controller for managing trap interactions.
	
	Provides:
	- Trap placement/pickup via TrapService
	- GoodSignal events for reactive UI updates
	- Local trap cache for fast UI access
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Create the controller
local TrapController = Knit.CreateController({
  Name = "TrapController",
})

-- GoodSignal events for reactive UI
TrapController.TrapPlaced = GoodSignal.new() -- Fires (trapId, trapType, userId, spotIndex)
TrapController.TrapPickedUp = GoodSignal.new() -- Fires (trapId, userId)
TrapController.TrapCaught = GoodSignal.new() -- Fires (trapId, predatorType, catchProbability)
TrapController.TrapCooldownStarted = GoodSignal.new() -- Fires (trapId, cooldownDuration)
TrapController.TrapCooldownEnded = GoodSignal.new() -- Fires (trapId)
TrapController.PredatorCollected = GoodSignal.new() -- Fires (trapId, predatorType, reward)

-- Reference to the server service
local trapService = nil

-- Local trap cache for fast synchronous access
local placedTrapsCache: { [string]: any } = {}

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function TrapController:KnitInit()
  print("[TrapController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function TrapController:KnitStart()
  -- Get reference to server service
  trapService = Knit.GetService("TrapService")

  -- Connect to server signals
  trapService.TrapPlaced:Connect(function(trapId, trapType, userId, spotIndex)
    -- Update local cache
    placedTrapsCache[trapId] = {
      id = trapId,
      trapType = trapType,
      userId = userId,
      spotIndex = spotIndex,
    }
    self.TrapPlaced:Fire(trapId, trapType, userId, spotIndex)
  end)

  trapService.TrapPickedUp:Connect(function(trapId, userId)
    -- Remove from cache
    placedTrapsCache[trapId] = nil
    self.TrapPickedUp:Fire(trapId, userId)
  end)

  trapService.TrapCaught:Connect(function(trapId, predatorType, catchProbability)
    -- Update cache with caught predator
    if placedTrapsCache[trapId] then
      placedTrapsCache[trapId].caughtPredator = predatorType
    end
    self.TrapCaught:Fire(trapId, predatorType, catchProbability)
  end)

  trapService.TrapCooldownStarted:Connect(function(trapId, cooldownDuration)
    -- Update cache with cooldown
    if placedTrapsCache[trapId] then
      placedTrapsCache[trapId].cooldownUntil = os.time() + cooldownDuration
    end
    self.TrapCooldownStarted:Fire(trapId, cooldownDuration)
  end)

  trapService.TrapCooldownEnded:Connect(function(trapId)
    -- Clear cooldown from cache
    if placedTrapsCache[trapId] then
      placedTrapsCache[trapId].cooldownUntil = nil
    end
    self.TrapCooldownEnded:Fire(trapId)
  end)

  trapService.PredatorCollected:Connect(function(trapId, predatorType, reward)
    -- Clear caught predator from cache
    if placedTrapsCache[trapId] then
      placedTrapsCache[trapId].caughtPredator = nil
    end
    self.PredatorCollected:Fire(trapId, predatorType, reward)
  end)

  print("[TrapController] Started")
end

-- ============================================================================
-- Cache Methods
-- ============================================================================

--[[
	Get all cached placed traps (synchronous).
	
	@return { [string]: TrapData }
]]
function TrapController:GetCachedTraps(): { [string]: any }
  return placedTrapsCache
end

--[[
	Get a specific cached trap (synchronous).
	
	@param trapId string - The trap ID
	@return TrapData?
]]
function TrapController:GetCachedTrap(trapId: string): any
  return placedTrapsCache[trapId]
end

--[[
	Get cached trap count (synchronous).
	
	@return number
]]
function TrapController:GetCachedTrapCount(): number
  local count = 0
  for _ in pairs(placedTrapsCache) do
    count += 1
  end
  return count
end

--[[
	Clear local cache (useful for refresh).
]]
function TrapController:ClearCache()
  placedTrapsCache = {}
end

-- ============================================================================
-- Query Methods (from service)
-- ============================================================================

--[[
	Get all placed traps from server.
	
	@return {TrapData}
]]
function TrapController:GetPlacedTraps()
  if not trapService then
    return {}
  end
  return trapService:GetPlacedTraps()
end

--[[
	Get trap summary from server.
	
	@return TrapSummary
]]
function TrapController:GetTrapSummary()
  if not trapService then
    return {
      totalTraps = 0,
      availableSpots = 0,
      readyTraps = 0,
      trapsWithPredators = 0,
      trapsOnCooldown = 0,
    }
  end
  return trapService:GetTrapSummary()
end

--[[
	Get catching summary from server.
	
	@return CatchingSummary
]]
function TrapController:GetCatchingSummary()
  if not trapService then
    return {
      totalTraps = 0,
      readyTraps = 0,
      trapsOnCooldown = 0,
      caughtPredators = 0,
      pendingReward = 0,
    }
  end
  return trapService:GetCatchingSummary()
end

--[[
	Get available trap spots from server.
	
	@return {number}
]]
function TrapController:GetAvailableSpots()
  if not trapService then
    return {}
  end
  return trapService:GetAvailableSpots()
end

--[[
	Get pending reward total from server.
	
	@return number
]]
function TrapController:GetPendingReward(): number
  if not trapService then
    return 0
  end
  return trapService:GetPendingReward()
end

--[[
	Get trap config by type.
	
	@param trapType string - The trap type
	@return TrapTypeConfig?
]]
function TrapController:GetTrapConfig(trapType: string)
  if not trapService then
    return nil
  end
  return trapService:GetTrapConfig(trapType)
end

--[[
	Get all trap configs sorted.
	
	@return {TrapTypeConfig}
]]
function TrapController:GetAllTrapConfigs()
  if not trapService then
    return {}
  end
  return trapService:GetAllTrapConfigs()
end

--[[
	Get catch probability for a trap vs predator.
	
	@param trapType string - The trap type
	@param predatorType string - The predator type
	@return number
]]
function TrapController:GetCatchProbability(trapType: string, predatorType: string): number
  if not trapService then
    return 0
  end
  return trapService:GetCatchProbability(trapType, predatorType)
end

--[[
	Check if can place more of a trap type.
	
	@param trapType string - The trap type
	@return boolean
]]
function TrapController:CanPlaceMoreOfType(trapType: string): boolean
  if not trapService then
    return false
  end
  return trapService:CanPlaceMoreOfType(trapType)
end

-- ============================================================================
-- Action Methods
-- ============================================================================

--[[
	Place a new trap at a spot.
	
	@param trapType string - The trap type to place
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapController:PlaceTrap(trapType: string, spotIndex: number)
  if not trapService then
    return { success = false, message = "Service not available", trap = nil }
  end
  return trapService:PlaceTrap(trapType, spotIndex)
end

--[[
	Place an existing trap from inventory.
	
	@param trapId string - The trap ID
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapController:PlaceTrapFromInventory(trapId: string, spotIndex: number)
  if not trapService then
    return { success = false, message = "Service not available", trap = nil }
  end
  return trapService:PlaceTrapFromInventory(trapId, spotIndex)
end

--[[
	Pick up (sell) a trap.
	
	@param trapId string - The trap ID
	@return PlacementResult
]]
function TrapController:PickupTrap(trapId: string)
  if not trapService then
    return { success = false, message = "Service not available", trap = nil }
  end
  return trapService:PickupTrap(trapId)
end

--[[
	Move a trap to a different spot.
	
	@param trapId string - The trap ID
	@param newSpotIndex number - The new spot index
	@return PlacementResult
]]
function TrapController:MoveTrap(trapId: string, newSpotIndex: number)
  if not trapService then
    return { success = false, message = "Service not available", trap = nil }
  end
  return trapService:MoveTrap(trapId, newSpotIndex)
end

--[[
	Collect reward from a caught predator.
	
	@param trapId string - The trap ID
	@return CatchResult
]]
function TrapController:CollectTrap(trapId: string)
  if not trapService then
    return { success = false, message = "Service not available" }
  end
  return trapService:CollectTrap(trapId)
end

--[[
	Collect all caught predators.
	
	@return {totalReward: number, count: number}
]]
function TrapController:CollectAllTraps()
  if not trapService then
    return { totalReward = 0, count = 0 }
  end
  return trapService:CollectAllTraps()
end

return TrapController
