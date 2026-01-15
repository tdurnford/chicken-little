--[[
	TrapPlacement Module
	Handles placing, picking up, and managing traps in coop spots.
	Manages validation of spots, durability tracking, and cooldown management.
]]

local TrapPlacement = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local TrapConfig = require(script.Parent.TrapConfig)

-- Constants
local MAX_TRAP_SPOTS = 8 -- Maximum trap spots per coop

-- Type definitions
export type PlacementResult = {
  success: boolean,
  message: string,
  trap: PlayerData.TrapData?,
}

export type TrapState = {
  isOnCooldown: boolean,
  cooldownRemaining: number,
  hasCaughtPredator: boolean,
  durabilityRemaining: number?,
}

-- Get the maximum number of trap spots
function TrapPlacement.getMaxSpots(): number
  return MAX_TRAP_SPOTS
end

-- Check if a spot index is valid (1 to MAX_TRAP_SPOTS)
function TrapPlacement.isValidSpot(spotIndex: number): boolean
  return type(spotIndex) == "number"
    and spotIndex >= 1
    and spotIndex <= MAX_TRAP_SPOTS
    and spotIndex == math.floor(spotIndex)
end

-- Get all occupied trap spot indices from player data
-- Only considers spots 1-8 as valid placements (spotIndex=-1 means unplaced/in inventory)
function TrapPlacement.getOccupiedSpots(playerData: PlayerData.PlayerDataSchema): { number }
  local occupied = {}
  for _, trap in ipairs(playerData.traps) do
    if trap.spotIndex and trap.spotIndex >= 1 and trap.spotIndex <= MAX_TRAP_SPOTS then
      table.insert(occupied, trap.spotIndex)
    end
  end
  return occupied
end

-- Get all available (empty) trap spot indices from player data
-- Only considers spots 1-8 as valid placements (spotIndex=-1 means unplaced/in inventory)
function TrapPlacement.getAvailableSpots(playerData: PlayerData.PlayerDataSchema): { number }
  local occupiedSet: { [number]: boolean } = {}
  for _, trap in ipairs(playerData.traps) do
    if trap.spotIndex and trap.spotIndex >= 1 and trap.spotIndex <= MAX_TRAP_SPOTS then
      occupiedSet[trap.spotIndex] = true
    end
  end

  local available = {}
  for i = 1, MAX_TRAP_SPOTS do
    if not occupiedSet[i] then
      table.insert(available, i)
    end
  end
  return available
end

-- Check if a specific spot is occupied
-- Only considers spots 1-8 as valid placements
function TrapPlacement.isSpotOccupied(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): boolean
  if not TrapPlacement.isValidSpot(spotIndex) then
    return false
  end

  for _, trap in ipairs(playerData.traps) do
    if trap.spotIndex and trap.spotIndex == spotIndex then
      return true
    end
  end
  return false
end

-- Check if a specific spot is available
function TrapPlacement.isSpotAvailable(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): boolean
  if not TrapPlacement.isValidSpot(spotIndex) then
    return false
  end
  return not TrapPlacement.isSpotOccupied(playerData, spotIndex)
end

-- Get the trap at a specific spot (or nil if empty)
function TrapPlacement.getTrapAtSpot(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): PlayerData.TrapData?
  if not TrapPlacement.isValidSpot(spotIndex) then
    return nil
  end

  for _, trap in ipairs(playerData.traps) do
    if trap.spotIndex == spotIndex then
      return trap
    end
  end
  return nil
end

-- Find a trap by ID
function TrapPlacement.findTrap(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): (PlayerData.TrapData?, number?)
  for index, trap in ipairs(playerData.traps) do
    if trap.id == trapId then
      return trap, index
    end
  end
  return nil, nil
end

-- Count traps of a specific type
function TrapPlacement.countTrapsOfType(
  playerData: PlayerData.PlayerDataSchema,
  trapType: string
): number
  local count = 0
  for _, trap in ipairs(playerData.traps) do
    if trap.trapType == trapType then
      count = count + 1
    end
  end
  return count
end

-- Check if player can place more traps of a specific type
function TrapPlacement.canPlaceMoreOfType(
  playerData: PlayerData.PlayerDataSchema,
  trapType: string
): boolean
  local config = TrapConfig.get(trapType)
  if not config then
    return false
  end

  local currentCount = TrapPlacement.countTrapsOfType(playerData, trapType)
  return currentCount < config.maxPlacement
end

-- Get remaining placement slots for a trap type
function TrapPlacement.getRemainingSlots(
  playerData: PlayerData.PlayerDataSchema,
  trapType: string
): number
  local config = TrapConfig.get(trapType)
  if not config then
    return 0
  end

  local currentCount = TrapPlacement.countTrapsOfType(playerData, trapType)
  return math.max(0, config.maxPlacement - currentCount)
end

-- Place a trap at a spot (creates new trap from type)
function TrapPlacement.placeTrap(
  playerData: PlayerData.PlayerDataSchema,
  trapType: string,
  spotIndex: number
): PlacementResult
  -- Validate trap type
  local config = TrapConfig.get(trapType)
  if not config then
    return {
      success = false,
      message = "Invalid trap type: " .. tostring(trapType),
      trap = nil,
    }
  end

  -- Validate spot
  if not TrapPlacement.isValidSpot(spotIndex) then
    return {
      success = false,
      message = "Invalid spot index. Must be between 1 and " .. MAX_TRAP_SPOTS,
      trap = nil,
    }
  end

  -- Check if spot is available
  if TrapPlacement.isSpotOccupied(playerData, spotIndex) then
    return {
      success = false,
      message = "Spot " .. spotIndex .. " is already occupied by a trap",
      trap = nil,
    }
  end

  -- Check placement limit for this trap type
  if not TrapPlacement.canPlaceMoreOfType(playerData, trapType) then
    return {
      success = false,
      message = "Maximum placement limit reached for " .. config.displayName,
      trap = nil,
    }
  end

  -- Check if player can afford the trap
  if playerData.money < config.price then
    return {
      success = false,
      message = "Not enough money. Need " .. config.price .. " but have " .. playerData.money,
      trap = nil,
    }
  end

  -- Deduct money
  playerData.money = playerData.money - config.price

  -- Create new trap data
  local newTrap: PlayerData.TrapData = {
    id = PlayerData.generateId(),
    trapType = trapType,
    tier = config.tierLevel,
    spotIndex = spotIndex,
    cooldownEndTime = nil,
    caughtPredator = nil,
  }

  -- Add trap to player data
  table.insert(playerData.traps, newTrap)

  return {
    success = true,
    message = config.displayName .. " placed at spot " .. spotIndex,
    trap = newTrap,
  }
end

-- Place an existing trap from inventory to a spot
function TrapPlacement.placeTrapFromInventory(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  spotIndex: number
): PlacementResult
  -- Validate spot
  if not TrapPlacement.isValidSpot(spotIndex) then
    return {
      success = false,
      message = "Invalid spot index. Must be between 1 and " .. MAX_TRAP_SPOTS,
      trap = nil,
    }
  end

  -- Check if spot is available
  if TrapPlacement.isSpotOccupied(playerData, spotIndex) then
    return {
      success = false,
      message = "Spot " .. spotIndex .. " is already occupied by a trap",
      trap = nil,
    }
  end

  -- Find the trap
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return {
      success = false,
      message = "Trap not found",
      trap = nil,
    }
  end

  -- Check trap is not already placed
  if trap.spotIndex and trap.spotIndex > 0 then
    return {
      success = false,
      message = "Trap is already placed at spot " .. trap.spotIndex,
      trap = nil,
    }
  end

  -- Get trap config for display name
  local config = TrapConfig.get(trap.trapType)
  if not config then
    return {
      success = false,
      message = "Invalid trap type: " .. tostring(trap.trapType),
      trap = nil,
    }
  end

  -- Update spot index to place the trap
  playerData.traps[trapIndex].spotIndex = spotIndex

  return {
    success = true,
    message = config.displayName .. " placed at spot " .. spotIndex,
    trap = playerData.traps[trapIndex],
  }
end

-- Pick up (remove) a trap from a spot
function TrapPlacement.pickupTrap(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): PlacementResult
  -- Find the trap
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return {
      success = false,
      message = "Trap not found",
      trap = nil,
    }
  end

  -- Get trap config for sell price
  local config = TrapConfig.get(trap.trapType)
  local sellPrice = config and config.sellPrice or 0

  -- Remove trap from player data
  table.remove(playerData.traps, trapIndex)

  -- Refund sell price
  playerData.money = playerData.money + sellPrice

  return {
    success = true,
    message = "Trap picked up. Received " .. sellPrice .. " money",
    trap = trap,
  }
end

-- Move a trap from one spot to another
function TrapPlacement.moveTrap(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  newSpotIndex: number
): PlacementResult
  -- Validate new spot
  if not TrapPlacement.isValidSpot(newSpotIndex) then
    return {
      success = false,
      message = "Invalid spot index. Must be between 1 and " .. MAX_TRAP_SPOTS,
      trap = nil,
    }
  end

  -- Find the trap
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return {
      success = false,
      message = "Trap not found",
      trap = nil,
    }
  end

  -- Check if already at this spot
  if trap.spotIndex == newSpotIndex then
    return {
      success = true,
      message = "Trap is already at spot " .. newSpotIndex,
      trap = trap,
    }
  end

  -- Check if new spot is available
  if TrapPlacement.isSpotOccupied(playerData, newSpotIndex) then
    return {
      success = false,
      message = "Spot " .. newSpotIndex .. " is already occupied",
      trap = nil,
    }
  end

  -- Update spot index
  playerData.traps[trapIndex].spotIndex = newSpotIndex

  return {
    success = true,
    message = "Trap moved to spot " .. newSpotIndex,
    trap = playerData.traps[trapIndex],
  }
end

-- Get current state of a trap
function TrapPlacement.getTrapState(trap: PlayerData.TrapData, currentTime: number): TrapState
  local config = TrapConfig.get(trap.trapType)
  local isOnCooldown = false
  local cooldownRemaining = 0

  if trap.cooldownEndTime and trap.cooldownEndTime > currentTime then
    isOnCooldown = true
    cooldownRemaining = trap.cooldownEndTime - currentTime
  end

  -- Calculate durability remaining (nil for infinite durability traps)
  local durabilityRemaining = nil
  if config and config.durability > 0 then
    -- This would need to be tracked in TrapData; for now, return max durability
    durabilityRemaining = config.durability
  end

  return {
    isOnCooldown = isOnCooldown,
    cooldownRemaining = cooldownRemaining,
    hasCaughtPredator = trap.caughtPredator ~= nil,
    durabilityRemaining = durabilityRemaining,
  }
end

-- Check if a trap is ready to catch (not on cooldown and no caught predator)
function TrapPlacement.isReadyToCatch(trap: PlayerData.TrapData, currentTime: number): boolean
  -- Cannot catch if already has a predator
  if trap.caughtPredator ~= nil then
    return false
  end

  -- Cannot catch if on cooldown
  if trap.cooldownEndTime and trap.cooldownEndTime > currentTime then
    return false
  end

  return true
end

-- Start cooldown on a trap
function TrapPlacement.startCooldown(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  currentTime: number
): boolean
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return false
  end

  local config = TrapConfig.get(trap.trapType)
  if not config then
    return false
  end

  playerData.traps[trapIndex].cooldownEndTime = currentTime + config.cooldownSeconds
  return true
end

-- Clear cooldown on a trap
function TrapPlacement.clearCooldown(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): boolean
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return false
  end

  playerData.traps[trapIndex].cooldownEndTime = nil
  return true
end

-- Set caught predator on a trap
function TrapPlacement.setCaughtPredator(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  predatorType: string
): boolean
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return false
  end

  playerData.traps[trapIndex].caughtPredator = predatorType
  return true
end

-- Clear caught predator from a trap (when sold or released)
function TrapPlacement.clearCaughtPredator(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string
): string?
  local trap, trapIndex = TrapPlacement.findTrap(playerData, trapId)
  if not trap or not trapIndex then
    return nil
  end

  local predator = trap.caughtPredator
  playerData.traps[trapIndex].caughtPredator = nil
  return predator
end

-- Get count of placed traps
function TrapPlacement.getPlacedTrapCount(playerData: PlayerData.PlayerDataSchema): number
  return #playerData.traps
end

-- Check if all trap spots are full
function TrapPlacement.areAllSpotsFull(playerData: PlayerData.PlayerDataSchema): boolean
  return #TrapPlacement.getAvailableSpots(playerData) == 0
end

-- Check if coop has no traps
function TrapPlacement.hasNoTraps(playerData: PlayerData.PlayerDataSchema): boolean
  return #playerData.traps == 0
end

-- Get the first available spot (or nil if full)
function TrapPlacement.getFirstAvailableSpot(playerData: PlayerData.PlayerDataSchema): number?
  local available = TrapPlacement.getAvailableSpots(playerData)
  if #available > 0 then
    return available[1]
  end
  return nil
end

-- Get all traps that are ready to catch
function TrapPlacement.getReadyTraps(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): { PlayerData.TrapData }
  local ready = {}
  for _, trap in ipairs(playerData.traps) do
    if TrapPlacement.isReadyToCatch(trap, currentTime) then
      table.insert(ready, trap)
    end
  end
  return ready
end

-- Get all traps that have caught predators
function TrapPlacement.getTrapsWithPredators(
  playerData: PlayerData.PlayerDataSchema
): { PlayerData.TrapData }
  local withPredators = {}
  for _, trap in ipairs(playerData.traps) do
    if trap.caughtPredator ~= nil then
      table.insert(withPredators, trap)
    end
  end
  return withPredators
end

-- Get all traps on cooldown
function TrapPlacement.getTrapsOnCooldown(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): { PlayerData.TrapData }
  local onCooldown = {}
  for _, trap in ipairs(playerData.traps) do
    if trap.cooldownEndTime and trap.cooldownEndTime > currentTime then
      table.insert(onCooldown, trap)
    end
  end
  return onCooldown
end

-- Get trap effectiveness info for display
function TrapPlacement.getTrapInfo(trap: PlayerData.TrapData): {
  displayName: string,
  tier: string,
  spotIndex: number,
  hasPredator: boolean,
}?
  local config = TrapConfig.get(trap.trapType)
  if not config then
    return nil
  end

  return {
    displayName = config.displayName,
    tier = config.tier,
    spotIndex = trap.spotIndex,
    hasPredator = trap.caughtPredator ~= nil,
  }
end

-- Validate placement state consistency
function TrapPlacement.validatePlacementState(playerData: PlayerData.PlayerDataSchema): boolean
  -- Check that no two traps share the same spot
  local usedSpots: { [number]: boolean } = {}
  for _, trap in ipairs(playerData.traps) do
    if trap.spotIndex then
      if usedSpots[trap.spotIndex] then
        return false -- Duplicate spot detected
      end
      usedSpots[trap.spotIndex] = true

      -- Validate spot is in range
      if not TrapPlacement.isValidSpot(trap.spotIndex) then
        return false
      end
    else
      return false -- Placed trap must have a spot
    end

    -- Validate trap type exists
    if not TrapConfig.isValidType(trap.trapType) then
      return false
    end
  end

  return true
end

-- Get summary of all traps for UI
function TrapPlacement.getSummary(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): {
  totalTraps: number,
  availableSpots: number,
  readyTraps: number,
  trapsWithPredators: number,
  trapsOnCooldown: number,
}
  return {
    totalTraps = #playerData.traps,
    availableSpots = #TrapPlacement.getAvailableSpots(playerData),
    readyTraps = #TrapPlacement.getReadyTraps(playerData, currentTime),
    trapsWithPredators = #TrapPlacement.getTrapsWithPredators(playerData),
    trapsOnCooldown = #TrapPlacement.getTrapsOnCooldown(playerData, currentTime),
  }
end

return TrapPlacement
