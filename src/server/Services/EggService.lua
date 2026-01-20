--[[
	EggService
	Knit service that handles all egg-related server logic.
	
	Provides:
	- Egg hatching operations
	- World egg spawning and collection
	- Egg purchase from store
	- Egg selling
	- Event broadcasting for visual updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggHatching = require(Shared:WaitForChild("EggHatching"))
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local WorldEgg = require(Shared:WaitForChild("WorldEgg"))
local Store = require(Shared:WaitForChild("Store"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

-- Services will be retrieved after Knit starts
local PlayerDataService

-- Create the service
local EggService = Knit.CreateService({
  Name = "EggService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    EggHatched = Knit.CreateSignal(), -- Fires to owner when egg hatched
    EggSpawned = Knit.CreateSignal(), -- Fires to owner when world egg spawned
    EggCollected = Knit.CreateSignal(), -- Fires to owner when egg collected
    EggDespawned = Knit.CreateSignal(), -- Fires to owner when egg despawned
    EggPurchased = Knit.CreateSignal(), -- Fires to owner when egg purchased
    EggSold = Knit.CreateSignal(), -- Fires to owner when egg sold
    StockUpdated = Knit.CreateSignal(), -- Fires to owner when store stock updates
  },
})

-- Server-side signals (for other services to listen to)
EggService.EggLaid = GoodSignal.new() -- (userId: number, eggData: WorldEggData)
EggService.EggHatchedSignal = GoodSignal.new() -- (userId: number, hatchResult: HatchResult)
EggService.XPAwarded = GoodSignal.new() -- (userId: number, amount: number, reason: string)

-- Per-player world egg registry
local playerEggRegistries: { [number]: WorldEgg.WorldEggRegistry } = {}

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function EggService:KnitInit()
  print("[EggService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function EggService:KnitStart()
  -- Get reference to PlayerDataService
  PlayerDataService = Knit.GetService("PlayerDataService")

  -- Get reference to MapService for section assignment events
  local MapService = Knit.GetService("MapService")
  local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
  local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

  -- Setup player connections
  Players.PlayerAdded:Connect(function(player)
    self:_initializePlayerState(player.UserId)
  end)

  Players.PlayerRemoving:Connect(function(player)
    self:_cleanupPlayerState(player.UserId)
  end)

  -- Initialize state for existing players (in case of late start)
  for _, player in ipairs(Players:GetPlayers()) do
    self:_initializePlayerState(player.UserId)
  end

  -- Listen for section assignments to spawn starter egg for new players
  MapService.PlayerSectionAssigned:Connect(function(userId: number, sectionIndex: number)
    self:_onPlayerSectionAssigned(userId, sectionIndex, MapGeneration, PlayerSection)
  end)

  print("[EggService] Started")
end

--[[
	Initialize egg state for a player.
	@param userId number - The user ID
]]
function EggService:_initializePlayerState(userId: number)
  if playerEggRegistries[userId] then
    return -- Already initialized
  end

  playerEggRegistries[userId] = WorldEgg.createRegistry()
end

--[[
	Cleanup egg state for a player.
	@param userId number - The user ID
]]
function EggService:_cleanupPlayerState(userId: number)
  playerEggRegistries[userId] = nil
end

--[[
	Internal: Handle player section assignment.
	Spawns a starter egg for new players in their section.
	@param userId number - The user ID
	@param sectionIndex number - The assigned section index
	@param MapGeneration module - Map generation module
	@param PlayerSection module - Player section module
]]
function EggService:_onPlayerSectionAssigned(userId: number, sectionIndex: number, MapGeneration: any, PlayerSection: any)
  -- Get player data to check if they're a new player
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return
  end

  -- Only spawn starter egg for new players (totalPlayTime == 0)
  local isNewPlayer = playerData.totalPlayTime == 0
  if not isNewPlayer then
    return
  end

  -- Get the section center for positioning
  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    warn(string.format("[EggService] Could not get section position for index %d", sectionIndex))
    return
  end

  -- Get a random position within the player's section for the starter egg
  local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
  local position = {
    x = spawnPos.x,
    y = spawnPos.y,
    z = spawnPos.z,
  }

  -- Spawn a starter Common Egg in the world
  local starterEggType = "CommonEgg"
  local starterChickenId = "starter_egg_source" -- Not from a real chicken
  
  local worldEgg = self:SpawnWorldEgg(userId, starterChickenId, starterEggType, position, nil)
  
  if worldEgg then
    local player = Players:GetPlayerByUserId(userId)
    print(string.format("[EggService] Spawned starter %s for new player %s", starterEggType, player and player.Name or tostring(userId)))
  else
    warn(string.format("[EggService] Failed to spawn starter egg for userId %d", userId))
  end
end

--[[
	Get the world egg registry for a player.
	@param userId number - The user ID
	@return WorldEggRegistry?
]]
function EggService:GetWorldEggRegistry(userId: number): WorldEgg.WorldEggRegistry?
  return playerEggRegistries[userId]
end

--[[
	Award XP to a player (internal helper).
	@param player Player - The player
	@param playerData PlayerDataSchema - The player's data
	@param amount number - XP amount to award
	@param reason string - Reason for XP award
]]
function EggService:_awardXP(player: Player, playerData: any, amount: number, reason: string)
  local newLevel = PlayerData.addXP(playerData, amount)

  -- Fire XP gained signal (will be handled by LevelService eventually)
  self.XPAwarded:Fire(player.UserId, amount, reason)

  -- If leveled up, fire level up event
  if newLevel then
    -- Get unlock info for new level
    local maxPredators = LevelConfig.getMaxPredatorsForLevel(newLevel)
    local threatLevel = LevelConfig.getUnlockedThreatLevel(newLevel)
    local unlocks = {
      maxPredators = maxPredators,
      threatLevel = threatLevel,
    }

    -- Fire level up event (will be handled by a future LevelService or client)
    print(string.format("[EggService] Player %s leveled up to %d", player.Name, newLevel))
  end
end

--[[
	CLIENT: Hatch an egg from inventory.
	
	@param player Player - The player hatching the egg
	@param eggId string - The egg's ID
	@return HatchResult
]]
function EggService.Client:HatchEgg(player: Player, eggId: string)
  return EggService:HatchEgg(player.UserId, eggId)
end

--[[
	SERVER: Hatch an egg from inventory.
	
	@param userId number - The user ID
	@param eggId string - The egg's ID
	@return HatchResult
]]
function EggService:HatchEgg(userId: number, eggId: string): EggHatching.HatchResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
      chickenType = nil,
      chickenRarity = nil,
      chickenId = nil,
      isRareHatch = false,
      celebrationTier = 0,
    }
  end

  -- Perform the hatch
  local result = EggHatching.hatch(playerData, eggId)

  if result.success then
    -- Get the player object for events
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client event with result
    if player then
      self.Client.EggHatched:Fire(player, {
        chickenType = result.chickenType,
        chickenRarity = result.chickenRarity,
        chickenId = result.chickenId,
        isRareHatch = result.isRareHatch,
        celebrationTier = result.celebrationTier,
      })
    end

    -- Award XP for hatching
    if result.chickenRarity and player then
      local xpAmount = XPConfig.calculateChickenHatchXP(result.chickenRarity)
      self:_awardXP(player, playerData, xpAmount, "Hatched " .. (result.chickenType or "chicken"))
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.EggHatchedSignal:Fire(userId, result)
  end

  return result
end

--[[
	CLIENT: Collect a world egg.
	
	@param player Player - The player collecting the egg
	@param eggId string - The world egg's ID
	@return CollectResult
]]
function EggService.Client:CollectWorldEgg(player: Player, eggId: string)
  return EggService:CollectWorldEgg(player.UserId, eggId)
end

--[[
	SERVER: Collect a world egg.
	
	@param userId number - The user ID
	@param eggId string - The world egg's ID
	@return CollectResult
]]
function EggService:CollectWorldEgg(
  userId: number,
  eggId: string
): { success: boolean, message: string, egg: PlayerData.EggData? }
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found", egg = nil }
  end

  local registry = playerEggRegistries[userId]
  if not registry then
    return { success = false, message = "Egg registry not found", egg = nil }
  end

  local success, message, inventoryEgg = WorldEgg.collect(registry, eggId, userId)

  if success and inventoryEgg then
    -- Add egg to player inventory
    table.insert(playerData.inventory.eggs, inventoryEgg)

    -- Get the player object for events
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client event
    if player then
      self.Client.EggCollected:Fire(player, {
        eggId = inventoryEgg.id,
        eggType = inventoryEgg.eggType,
        rarity = inventoryEgg.rarity,
      })
    end

    -- Award XP for collecting
    if inventoryEgg.rarity and player then
      local xpAmount = XPConfig.calculateEggCollectedXP(inventoryEgg.rarity)
      self:_awardXP(player, playerData, xpAmount, "Collected " .. inventoryEgg.eggType)
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    return { success = true, message = message, egg = inventoryEgg }
  end

  return { success = false, message = message, egg = nil }
end

--[[
	CLIENT: Buy an egg from the store.
	
	@param player Player - The player buying the egg
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return PurchaseResult
]]
function EggService.Client:BuyEgg(player: Player, eggType: string, quantity: number?)
  return EggService:BuyEgg(player.UserId, eggType, quantity)
end

--[[
	SERVER: Buy an egg from the store.
	
	@param userId number - The user ID
	@param eggType string - The egg type to buy
	@param quantity number? - Optional quantity (default 1)
	@return PurchaseResult
]]
function EggService:BuyEgg(
  userId: number,
  eggType: string,
  quantity: number?
): { success: boolean, message: string, newBalance: number? }
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  -- Use purchaseEggFromInventory to track stock
  local result = Store.purchaseEggFromInventory(playerData, eggType, quantity)

  if result.success then
    -- Get the player object for events
    local player = Players:GetPlayerByUserId(userId)

    -- Fire stock update event
    if player then
      local newStock = Store.getStock("egg", eggType)
      self.Client.StockUpdated:Fire(player, {
        itemType = "egg",
        itemId = eggType,
        newStock = newStock,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)
  end

  return result
end

--[[
	CLIENT: Sell an egg from inventory.
	
	@param player Player - The player selling the egg
	@param eggId string - The egg's ID
	@return SellResult
]]
function EggService.Client:SellEgg(player: Player, eggId: string)
  return EggService:SellEgg(player.UserId, eggId)
end

--[[
	SERVER: Sell an egg from inventory.
	
	@param userId number - The user ID
	@param eggId string - The egg's ID
	@return SellResult
]]
function EggService:SellEgg(userId: number, eggId: string): { success: boolean, message: string }
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellEgg(playerData, eggId)

  if result.success then
    -- Get the player object for events
    local player = Players:GetPlayerByUserId(userId)

    -- Fire client event
    if player then
      self.Client.EggSold:Fire(player, {
        eggId = eggId,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)
  end

  return result
end

--[[
	SERVER: Spawn a world egg for a chicken.
	Called by the game loop when a chicken lays an egg.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@param eggType string - The egg type to spawn
	@param position {x: number, y: number, z: number} - Spawn position
	@return WorldEggData?
]]
function EggService:SpawnWorldEgg(
  userId: number,
  chickenId: string,
  eggType: string,
  position: { x: number, y: number, z: number },
  spotIndex: number?
): WorldEgg.WorldEggData?
  local registry = playerEggRegistries[userId]
  if not registry then
    return nil
  end

  -- Create the world egg
  local worldEgg = WorldEgg.create(eggType, userId, chickenId, spotIndex or 0, position)
  if not worldEgg then
    return nil
  end

  -- Add to registry
  WorldEgg.add(registry, worldEgg)

  -- Get the player object for events
  local player = Players:GetPlayerByUserId(userId)
  if player then
    self.Client.EggSpawned:Fire(player, WorldEgg.toNetworkData(worldEgg))
  end

  -- Fire server signal
  self.EggLaid:Fire(userId, worldEgg)

  return worldEgg
end

--[[
	SERVER: Update world eggs and handle despawns.
	Called by the game loop periodically.
	
	@param userId number - The user ID
	@param currentTime number - Current time in seconds
	@return { WorldEggData } - List of despawned eggs
]]
function EggService:UpdateWorldEggs(userId: number, currentTime: number): { WorldEgg.WorldEggData }
  local registry = playerEggRegistries[userId]
  if not registry then
    return {}
  end

  local expiredEggs = WorldEgg.updateAndGetExpired(registry, currentTime)

  -- Fire despawn events for expired eggs
  if #expiredEggs > 0 then
    local player = Players:GetPlayerByUserId(userId)
    if player then
      for _, expiredEgg in ipairs(expiredEggs) do
        self.Client.EggDespawned:Fire(player, {
          eggId = expiredEgg.id,
        })
      end
    end
  end

  return expiredEggs
end

--[[
	SERVER: Get all world eggs for a player.
	
	@param userId number - The user ID
	@return { WorldEggData }
]]
function EggService:GetWorldEggs(userId: number): { WorldEgg.WorldEggData }
  local registry = playerEggRegistries[userId]
  if not registry then
    return {}
  end

  return WorldEgg.getAll(registry)
end

--[[
	SERVER: Get world egg count for a player.
	
	@param userId number - The user ID
	@return number
]]
function EggService:GetWorldEggCount(userId: number): number
  local registry = playerEggRegistries[userId]
  if not registry then
    return 0
  end

  return WorldEgg.getCount(registry)
end

--[[
	SERVER: Get hatch preview for an egg type.
	
	@param eggType string - The egg type
	@return { HatchOutcome }?
]]
function EggService:GetHatchPreview(eggType: string): { EggConfig.HatchOutcome }?
  return EggHatching.getHatchPreview(eggType)
end

--[[
	SERVER: Get all egg types available.
	
	@return { string }
]]
function EggService:GetAllEggTypes(): { string }
  return EggConfig.getAllTypes()
end

--[[
	SERVER: Get egg config for a specific type.
	
	@param eggType string - The egg type
	@return EggTypeConfig?
]]
function EggService:GetEggConfig(eggType: string): EggConfig.EggTypeConfig?
  return EggConfig.get(eggType)
end

return EggService
