local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Util = require(Shared:WaitForChild("Util"))
local RemoteSetup = require(Server:WaitForChild("RemoteSetup"))
local DataPersistence = require(Server:WaitForChild("DataPersistence"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Game loop modules
local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
local PredatorAttack = require(Shared:WaitForChild("PredatorAttack"))
local CageLocking = require(Shared:WaitForChild("CageLocking"))
local ChickenStealing = require(Shared:WaitForChild("ChickenStealing"))
local RandomChickenSpawn = require(Shared:WaitForChild("RandomChickenSpawn"))

-- Store module for buy/sell operations
local Store = require(Shared:WaitForChild("Store"))

-- Chicken placement module
local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))

-- Egg hatching module
local EggHatching = require(Shared:WaitForChild("EggHatching"))

-- Player Data Sync Configuration
local DATA_SYNC_THROTTLE_INTERVAL = 0.1 -- Minimum seconds between data updates per player
local lastDataSyncTime: { [number]: number } = {} -- Tracks last sync time per player

-- Game Loop Configuration
local PREDATOR_CLEANUP_INTERVAL = 10 -- Seconds between predator cleanup passes
local lastCleanupTime = 0

-- Per-player game state tracking
type PlayerGameState = {
  spawnState: PredatorSpawning.SpawnState,
  lockState: CageLocking.LockState,
  stealState: ChickenStealing.StealState,
}
local playerGameStates: { [number]: PlayerGameState } = {}

-- Global random chicken spawn state (shared event for all players)
local randomChickenSpawnState: RandomChickenSpawn.SpawnEventState

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
    local data = DataPersistence.getData(userId)
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

    local result = Store.buyEgg(playerData, eggType, quantity)
    if result.success then
      syncPlayerData(player, playerData, true)
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
local hatchEggFunc = RemoteSetup.getFunction("HatchEgg")
if hatchEggFunc then
  hatchEggFunc.OnServerInvoke = function(player: Player, eggId: string)
    local userId = player.UserId
    local playerData = DataPersistence.getData(userId)
    if not playerData then
      return { success = false, message = "Player data not found" }
    end

    local result = EggHatching.hatch(playerData, eggId)
    if result.success then
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
        -- Fire MoneyCollected event to update client HUD
        local moneyCollectedEvent = RemoteSetup.getEvent("MoneyCollected")
        if moneyCollectedEvent then
          moneyCollectedEvent:FireClient(player, {
            amountCollected = amountCollected,
            newBalance = result.newBalance,
            message = result.message,
          })
        end
        syncPlayerData(player, playerData, true)
      end
    end
    return result
  end
end

-- Initialize DataPersistence system (handles player data saving/loading)
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

-- Create game state for a player
local function createPlayerGameState(): PlayerGameState
  return {
    spawnState = PredatorSpawning.createSpawnState(),
    lockState = CageLocking.createLockState(),
    stealState = ChickenStealing.createStealState(),
  }
end

-- Get or create player game state
local function getPlayerGameState(userId: number): PlayerGameState
  if not playerGameStates[userId] then
    playerGameStates[userId] = createPlayerGameState()
  end
  return playerGameStates[userId]
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

  -- Clean up player game state
  playerGameStates[player.UserId] = nil
end)

print("Server started. Clamp demo:", Util.clamp(10, 0, 5))
print("[Main.server] " .. RemoteSetup.getSummary())
print("[Main.server] " .. MapGeneration.getSummary(mapState))

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

    -- 1. Update chicken money generation
    local moneyGenerated = MoneyCollection.updateAllChickenMoney(playerData, deltaTime)
    if moneyGenerated > 0 then
      dataChanged = true
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
          predatorSpawnedEvent:FireClient(player, {
            predator = result.predator,
            message = result.message,
          })
        end
      end
    end

    -- 5. Update predator states (transition spawning -> approaching -> attacking)
    local nowAttacking = PredatorAttack.updatePredatorStates(gameState.spawnState, currentTime)

    -- 6. Execute attacks for predators that just started attacking
    for _, predatorId in ipairs(nowAttacking) do
      local attackResult =
        PredatorAttack.executeAttack(playerData, gameState.spawnState, predatorId)
      if attackResult.success and attackResult.chickensLost > 0 then
        dataChanged = true
        -- Notify player of attack
        local alertEvent = RemoteSetup.getEvent("AlertTriggered")
        if alertEvent then
          local predator = PredatorSpawning.findPredator(gameState.spawnState, predatorId)
          if predator then
            local alert = PredatorAttack.generateAlert(predator, "attacking")
            alertEvent:FireClient(player, alert)
          end
        end

        -- If predator escaped after attack, notify
        if attackResult.predatorEscaped then
          local predatorDefeatedEvent = RemoteSetup.getEvent("PredatorDefeated")
          if predatorDefeatedEvent then
            predatorDefeatedEvent:FireClient(player, {
              escaped = true,
              message = attackResult.message,
            })
          end
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
end

-- Start the game loop
gameLoopConnection = RunService.Heartbeat:Connect(runGameLoop)
print("[Main.server] Game loop started")
