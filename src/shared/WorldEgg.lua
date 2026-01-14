--[[
	WorldEgg Module
	Manages eggs that exist in the game world (laid by chickens).
	Eggs must be manually collected by players rather than automatically added to inventory.
]]

local WorldEgg = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local EggConfig = require(script.Parent.EggConfig)

-- Constants
local EGG_DESPAWN_TIME = 300 -- Eggs despawn after 5 minutes if not collected
local EGG_HEIGHT_OFFSET = 1.5 -- Height above the chicken spot where eggs spawn

-- Type definitions
export type WorldEggData = {
  id: string,
  eggType: string,
  rarity: string,
  ownerId: number, -- Player who owns the chicken that laid this egg
  chickenId: string, -- The chicken that laid this egg
  spotIndex: number, -- The spot where the chicken is placed
  position: { x: number, y: number, z: number },
  spawnTime: number, -- When the egg was laid
}

export type WorldEggRegistry = {
  eggs: { [string]: WorldEggData },
}

-- Create a new world egg registry
function WorldEgg.createRegistry(): WorldEggRegistry
  return {
    eggs = {},
  }
end

-- Create a new world egg
function WorldEgg.create(
  eggType: string,
  ownerId: number,
  chickenId: string,
  spotIndex: number,
  position: { x: number, y: number, z: number }
): WorldEggData?
  local config = EggConfig.get(eggType)
  if not config then
    return nil
  end

  -- Offset the position to be slightly in front/to the side of the chicken
  local offsetPosition = {
    x = position.x + (math.random() - 0.5) * 2,
    y = position.y + EGG_HEIGHT_OFFSET,
    z = position.z + (math.random() - 0.5) * 2,
  }

  local eggData: WorldEggData = {
    id = PlayerData.generateId(),
    eggType = eggType,
    rarity = config.rarity,
    ownerId = ownerId,
    chickenId = chickenId,
    spotIndex = spotIndex,
    position = offsetPosition,
    spawnTime = os.time(),
  }

  return eggData
end

-- Add an egg to the registry
function WorldEgg.add(registry: WorldEggRegistry, egg: WorldEggData): boolean
  if registry.eggs[egg.id] then
    return false -- Already exists
  end
  registry.eggs[egg.id] = egg
  return true
end

-- Remove an egg from the registry
function WorldEgg.remove(registry: WorldEggRegistry, eggId: string): WorldEggData?
  local egg = registry.eggs[eggId]
  if egg then
    registry.eggs[eggId] = nil
  end
  return egg
end

-- Get an egg by ID
function WorldEgg.get(registry: WorldEggRegistry, eggId: string): WorldEggData?
  return registry.eggs[eggId]
end

-- Get all eggs for a specific owner
function WorldEgg.getByOwner(registry: WorldEggRegistry, ownerId: number): { WorldEggData }
  local result = {}
  for _, egg in pairs(registry.eggs) do
    if egg.ownerId == ownerId then
      table.insert(result, egg)
    end
  end
  return result
end

-- Get all eggs in the registry
function WorldEgg.getAll(registry: WorldEggRegistry): { WorldEggData }
  local result = {}
  for _, egg in pairs(registry.eggs) do
    table.insert(result, egg)
  end
  return result
end

-- Get count of eggs in registry
function WorldEgg.getCount(registry: WorldEggRegistry): number
  local count = 0
  for _ in pairs(registry.eggs) do
    count = count + 1
  end
  return count
end

-- Check if an egg has expired (should be despawned)
function WorldEgg.isExpired(egg: WorldEggData, currentTime: number?): boolean
  local now = currentTime or os.time()
  return (now - egg.spawnTime) >= EGG_DESPAWN_TIME
end

-- Update registry and return list of expired eggs (for despawning)
function WorldEgg.updateAndGetExpired(
  registry: WorldEggRegistry,
  currentTime: number?
): { WorldEggData }
  local now = currentTime or os.time()
  local expired = {}

  for eggId, egg in pairs(registry.eggs) do
    if WorldEgg.isExpired(egg, now) then
      table.insert(expired, egg)
      registry.eggs[eggId] = nil
    end
  end

  return expired
end

-- Validate that an egg can be collected by a player
function WorldEgg.canCollect(
  registry: WorldEggRegistry,
  eggId: string,
  playerId: number
): (boolean, string)
  local egg = registry.eggs[eggId]
  if not egg then
    return false, "Egg not found"
  end

  -- Only the owner can collect their eggs
  if egg.ownerId ~= playerId then
    return false, "You can only collect eggs from your own chickens"
  end

  return true, "Can collect"
end

-- Collect an egg (removes from registry and returns egg data for adding to inventory)
function WorldEgg.collect(
  registry: WorldEggRegistry,
  eggId: string,
  playerId: number
): (boolean, string, PlayerData.EggData?)
  local canCollect, message = WorldEgg.canCollect(registry, eggId, playerId)
  if not canCollect then
    return false, message, nil
  end

  local egg = WorldEgg.remove(registry, eggId)
  if not egg then
    return false, "Failed to remove egg", nil
  end

  -- Create inventory egg data
  local inventoryEgg: PlayerData.EggData = {
    id = egg.id, -- Keep same ID for tracking
    eggType = egg.eggType,
    rarity = egg.rarity,
  }

  return true, "Egg collected!", inventoryEgg
end

-- Get despawn time constant
function WorldEgg.getDespawnTime(): number
  return EGG_DESPAWN_TIME
end

-- Get height offset constant
function WorldEgg.getHeightOffset(): number
  return EGG_HEIGHT_OFFSET
end

-- Convert world egg to network-safe format (for sending to clients)
function WorldEgg.toNetworkData(egg: WorldEggData): { [string]: any }
  return {
    id = egg.id,
    eggType = egg.eggType,
    rarity = egg.rarity,
    ownerId = egg.ownerId,
    chickenId = egg.chickenId,
    spotIndex = egg.spotIndex,
    position = egg.position,
    spawnTime = egg.spawnTime,
  }
end

return WorldEgg
