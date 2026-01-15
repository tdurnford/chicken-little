local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local RemoteSetup = require(ServerScriptService:WaitForChild("RemoteSetup"))
local DataPersistence = require(ServerScriptService:WaitForChild("DataPersistence"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Game loop modules
local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
local PredatorAttack = require(Shared:WaitForChild("PredatorAttack"))
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
local CageLocking = require(Shared:WaitForChild("CageLocking"))
local ChickenStealing = require(Shared:WaitForChild("ChickenStealing"))
local RandomChickenSpawn = require(Shared:WaitForChild("RandomChickenSpawn"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))
local CombatHealth = require(Shared:WaitForChild("CombatHealth"))
local ChickenHealth = require(Shared:WaitForChild("ChickenHealth"))
local PredatorAI = require(Shared:WaitForChild("PredatorAI"))
local ChickenAI = require(Shared:WaitForChild("ChickenAI"))

-- Store module for buy/sell operations
local Store = require(Shared:WaitForChild("Store"))

-- Chicken placement module
local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))

-- Egg hatching module
local EggHatching = require(Shared:WaitForChild("EggHatching"))

-- Chicken and Egg modules for egg laying system
local Chicken = require(Shared:WaitForChild("Chicken"))
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

-- Power-up configuration module
local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))

-- Trap configuration module
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))

-- Trap placement module
local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))

-- Weapon configuration module
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

-- Weapon tool module for creating Roblox Tools
local WeaponTool = require(Shared:WaitForChild("WeaponTool"))

-- Area shield module
local AreaShield = require(Shared:WaitForChild("AreaShield"))

-- World egg module for manual egg collection
local WorldEgg = require(Shared:WaitForChild("WorldEgg"))

-- Offline earnings module
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

-- Player section module for coop positioning
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

-- Day/Night cycle module
local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))

-- Admin commands module
local AdminCommands = require(ServerScriptService:WaitForChild("AdminCommands"))

-- Section labels module for player name displays
local SectionLabels = require(ServerScriptService:WaitForChild("SectionLabels"))

-- Player Data Sync Configuration
local DATA_SYNC_THROTTLE_INTERVAL = 0.1 -- Minimum seconds between data updates per player
local lastDataSyncTime: { [number]: number } = {} -- Tracks last sync time per player

-- Game Loop Configuration
local PREDATOR_CLEANUP_INTERVAL = 10 -- Seconds between predator cleanup passes
local lastCleanupTime = 0
local CHICKEN_PLACEMENT_PROTECTION_SECONDS = 5 -- Protection period for newly placed chickens
local PREDATOR_ATTACK_RANGE_STUDS = 15 -- Predators must be within this range of coop to damage chickens

-- New Player Protection Configuration
local NEW_PLAYER_PROTECTION_DURATION = 180 -- 3 minutes of predator immunity for new players
local playerJoinTimes: { [number]: number } = {} -- Tracks when each player joined (userId -> os.time())

-- Bankruptcy Protection Configuration
local BANKRUPTCY_ASSISTANCE_COOLDOWN = 300 -- 5 minute cooldown between assistance grants
local lastBankruptcyAssistanceTime: { [number]: number } = {} -- Tracks last assistance time (userId -> os.time())

-- Store Replenishment Configuration
local lastStoreReplenishCheck = 0
local STORE_REPLENISH_CHECK_INTERVAL = 10 -- Check every 10 seconds if replenish needed

-- Robux Product Configuration
-- Developer Product ID for instant store replenish (set this in Roblox Studio)
local STORE_REPLENISH_PRODUCT_ID = 0 -- TODO: Replace with actual Developer Product ID from Roblox
local STORE_REPLENISH_ROBUX_PRICE = 50 -- Display price in Robux

-- Developer Product IDs for item purchases by rarity tier
-- These IDs should be created in Roblox Studio and set here
local ITEM_ROBUX_PRODUCT_IDS: { [string]: number } = {
  Common = 0, -- R$5 - TODO: Replace with actual Developer Product ID
  Uncommon = 0, -- R$15 - TODO: Replace with actual Developer Product ID
  Rare = 0, -- R$50 - TODO: Replace with actual Developer Product ID
  Epic = 0, -- R$150 - TODO: Replace with actual Developer Product ID
  Legendary = 0, -- R$500 - TODO: Replace with actual Developer Product ID
  Mythic = 0, -- R$1500 - TODO: Replace with actual Developer Product ID
}

-- Developer Product IDs for power-up purchases
-- These IDs should be created in Roblox Studio and set here
local POWERUP_ROBUX_PRODUCT_IDS: { [string]: number } = {
  HatchLuck15 = 0, -- R$25 - TODO: Replace with actual Developer Product ID
  HatchLuck60 = 0, -- R$75 - TODO: Replace with actual Developer Product ID
  HatchLuck240 = 0, -- R$200 - TODO: Replace with actual Developer Product ID
  EggQuality15 = 0, -- R$35 - TODO: Replace with actual Developer Product ID
  EggQuality60 = 0, -- R$100 - TODO: Replace with actual Developer Product ID
  EggQuality240 = 0, -- R$275 - TODO: Replace with actual Developer Product ID
}

-- Track pending replenish purchases
local pendingReplenishPurchases: { [number]: boolean } = {}

-- Track pending item purchases (userId -> {itemType, itemId, rarity})
local pendingItemPurchases: { [number]: { itemType: string, itemId: string, rarity: string } } = {}

-- Track pending power-up purchases (userId -> powerUpId)
local pendingPowerUpPurchases: { [number]: string } = {}

-- Per-player game state tracking
type PlayerGameState = {
  spawnState: PredatorSpawning.SpawnState,
  lockState: CageLocking.LockState,
  stealState: ChickenStealing.StealState,
  batState: BaseballBat.BatState,
  combatState: CombatHealth.CombatState,
  chickenHealthRegistry: ChickenHealth.ChickenHealthRegistry,
  predatorAIState: PredatorAI.PredatorAIState,
  worldEggRegistry: WorldEgg.WorldEggRegistry,
  playerChickenAIState: ChickenAI.ChickenAIState?, -- For free-roaming owned chickens
}
local playerGameStates: { [number]: PlayerGameState } = {}

-- Per-player spawn point tracking for respawning
local playerSpawnPoints: { [number]: { x: number, y: number, z: number } } = {}

-- Global random chicken spawn state (shared event for all players)
local randomChickenSpawnState: RandomChickenSpawn.SpawnEventState

-- Global chicken AI state for tracking random chicken movement
local chickenAIState: ChickenAI.ChickenAIState

-- Global day/night cycle state
local dayNightState: DayNightCycle.DayNightState

-- Track previous time of day for nightfall warnings
local previousTimeOfDay: string = "day"

-- Initialize all RemoteEvents and RemoteFunctions
local remotes = RemoteSetup.initialize()

--[[
  Fires PlayerDataChanged event to a specific player with throttling.
  Throttles frequent updates to prevent network spam.
  @param player Player - The player to send data to
  @param data table? - Optional data to send (defaults to cached data)
  @param forceSync boolean? - Optional flag to bypass throttle
]]
local function syncPlayerData(player: Player, data: { [string]: any }?, forceSync: boolean?)
  local userId = player.UserId
  local currentTime = os.clock()
  local lastSync = lastDataSyncTime[userId] or 0

  -- Throttle check (skip if forceSync is true)
  if not forceSync and (currentTime - lastSync) < DATA_SYNC_THROTTLE_INTERVAL then
    return
  end

  -- Get data from cache if not provided
  local syncData = data or DataPersistence.getData(userId)
  if not syncData then
    return
  end

  -- Fire the event to the client
  local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
  if playerDataChangedEvent then
    playerDataChangedEvent:FireClient(player, syncData)
    lastDataSyncTime[userId] = currentTime
  end
end

-- Setup GetPlayerData RemoteFunction handler
local getPlayerDataFunc = RemoteSetup.getFunction("GetPlayerData")
if getPlayerDataFunc then
  getPlayerDataFunc.OnServerInvoke = function(player: Player)
    local userId = player.UserId
    local playerId = tostring(userId)
    local data = DataPersistence.getData(userId)

    -- Ensure section index is included from mapState
    if data and not data.sectionIndex then
      local sectionIndex = MapGeneration.getPlayerSection(mapState, playerId)
      if sectionIndex then
        data.sectionIndex = sectionIndex
      end
    end

    return data
  end
end

-- Setup GetGlobalChickenCounts RemoteFunction handler
local getGlobalChickenCountsFunc = RemoteSetup.getFunction("GetGlobalChickenCounts")
if getGlobalChickenCountsFunc then
  getGlobalChickenCountsFunc.OnServerInvoke = function(_player: Player)
    return DataPersistence.getGlobalChickenCounts()
  end
end

--[[
  Store Server Handlers
  Handles BuyEgg, SellChicken, SellEgg, and SellPredator RemoteFunctions.
  All operations validate player data and fire PlayerDataChanged on success.
]]

-- BuyEgg RemoteFunction handler
local buyEggFunc = RemoteSetup.getFunction("BuyEgg")
if buyEggFunc then
  buyEggFunc.OnServerInvoke = function(player: Player, eggType: string, quantity: number?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Use purchaseEggFromInventory to track stock
    local result = Store.purchaseEggFromInventory(playerData, eggType, quantity)
    if result.success then
      syncPlayerData(player, playerData, true)
      -- Notify all clients about stock update
      local storeInventoryUpdatedEvent = RemoteSetup.getEvent("StoreInventoryUpdated")
      if storeInventoryUpdatedEvent then
        local newStock = Store.getStock("egg", eggType)
        storeInventoryUpdatedEvent:FireAllClients({
          itemType = "egg",
          itemId = eggType,
          newStock = newStock,
        })
      end
    end
    return result
  end
end

-- BuyChicken RemoteFunction handler
local buyChickenFunc = RemoteSetup.getFunction("BuyChicken")
if buyChickenFunc then
  buyChickenFunc.OnServerInvoke = function(player: Player, chickenType: string, quantity: number?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Use purchaseChickenFromInventory to track stock
    local result = Store.purchaseChickenFromInventory(playerData, chickenType, quantity)
    if result.success then
      syncPlayerData(player, playerData, true)
      -- Notify all clients about stock update
      local storeInventoryUpdatedEvent = RemoteSetup.getEvent("StoreInventoryUpdated")
      if storeInventoryUpdatedEvent then
        local newStock = Store.getStock("chicken", chickenType)
        storeInventoryUpdatedEvent:FireAllClients({
          itemType = "chicken",
          itemId = chickenType,
          newStock = newStock,
        })
      end
    end
    return result
  end
end

-- SellChicken RemoteFunction handler
local sellChickenFunc = RemoteSetup.getFunction("SellChicken")
if sellChickenFunc then
  sellChickenFunc.OnServerInvoke = function(player: Player, chickenId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = Store.sellChicken(playerData, chickenId)
    if result.success then
      -- Fire ChickenSold event to update clients
      local chickenSoldEvent = RemoteSetup.getEvent("ChickenSold")
      if chickenSoldEvent then
        chickenSoldEvent:FireClient(player, { chickenId = chickenId, message = result.message })
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- BuyTrap RemoteFunction handler
local buyTrapFunc = RemoteSetup.getFunction("BuyTrap")
if buyTrapFunc then
  buyTrapFunc.OnServerInvoke = function(player: Player, trapType: string)
    print("[Server] BuyTrap invoked by", player.Name, "for trapType:", trapType)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = Store.buyTrap(playerData, trapType)
    print("[Server] BuyTrap result:", result.success, result.message)
    if result.success then
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- BuyWeapon RemoteFunction handler
local buyWeaponFunc = RemoteSetup.getFunction("BuyWeapon")
if buyWeaponFunc then
  buyWeaponFunc.OnServerInvoke = function(player: Player, weaponType: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = Store.buyWeapon(playerData, weaponType)
    if result.success then
      -- Give the weapon Tool to player's Backpack
      WeaponTool.giveToPlayer(player, weaponType)
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- ActivateShield RemoteFunction handler
local activateShieldFunc = RemoteSetup.getFunction("ActivateShield")
if activateShieldFunc then
  activateShieldFunc.OnServerInvoke = function(player: Player)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Initialize shield state if not present
    if not playerData.shieldState then
      playerData.shieldState = AreaShield.createDefaultState()
    end

    local currentTime = os.time()
    local result = AreaShield.activate(playerData.shieldState, currentTime)

    if result.success then
      -- Sync player data
      syncPlayerData(player, playerData, true)

      -- Fire ShieldActivated event to all clients so they can see the shield effect
      local shieldActivatedEvent = RemoteSetup.getEvent("ShieldActivated")
      if shieldActivatedEvent then
        shieldActivatedEvent:FireAllClients(userId, playerData.sectionIndex or 1, {
          isActive = true,
          expiresAt = playerData.shieldState.expiresAt,
          durationTotal = AreaShield.getConstants().shieldDuration,
        })
      end
    end

    return result
  end
end

-- SellEgg RemoteFunction handler
local sellEggFunc = RemoteSetup.getFunction("SellEgg")
if sellEggFunc then
  sellEggFunc.OnServerInvoke = function(player: Player, eggId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = Store.sellEgg(playerData, eggId)
    if result.success then
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- SellPredator RemoteFunction handler
local sellPredatorFunc = RemoteSetup.getFunction("SellPredator")
if sellPredatorFunc then
  sellPredatorFunc.OnServerInvoke = function(player: Player, trapId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = Store.sellPredator(playerData, trapId)
    if result.success then
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- Create game state for a player
local function createPlayerGameState(): PlayerGameState
  return {
    spawnState = PredatorSpawning.createSpawnState(),
    lockState = CageLocking.createLockState(),
    stealState = ChickenStealing.createStealState(),
    batState = BaseballBat.createBatState(),
    combatState = CombatHealth.createState(),
    chickenHealthRegistry = ChickenHealth.createRegistry(),
    predatorAIState = PredatorAI.createState(),
    worldEggRegistry = WorldEgg.createRegistry(),
    playerChickenAIState = nil, -- Initialized later when section is assigned
  }
end

-- Get or create player game state
local function getPlayerGameState(userId: number): PlayerGameState
  if not playerGameStates[userId] then
    playerGameStates[userId] = createPlayerGameState()
  end
  return playerGameStates[userId]
end

--[[
  Chicken Placement Server Handlers
  Handles PlaceChicken and PickupChicken RemoteFunctions.
  All operations validate player data and fire events to update clients.
]]

-- PlaceChicken RemoteFunction handler
-- Now uses free-roaming placement instead of spot-based
local placeChickenFunc = RemoteSetup.getFunction("PlaceChicken")
if placeChickenFunc then
  placeChickenFunc.OnServerInvoke = function(player: Player, chickenId: string, _spotIndex: number?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Check chicken limit before placing
    if ChickenPlacement.isAtChickenLimit(playerData) then
      local limitInfo = ChickenPlacement.getChickenLimitInfo(playerData)
      return {
        success = false,
        message = "Area full! Maximum " .. limitInfo.max .. " chickens per area.",
        atLimit = true,
      }
    end

    -- Use free-roaming placement (spotIndex is now optional/ignored)
    local result = ChickenPlacement.placeChickenFreeRoaming(playerData, chickenId)
    if result.success then
      local gameState = getPlayerGameState(userId)

      -- Register chicken with health system
      if result.chicken and result.chicken.chickenType then
        ChickenHealth.register(
          gameState.chickenHealthRegistry,
          chickenId,
          result.chicken.chickenType
        )
      end

      -- Register chicken with AI for free-roaming behavior
      if gameState.playerChickenAIState and result.chicken then
        local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
        if sectionCenter then
          local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
          local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
          ChickenAI.registerChicken(
            gameState.playerChickenAIState,
            chickenId,
            result.chicken.chickenType,
            spawnPosV3,
            os.clock()
          )
        end
      end

      -- Fire ChickenPlaced event to all clients so they can update visuals
      local chickenPlacedEvent = RemoteSetup.getEvent("ChickenPlaced")
      if chickenPlacedEvent then
        -- Get initial position from AI
        local initialPosition = nil
        if gameState.playerChickenAIState then
          local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, chickenId)
          if aiPos then
            initialPosition = aiPos.currentPosition
          end
        end

        chickenPlacedEvent:FireAllClients({
          playerId = userId,
          chicken = result.chicken,
          spotIndex = nil, -- No longer using spots
          position = initialPosition,
        })
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- PickupChicken RemoteFunction handler
local pickupChickenFunc = RemoteSetup.getFunction("PickupChicken")
if pickupChickenFunc then
  pickupChickenFunc.OnServerInvoke = function(player: Player, chickenId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Get the spot index before pickup for the event (legacy)
    local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
    local spotIndex = chicken and chicken.spotIndex or nil

    local result = ChickenPlacement.pickupChicken(playerData, chickenId)
    if result.success then
      local gameState = getPlayerGameState(userId)

      -- Unregister chicken from health system
      ChickenHealth.unregister(gameState.chickenHealthRegistry, chickenId)

      -- Unregister chicken from AI (free-roaming)
      if gameState.playerChickenAIState then
        ChickenAI.unregisterChicken(gameState.playerChickenAIState, chickenId)
      end

      -- Fire ChickenPickedUp event to all clients so they can update visuals
      local chickenPickedUpEvent = RemoteSetup.getEvent("ChickenPickedUp")
      if chickenPickedUpEvent then
        chickenPickedUpEvent:FireAllClients({
          playerId = userId,
          chickenId = chickenId,
          spotIndex = spotIndex,
        })
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

-- MoveChicken RemoteFunction handler
-- Moves a chicken from one coop spot to another without going through inventory
local moveChickenFunc = RemoteSetup.getFunction("MoveChicken")
if moveChickenFunc then
  moveChickenFunc.OnServerInvoke = function(player: Player, chickenId: string, newSpotIndex: number)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Get the old spot index before the move for the event
    local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
    local oldSpotIndex = chicken and chicken.spotIndex or nil

    local result = ChickenPlacement.moveChicken(playerData, chickenId, newSpotIndex)
    if result.success then
      -- Fire ChickenMoved event to all clients so they can update visuals
      local chickenMovedEvent = RemoteSetup.getEvent("ChickenMoved")
      if chickenMovedEvent then
        chickenMovedEvent:FireAllClients({
          playerId = userId,
          chickenId = chickenId,
          oldSpotIndex = oldSpotIndex,
          newSpotIndex = newSpotIndex,
          chicken = result.chicken,
        })
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

--[[
  Trap Placement Server Handlers
  Handles PlaceTrap RemoteFunction.
  Places a trap from inventory to a trap spot in the player's coop.
]]

-- PlaceTrap RemoteFunction handler
local placeTrapFunc = RemoteSetup.getFunction("PlaceTrap")
if placeTrapFunc then
  placeTrapFunc.OnServerInvoke = function(player: Player, trapId: string, spotIndex: number)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = TrapPlacement.placeTrapFromInventory(playerData, trapId, spotIndex)
    if result.success then
      -- Calculate trap position for visual feedback
      local sectionIndex = playerData.sectionIndex
      local trapPosition = nil
      if sectionIndex then
        local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
        if sectionCenter then
          local spotPos = PlayerSection.getTrapSpotPosition(spotIndex, sectionCenter)
          if spotPos then
            trapPosition = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
          end
        end
      end

      -- Fire TrapPlaced event to all clients so they can update visuals
      local trapPlacedEvent = RemoteSetup.getEvent("TrapPlaced")
      if trapPlacedEvent and result.trap then
        trapPlacedEvent:FireAllClients(
          result.trap.id,
          result.trap.trapType,
          trapPosition or Vector3.new(0, 0, 0),
          result.trap.spotIndex
        )
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

--[[
  Egg Hatching Server Handlers
  Handles HatchEgg RemoteFunction.
  Validates egg ownership, performs hatch, adds chicken to inventory or area.
]]

-- HatchEgg RemoteFunction handler
-- Parameters: eggId, spotIndex (optional, legacy - ignored for free-roaming)
-- If any placement hint is provided, chicken is placed as free-roaming
local hatchEggFunc = RemoteSetup.getFunction("HatchEgg")
if hatchEggFunc then
  hatchEggFunc.OnServerInvoke = function(player: Player, eggId: string, placementHint: number?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- If placement hint provided, check chicken limit before hatching
    if placementHint and ChickenPlacement.isAtChickenLimit(playerData) then
      local limitInfo = ChickenPlacement.getChickenLimitInfo(playerData)
      return {
        success = false,
        message = "Area full! Maximum " .. limitInfo.max .. " chickens per area.",
        atLimit = true,
      }
    end

    local result = EggHatching.hatch(playerData, eggId)
    if result.success then
      -- If placement hint provided, move the chicken from inventory to placed (free-roaming)
      if placementHint and result.chickenId then
        -- Find the chicken in inventory
        local chickenIndex = nil
        local chickenData = nil
        for i, chicken in ipairs(playerData.inventory.chickens) do
          if chicken.id == result.chickenId then
            chickenIndex = i
            chickenData = chicken
            break
          end
        end

        if chickenIndex and chickenData then
          -- Remove from inventory and add to placed chickens (free-roaming)
          local chicken = table.remove(playerData.inventory.chickens, chickenIndex)
          chicken.spotIndex = nil -- Free-roaming: no specific spot
          table.insert(playerData.placedChickens, chicken)

          local gameState = getPlayerGameState(userId)

          -- Register chicken with health system
          ChickenHealth.register(
            gameState.chickenHealthRegistry,
            result.chickenId,
            chicken.chickenType
          )

          -- Register chicken with AI for free-roaming behavior
          if gameState.playerChickenAIState then
            local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
            if sectionCenter then
              local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
              local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
              ChickenAI.registerChicken(
                gameState.playerChickenAIState,
                result.chickenId,
                chicken.chickenType,
                spawnPosV3,
                os.clock()
              )
            end
          end

          -- Fire ChickenPlaced event
          local chickenPlacedEvent = RemoteSetup.getEvent("ChickenPlaced")
          if chickenPlacedEvent then
            -- Get initial position from AI
            local initialPosition = nil
            if gameState.playerChickenAIState then
              local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, result.chickenId)
              if aiPos then
                initialPosition = aiPos.currentPosition
              end
            end

            chickenPlacedEvent:FireClient(player, {
              chicken = chicken,
              spotIndex = nil, -- Free-roaming
              position = initialPosition,
            })
          end
        end
      end

      -- Fire EggHatched event to player with result
      local eggHatchedEvent = RemoteSetup.getEvent("EggHatched")
      if eggHatchedEvent then
        eggHatchedEvent:FireClient(player, {
          chickenType = result.chickenType,
          chickenRarity = result.chickenRarity,
          chickenId = result.chickenId,
          isRareHatch = result.isRareHatch,
          celebrationTier = result.celebrationTier,
          message = result.message,
        })
      end
      syncPlayerData(player, playerData, true)
    end
    return result
  end
end

--[[
  World Egg Collection Handler
  Handles CollectWorldEgg RemoteFunction.
  Validates egg ownership and adds to player inventory.
]]

-- CollectWorldEgg RemoteFunction handler
local collectWorldEggFunc = RemoteSetup.getFunction("CollectWorldEgg")
if collectWorldEggFunc then
  collectWorldEggFunc.OnServerInvoke = function(player: Player, eggId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local gameState = getPlayerGameState(userId)
    local success, message, inventoryEgg =
      WorldEgg.collect(gameState.worldEggRegistry, eggId, userId)

    if success and inventoryEgg then
      -- Add egg to player inventory
      table.insert(playerData.inventory.eggs, inventoryEgg)

      -- Fire EggCollected event to player
      local eggCollectedEvent = RemoteSetup.getEvent("EggCollected")
      if eggCollectedEvent then
        eggCollectedEvent:FireClient(player, {
          eggId = inventoryEgg.id,
          eggType = inventoryEgg.eggType,
          rarity = inventoryEgg.rarity,
        })
      end

      syncPlayerData(player, playerData, true)
      return { success = true, message = message, egg = inventoryEgg }
    end

    return { success = false, message = message }
  end
end

--[[
  Money Collection Server Handlers
  Handles CollectMoney RemoteFunction.
  Validates chicken ownership and collects accumulated money.
]]

-- CollectMoney RemoteFunction handler
-- Parameters: chickenId (optional) - if nil, collects from all chickens
local collectMoneyFunc = RemoteSetup.getFunction("CollectMoney")
if collectMoneyFunc then
  collectMoneyFunc.OnServerInvoke = function(player: Player, chickenId: string?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result
    if chickenId then
      -- Collect from a specific chicken
      result = MoneyCollection.collect(playerData, chickenId)
    else
      -- Collect from all chickens
      result = MoneyCollection.collectAll(playerData)
    end

    if result.success then
      local amountCollected = result.amountCollected or result.totalCollected or 0
      if amountCollected > 0 then
        -- Fire MoneyCollected event to update client visuals
        local moneyCollectedEvent = RemoteSetup.getEvent("MoneyCollected")
        if moneyCollectedEvent then
          -- Pass amount as number, position is optional (nil for collect all)
          moneyCollectedEvent:FireClient(player, amountCollected, nil)
        end
        syncPlayerData(player, playerData, true)
      end
    end
    return result
  end
end

--[[
  Combat Server Handlers
  Handles SwingBat RemoteFunction for weapon attacks.
  Uses Roblox's native Tool system - weapons are equipped via Backpack/Hotbar.
  Validates swing conditions and applies damage to predators/knockback to players.
]]

-- SwingBat RemoteFunction handler
-- Parameters: targetType ("predator" | "player" | nil), targetId (optional)
local swingBatFunc = RemoteSetup.getFunction("SwingBat")
if swingBatFunc then
  swingBatFunc.OnServerInvoke = function(
    player: Player,
    action: string,
    targetType: string?,
    targetId: string?
  )
    local userId = player.UserId
    local gameState = getPlayerGameState(userId)
    local batState = gameState.batState
    local currentTime = os.clock()

    -- Only handle swing action - equip/unequip is now handled by Roblox Tool system
    if action == "swing" then
      -- Check if player has a weapon Tool equipped
      local equippedTool = WeaponTool.getEquippedWeapon(player)
      if not equippedTool then
        return { success = false, message = "No weapon equipped" }
      end

      -- Get weapon type from the equipped tool
      local weaponType = WeaponTool.getWeaponType(equippedTool)
      if not weaponType then
        return { success = false, message = "Invalid weapon" }
      end

      -- Sync batState.isEquipped with Tool state for BaseballBat module compatibility
      batState.isEquipped = true

      -- Handle predator swing
      if targetType == "predator" and targetId then
        local playerData = DataPersistence.getData(userId)
        if not playerData then
          return { success = false, message = "Player data not found" }
        end

        local result =
          BaseballBat.hitPredator(batState, gameState.spawnState, targetId, currentTime)
        if result.success then
          -- Broadcast health update to ALL clients so all players see health bar changes
          local predatorHealthUpdatedEvent = RemoteSetup.getEvent("PredatorHealthUpdated")
          if predatorHealthUpdatedEvent then
            local predator = PredatorSpawning.findPredator(gameState.spawnState, targetId)
            local maxHealth = predator and PredatorConfig.getBatHitsRequired(predator.predatorType)
              or 1
            predatorHealthUpdatedEvent:FireAllClients(
              targetId,
              result.remainingHealth,
              maxHealth,
              result.damage
            )
          end

          if result.defeated then
            -- Award money for defeating predator
            playerData.money = (playerData.money or 0) + result.rewardMoney

            -- Unregister from predator AI
            PredatorAI.unregisterPredator(gameState.predatorAIState, targetId)

            -- Fire PredatorDefeated event to ALL clients
            local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
            if predatorDefeatedEvent then
              predatorDefeatedEvent:FireAllClients(targetId, true)
            end

            syncPlayerData(player, playerData, true)
          end
        end
        return result

        -- Handle player swing (knockback)
      elseif targetType == "player" and targetId then
        local result = BaseballBat.hitPlayer(batState, targetId, currentTime)

        if result.success then
          -- Find target player and incapacitate them
          local targetUserId = tonumber(targetId)
          local targetPlayer: Player? = nil
          if targetUserId then
            for _, p in ipairs(Players:GetPlayers()) do
              if p.UserId == targetUserId then
                targetPlayer = p
                break
              end
            end
          end

          if targetPlayer then
            -- Get target's combat state and incapacitate them
            local targetGameState = getPlayerGameState(targetUserId :: number)
            local incapResult =
              CombatHealth.incapacitate(targetGameState.combatState, tostring(userId), currentTime)

            if incapResult.success then
              -- Fire incapacitation event to target player
              local incapEvent = RemoteSetup.getEvent("PlayerIncapacitated")
              if incapEvent then
                incapEvent:FireClient(targetPlayer, {
                  duration = incapResult.duration,
                  attackerId = tostring(userId),
                  attackerName = player.Name,
                })
              end
            end
          end
        end

        return result

        -- Handle miss (swing at nothing)
      else
        local result = BaseballBat.swingMiss(batState, currentTime)
        return result
      end
    end

    return { success = false, message = "Invalid action" }
  end
end

-- Setup ClaimRandomChicken RemoteFunction handler
local claimRandomChickenFunc = RemoteSetup.getFunction("ClaimRandomChicken")
if claimRandomChickenFunc then
  claimRandomChickenFunc.OnServerInvoke = function(player: Player)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    -- Get player position
    local character = player.Character
    if not character then
      return { success = false, message = "No character" }
    end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then
      return { success = false, message = "No HumanoidRootPart" }
    end
    local position = rootPart.Position
    local playerPosition: RandomChickenSpawn.Vector3 = {
      x = position.X,
      y = position.Y,
      z = position.Z,
    }

    -- Attempt to claim the chicken
    local currentTime = os.time()
    local playerId = tostring(userId)
    local result = RandomChickenSpawn.claimChicken(
      randomChickenSpawnState,
      playerId,
      playerPosition,
      currentTime
    )

    if result.success and result.chicken then
      -- Remove chicken from AI tracking
      ChickenAI.unregisterChicken(chickenAIState, result.chicken.id)

      -- Add chicken to player's inventory
      local chickenData: PlayerData.ChickenData = {
        id = PlayerData.generateId(),
        chickenType = result.chicken.chickenType,
        rarity = result.chicken.rarity,
        accumulatedMoney = 0,
        lastEggTime = currentTime,
        spotIndex = nil, -- In inventory, not placed
      }
      table.insert(playerData.inventory.chickens, chickenData)

      -- Fire RandomChickenClaimed event to all clients
      local randomChickenClaimedEvent = RemoteSetup.getEvent("RandomChickenClaimed")
      if randomChickenClaimedEvent then
        randomChickenClaimedEvent:FireAllClients(result.chicken.id, player)
      end

      -- Sync player data
      syncPlayerData(player, playerData, true)

      print(
        "[Main.server] Player",
        player.Name,
        "claimed random chicken:",
        result.chicken.chickenType,
        result.chicken.rarity
      )

      return {
        success = true,
        chicken = result.chicken,
        message = "Chicken claimed!",
        playerData = playerData, -- Include updated player data for immediate client sync
      }
    else
      return {
        success = false,
        message = result.reason or "Failed to claim chicken",
      }
    end
  end
end

-- Setup ReplenishStoreWithRobux RemoteFunction handler
-- Prompts the player to purchase the Robux product for instant store replenish
local replenishStoreWithRobuxFunc = RemoteSetup.getFunction("ReplenishStoreWithRobux")
if replenishStoreWithRobuxFunc then
  replenishStoreWithRobuxFunc.OnServerInvoke = function(player: Player)
    -- Check if product ID is configured
    if STORE_REPLENISH_PRODUCT_ID == 0 then
      -- For testing: perform free replenish when product ID not set
      local newInventory = Store.forceReplenish()
      print("[Main.server] Free store replenish (product ID not configured) for", player.Name)

      -- Notify all connected players about replenish
      local storeReplenishedEvent = RemoteSetup.getEvent("StoreReplenished")
      if storeReplenishedEvent then
        for _, p in ipairs(Players:GetPlayers()) do
          storeReplenishedEvent:FireClient(p, newInventory)
        end
      end

      return {
        success = true,
        message = "Store replenished! (Free - product not configured)",
        productId = 0,
        robuxPrice = 0,
      }
    end

    -- Prompt player to purchase the developer product
    local success, errorMessage = pcall(function()
      MarketplaceService:PromptProductPurchase(player, STORE_REPLENISH_PRODUCT_ID)
    end)

    if success then
      pendingReplenishPurchases[player.UserId] = true
      return {
        success = true,
        message = "Purchase prompt opened",
        productId = STORE_REPLENISH_PRODUCT_ID,
        robuxPrice = STORE_REPLENISH_ROBUX_PRICE,
      }
    else
      return {
        success = false,
        message = "Failed to open purchase prompt: " .. tostring(errorMessage),
      }
    end
  end
end

-- Setup BuyItemWithRobux RemoteFunction handler
-- Prompts the player to purchase an item with Robux
local buyItemWithRobuxFunc = RemoteSetup.getFunction("BuyItemWithRobux")
if buyItemWithRobuxFunc then
  buyItemWithRobuxFunc.OnServerInvoke = function(player: Player, itemType: string, itemId: string)
    -- Validate input
    if
      itemType ~= "egg"
      and itemType ~= "chicken"
      and itemType ~= "trap"
      and itemType ~= "weapon"
    then
      return {
        success = false,
        message = "Invalid item type",
      }
    end

    -- Handle weapon purchases
    if itemType == "weapon" then
      local weaponConfig = WeaponConfig.get(itemId)
      if not weaponConfig then
        return {
          success = false,
          message = "Weapon type not found",
        }
      end

      local robuxPrice = weaponConfig.robuxPrice

      -- For testing: deliver item for free when product ID not set
      -- In production, this would prompt for Robux purchase
      local playerData = DataPersistence.get(player)
      if not playerData then
        return {
          success = false,
          message = "Player data not found",
        }
      end

      local result = Store.buyWeaponWithRobux(playerData, itemId)
      if result.success then
        -- Give the weapon Tool to player's Backpack
        WeaponTool.giveToPlayer(player, itemId)
        DataPersistence.save(player)
        local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
        if playerDataChangedEvent then
          playerDataChangedEvent:FireClient(player, playerData)
        end
        print(
          "[Main.server] Free Robux weapon purchase (product ID not configured) for",
          player.Name,
          itemId
        )
      end

      return result
    end

    -- Handle trap purchases differently (traps use tier-based pricing)
    if itemType == "trap" then
      local trapConfig = TrapConfig.get(itemId)
      if not trapConfig then
        return {
          success = false,
          message = "Trap type not found",
        }
      end

      local robuxPrice = Store.getTrapRobuxPrice(trapConfig.tier)

      -- For testing: deliver item for free when product ID not set
      -- In production, this would prompt for Robux purchase
      local playerData = DataPersistence.get(player)
      if not playerData then
        return {
          success = false,
          message = "Player data not found",
        }
      end

      local result = Store.buyTrapWithRobux(playerData, itemId)
      if result.success then
        DataPersistence.save(player)
        local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
        if playerDataChangedEvent then
          playerDataChangedEvent:FireClient(player, playerData)
        end
        print(
          "[Main.server] Free Robux trap purchase (product ID not configured) for",
          player.Name,
          itemId
        )
      end

      return result
    end

    -- Get item rarity from store inventory
    local storeInventory = Store.getStoreInventory()
    local item = nil
    if itemType == "egg" then
      item = storeInventory.eggs[itemId]
    else
      item = storeInventory.chickens[itemId]
    end

    if not item then
      return {
        success = false,
        message = "Item not found in store",
      }
    end

    local rarity = item.rarity
    local productId = ITEM_ROBUX_PRODUCT_IDS[rarity]

    -- Check if product ID is configured for testing
    if productId == 0 then
      -- For testing: deliver item for free when product ID not set
      local playerData = DataPersistence.get(player)
      if not playerData then
        return {
          success = false,
          message = "Player data not found",
        }
      end

      local result
      if itemType == "egg" then
        result = Store.purchaseEggWithRobux(playerData, itemId)
      else
        result = Store.purchaseChickenWithRobux(playerData, itemId)
      end

      if result.success then
        -- Save player data
        DataPersistence.save(player)
        -- Notify client of data change
        local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
        if playerDataChangedEvent then
          playerDataChangedEvent:FireClient(player, playerData)
        end
        print(
          "[Main.server] Free Robux item purchase (product ID not configured) for",
          player.Name,
          itemType,
          itemId
        )
      end

      return result
    end

    -- Store pending purchase info
    pendingItemPurchases[player.UserId] = {
      itemType = itemType,
      itemId = itemId,
      rarity = rarity,
    }

    -- Prompt player to purchase the developer product
    local success, errorMessage = pcall(function()
      MarketplaceService:PromptProductPurchase(player, productId)
    end)

    if success then
      return {
        success = true,
        message = "Purchase prompt opened",
        productId = productId,
        robuxPrice = item.robuxPrice,
      }
    else
      pendingItemPurchases[player.UserId] = nil
      return {
        success = false,
        message = "Failed to open purchase prompt: " .. tostring(errorMessage),
      }
    end
  end
end

-- Setup BuyPowerUp RemoteFunction handler
-- Handles player requests to purchase power-ups with Robux
local buyPowerUpFunc = RemoteSetup.getFunction("BuyPowerUp")
if buyPowerUpFunc then
  buyPowerUpFunc.OnServerInvoke = function(player: Player, powerUpId: string)
    -- Validate power-up ID
    local powerUpConfigData = PowerUpConfig.get(powerUpId)
    if not powerUpConfigData then
      return {
        success = false,
        message = "Invalid power-up: " .. tostring(powerUpId),
      }
    end

    -- Get product ID for this power-up
    local productId = POWERUP_ROBUX_PRODUCT_IDS[powerUpId]
    if not productId or productId == 0 then
      -- Product ID not configured - give power-up for free (development mode)
      local playerData = DataPersistence.get(player)
      if not playerData then
        return {
          success = false,
          message = "Player data not found",
        }
      end

      -- Add power-up to player data
      PlayerData.addPowerUp(playerData, powerUpId, powerUpConfigData.durationSeconds)

      -- Save player data
      DataPersistence.save(player)

      -- Notify client of data change
      local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
      if playerDataChangedEvent then
        playerDataChangedEvent:FireClient(player, playerData)
      end

      -- Fire power-up activated event
      local powerUpActivatedEvent = RemoteSetup.getEvent("PowerUpActivated")
      if powerUpActivatedEvent then
        powerUpActivatedEvent:FireClient(player, {
          powerUpId = powerUpId,
          expiresAt = os.time() + powerUpConfigData.durationSeconds,
        })
      end

      print("[Main.server] Power-up activated (free/dev mode):", powerUpId, "for", player.Name)

      return {
        success = true,
        message = "Power-up activated! " .. powerUpConfigData.displayName,
        powerUpId = powerUpId,
      }
    end

    -- Store pending purchase info
    pendingPowerUpPurchases[player.UserId] = powerUpId

    -- Prompt player to purchase the developer product
    local success, errorMessage = pcall(function()
      MarketplaceService:PromptProductPurchase(player, productId)
    end)

    if success then
      return {
        success = true,
        message = "Purchase prompt opened",
        productId = productId,
        robuxPrice = powerUpConfigData.robuxPrice,
      }
    else
      pendingPowerUpPurchases[player.UserId] = nil
      return {
        success = false,
        message = "Failed to open purchase prompt: " .. tostring(errorMessage),
      }
    end
  end
end

--[[
  Admin Command Handlers
  Handles admin-only operations like kick, ban, and data reset.
  All actions are logged for accountability.
]]

-- AdminCommand RemoteFunction handler
local adminCommandFunc = RemoteSetup.getFunction("AdminCommand")
if adminCommandFunc then
  adminCommandFunc.OnServerInvoke = function(
    player: Player,
    command: string,
    targetName: string?,
    arg1: any?
  )
    -- Dispatch to appropriate admin command
    if command == "kick" then
      return AdminCommands.kick(player, targetName or "", arg1)
    elseif command == "ban" then
      return AdminCommands.ban(player, targetName or "", arg1)
    elseif command == "resetdata" then
      return AdminCommands.resetData(player, targetName or "")
    elseif command == "givemoney" then
      local amount = tonumber(arg1) or 0
      return AdminCommands.giveMoney(player, targetName or "", amount)
    elseif command == "warn" then
      return AdminCommands.warn(player, targetName or "", tostring(arg1 or "Warning"))
    elseif command == "unban" then
      local userId = tonumber(targetName) or 0
      return AdminCommands.unban(player, userId)
    else
      return { success = false, message = "Unknown command: " .. tostring(command) }
    end
  end
end

-- GetAdminStatus RemoteFunction handler
local getAdminStatusFunc = RemoteSetup.getFunction("GetAdminStatus")
if getAdminStatusFunc then
  getAdminStatusFunc.OnServerInvoke = function(player: Player)
    return AdminCommands.getAdminStatus(player)
  end
end

-- GetAdminLog RemoteFunction handler
local getAdminLogFunc = RemoteSetup.getFunction("GetAdminLog")
if getAdminLogFunc then
  getAdminLogFunc.OnServerInvoke = function(player: Player, count: number?)
    -- Only admins can view the log
    local status = AdminCommands.getAdminStatus(player)
    if not status.isAdmin then
      return { success = false, message = "Not authorized", entries = {} }
    end
    return { success = true, entries = AdminCommands.getLog(count) }
  end
end

-- GetOnlinePlayers RemoteFunction handler
local getOnlinePlayersFunc = RemoteSetup.getFunction("GetOnlinePlayers")
if getOnlinePlayersFunc then
  getOnlinePlayersFunc.OnServerInvoke = function(player: Player)
    -- Only admins can view online players list
    local status = AdminCommands.getAdminStatus(player)
    if not status.isAdmin then
      return { success = false, message = "Not authorized", players = {} }
    end
    return { success = true, players = AdminCommands.getOnlinePlayers() }
  end
end
MarketplaceService.ProcessReceipt = function(receiptInfo: { [string]: any })
  local userId = receiptInfo.PlayerId
  local productId = receiptInfo.ProductId
  local player = Players:GetPlayerByUserId(userId)

  print("[Main.server] ProcessReceipt:", productId, "for user", userId)

  -- Handle store replenish product
  if productId == STORE_REPLENISH_PRODUCT_ID then
    -- Perform store replenish
    local newInventory = Store.forceReplenish()
    print("[Main.server] Store replenished via Robux purchase for user", userId)

    -- Clear pending purchase flag
    pendingReplenishPurchases[userId] = nil

    -- Notify all connected players about replenish
    local storeReplenishedEvent = RemoteSetup.getEvent("StoreReplenished")
    if storeReplenishedEvent then
      for _, p in ipairs(Players:GetPlayers()) do
        storeReplenishedEvent:FireClient(p, newInventory)
      end
    end

    return Enum.ProductPurchaseDecision.PurchaseGranted
  end

  -- Handle item purchase products (check each rarity tier)
  for rarity, rarityProductId in pairs(ITEM_ROBUX_PRODUCT_IDS) do
    if productId == rarityProductId and rarityProductId ~= 0 then
      -- Check if we have a pending purchase for this user
      local pendingPurchase = pendingItemPurchases[userId]
      if pendingPurchase and pendingPurchase.rarity == rarity then
        -- Deliver the item
        if player then
          local playerData = DataPersistence.get(player)
          if playerData then
            local result
            if pendingPurchase.itemType == "egg" then
              result = Store.purchaseEggWithRobux(playerData, pendingPurchase.itemId)
            else
              result = Store.purchaseChickenWithRobux(playerData, pendingPurchase.itemId)
            end

            if result.success then
              -- Save player data
              DataPersistence.save(player)
              -- Notify client of data change
              local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
              if playerDataChangedEvent then
                playerDataChangedEvent:FireClient(player, playerData)
              end
              print(
                "[Main.server] Item purchased with Robux:",
                pendingPurchase.itemType,
                pendingPurchase.itemId,
                "for user",
                userId
              )
            end
          end
        end

        -- Clear pending purchase
        pendingItemPurchases[userId] = nil
      end

      return Enum.ProductPurchaseDecision.PurchaseGranted
    end
  end

  -- Handle power-up purchase products
  for powerUpId, powerUpProductId in pairs(POWERUP_ROBUX_PRODUCT_IDS) do
    if productId == powerUpProductId and powerUpProductId ~= 0 then
      -- Check if we have a pending purchase for this user
      local pendingPowerUpId = pendingPowerUpPurchases[userId]
      if pendingPowerUpId == powerUpId then
        -- Deliver the power-up
        if player then
          local playerData = DataPersistence.get(player)
          if playerData then
            local powerUpConfigData = PowerUpConfig.get(powerUpId)
            if powerUpConfigData then
              -- Add power-up to player data
              PlayerData.addPowerUp(playerData, powerUpId, powerUpConfigData.durationSeconds)

              -- Save player data
              DataPersistence.save(player)

              -- Notify client of data change
              local playerDataChangedEvent = RemoteSetup.getEvent("PlayerDataChanged")
              if playerDataChangedEvent then
                playerDataChangedEvent:FireClient(player, playerData)
              end

              -- Fire power-up activated event
              local powerUpActivatedEvent = RemoteSetup.getEvent("PowerUpActivated")
              if powerUpActivatedEvent then
                powerUpActivatedEvent:FireClient(player, {
                  powerUpId = powerUpId,
                  expiresAt = os.time() + powerUpConfigData.durationSeconds,
                })
              end

              print("[Main.server] Power-up purchased with Robux:", powerUpId, "for user", userId)
            end
          end
        end

        -- Clear pending purchase
        pendingPowerUpPurchases[userId] = nil
      end

      return Enum.ProductPurchaseDecision.PurchaseGranted
    end
  end

  -- Unknown product - grant anyway to avoid issues
  return Enum.ProductPurchaseDecision.PurchaseGranted
end
local dataPersistenceStarted = DataPersistence.start()
if dataPersistenceStarted then
  print("[Main.server] DataPersistence initialized successfully")
else
  warn("[Main.server] DataPersistence failed to initialize DataStore - running in offline mode")
end

-- Initialize Admin Commands with DataPersistence reference
AdminCommands.init(DataPersistence)
print("[Main.server] AdminCommands initialized")

-- Initialize Map Generation system
local mapState = MapGeneration.createMapState()
local sectionCount = #mapState.sections
print(string.format("[Main.server] MapGeneration initialized: %d sections created", sectionCount))

-- Initialize section labels for player name displays
SectionLabels.initialize(mapState)
print("[Main.server] SectionLabels initialized")

-- Initialize global random chicken spawn state
local initialTime = os.time()
randomChickenSpawnState = RandomChickenSpawn.createSpawnState(nil, initialTime)
print("[Main.server] RandomChickenSpawn initialized")

-- Initialize global chicken AI state for random chicken movement
-- Use the neutral zone center and size from the spawn config
local spawnConfig = randomChickenSpawnState.config
chickenAIState = ChickenAI.createState(
  Vector3.new(
    spawnConfig.neutralZoneCenter.x,
    spawnConfig.neutralZoneCenter.y,
    spawnConfig.neutralZoneCenter.z
  ),
  spawnConfig.neutralZoneSize
)
print("[Main.server] ChickenAI initialized")

-- Initialize store inventory
local storeInventory = Store.initializeInventory()
print("[Main.server] Store inventory initialized")

-- Initialize day/night cycle
dayNightState = DayNightCycle.init()
print("[Main.server] Day/Night cycle initialized")

-- Teleport a character to a spawn point position
local function teleportCharacterToSpawnPoint(
  character: Model,
  spawnPoint: { x: number, y: number, z: number }
)
  local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if humanoidRootPart then
    humanoidRootPart.CFrame = CFrame.new(spawnPoint.x, spawnPoint.y, spawnPoint.z)
  end
end

-- Check and apply bankruptcy assistance if player is broke with no assets
local function checkAndApplyBankruptcyAssistance(player: Player)
  local currentTime = os.time()
  local userId = player.UserId

  -- Get player data
  local playerData = DataPersistence.getData(userId)
  if not playerData then
    return
  end

  -- Check if player is actually bankrupt
  if not PlayerData.isBankrupt(playerData) then
    return
  end

  -- Check cooldown to prevent exploitation
  local lastAssistance = lastBankruptcyAssistanceTime[userId]
  if lastAssistance and (currentTime - lastAssistance) < BANKRUPTCY_ASSISTANCE_COOLDOWN then
    local remainingCooldown = BANKRUPTCY_ASSISTANCE_COOLDOWN - (currentTime - lastAssistance)
    print(
      string.format(
        "[Main.server] Bankruptcy assistance on cooldown for %s (%d seconds remaining)",
        player.Name,
        remainingCooldown
      )
    )
    return
  end

  -- Apply bankruptcy assistance - only add the difference needed to reach $100
  local starterMoney = PlayerData.getBankruptcyStarterMoney()
  local amountNeeded = math.max(0, starterMoney - playerData.money)
  if amountNeeded <= 0 then
    return -- Player already has enough money
  end
  playerData.money = playerData.money + amountNeeded
  lastBankruptcyAssistanceTime[userId] = currentTime

  -- Sync player data
  syncPlayerData(player, playerData, true)

  -- Notify client about bankruptcy assistance
  local bankruptcyEvent = RemoteSetup.getEvent("BankruptcyAssistance")
  if bankruptcyEvent then
    bankruptcyEvent:FireClient(player, {
      moneyAwarded = amountNeeded,
      message = string.format(
        "You've been given $%d to help you get back on your feet!",
        amountNeeded
      ),
    })
  end

  print(
    string.format(
      "[Main.server] Awarded $%d bankruptcy assistance to %s",
      amountNeeded,
      player.Name
    )
  )
end

-- Handle character spawning/respawning to player's section
local function setupCharacterSpawning(
  player: Player,
  spawnPoint: { x: number, y: number, z: number }
)
  -- Store spawn point for this player
  playerSpawnPoints[player.UserId] = spawnPoint

  -- Handle character added (initial spawn and respawns)
  player.CharacterAdded:Connect(function(character)
    -- Wait for character to be fully loaded
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
    if humanoidRootPart and playerSpawnPoints[player.UserId] then
      local sp = playerSpawnPoints[player.UserId]
      humanoidRootPart.CFrame = CFrame.new(sp.x, sp.y, sp.z)
      print(
        string.format(
          "[Main.server] Spawned %s at section (%.1f, %.1f, %.1f)",
          player.Name,
          sp.x,
          sp.y,
          sp.z
        )
      )
    end

    -- Check bankruptcy status on respawn
    task.defer(function()
      checkAndApplyBankruptcyAssistance(player)
    end)

    -- Give owned weapon tools to player's Backpack
    task.defer(function()
      local playerData = DataPersistence.getData(player.UserId)
      if playerData and playerData.ownedWeapons then
        local weaponCount = WeaponTool.restoreOwnedWeapons(player, playerData.ownedWeapons)
        if weaponCount > 0 then
          print(
            string.format("[Main.server] Restored %d weapon(s) to %s", weaponCount, player.Name)
          )
        end
      end
    end)
  end)

  -- If character already exists, teleport immediately
  if player.Character then
    teleportCharacterToSpawnPoint(player.Character, spawnPoint)
  end
end

-- Handle player section assignment on join
Players.PlayerAdded:Connect(function(player)
  -- Check if player is banned (session-only bans)
  if AdminCommands.isBanned(player.UserId) then
    player:Kick("You are banned from this server")
    return
  end

  local currentTime = os.time()
  local playerId = tostring(player.UserId)
  local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)

  -- Track join time for new player protection
  playerJoinTimes[player.UserId] = currentTime

  -- Initialize player game state
  playerGameStates[player.UserId] = createPlayerGameState()

  -- Send initial protection status to client
  task.defer(function()
    local protectionEvent = RemoteSetup.getEvent("ProtectionStatusChanged")
    if protectionEvent then
      protectionEvent:FireClient(player, {
        isProtected = true,
        remainingSeconds = NEW_PLAYER_PROTECTION_DURATION,
        totalDuration = NEW_PLAYER_PROTECTION_DURATION,
      })
    end
  end)

  if sectionIndex then
    print(string.format("[Main.server] Assigned section %d to %s", sectionIndex, player.Name))

    -- Update section label with player's name
    SectionLabels.onPlayerJoined(player, sectionIndex)

    local spawnPoint = MapGeneration.getPlayerSpawnPoint(mapState, playerId)
    if spawnPoint then
      print(
        string.format(
          "[Main.server] Spawn point for %s: (%.1f, %.1f, %.1f)",
          player.Name,
          spawnPoint.x,
          spawnPoint.y,
          spawnPoint.z
        )
      )
      -- Setup character spawning for initial spawn and respawns
      setupCharacterSpawning(player, spawnPoint)
    end
  else
    warn(
      string.format("[Main.server] Failed to assign section to %s - map may be full", player.Name)
    )
  end

  -- Sync player data to client after DataPersistence has loaded it
  -- Use task.defer to ensure DataPersistence.PlayerAdded completes first
  task.defer(function()
    local data = DataPersistence.getData(player.UserId)
    if data then
      -- Store section index in player data so client can build visuals
      if sectionIndex then
        data.sectionIndex = sectionIndex
      end

      -- Register existing placed chickens with health system
      local gameState = getPlayerGameState(player.UserId)
      if data.placedChickens then
        for _, chicken in ipairs(data.placedChickens) do
          ChickenHealth.register(gameState.chickenHealthRegistry, chicken.id, chicken.chickenType)
        end
      end

      -- Initialize player chicken AI for free-roaming chickens in their section
      if sectionIndex then
        local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
        if sectionCenter then
          gameState.playerChickenAIState = ChickenAI.createSectionState(sectionCenter)

          -- Register existing placed chickens with the AI for roaming
          local currentTime = os.clock()
          if data.placedChickens then
            for _, chicken in ipairs(data.placedChickens) do
              -- Generate random spawn position within section
              local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
              local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
              ChickenAI.registerChicken(
                gameState.playerChickenAIState,
                chicken.id,
                chicken.chickenType,
                spawnPosV3,
                currentTime
              )
            end
          end
        end
      end

      -- Calculate and apply offline earnings before syncing
      local joinTime = os.time()
      if OfflineEarnings.hasEarnings(data, joinTime) then
        local earnings = OfflineEarnings.calculate(data, joinTime)
        local applyResult = OfflineEarnings.apply(data, earnings)

        if applyResult.success and (applyResult.moneyAdded > 0 or applyResult.eggsAdded > 0) then
          -- Fire OfflineEarningsAwarded event to client with earnings summary
          local offlineEarningsEvent = RemoteSetup.getEvent("OfflineEarningsAwarded")
          if offlineEarningsEvent then
            offlineEarningsEvent:FireClient(player, {
              totalMoney = earnings.cappedMoney,
              totalEggs = #earnings.eggsEarned,
              offlineHours = earnings.cappedSeconds / 3600,
              wasCapped = earnings.wasCapped,
              message = applyResult.message,
              moneyPerChicken = earnings.moneyPerChicken,
              eggsEarned = earnings.eggsEarned,
            })
          end
          print(
            string.format(
              "[Main.server] Applied offline earnings to %s: $%.2f, %d eggs (%.1f hours)",
              player.Name,
              applyResult.moneyAdded,
              applyResult.eggsAdded,
              earnings.cappedSeconds / 3600
            )
          )
        end
      end

      syncPlayerData(player, data, true) -- Force sync on join
      print(string.format("[Main.server] Synced player data to %s", player.Name))
    end
  end)
end)

-- Handle player section reservation on leave
Players.PlayerRemoving:Connect(function(player)
  local playerId = tostring(player.UserId)

  -- Get section index before handling leave (for label update)
  local sectionIndex = MapGeneration.getPlayerSection(mapState, playerId)

  local reservedSection = MapGeneration.handlePlayerLeave(mapState, playerId)

  if reservedSection then
    print(string.format("[Main.server] Reserved section %d for %s", reservedSection, player.Name))
  end

  -- Update section label to "Unclaimed"
  if sectionIndex then
    SectionLabels.onPlayerLeft(sectionIndex)
  end

  -- Clean up sync tracking for this player
  lastDataSyncTime[player.UserId] = nil

  -- Clean up player spawn point tracking
  playerSpawnPoints[player.UserId] = nil

  -- Clean up player game state
  playerGameStates[player.UserId] = nil

  -- Clean up player join time tracking
  playerJoinTimes[player.UserId] = nil

  -- Clean up bankruptcy assistance cooldown tracking
  lastBankruptcyAssistanceTime[player.UserId] = nil
end)

print("[Main.server] " .. RemoteSetup.getSummary())
print("[Main.server] " .. MapGeneration.getSummary(mapState))

--[[
  Tutorial Completion Handler
  Marks the player's tutorial as complete when they finish or skip it.
]]
local completeTutorialEvent = RemoteSetup.getEvent("CompleteTutorial")
if completeTutorialEvent then
  completeTutorialEvent.OnServerEvent:Connect(function(player: Player)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return
    end

    playerData.tutorialComplete = true
    syncPlayerData(player, playerData, true)
    print("[Main.server] Tutorial completed for player:", player.Name)
  end)
end

--[[
  Main Server Game Loop
  Updates all time-based game systems using RunService.Heartbeat.
  Runs at ~60 FPS and handles:
  - Chicken money generation
  - Predator spawning, movement, and attacks
  - Cage lock state expiration
  - Steal progress updates
  - Random chicken spawn events
  - Periodic cleanup of inactive predators
]]
local gameLoopConnection: RBXScriptConnection?

local function runGameLoop(deltaTime: number)
  local currentTime = os.time()
  local players = Players:GetPlayers()

  -- Update day/night cycle lighting
  DayNightCycle.update(dayNightState)

  -- Track time-of-day transitions (notifications removed per Work Item #8)
  local currentTimeOfDay = DayNightCycle.getTimeOfDay(dayNightState)
  if currentTimeOfDay ~= previousTimeOfDay then
    previousTimeOfDay = currentTimeOfDay
  end

  -- Calculate max allowed rarity based on minimum playtime of all active players
  -- This prevents new players from encountering overpowered chickens they could claim
  local maxAllowedRarity: ChickenConfig.Rarity? = nil
  if #players > 0 then
    local minPlayTime = math.huge
    for _, player in ipairs(players) do
      local playerData = DataPersistence.getData(player.UserId)
      if playerData and playerData.totalPlayTime then
        minPlayTime = math.min(minPlayTime, playerData.totalPlayTime)
      else
        -- If any player has no data yet, treat them as 0 playtime
        minPlayTime = 0
      end
    end
    if minPlayTime ~= math.huge then
      maxAllowedRarity = RandomChickenSpawn.getMaxAllowedRarity(minPlayTime)
    end
  end

  -- Update random chicken spawn events (global)
  local updateResult =
    RandomChickenSpawn.update(randomChickenSpawnState, currentTime, maxAllowedRarity)

  -- Handle despawned chicken (timeout)
  if updateResult.despawned then
    local despawnedChicken = updateResult.despawned
    -- Remove chicken from AI tracking
    ChickenAI.unregisterChicken(chickenAIState, despawnedChicken.id)

    -- Notify all players of the despawn event
    local randomChickenDespawnedEvent = RemoteSetup.getEvent("RandomChickenDespawned")
    if randomChickenDespawnedEvent then
      for _, player in ipairs(players) do
        randomChickenDespawnedEvent:FireClient(player, {
          chickenId = despawnedChicken.id,
          reason = "timeout",
        })
      end
    end
    print(
      "[Main.server] Random chicken despawned:",
      despawnedChicken.id,
      despawnedChicken.chickenType
    )
  end

  -- Handle newly spawned chicken
  if updateResult.spawned then
    -- Register chicken with AI for movement tracking
    local chicken = updateResult.spawned
    local spawnPos = Vector3.new(chicken.position.x, chicken.position.y, chicken.position.z)
    ChickenAI.registerChicken(
      chickenAIState,
      chicken.id,
      chicken.chickenType,
      spawnPos,
      currentTime
    )

    -- Notify all players of the spawn event
    local randomChickenSpawnedEvent = RemoteSetup.getEvent("RandomChickenSpawned")
    if randomChickenSpawnedEvent then
      local announcement = RandomChickenSpawn.getAnnouncementText(chicken)
      for _, player in ipairs(players) do
        randomChickenSpawnedEvent:FireClient(player, {
          chicken = chicken,
          announcement = announcement,
        })
      end
    end
  end

  -- Update random chicken AI positions (global) and sync state changes to clients
  local chickenPositions = ChickenAI.updateAll(chickenAIState, deltaTime, currentTime)
  local activeChicken = RandomChickenSpawn.getCurrentChicken(randomChickenSpawnState)
  if activeChicken and chickenPositions[activeChicken.id] then
    local chickenPos = chickenPositions[activeChicken.id]
    -- Update the spawn state position so claiming uses the current position
    activeChicken.position = {
      x = chickenPos.currentPosition.X,
      y = chickenPos.currentPosition.Y,
      z = chickenPos.currentPosition.Z,
    }

    -- Only sync to clients when chicken state changes (new target, idle change)
    if chickenPos.stateChanged then
      local positionUpdateEvent = RemoteSetup.getEvent("RandomChickenPositionUpdated")
      if positionUpdateEvent then
        for _, player in ipairs(players) do
          positionUpdateEvent:FireClient(player, {
            id = activeChicken.id,
            position = activeChicken.position,
            targetPosition = {
              x = chickenPos.targetPosition.X,
              y = chickenPos.targetPosition.Y,
              z = chickenPos.targetPosition.Z,
            },
            facingDirection = {
              x = chickenPos.facingDirection.X,
              y = chickenPos.facingDirection.Y,
              z = chickenPos.facingDirection.Z,
            },
            walkSpeed = chickenPos.walkSpeed,
            isIdle = chickenPos.isIdle,
          })
        end
      end
      chickenPos.stateChanged = false -- Clear flag after sync
    end
  end

  -- Clean up chicken AI when chicken despawns
  if not activeChicken and ChickenAI.getActiveCount(chickenAIState) > 0 then
    ChickenAI.reset(chickenAIState)
  end

  -- Update each player's game systems
  for _, player in ipairs(players) do
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      continue
    end

    local gameState = getPlayerGameState(userId)
    local playerId = tostring(userId)
    local dataChanged = false

    -- 1. Update chicken money generation (accumulates locally, don't sync for this)
    -- Damaged chickens generate less money proportional to their health
    MoneyCollection.updateAllChickenMoney(playerData, deltaTime, gameState.chickenHealthRegistry)

    -- 1.2. Update player's chicken AI (free-roaming chickens)
    if gameState.playerChickenAIState then
      -- Update AI state (handles movement, idle timing, etc.)
      ChickenAI.updateAll(gameState.playerChickenAIState, deltaTime, currentTime)

      -- Only sync chickens that have changed state (new target, idle change)
      -- This reduces network traffic and enables smooth client-side interpolation
      local changedChickens = ChickenAI.getChangedChickens(gameState.playerChickenAIState)
      if #changedChickens > 0 then
        local chickenPositionEvent = RemoteSetup.getEvent("ChickenPositionUpdated")
        if chickenPositionEvent then
          -- Batch all changed chicken positions into a single event
          local batchedPositions = {}
          for _, chicken in ipairs(changedChickens) do
            table.insert(batchedPositions, {
              chickenId = chicken.id,
              position = chicken.position,
              targetPosition = chicken.target,
              facingDirection = chicken.facingDirection,
              walkSpeed = chicken.walkSpeed,
              isIdle = chicken.isIdle,
            })
          end
          chickenPositionEvent:FireAllClients({
            ownerId = userId,
            chickens = batchedPositions,
          })
        end
      end
    end

    -- 1.5. Update egg laying for all placed chickens
    local currentTimeSeconds = os.time()
    local eggSpawnedEvent = RemoteSetup.getEvent("EggSpawned")
    for _, chickenData in ipairs(playerData.placedChickens) do
      local chickenInstance = Chicken.new(chickenData)
      if chickenInstance and chickenInstance:canLayEgg(currentTimeSeconds) then
        local eggType = chickenInstance:layEgg(currentTimeSeconds)
        if eggType then
          -- Apply egg quality boost if player has active power-up
          if PlayerData.hasActivePowerUp(playerData, "EggQuality") then
            eggType = Chicken.getUpgradedEggType(eggType)
          end

          -- Get egg spawn position - use chicken AI position for free-roaming chickens
          local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
          local eggPos: PlayerSection.Vector3? = nil

          if gameState.playerChickenAIState then
            -- Get position from AI (free-roaming)
            local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, chickenData.id)
            if aiPos then
              eggPos = {
                x = aiPos.currentPosition.X,
                y = aiPos.currentPosition.Y,
                z = aiPos.currentPosition.Z,
              }
            end
          end

          -- Fallback to spot position if AI position not available
          if not eggPos and sectionCenter and chickenData.spotIndex then
            eggPos = PlayerSection.getSpotPosition(chickenData.spotIndex, sectionCenter)
          end

          -- Final fallback: random position in section
          if not eggPos and sectionCenter then
            eggPos = PlayerSection.getRandomPositionInSection(sectionCenter)
          end

          if eggPos then
            -- Create world egg at the chicken's current position
            local worldEgg =
              WorldEgg.create(eggType, userId, chickenData.id, chickenData.spotIndex or 0, eggPos)
            if worldEgg then
              WorldEgg.add(gameState.worldEggRegistry, worldEgg)

              -- Update chicken's lastEggTime in player data
              chickenData.lastEggTime = chickenInstance.lastEggTime
              dataChanged = true

              -- Notify player of egg spawned in world
              if eggSpawnedEvent then
                eggSpawnedEvent:FireClient(player, WorldEgg.toNetworkData(worldEgg))
              end
            end
          end
        end
      end
    end

    -- 1.6. Update world eggs and handle despawns
    local expiredEggs = WorldEgg.updateAndGetExpired(gameState.worldEggRegistry, currentTimeSeconds)
    if #expiredEggs > 0 then
      local eggDespawnedEvent = RemoteSetup.getEvent("EggDespawned")
      for _, expiredEgg in ipairs(expiredEggs) do
        if eggDespawnedEvent then
          eggDespawnedEvent:FireClient(player, {
            eggId = expiredEgg.id,
            reason = "expired",
          })
        end
      end
    end

    -- 2. Update cage lock states (check for expiration)
    local lockExpired = CageLocking.update(gameState.lockState, currentTime)
    if lockExpired then
      -- Lock expired, players can now enter the cage
      local lockActivatedEvent = RemoteSetup.getEvent("LockActivated")
      if lockActivatedEvent then
        lockActivatedEvent:FireClient(player, { expired = true })
      end
    end

    -- 3. Update steal progress states
    local stealCompleted = ChickenStealing.update(gameState.stealState, currentTime)
    if stealCompleted then
      -- Steal timer completed - actual completion handled by remote handler
      -- This just tracks that the timer is done
    end

    -- 3.5. Update shield state and check for expiration
    if playerData.shieldState then
      local shieldUpdate = AreaShield.update(playerData.shieldState, currentTime)
      if shieldUpdate.expired then
        -- Shield just expired - notify all clients
        local shieldDeactivatedEvent = RemoteSetup.getEvent("ShieldDeactivated")
        if shieldDeactivatedEvent then
          shieldDeactivatedEvent:FireAllClients(player.UserId, playerData.sectionIndex or 1)
        end
        syncPlayerData(player, playerData, true)
      end
    end

    -- 4. Update predator spawning (check if should spawn new predator)
    -- Skip predator spawning for new players who still have protection
    local joinTime = playerJoinTimes[player.UserId]
    local isProtected = joinTime and (currentTime - joinTime) < NEW_PLAYER_PROTECTION_DURATION

    -- Skip predator spawning if shield is active
    local hasShieldActive = playerData.shieldState
      and AreaShield.isActive(playerData.shieldState, currentTime)

    -- Get time-of-day spawn multiplier for increased predator danger at night
    local timeSpawnMultiplier = DayNightCycle.getPredatorSpawnMultiplier(dayNightState)

    -- Skip predator spawning if player has no placed chickens (nothing to target)
    local hasPlacedChickens = #playerData.placedChickens > 0

    if
      not isProtected
      and not hasShieldActive
      and hasPlacedChickens
      and PredatorSpawning.shouldSpawn(gameState.spawnState, currentTime, timeSpawnMultiplier)
    then
      local result =
        PredatorSpawning.spawn(gameState.spawnState, currentTime, playerId, timeSpawnMultiplier)
      if result.success and result.predator then
        -- Notify player of predator spawn
        local predatorSpawnedEvent = RemoteSetup.getEvent("PredatorSpawned")
        if predatorSpawnedEvent then
          local predator = result.predator
          -- Get threat level from config
          local predatorConfig = PredatorConfig.get(predator.predatorType)
          local threatLevel = predatorConfig and predatorConfig.threatLevel or "Minor"

          -- Generate spawn position at section edge using PredatorAI
          local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
          local sectionCenterV3 = Vector3.new(sectionCenter.x, sectionCenter.y, sectionCenter.z)

          -- Select a random target chicken if there are any placed
          local targetChickenPosition: Vector3? = nil
          local targetChickenId: string? = nil
          if #playerData.placedChickens > 0 then
            local targetChicken =
              playerData.placedChickens[math.random(1, #playerData.placedChickens)]
            if targetChicken then
              targetChickenId = targetChicken.id
              -- Get chicken position from AI (free-roaming) or fallback to spot
              if gameState.playerChickenAIState then
                local aiPos =
                  ChickenAI.getPosition(gameState.playerChickenAIState, targetChicken.id)
                if aiPos then
                  targetChickenPosition = Vector3.new(
                    aiPos.currentPosition.X,
                    aiPos.currentPosition.Y + 1,
                    aiPos.currentPosition.Z
                  )
                end
              end
              -- Fallback to spot position
              if not targetChickenPosition and targetChicken.spotIndex then
                local spotPos =
                  PlayerSection.getSpotPosition(targetChicken.spotIndex, sectionCenter)
                if spotPos then
                  targetChickenPosition = Vector3.new(spotPos.x, spotPos.y + 1, spotPos.z)
                end
              end
            end
          end

          -- Update predator's targetChickenId in spawn state
          if targetChickenId then
            PredatorSpawning.updateTargetChicken(gameState.spawnState, predator.id, targetChickenId)
          end

          -- Register predator with AI for walking behavior (with target chicken position)
          local predatorPosition = PredatorAI.registerPredator(
            gameState.predatorAIState,
            predator.id,
            predator.predatorType,
            sectionCenterV3,
            nil, -- preferredEdge
            targetChickenPosition -- target chicken position if available
          )

          -- Send predator data to ALL clients so all players can see predators
          predatorSpawnedEvent:FireAllClients(
            predator.id,
            predator.predatorType,
            threatLevel,
            predatorPosition.currentPosition,
            playerData.sectionIndex or 1, -- Include section so clients know which coop is being targeted
            targetChickenId -- Include target chicken ID so clients can show visual feedback
          )
        end
      end
    end

    -- 4.5. Update approaching predator targets (follow target chicken or re-target if needed)
    for _, predator in ipairs(PredatorSpawning.getActivePredators(gameState.spawnState)) do
      if predator.state == "approaching" then
        local targetChickenId =
          PredatorSpawning.getTargetChickenId(gameState.spawnState, predator.id)

        -- Check if target chicken still exists
        local targetChickenExists = false
        local targetChicken = nil
        if targetChickenId then
          for _, chicken in ipairs(playerData.placedChickens) do
            if chicken.id == targetChickenId then
              targetChickenExists = true
              targetChicken = chicken
              break
            end
          end
        end

        -- Re-target if target doesn't exist or is nil
        if not targetChickenExists and #playerData.placedChickens > 0 then
          local newTarget = playerData.placedChickens[math.random(1, #playerData.placedChickens)]
          if newTarget then
            PredatorSpawning.updateTargetChicken(gameState.spawnState, predator.id, newTarget.id)
            targetChicken = newTarget

            -- Get new target position
            local newTargetPos: Vector3? = nil
            if gameState.playerChickenAIState then
              local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, newTarget.id)
              if aiPos then
                newTargetPos = Vector3.new(
                  aiPos.currentPosition.X,
                  aiPos.currentPosition.Y + 1,
                  aiPos.currentPosition.Z
                )
              end
            end
            if not newTargetPos and newTarget.spotIndex then
              local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
              local spotPos = PlayerSection.getSpotPosition(newTarget.spotIndex, sectionCenter)
              if spotPos then
                newTargetPos = Vector3.new(spotPos.x, spotPos.y + 1, spotPos.z)
              end
            end
            if newTargetPos then
              PredatorAI.updateApproachTarget(gameState.predatorAIState, predator.id, newTargetPos)
            end

            -- Notify clients of new target
            local predatorTargetChangedEvent = RemoteSetup.getEvent("PredatorTargetChanged")
            if predatorTargetChangedEvent then
              predatorTargetChangedEvent:FireAllClients(predator.id, newTarget.id)
            end
          end
        elseif targetChicken then
          -- Update target position as chicken may have moved
          local targetPos: Vector3? = nil
          if gameState.playerChickenAIState then
            local aiPos = ChickenAI.getPosition(gameState.playerChickenAIState, targetChicken.id)
            if aiPos then
              targetPos = Vector3.new(
                aiPos.currentPosition.X,
                aiPos.currentPosition.Y + 1,
                aiPos.currentPosition.Z
              )
            end
          end
          if not targetPos and targetChicken.spotIndex then
            local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
            local spotPos = PlayerSection.getSpotPosition(targetChicken.spotIndex, sectionCenter)
            if spotPos then
              targetPos = Vector3.new(spotPos.x, spotPos.y + 1, spotPos.z)
            end
          end
          if targetPos then
            PredatorAI.updateApproachTarget(gameState.predatorAIState, predator.id, targetPos)
          end
        end
      end
    end

    -- 4.6. Update predator AI positions (walking towards target)
    local predatorPositionUpdatedEvent = RemoteSetup.getEvent("PredatorPositionUpdated")
    local updatedPositions = PredatorAI.updateAll(gameState.predatorAIState, deltaTime, currentTime)
    for predatorId, position in pairs(updatedPositions) do
      -- Send position update to ALL clients so all players can see predator movement
      if predatorPositionUpdatedEvent then
        predatorPositionUpdatedEvent:FireAllClients(
          predatorId,
          position.currentPosition,
          position.hasReachedTarget
        )
      end
    end

    -- 5. Update predator states based on AI entering section (not reaching coop center)
    -- Predators attack when they enter the player's section boundary
    local nowAttacking = {}
    for _, predator in ipairs(PredatorSpawning.getActivePredators(gameState.spawnState)) do
      if predator.state == "spawning" or predator.state == "approaching" then
        -- Check if predator has entered the target section boundary
        if PredatorAI.hasEnteredSection(gameState.predatorAIState, predator.id) then
          PredatorSpawning.updatePredatorState(gameState.spawnState, predator.id, "attacking")
          table.insert(nowAttacking, predator.id)
        elseif predator.state == "spawning" then
          -- Transition from spawning to approaching
          PredatorSpawning.updatePredatorState(gameState.spawnState, predator.id, "approaching")
        end
      end
    end

    -- 6. Execute attacks for predators that just started attacking
    for _, predatorId in ipairs(nowAttacking) do
      local attackResult =
        PredatorAttack.executeAttack(playerData, gameState.spawnState, predatorId, currentTime)
      if attackResult.success and attackResult.chickensLost > 0 then
        dataChanged = true

        -- Notify client to remove chicken visuals for killed chickens
        local chickenPickedUpEvent = RemoteSetup.getEvent("ChickenPickedUp")
        if chickenPickedUpEvent and attackResult.chickenIds then
          for _, chickenId in ipairs(attackResult.chickenIds) do
            local spotIndex = attackResult.chickenSpots and attackResult.chickenSpots[chickenId]
            chickenPickedUpEvent:FireClient(player, {
              chickenId = chickenId,
              spotIndex = spotIndex,
            })
          end
        end

        -- Notify player of attack
        local alertEvent = RemoteSetup.getEvent("AlertTriggered")
        if alertEvent then
          local predator = PredatorSpawning.findPredator(gameState.spawnState, predatorId)
          if predator then
            local alert = PredatorAttack.generateAlert(predator, "attacking")
            alertEvent:FireClient(player, alert)
          end
        end

        -- If predator escaped after attack, notify and cleanup AI
        if attackResult.predatorEscaped then
          PredatorAI.unregisterPredator(gameState.predatorAIState, predatorId)
          -- Fire PredatorDefeated event to ALL clients (escaped after attack)
          local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
          if predatorDefeatedEvent then
            predatorDefeatedEvent:FireAllClients(predatorId, false)
          end
        end
      end
    end

    -- 6.5. Apply predator damage to player if in combat range
    local character = player.Character
    if character then
      local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
      if humanoidRootPart then
        local playerPosition = humanoidRootPart.Position
        local combatConstants = CombatHealth.getConstants()
        local combatRange = combatConstants.combatRangeStuds

        -- Check for attacking predators near player
        local activePredators = PredatorSpawning.getActivePredators(gameState.spawnState)
        local totalDamage = 0
        local damagingPredator: string? = nil

        for _, predator in ipairs(activePredators) do
          if predator.state == "attacking" then
            -- Get predator position from AI state
            local predatorPos = PredatorAI.getPosition(gameState.predatorAIState, predator.id)
            if predatorPos then
              local distance = (predatorPos.currentPosition - playerPosition).Magnitude
              if distance <= combatRange then
                -- Player is in combat range - apply damage
                local predatorConfig = PredatorConfig.get(predator.predatorType)
                if predatorConfig then
                  totalDamage = totalDamage + predatorConfig.damage * deltaTime
                  damagingPredator = predator.predatorType
                end
              end
            end
          end
        end

        -- Apply accumulated damage if any
        if totalDamage > 0 and damagingPredator then
          local damageResult = CombatHealth.applyFixedDamage(
            gameState.combatState,
            totalDamage,
            currentTime,
            damagingPredator
          )

          if damageResult.success then
            -- Notify client of damage
            local playerDamagedEvent = RemoteSetup.getEvent("PlayerDamaged")
            if playerDamagedEvent then
              playerDamagedEvent:FireClient(player, {
                damage = damageResult.damageDealt,
                newHealth = damageResult.newHealth,
                maxHealth = gameState.combatState.maxHealth,
                source = damagingPredator,
              })
            end

            -- Handle knockback
            if damageResult.wasKnockedBack then
              local playerKnockbackEvent = RemoteSetup.getEvent("PlayerKnockback")
              if playerKnockbackEvent then
                playerKnockbackEvent:FireClient(player, {
                  duration = combatConstants.knockbackDuration,
                  source = damagingPredator,
                })
              end

              -- Steal money from player when knocked back by predator (15% of current money)
              local moneyLossPercent = 0.15
              local moneyLost = math.floor(playerData.money * moneyLossPercent)
              if moneyLost > 0 then
                playerData.money = playerData.money - moneyLost
                -- Fire MoneyLost event to show visual feedback
                local moneyLostEvent = RemoteSetup.getEvent("MoneyLost")
                if moneyLostEvent then
                  moneyLostEvent:FireClient(player, {
                    amount = moneyLost,
                    source = damagingPredator,
                  })
                end
                -- Sync player data to update money display
                syncPlayerData(player, playerData, true)
              end
            end
          end
        end

        -- 6.6. Update combat state (regeneration, knockback expiry)
        local combatUpdate = CombatHealth.update(gameState.combatState, deltaTime, currentTime)
        if combatUpdate.healthChanged then
          local playerHealthChangedEvent = RemoteSetup.getEvent("PlayerHealthChanged")
          if playerHealthChangedEvent then
            playerHealthChangedEvent:FireClient(player, {
              health = gameState.combatState.health,
              maxHealth = gameState.combatState.maxHealth,
              isKnockedBack = gameState.combatState.isKnockedBack,
              inCombat = gameState.combatState.inCombat,
            })
          end
        end
      end
    end

    -- 6.7. Apply predator damage to chickens when attacking
    local activePredators = PredatorSpawning.getActivePredators(gameState.spawnState)
    for _, predator in ipairs(activePredators) do
      if predator.state == "attacking" then
        -- Check if predator is within attack range of coop
        local predatorPos = PredatorAI.getPosition(gameState.predatorAIState, predator.id)
        if not predatorPos then
          continue
        end

        -- Get coop center for this player's section
        local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
        if not sectionCenter then
          continue
        end
        local coopCenter = PlayerSection.getCoopCenter(sectionCenter)
        local coopCenterV3 = Vector3.new(coopCenter.x, coopCenter.y, coopCenter.z)

        -- Check distance from predator to coop
        local distanceToCoop = (predatorPos.currentPosition - coopCenterV3).Magnitude
        if distanceToCoop > PREDATOR_ATTACK_RANGE_STUDS then
          continue -- Predator too far to attack chickens
        end

        local predatorConfig = PredatorConfig.get(predator.predatorType)
        if predatorConfig then
          -- Damage all placed chickens (predator attacks the whole coop)
          local chickenDamagePerSecond = predatorConfig.damage * 0.5 -- Reduced from player damage
          local damageThisFrame = chickenDamagePerSecond * deltaTime

          for _, chicken in ipairs(playerData.placedChickens) do
            -- Skip chickens in protection period (newly placed)
            local placedTime = chicken.placedTime or 0
            local timeSincePlaced = currentTime - placedTime
            if timeSincePlaced < CHICKEN_PLACEMENT_PROTECTION_SECONDS then
              continue
            end

            local damageResult = ChickenHealth.applyDamage(
              gameState.chickenHealthRegistry,
              chicken.id,
              damageThisFrame,
              currentTime
            )

            if damageResult.success and damageResult.damageDealt > 0 then
              -- Notify client of chicken damage
              local chickenDamagedEvent = RemoteSetup.getEvent("ChickenDamaged")
              if chickenDamagedEvent then
                local healthState = ChickenHealth.get(gameState.chickenHealthRegistry, chicken.id)
                chickenDamagedEvent:FireClient(player, {
                  chickenId = chicken.id,
                  damage = damageResult.damageDealt,
                  newHealth = damageResult.newHealth,
                  maxHealth = healthState and healthState.maxHealth or 50,
                  source = predator.predatorType,
                })
              end

              -- Handle chicken death
              if damageResult.died then
                dataChanged = true

                -- Remove chicken from placed chickens
                for i, placedChicken in ipairs(playerData.placedChickens) do
                  if placedChicken.id == chicken.id then
                    table.remove(playerData.placedChickens, i)
                    break
                  end
                end

                -- Unregister from health system
                ChickenHealth.unregister(gameState.chickenHealthRegistry, chicken.id)

                -- Notify client of chicken death
                local chickenDiedEvent = RemoteSetup.getEvent("ChickenDied")
                if chickenDiedEvent then
                  chickenDiedEvent:FireClient(player, {
                    chickenId = chicken.id,
                    spotIndex = chicken.spotIndex,
                    killedBy = predator.predatorType,
                  })
                end
              end
            end
          end
        end
      end
    end

    -- 6.75. Update predator chicken targeting and despawn logic
    for _, predator in ipairs(activePredators) do
      if predator.state == "attacking" then
        local hasChickens = #playerData.placedChickens > 0

        -- Check if predator is actively engaging the player (within combat range)
        local isEngagingPlayer = false
        local character = player.Character
        if character then
          local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
          if humanoidRootPart then
            local playerPosition = humanoidRootPart.Position
            local predatorPos = PredatorAI.getPosition(gameState.predatorAIState, predator.id)
            if predatorPos then
              local combatConstants = CombatHealth.getConstants()
              local distance = (predatorPos.currentPosition - playerPosition).Magnitude
              -- Predator is engaging if within combat range
              isEngagingPlayer = distance <= combatConstants.combatRangeStuds
            end
          end
        end

        -- Update chicken presence and check if predator should despawn
        -- Predators don't despawn while actively attacking a player
        local shouldDespawn = PredatorAI.updateChickenPresence(
          gameState.predatorAIState,
          predator.id,
          hasChickens,
          currentTime,
          isEngagingPlayer
        )

        if shouldDespawn then
          -- Predator leaves because no chickens to attack
          PredatorSpawning.updatePredatorState(gameState.spawnState, predator.id, "escaped")
          PredatorAI.unregisterPredator(gameState.predatorAIState, predator.id)

          -- Notify clients that predator is leaving
          local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
          if predatorDefeatedEvent then
            predatorDefeatedEvent:FireAllClients(predator.id, false) -- false = not defeated, just left
          end
        elseif hasChickens then
          -- Target a random chicken for visual approach
          local currentTarget = PredatorAI.getTargetChicken(gameState.predatorAIState, predator.id)
          local shouldRetarget = currentTarget == nil or math.random() < 0.02 -- 2% chance to switch targets per frame

          if shouldRetarget then
            -- Pick a random chicken to approach
            local targetChicken =
              playerData.placedChickens[math.random(1, #playerData.placedChickens)]
            if targetChicken then
              -- Get chicken position from AI (free-roaming) or fallback to spot
              local targetPosV3: Vector3? = nil

              if gameState.playerChickenAIState then
                local aiPos =
                  ChickenAI.getPosition(gameState.playerChickenAIState, targetChicken.id)
                if aiPos then
                  targetPosV3 = Vector3.new(
                    aiPos.currentPosition.X,
                    aiPos.currentPosition.Y + 1,
                    aiPos.currentPosition.Z
                  )
                end
              end

              -- Fallback to spot position (legacy)
              if not targetPosV3 and targetChicken.spotIndex then
                local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
                if sectionCenter then
                  local spotPos =
                    PlayerSection.getSpotPosition(targetChicken.spotIndex, sectionCenter)
                  if spotPos then
                    targetPosV3 = Vector3.new(spotPos.x, spotPos.y + 1, spotPos.z)
                  end
                end
              end

              if targetPosV3 then
                PredatorAI.setTargetChicken(
                  gameState.predatorAIState,
                  predator.id,
                  targetChicken.id, -- Use chicken ID instead of spotIndex
                  targetPosV3
                )
              end
            end
          end
        end
      end
    end

    -- 6.8. Regenerate chicken health when not under attack
    local anyPredatorAttacking = false
    for _, predator in ipairs(activePredators) do
      if predator.state == "attacking" then
        anyPredatorAttacking = true
        break
      end
    end

    if not anyPredatorAttacking then
      local regenUpdates =
        ChickenHealth.updateAll(gameState.chickenHealthRegistry, deltaTime, currentTime)

      -- Send health updates for chickens that regenerated
      for chickenId, update in pairs(regenUpdates) do
        local chickenHealthChangedEvent = RemoteSetup.getEvent("ChickenHealthChanged")
        if chickenHealthChangedEvent then
          local healthState = ChickenHealth.get(gameState.chickenHealthRegistry, chickenId)
          chickenHealthChangedEvent:FireClient(player, {
            chickenId = chickenId,
            newHealth = update.newHealth,
            maxHealth = healthState and healthState.maxHealth or 50,
          })
        end
      end
    end

    -- Sync data to client if changed
    if dataChanged then
      syncPlayerData(player, playerData, false)
    end
  end

  -- 7. Periodic cleanup of inactive predators (every PREDATOR_CLEANUP_INTERVAL seconds)
  if currentTime - lastCleanupTime >= PREDATOR_CLEANUP_INTERVAL then
    lastCleanupTime = currentTime
    for userId, gameState in pairs(playerGameStates) do
      local removed = PredatorSpawning.cleanup(gameState.spawnState)
      if removed > 0 then
        -- Optional: Log cleanup for debugging
        -- print(string.format("[Main.server] Cleaned up %d inactive predators for user %d", removed, userId))
      end
    end
  end

  -- 8. Check for store replenishment (every STORE_REPLENISH_CHECK_INTERVAL seconds)
  if currentTime - lastStoreReplenishCheck >= STORE_REPLENISH_CHECK_INTERVAL then
    lastStoreReplenishCheck = currentTime
    if Store.needsReplenish() then
      local newInventory = Store.replenishStore()
      print("[Main.server] Store inventory replenished")

      -- Notify all connected players
      local storeReplenishedEvent = RemoteSetup.getEvent("StoreReplenished")
      if storeReplenishedEvent then
        for _, player in ipairs(Players:GetPlayers()) do
          storeReplenishedEvent:FireClient(player, newInventory)
        end
      end
    end
  end

  -- 9. Update protection status for players approaching/exceeding protection duration
  local protectionEvent = RemoteSetup.getEvent("ProtectionStatusChanged")
  if protectionEvent then
    for userId, joinTime in pairs(playerJoinTimes) do
      local timeSinceJoin = currentTime - joinTime
      local remainingSeconds = NEW_PLAYER_PROTECTION_DURATION - timeSinceJoin

      -- Send update when protection is about to expire or has expired
      if remainingSeconds <= 0 then
        -- Protection has expired - notify once and remove tracking
        local player = Players:GetPlayerByUserId(userId)
        if player then
          protectionEvent:FireClient(player, {
            isProtected = false,
            remainingSeconds = 0,
            totalDuration = NEW_PLAYER_PROTECTION_DURATION,
          })
        end
        playerJoinTimes[userId] = nil
      end
    end
  end
end

-- Start the game loop
gameLoopConnection = RunService.Heartbeat:Connect(runGameLoop)
print("[Main.server] Game loop started")
