--[[
	ChickenPlacement Module
	Handles placing and picking up chickens in coop spots.
	Manages validation of spots and updates to player data.
]]

local ChickenPlacement = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local Chicken = require(script.Parent.Chicken)

-- Constants
local MAX_COOP_SPOTS = 12

-- Type definitions
export type PlacementResult = {
  success: boolean,
  message: string,
  chicken: PlayerData.ChickenData?,
}

-- Get the maximum number of coop spots
function ChickenPlacement.getMaxSpots(): number
  return MAX_COOP_SPOTS
end

-- Check if a spot index is valid (1-12)
function ChickenPlacement.isValidSpot(spotIndex: number): boolean
  return type(spotIndex) == "number"
    and spotIndex >= 1
    and spotIndex <= MAX_COOP_SPOTS
    and spotIndex == math.floor(spotIndex)
end

-- Get all occupied spot indices from player data
function ChickenPlacement.getOccupiedSpots(playerData: PlayerData.PlayerDataSchema): { number }
  local occupied = {}
  for _, chicken in ipairs(playerData.placedChickens) do
    if chicken.spotIndex then
      table.insert(occupied, chicken.spotIndex)
    end
  end
  return occupied
end

-- Get all available (empty) spot indices from player data
function ChickenPlacement.getAvailableSpots(playerData: PlayerData.PlayerDataSchema): { number }
  local occupiedSet: { [number]: boolean } = {}
  for _, chicken in ipairs(playerData.placedChickens) do
    if chicken.spotIndex then
      occupiedSet[chicken.spotIndex] = true
    end
  end

  local available = {}
  for i = 1, MAX_COOP_SPOTS do
    if not occupiedSet[i] then
      table.insert(available, i)
    end
  end
  return available
end

-- Check if a specific spot is occupied
function ChickenPlacement.isSpotOccupied(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): boolean
  if not ChickenPlacement.isValidSpot(spotIndex) then
    return false
  end

  for _, chicken in ipairs(playerData.placedChickens) do
    if chicken.spotIndex == spotIndex then
      return true
    end
  end
  return false
end

-- Check if a specific spot is available
function ChickenPlacement.isSpotAvailable(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): boolean
  if not ChickenPlacement.isValidSpot(spotIndex) then
    return false
  end
  return not ChickenPlacement.isSpotOccupied(playerData, spotIndex)
end

-- Get the chicken at a specific spot (or nil if empty)
function ChickenPlacement.getChickenAtSpot(
  playerData: PlayerData.PlayerDataSchema,
  spotIndex: number
): PlayerData.ChickenData?
  if not ChickenPlacement.isValidSpot(spotIndex) then
    return nil
  end

  for _, chicken in ipairs(playerData.placedChickens) do
    if chicken.spotIndex == spotIndex then
      return chicken
    end
  end
  return nil
end

-- Find a chicken in inventory by ID
function ChickenPlacement.findChickenInInventory(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): (PlayerData.ChickenData?, number?)
  for index, chicken in ipairs(playerData.inventory.chickens) do
    if chicken.id == chickenId then
      return chicken, index
    end
  end
  return nil, nil
end

-- Find a placed chicken by ID
function ChickenPlacement.findPlacedChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): (PlayerData.ChickenData?, number?)
  for index, chicken in ipairs(playerData.placedChickens) do
    if chicken.id == chickenId then
      return chicken, index
    end
  end
  return nil, nil
end

-- Place a chicken from inventory into a coop spot
-- Returns updated player data (or nil if placement fails)
function ChickenPlacement.placeChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string,
  spotIndex: number
): PlacementResult
  -- Validate spot
  if not ChickenPlacement.isValidSpot(spotIndex) then
    return {
      success = false,
      message = "Invalid spot index. Must be between 1 and " .. MAX_COOP_SPOTS,
      chicken = nil,
    }
  end

  -- Check if spot is available
  if ChickenPlacement.isSpotOccupied(playerData, spotIndex) then
    return {
      success = false,
      message = "Spot " .. spotIndex .. " is already occupied",
      chicken = nil,
    }
  end

  -- Find chicken in inventory
  local chicken, inventoryIndex = ChickenPlacement.findChickenInInventory(playerData, chickenId)
  if not chicken or not inventoryIndex then
    return {
      success = false,
      message = "Chicken not found in inventory",
      chicken = nil,
    }
  end

  -- Validate the chicken data
  if not PlayerData.validateChicken(chicken) then
    return {
      success = false,
      message = "Invalid chicken data",
      chicken = nil,
    }
  end

  -- Remove chicken from inventory
  table.remove(playerData.inventory.chickens, inventoryIndex)

  -- Update chicken with spot index and add to placed chickens
  local placedChicken: PlayerData.ChickenData = {
    id = chicken.id,
    chickenType = chicken.chickenType,
    rarity = chicken.rarity,
    accumulatedMoney = chicken.accumulatedMoney,
    lastEggTime = chicken.lastEggTime,
    spotIndex = spotIndex,
  }
  table.insert(playerData.placedChickens, placedChicken)

  return {
    success = true,
    message = "Chicken placed successfully at spot " .. spotIndex,
    chicken = placedChicken,
  }
end

-- Pick up a chicken from a coop spot and return to inventory
function ChickenPlacement.pickupChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string
): PlacementResult
  -- Find placed chicken
  local chicken, placedIndex = ChickenPlacement.findPlacedChicken(playerData, chickenId)
  if not chicken or not placedIndex then
    return {
      success = false,
      message = "Chicken not found in coop",
      chicken = nil,
    }
  end

  -- Validate the chicken data
  if not PlayerData.validateChicken(chicken) then
    return {
      success = false,
      message = "Invalid chicken data",
      chicken = nil,
    }
  end

  -- Remove from placed chickens
  table.remove(playerData.placedChickens, placedIndex)

  -- Remove spot index and add to inventory
  local inventoryChicken: PlayerData.ChickenData = {
    id = chicken.id,
    chickenType = chicken.chickenType,
    rarity = chicken.rarity,
    accumulatedMoney = chicken.accumulatedMoney,
    lastEggTime = chicken.lastEggTime,
    spotIndex = nil,
  }
  table.insert(playerData.inventory.chickens, inventoryChicken)

  return {
    success = true,
    message = "Chicken picked up successfully",
    chicken = inventoryChicken,
  }
end

-- Move a chicken from one spot to another
function ChickenPlacement.moveChicken(
  playerData: PlayerData.PlayerDataSchema,
  chickenId: string,
  newSpotIndex: number
): PlacementResult
  -- Validate new spot
  if not ChickenPlacement.isValidSpot(newSpotIndex) then
    return {
      success = false,
      message = "Invalid spot index. Must be between 1 and " .. MAX_COOP_SPOTS,
      chicken = nil,
    }
  end

  -- Find placed chicken
  local chicken, placedIndex = ChickenPlacement.findPlacedChicken(playerData, chickenId)
  if not chicken or not placedIndex then
    return {
      success = false,
      message = "Chicken not found in coop",
      chicken = nil,
    }
  end

  -- Check if already at this spot
  if chicken.spotIndex == newSpotIndex then
    return {
      success = true,
      message = "Chicken is already at spot " .. newSpotIndex,
      chicken = chicken,
    }
  end

  -- Check if new spot is available
  if ChickenPlacement.isSpotOccupied(playerData, newSpotIndex) then
    return {
      success = false,
      message = "Spot " .. newSpotIndex .. " is already occupied",
      chicken = nil,
    }
  end

  -- Update spot index
  playerData.placedChickens[placedIndex].spotIndex = newSpotIndex

  return {
    success = true,
    message = "Chicken moved to spot " .. newSpotIndex,
    chicken = playerData.placedChickens[placedIndex],
  }
end

-- Get the count of chickens in inventory
function ChickenPlacement.getInventoryChickenCount(playerData: PlayerData.PlayerDataSchema): number
  return #playerData.inventory.chickens
end

-- Get the count of placed chickens
function ChickenPlacement.getPlacedChickenCount(playerData: PlayerData.PlayerDataSchema): number
  return #playerData.placedChickens
end

-- Get the total number of chickens (inventory + placed)
function ChickenPlacement.getTotalChickenCount(playerData: PlayerData.PlayerDataSchema): number
  return #playerData.inventory.chickens + #playerData.placedChickens
end

-- Check if the coop is full (all spots occupied)
function ChickenPlacement.isCoopFull(playerData: PlayerData.PlayerDataSchema): boolean
  return #ChickenPlacement.getAvailableSpots(playerData) == 0
end

-- Check if the coop is empty (no chickens placed)
function ChickenPlacement.isCoopEmpty(playerData: PlayerData.PlayerDataSchema): boolean
  return #playerData.placedChickens == 0
end

-- Get the first available spot (or nil if full)
function ChickenPlacement.getFirstAvailableSpot(playerData: PlayerData.PlayerDataSchema): number?
  local available = ChickenPlacement.getAvailableSpots(playerData)
  if #available > 0 then
    return available[1]
  end
  return nil
end

-- Validate placement state consistency
function ChickenPlacement.validatePlacementState(playerData: PlayerData.PlayerDataSchema): boolean
  -- Check that no two chickens share the same spot
  local usedSpots: { [number]: boolean } = {}
  for _, chicken in ipairs(playerData.placedChickens) do
    if chicken.spotIndex then
      if usedSpots[chicken.spotIndex] then
        return false -- Duplicate spot detected
      end
      usedSpots[chicken.spotIndex] = true

      -- Validate spot is in range
      if not ChickenPlacement.isValidSpot(chicken.spotIndex) then
        return false
      end
    else
      return false -- Placed chicken must have a spot
    end
  end

  -- Check that inventory chickens don't have spots
  for _, chicken in ipairs(playerData.inventory.chickens) do
    if chicken.spotIndex ~= nil then
      return false -- Inventory chicken should not have a spot
    end
  end

  return true
end

return ChickenPlacement
