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

-- Offline earnings module
local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

-- Player Data Sync Configuration
local DATA_SYNC_THROTTLE_INTERVAL = 0.1 -- Minimum seconds between data updates per player
local lastDataSyncTime: { [number]: number } = {} -- Tracks last sync time per player

-- Game Loop Configuration
local PREDATOR_CLEANUP_INTERVAL = 10 -- Seconds between predator cleanup passes
local lastCleanupTime = 0

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

-- Track pending replenish purchases
local pendingReplenishPurchases: { [number]: boolean } = {}

-- Track pending item purchases (userId -> {itemType, itemId, rarity})
local pendingItemPurchases: { [number]: { itemType: string, itemId: string, rarity: string } } = {}

-- Per-player game state tracking
type PlayerGameState = {
  spawnState: PredatorSpawning.SpawnState,
  lockState: CageLocking.LockState,
  stealState: ChickenStealing.StealState,
  batState: BaseballBat.BatState,
  combatState: CombatHealth.CombatState,
  chickenHealthRegistry: ChickenHealth.ChickenHealthRegistry,
  predatorAIState: PredatorAI.PredatorAIState,
}
local playerGameStates: { [number]: PlayerGameState } = {}

-- Per-player spawn point tracking for respawning
local playerSpawnPoints: { [number]: { x: number, y: number, z: number } } = {}

-- Global random chicken spawn state (shared event for all players)
local randomChickenSpawnState: RandomChickenSpawn.SpawnEventState

-- Global chicken AI state for tracking random chicken movement
local chickenAIState: ChickenAI.ChickenAIState

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

--[[
  Chicken Placement Server Handlers
  Handles PlaceChicken and PickupChicken RemoteFunctions.
  All operations validate player data and fire events to update clients.
]]

-- PlaceChicken RemoteFunction handler
local placeChickenFunc = RemoteSetup.getFunction("PlaceChicken")
if placeChickenFunc then
  placeChickenFunc.OnServerInvoke = function(player: Player, chickenId: string, spotIndex: number)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = ChickenPlacement.placeChicken(playerData, chickenId, spotIndex)
    if result.success then
      -- Register chicken with health system
      local gameState = getPlayerGameState(userId)
      if result.chicken and result.chicken.chickenType then
        ChickenHealth.register(
          gameState.chickenHealthRegistry,
          chickenId,
          result.chicken.chickenType
        )
      end

      -- Fire ChickenPlaced event to all clients so they can update visuals
      local chickenPlacedEvent = RemoteSetup.getEvent("ChickenPlaced")
      if chickenPlacedEvent then
        chickenPlacedEvent:FireAllClients({
          playerId = userId,
          chicken = result.chicken,
          spotIndex = spotIndex,
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

    -- Get the spot index before pickup for the event
    local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
    local spotIndex = chicken and chicken.spotIndex or nil

    local result = ChickenPlacement.pickupChicken(playerData, chickenId)
    if result.success then
      -- Unregister chicken from health system
      local gameState = getPlayerGameState(userId)
      ChickenHealth.unregister(gameState.chickenHealthRegistry, chickenId)

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

--[[
  Egg Hatching Server Handlers
  Handles HatchEgg RemoteFunction.
  Validates egg ownership, performs hatch, adds chicken to inventory.
]]

-- HatchEgg RemoteFunction handler
-- Parameters: eggId, spotIndex (optional) - if spotIndex provided, place chicken there directly
local hatchEggFunc = RemoteSetup.getFunction("HatchEgg")
if hatchEggFunc then
  hatchEggFunc.OnServerInvoke = function(player: Player, eggId: string, spotIndex: number?)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = EggHatching.hatch(playerData, eggId)
    if result.success then
      -- If spotIndex provided, move the chicken from inventory to placed
      if spotIndex and result.chickenId then
        -- Find the chicken in inventory
        local chickenIndex = nil
        for i, chicken in ipairs(playerData.inventory.chickens) do
          if chicken.id == result.chickenId then
            chickenIndex = i
            break
          end
        end

        if chickenIndex then
          -- Remove from inventory and add to placed chickens
          local chicken = table.remove(playerData.inventory.chickens, chickenIndex)
          chicken.spotIndex = spotIndex
          table.insert(playerData.placedChickens, chicken)

          -- Register chicken with health system
          local gameState = getPlayerGameState(userId)
          ChickenHealth.register(
            gameState.chickenHealthRegistry,
            result.chickenId,
            chicken.chickenType
          )

          -- Fire ChickenPlaced event
          local chickenPlacedEvent = RemoteSetup.getEvent("ChickenPlaced")
          if chickenPlacedEvent then
            chickenPlacedEvent:FireClient(player, {
              chicken = chicken,
              spotIndex = spotIndex,
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
  Handles SwingBat RemoteFunction and BatEquipped RemoteEvent.
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

    -- Handle equip/unequip actions
    if action == "equip" then
      local equipped = BaseballBat.equip(batState)
      if equipped then
        -- Broadcast to all clients that this player equipped bat
        local batEquippedEvent = RemoteSetup.getEvent("BatEquipped")
        if batEquippedEvent then
          batEquippedEvent:FireAllClients(player, true)
        end
      end
      return { success = equipped, isEquipped = batState.isEquipped }
    elseif action == "unequip" then
      local unequipped = BaseballBat.unequip(batState)
      if unequipped then
        -- Broadcast to all clients that this player unequipped bat
        local batEquippedEvent = RemoteSetup.getEvent("BatEquipped")
        if batEquippedEvent then
          batEquippedEvent:FireAllClients(player, false)
        end
      end
      return { success = unequipped, isEquipped = batState.isEquipped }
    elseif action == "toggle" then
      local isNowEquipped = BaseballBat.toggle(batState)
      -- Broadcast to all clients
      local batEquippedEvent = RemoteSetup.getEvent("BatEquipped")
      if batEquippedEvent then
        batEquippedEvent:FireAllClients(player, isNowEquipped)
      end
      return { success = true, isEquipped = isNowEquipped }
    elseif action == "swing" then
      -- Check if bat is equipped
      if not batState.isEquipped then
        return { success = false, message = "Bat not equipped" }
      end

      -- Handle predator swing
      if targetType == "predator" and targetId then
        local playerData = DataPersistence.getData(userId)
        if not playerData then
          return { success = false, message = "Player data not found" }
        end

        local result =
          BaseballBat.hitPredator(batState, gameState.spawnState, targetId, currentTime)
        if result.success and result.defeated then
          -- Award money for defeating predator
          playerData.money = (playerData.money or 0) + result.rewardMoney

          -- Unregister from predator AI
          PredatorAI.unregisterPredator(gameState.predatorAIState, targetId)

          -- Fire PredatorDefeated event
          local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
          if predatorDefeatedEvent then
            predatorDefeatedEvent:FireClient(player, targetId, true)
          end

          syncPlayerData(player, playerData, true)
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
    if itemType ~= "egg" and itemType ~= "chicken" then
      return {
        success = false,
        message = "Invalid item type",
      }
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

-- ProcessReceipt callback for handling Robux purchases
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

  -- Unknown product - grant anyway to avoid issues
  return Enum.ProductPurchaseDecision.PurchaseGranted
end
local dataPersistenceStarted = DataPersistence.start()
if dataPersistenceStarted then
  print("[Main.server] DataPersistence initialized successfully")
else
  warn("[Main.server] DataPersistence failed to initialize DataStore - running in offline mode")
end

-- Initialize Map Generation system
local mapState = MapGeneration.createMapState()
local sectionCount = #mapState.sections
print(string.format("[Main.server] MapGeneration initialized: %d sections created", sectionCount))

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
  }
end

-- Get or create player game state
local function getPlayerGameState(userId: number): PlayerGameState
  if not playerGameStates[userId] then
    playerGameStates[userId] = createPlayerGameState()
  end
  return playerGameStates[userId]
end

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
  end)

  -- If character already exists, teleport immediately
  if player.Character then
    teleportCharacterToSpawnPoint(player.Character, spawnPoint)
  end
end

-- Handle player section assignment on join
Players.PlayerAdded:Connect(function(player)
  local currentTime = os.time()
  local playerId = tostring(player.UserId)
  local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)

  -- Initialize player game state
  playerGameStates[player.UserId] = createPlayerGameState()

  if sectionIndex then
    print(string.format("[Main.server] Assigned section %d to %s", sectionIndex, player.Name))
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
  local reservedSection = MapGeneration.handlePlayerLeave(mapState, playerId)

  if reservedSection then
    print(string.format("[Main.server] Reserved section %d for %s", reservedSection, player.Name))
  end

  -- Clean up sync tracking for this player
  lastDataSyncTime[player.UserId] = nil

  -- Clean up player spawn point tracking
  playerSpawnPoints[player.UserId] = nil

  -- Clean up player game state
  playerGameStates[player.UserId] = nil
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

  -- Update random chicken spawn events (global)
  local spawnResult = RandomChickenSpawn.update(randomChickenSpawnState, currentTime)
  if spawnResult and spawnResult.success and spawnResult.chicken then
    -- Register chicken with AI for movement tracking
    local chicken = spawnResult.chicken
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
      local announcement = RandomChickenSpawn.getAnnouncementText(spawnResult.chicken)
      for _, player in ipairs(players) do
        randomChickenSpawnedEvent:FireClient(player, {
          chicken = spawnResult.chicken,
          announcement = announcement,
        })
      end
    end
  end

  -- Update random chicken AI positions (global) and sync to clients
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

    -- Sync position to all clients
    local positionUpdateEvent = RemoteSetup.getEvent("RandomChickenPositionUpdated")
    if positionUpdateEvent then
      for _, player in ipairs(players) do
        positionUpdateEvent:FireClient(player, {
          id = activeChicken.id,
          position = activeChicken.position,
          facingDirection = {
            x = chickenPos.facingDirection.X,
            y = chickenPos.facingDirection.Y,
            z = chickenPos.facingDirection.Z,
          },
          isIdle = chickenPos.isIdle,
        })
      end
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

    -- 1.5. Update egg laying for all placed chickens
    local currentTimeSeconds = os.time()
    local eggLaidEvent = RemoteSetup.getEvent("EggLaid")
    for _, chickenData in ipairs(playerData.placedChickens) do
      local chickenInstance = Chicken.new(chickenData)
      if chickenInstance and chickenInstance:canLayEgg(currentTimeSeconds) then
        local eggType = chickenInstance:layEgg(currentTimeSeconds)
        if eggType then
          -- Get egg config to get rarity
          local eggConfigData = EggConfig.get(eggType)
          local eggRarity = if eggConfigData then eggConfigData.rarity else "Common"

          -- Create new egg and add to inventory
          local newEgg: PlayerData.EggData = {
            id = PlayerData.generateId(),
            eggType = eggType,
            rarity = eggRarity,
          }
          table.insert(playerData.inventory.eggs, newEgg)

          -- Update chicken's lastEggTime in player data
          chickenData.lastEggTime = chickenInstance.lastEggTime

          dataChanged = true

          -- Notify player of egg laid
          if eggLaidEvent then
            eggLaidEvent:FireClient(player, {
              chickenId = chickenData.id,
              chickenType = chickenData.chickenType,
              eggId = newEgg.id,
              eggType = eggType,
              eggRarity = eggRarity,
            })
          end
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

    -- 4. Update predator spawning (check if should spawn new predator)
    if PredatorSpawning.shouldSpawn(gameState.spawnState, currentTime) then
      local result = PredatorSpawning.spawn(gameState.spawnState, currentTime, playerId)
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

          -- Register predator with AI for walking behavior
          local predatorPosition = PredatorAI.registerPredator(
            gameState.predatorAIState,
            predator.id,
            predator.predatorType,
            sectionCenterV3
          )

          -- Send predator data in the format the client expects
          predatorSpawnedEvent:FireClient(
            player,
            predator.id,
            predator.predatorType,
            threatLevel,
            predatorPosition.currentPosition
          )
        end
      end
    end

    -- 4.5. Update predator AI positions (walking towards coop)
    local predatorPositionUpdatedEvent = RemoteSetup.getEvent("PredatorPositionUpdated")
    local updatedPositions = PredatorAI.updateAll(gameState.predatorAIState, deltaTime)
    for predatorId, position in pairs(updatedPositions) do
      -- Send position update to client
      if predatorPositionUpdatedEvent then
        predatorPositionUpdatedEvent:FireClient(
          player,
          predatorId,
          position.currentPosition,
          position.hasReachedTarget
        )
      end
    end

    -- 5. Update predator states based on AI reaching coop (not time-based)
    -- Predators only attack when they physically reach the coop
    local nowAttacking = {}
    for _, predator in ipairs(PredatorSpawning.getActivePredators(gameState.spawnState)) do
      if predator.state == "spawning" or predator.state == "approaching" then
        -- Check if predator has reached coop via AI
        if PredatorAI.hasReachedCoop(gameState.predatorAIState, predator.id) then
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
        PredatorAttack.executeAttack(playerData, gameState.spawnState, predatorId)
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
          local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
          if predatorDefeatedEvent then
            predatorDefeatedEvent:FireClient(player, predatorId, false)
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
        local predatorConfig = PredatorConfig.get(predator.predatorType)
        if predatorConfig then
          -- Damage all placed chickens (predator attacks the whole coop)
          local chickenDamagePerSecond = predatorConfig.damage * 0.5 -- Reduced from player damage
          local damageThisFrame = chickenDamagePerSecond * deltaTime

          for _, chicken in ipairs(playerData.placedChickens) do
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
end

-- Start the game loop
gameLoopConnection = RunService.Heartbeat:Connect(runGameLoop)
print("[Main.server] Game loop started")
