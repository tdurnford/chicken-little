--[[
	Main Client Script
	Wires up all RemoteEvent listeners and initializes client-side systems.
	Handles server event responses and updates local state/visuals accordingly.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get client modules
local ClientModules = script.Parent
local SoundEffects = require(ClientModules:WaitForChild("SoundEffects"))
local ChickenVisuals = require(ClientModules:WaitForChild("ChickenVisuals"))
local PredatorVisuals = require(ClientModules:WaitForChild("PredatorVisuals"))
local EggVisuals = require(ClientModules:WaitForChild("EggVisuals"))
local MainHUD = require(ClientModules:WaitForChild("MainHUD"))

-- Get shared modules for position calculations
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Local state cache for player data
local playerDataCache: { [string]: any } = {}

-- Wait for Remotes folder from server
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
  warn("[Client] Remotes folder not found in ReplicatedStorage")
  return
end

-- Helper to get RemoteEvent safely
local function getEvent(name: string): RemoteEvent?
  local event = Remotes:FindFirstChild(name)
  if event and event:IsA("RemoteEvent") then
    return event :: RemoteEvent
  end
  warn("[Client] RemoteEvent not found:", name)
  return nil
end

-- Helper to get RemoteFunction safely
local function getFunction(name: string): RemoteFunction?
  local func = Remotes:FindFirstChild(name)
  if func and func:IsA("RemoteFunction") then
    return func :: RemoteFunction
  end
  warn("[Client] RemoteFunction not found:", name)
  return nil
end

-- Helper to calculate chicken position from spotIndex using player's section
local function getChickenPosition(spotIndex: number): Vector3?
  local sectionIndex = playerDataCache.sectionIndex
  if not sectionIndex then
    return nil
  end

  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    return nil
  end

  local spotPos = PlayerSection.getSpotPosition(spotIndex, sectionCenter)
  if not spotPos then
    return nil
  end

  return Vector3.new(spotPos.x, spotPos.y, spotPos.z)
end

-- Initialize client systems
SoundEffects.initialize()
print("[Client] SoundEffects initialized")

-- Create Main HUD
MainHUD.create()
print("[Client] MainHUD created")

-- Request initial player data from server
local getPlayerDataFunc = getFunction("GetPlayerData")
if getPlayerDataFunc then
  local initialData = getPlayerDataFunc:InvokeServer()
  if initialData then
    playerDataCache = initialData
    MainHUD.updateFromPlayerData(initialData)

    -- Create initial chicken visuals for placed chickens
    if initialData.placedChickens then
      for _, chicken in ipairs(initialData.placedChickens) do
        if chicken.spotIndex then
          local position = getChickenPosition(chicken.spotIndex)
          if position then
            ChickenVisuals.create(chicken.id, chicken.chickenType, position, chicken.spotIndex)
            ChickenVisuals.updateMoney(chicken.id, chicken.accumulatedMoney or 0)
          end
        end
      end
    end

    print("[Client] Initial player data loaded")
  end
end

--[[ RemoteEvent Listeners ]]

-- PlayerDataChanged: Update local player data cache, HUD, and chicken money indicators
local playerDataChangedEvent = getEvent("PlayerDataChanged")
if playerDataChangedEvent then
  playerDataChangedEvent.OnClientEvent:Connect(function(data: { [string]: any })
    playerDataCache = data
    -- Update MainHUD with new money data
    MainHUD.updateFromPlayerData(data)

    -- Update chicken money indicators from placed chickens
    if data.placedChickens then
      for _, chicken in ipairs(data.placedChickens) do
        ChickenVisuals.updateMoney(chicken.id, chicken.accumulatedMoney or 0)
      end
    end

    print("[Client] Player data updated")
  end)
end

-- ChickenPlaced: Create chicken visual at position
local chickenPlacedEvent = getEvent("ChickenPlaced")
if chickenPlacedEvent then
  chickenPlacedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chicken = eventData.chicken
    local spotIndex = eventData.spotIndex
    if not chicken or not spotIndex then
      warn("[Client] ChickenPlaced: Invalid event data")
      return
    end

    local position = getChickenPosition(spotIndex)
    if position then
      ChickenVisuals.create(chicken.id, chicken.chickenType, position, spotIndex)
      SoundEffects.play("chickenPlace")
      print("[Client] Chicken placed:", chicken.id)
    end
  end)
end

-- ChickenPickedUp: Remove chicken visual
local chickenPickedUpEvent = getEvent("ChickenPickedUp")
if chickenPickedUpEvent then
  chickenPickedUpEvent.OnClientEvent:Connect(function(chickenId: string)
    ChickenVisuals.destroy(chickenId)
    SoundEffects.play("chickenPickup")
    print("[Client] Chicken picked up:", chickenId)
  end)
end

-- ChickenSold: Remove chicken visual and play sell sound
local chickenSoldEvent = getEvent("ChickenSold")
if chickenSoldEvent then
  chickenSoldEvent.OnClientEvent:Connect(function(chickenId: string, sellPrice: number)
    ChickenVisuals.destroy(chickenId)
    SoundEffects.playMoneyCollect(sellPrice)
    print("[Client] Chicken sold:", chickenId, "for", sellPrice)
  end)
end

-- EggHatched: Show hatch animation and result
local eggHatchedEvent = getEvent("EggHatched")
if eggHatchedEvent then
  eggHatchedEvent.OnClientEvent:Connect(function(eggId: string, chickenType: string, rarity: string)
    EggVisuals.playHatchAnimation(eggId)
    SoundEffects.playEggHatch(rarity)
    print("[Client] Egg hatched:", eggId, "->", chickenType, rarity)
  end)
end

-- EggLaid: Play laying animation and create egg visual
local eggLaidEvent = getEvent("EggLaid")
if eggLaidEvent then
  eggLaidEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local eggId = eventData.eggId
    local eggRarity = eventData.eggRarity

    -- Play laying animation on the chicken
    if chickenId then
      ChickenVisuals.playLayingAnimation(chickenId)
    end

    SoundEffects.play("eggPlace")
    print("[Client] Egg laid:", eggId, "from chicken", chickenId)
  end)
end

-- MoneyCollected: Play money collection effects
local moneyCollectedEvent = getEvent("MoneyCollected")
if moneyCollectedEvent then
  moneyCollectedEvent.OnClientEvent:Connect(function(amount: number, position: Vector3?)
    SoundEffects.playMoneyCollect(amount)
    if position then
      ChickenVisuals.createMoneyPopEffect({
        amount = amount,
        position = position,
        isLarge = amount >= 1000,
      })
    end
    print("[Client] Money collected:", amount)
  end)
end

-- TrapPlaced: Visual feedback for trap placement
local trapPlacedEvent = getEvent("TrapPlaced")
if trapPlacedEvent then
  trapPlacedEvent.OnClientEvent:Connect(
    function(trapId: string, trapType: string, position: Vector3)
      SoundEffects.play("trapPlace")
      print("[Client] Trap placed:", trapId, trapType, "at", position)
    end
  )
end

-- TrapCaught: Update trap visual to show caught predator
local trapCaughtEvent = getEvent("TrapCaught")
if trapCaughtEvent then
  trapCaughtEvent.OnClientEvent:Connect(function(trapId: string, predatorId: string)
    PredatorVisuals.playTrappedAnimation(predatorId)
    SoundEffects.play("trapCatch")
    print("[Client] Trap caught predator:", trapId, predatorId)
  end)
end

-- PredatorSpawned: Create predator visual
local predatorSpawnedEvent = getEvent("PredatorSpawned")
if predatorSpawnedEvent then
  predatorSpawnedEvent.OnClientEvent:Connect(
    function(predatorId: string, predatorType: string, threatLevel: string, position: Vector3)
      PredatorVisuals.create(predatorId, predatorType, threatLevel, position)
      SoundEffects.playPredatorAlert(threatLevel == "Deadly" or threatLevel == "Catastrophic")
      print("[Client] Predator spawned:", predatorId, predatorType, threatLevel)
    end
  )
end

-- PredatorDefeated: Play defeated animation and remove
local predatorDefeatedEvent = getEvent("PredatorDefeated")
if predatorDefeatedEvent then
  predatorDefeatedEvent.OnClientEvent:Connect(function(predatorId: string, byPlayer: boolean)
    PredatorVisuals.playDefeatedAnimation(predatorId)
    if byPlayer then
      SoundEffects.playBatSwing("predator")
    end
    print("[Client] Predator defeated:", predatorId)
  end)
end

-- LockActivated: Visual/audio feedback for cage lock
local lockActivatedEvent = getEvent("LockActivated")
if lockActivatedEvent then
  lockActivatedEvent.OnClientEvent:Connect(function(cageId: string, lockDuration: number)
    SoundEffects.play("lockActivate")
    print("[Client] Lock activated:", cageId, "for", lockDuration, "seconds")
  end)
end

-- TradeRequested: Notification for incoming trade request
local tradeRequestedEvent = getEvent("TradeRequested")
if tradeRequestedEvent then
  tradeRequestedEvent.OnClientEvent:Connect(function(fromPlayer: Player, tradeId: string)
    SoundEffects.play("uiNotification")
    print("[Client] Trade requested from:", fromPlayer.Name, tradeId)
  end)
end

-- TradeUpdated: Update trade UI state
local tradeUpdatedEvent = getEvent("TradeUpdated")
if tradeUpdatedEvent then
  tradeUpdatedEvent.OnClientEvent:Connect(function(tradeId: string, tradeData: { [string]: any })
    print("[Client] Trade updated:", tradeId, tradeData)
  end)
end

-- TradeCompleted: Trade finished successfully
local tradeCompletedEvent = getEvent("TradeCompleted")
if tradeCompletedEvent then
  tradeCompletedEvent.OnClientEvent:Connect(function(tradeId: string, success: boolean)
    if success then
      SoundEffects.play("tradeComplete")
    else
      SoundEffects.play("uiError")
    end
    print("[Client] Trade completed:", tradeId, success)
  end)
end

-- RandomChickenSpawned: Show notification for random chicken
local randomChickenSpawnedEvent = getEvent("RandomChickenSpawned")
if randomChickenSpawnedEvent then
  randomChickenSpawnedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chicken = eventData.chicken
    if not chicken then
      warn("[Client] RandomChickenSpawned: Invalid event data")
      return
    end

    SoundEffects.play("uiNotification")
    local pos = chicken.position
    local position = Vector3.new(pos.x, pos.y, pos.z)
    ChickenVisuals.create(chicken.id, chicken.chickenType, position, nil)
    print("[Client] Random chicken spawned:", chicken.id, chicken.chickenType, chicken.rarity)
  end)
end

-- RandomChickenClaimed: Player claimed the random chicken
local randomChickenClaimedEvent = getEvent("RandomChickenClaimed")
if randomChickenClaimedEvent then
  randomChickenClaimedEvent.OnClientEvent:Connect(function(chickenId: string, claimedBy: Player)
    local chicken = ChickenVisuals.get(chickenId)
    if chicken then
      ChickenVisuals.playCelebrationAnimation(chickenId)
    end
    if claimedBy == localPlayer then
      SoundEffects.play("chickenClaim")
    end
    print("[Client] Random chicken claimed:", chickenId, "by", claimedBy.Name)
  end)
end

-- AlertTriggered: Play alert sound
local alertTriggeredEvent = getEvent("AlertTriggered")
if alertTriggeredEvent then
  alertTriggeredEvent.OnClientEvent:Connect(function(alertType: string, urgent: boolean)
    SoundEffects.playPredatorAlert(urgent)
    print("[Client] Alert triggered:", alertType, urgent)
  end)
end

--[[ Utility Functions for other modules ]]

-- Expose player data cache getter
local function getPlayerData(): { [string]: any }
  return playerDataCache
end

-- Expose remote function invoker
local function invokeServer(funcName: string, ...: any): any
  local func = getFunction(funcName)
  if func then
    return func:InvokeServer(...)
  end
  return nil
end

-- Module exports for other client scripts
local ClientMain = {
  getPlayerData = getPlayerData,
  invokeServer = invokeServer,
  getEvent = getEvent,
  getFunction = getFunction,
}

-- Store in ReplicatedStorage for other client modules to access
local clientMainValue = Instance.new("ObjectValue")
clientMainValue.Name = "ClientMainRef"
clientMainValue.Parent = localPlayer

print("[Client] Started - RemoteEvent listeners connected")
