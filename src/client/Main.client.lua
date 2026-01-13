--[[
	Main Client Script
	Wires up all RemoteEvent listeners and initializes client-side systems.
	Handles server event responses and updates local state/visuals accordingly.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Get client modules
local ClientModules = script.Parent
local SoundEffects = require(ClientModules:WaitForChild("SoundEffects"))
local ChickenVisuals = require(ClientModules:WaitForChild("ChickenVisuals"))
local PredatorVisuals = require(ClientModules:WaitForChild("PredatorVisuals"))
local EggVisuals = require(ClientModules:WaitForChild("EggVisuals"))
local MainHUD = require(ClientModules:WaitForChild("MainHUD"))
local ChickenPickup = require(ClientModules:WaitForChild("ChickenPickup"))
local ChickenSelling = require(ClientModules:WaitForChild("ChickenSelling"))
local InventoryUI = require(ClientModules:WaitForChild("InventoryUI"))
local HatchPreviewUI = require(ClientModules:WaitForChild("HatchPreviewUI"))
local Tutorial = require(ClientModules:WaitForChild("Tutorial"))
local SectionVisuals = require(ClientModules:WaitForChild("SectionVisuals"))

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

-- Create Inventory UI
InventoryUI.create()
print("[Client] InventoryUI created")

-- Create Hatch Preview UI
HatchPreviewUI.create()
print("[Client] HatchPreviewUI created")

-- Create Tutorial UI
Tutorial.create()
print("[Client] Tutorial created")

-- Track placed egg for hatching flow
local placedEggData: { id: string, eggType: string, spotIndex: number }? = nil

-- Request initial player data from server
local getPlayerDataFunc = getFunction("GetPlayerData")
if getPlayerDataFunc then
  local initialData = getPlayerDataFunc:InvokeServer()
  if initialData then
    playerDataCache = initialData
    MainHUD.updateFromPlayerData(initialData)
    InventoryUI.updateFromPlayerData(initialData)

    print("[Client] Got initial data, sectionIndex =", initialData.sectionIndex)

    -- Build section visuals for player's assigned section
    if initialData.sectionIndex then
      -- Get occupied spots from placed chickens
      local occupiedSpots: { [number]: boolean } = {}
      if initialData.placedChickens then
        for _, chicken in ipairs(initialData.placedChickens) do
          if chicken.spotIndex then
            occupiedSpots[chicken.spotIndex] = true
          end
        end
      end
      SectionVisuals.buildSection(initialData.sectionIndex, occupiedSpots)
      print("[Client] Section visuals built for section", initialData.sectionIndex)
      
      -- Build the central store (shared by all players)
      SectionVisuals.buildCentralStore()
    else
      warn("[Client] No sectionIndex in player data - cannot build section visuals")
    end

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
    
    -- Start tutorial for new players
    if Tutorial.shouldShowTutorial(initialData) then
      Tutorial.start()
      print("[Client] Tutorial started for new player")
    end
  end
end

--[[ RemoteEvent Listeners ]]

-- PlayerDataChanged: Update local player data cache, HUD, inventory, and chicken money indicators
local playerDataChangedEvent = getEvent("PlayerDataChanged")
if playerDataChangedEvent then
  playerDataChangedEvent.OnClientEvent:Connect(function(data: { [string]: any })
    playerDataCache = data
    -- Update MainHUD with new money data
    MainHUD.updateFromPlayerData(data)
    -- Update InventoryUI with new inventory data
    InventoryUI.updateFromPlayerData(data)

    -- Build section visuals if we have a section index but haven't built yet
    if data.sectionIndex and not SectionVisuals.getCurrentSection() then
      local occupiedSpots: { [number]: boolean } = {}
      if data.placedChickens then
        for _, chicken in ipairs(data.placedChickens) do
          if chicken.spotIndex then
            occupiedSpots[chicken.spotIndex] = true
          end
        end
      end
      SectionVisuals.buildSection(data.sectionIndex, occupiedSpots)
      print("[Client] Section visuals built from PlayerDataChanged for section", data.sectionIndex)
      
      -- Build the central store (shared by all players)
      SectionVisuals.buildCentralStore()
    else
      -- Update section spot visuals based on placed chickens
      SectionVisuals.updateAllSpots(data.placedChickens)
    end

    -- Update chicken money indicators from placed chickens
    if data.placedChickens then
      for _, chicken in ipairs(data.placedChickens) do
        ChickenVisuals.updateMoney(chicken.id, chicken.accumulatedMoney or 0)
      end
    end
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
  chickenPickedUpEvent.OnClientEvent:Connect(function(data: any)
    -- Handle both formats: string (chickenId) or table ({ chickenId, playerId, spotIndex })
    local chickenId: string
    local spotIndex: number?
    
    if type(data) == "string" then
      chickenId = data
    elseif type(data) == "table" then
      chickenId = data.chickenId
      spotIndex = data.spotIndex
    else
      warn("[Client] ChickenPickedUp: Invalid data format")
      return
    end
    
    ChickenVisuals.destroy(chickenId)
    SoundEffects.play("chickenPickup")
    
    -- Update the spot to show as available
    if spotIndex then
      SectionVisuals.updateSpotOccupancy(spotIndex, false)
    end
    
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
    -- Complete tutorial step if active
    if Tutorial.isActive() then
      Tutorial.completeStep("collect_money")
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

--[[ Client Game Loop ]]

-- Configuration for game loop updates
local PROXIMITY_CHECK_INTERVAL = 0.1 -- How often to check proximity (seconds)
local LOCK_TIMER_UPDATE_INTERVAL = 1.0 -- How often to update lock timer display
local MONEY_COLLECTION_COOLDOWN = 0.5 -- Cooldown between collections from same chicken

-- Tracking variables
local lastProximityCheckTime = 0
local lastLockTimerUpdateTime = 0
local isNearChicken = false
local nearestChickenId: string? = nil
local nearestChickenType: string? = nil
local lastCollectedChickenTimes: { [string]: number } = {} -- Track when each chicken was last collected

--[[
	Helper function to find the nearest placed chicken within pickup range.
	Returns chickenId, spotIndex, chickenType, rarity, accumulatedMoney or nil.
]]
local function findNearbyPlacedChicken(
  playerPosition: Vector3
): (string?, number?, string?, string?, number?)
  if not playerDataCache or not playerDataCache.placedChickens then
    return nil, nil, nil, nil, nil
  end

  local pickupRange = ChickenPickup.getPickupRange()
  local nearestDistance = pickupRange
  local nearestChicken = nil
  local nearestSpot = nil

  for _, chicken in ipairs(playerDataCache.placedChickens) do
    if chicken.spotIndex then
      local chickenPos = getChickenPosition(chicken.spotIndex)
      if chickenPos then
        local distance = (playerPosition - chickenPos).Magnitude
        if distance < nearestDistance then
          nearestDistance = distance
          nearestChicken = chicken
          nearestSpot = chicken.spotIndex
        end
      end
    end
  end

  if nearestChicken then
    -- Get real-time accumulated money from ChickenVisuals, not stale cache
    local realTimeAccumulatedMoney = ChickenVisuals.getAccumulatedMoney(nearestChicken.id)
    return nearestChicken.id,
      nearestSpot,
      nearestChicken.chickenType,
      nearestChicken.rarity,
      realTimeAccumulatedMoney
  end

  return nil, nil, nil, nil, nil
end

--[[
	Helper function to find an available coop spot near the player.
	Returns spotIndex or nil.
]]
local function findNearbyAvailableSpot(playerPosition: Vector3): number?
  if not playerDataCache then
    return nil
  end

  local sectionIndex = playerDataCache.sectionIndex
  if not sectionIndex then
    return nil
  end

  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    return nil
  end

  -- Check which spots are occupied
  local occupiedSpots: { [number]: boolean } = {}
  if playerDataCache.placedChickens then
    for _, chicken in ipairs(playerDataCache.placedChickens) do
      if chicken.spotIndex then
        occupiedSpots[chicken.spotIndex] = true
      end
    end
  end

  -- Find closest unoccupied spot
  local placeRange = ChickenPickup.getPickupRange() -- Use same range for placing
  local nearestDistance = placeRange
  local nearestSpot = nil

  local totalSpots = PlayerSection.getMaxSpots()
  for spotIndex = 1, totalSpots do
    if not occupiedSpots[spotIndex] then
      local spotPos = PlayerSection.getSpotPosition(spotIndex, sectionCenter)
      if spotPos then
        local spotVec = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
        local distance = (playerPosition - spotVec).Magnitude
        if distance < nearestDistance then
          nearestDistance = distance
          nearestSpot = spotIndex
        end
      end
    end
  end

  return nearestSpot
end

-- Wire up ChickenPickup callbacks for proximity checking
ChickenPickup.create()
ChickenPickup.setGetNearbyChicken(function(position: Vector3): (string?, number?)
  local chickenId, spotIndex = findNearbyPlacedChicken(position)
  return chickenId, spotIndex
end)
ChickenPickup.setGetAvailableSpot(function(position: Vector3): number?
  return findNearbyAvailableSpot(position)
end)
ChickenPickup.setGetPlayerData(function()
  return playerDataCache
end)
print("[Client] ChickenPickup system initialized")

-- Wire up ChickenSelling callbacks for proximity checking
ChickenSelling.create()
ChickenSelling.setGetNearbyChicken(function(position: Vector3)
  return findNearbyPlacedChicken(position)
end)
ChickenSelling.setGetPlayerData(function()
  return playerDataCache
end)
print("[Client] ChickenSelling system initialized")

-- Wire InventoryUI callbacks for item actions (after helper functions are defined)
InventoryUI.onItemSelected(function(selectedItem)
  if selectedItem then
    print("[Client] Inventory item selected:", selectedItem.itemType, selectedItem.itemId)
  else
    print("[Client] Inventory selection cleared")
  end
end)

InventoryUI.onAction(function(actionType: string, selectedItem)
  print("[Client] Inventory action:", actionType, selectedItem.itemType, selectedItem.itemId)

  if selectedItem.itemType == "egg" then
    if actionType == "place" then
      -- Place egg in coop spot and show hatch preview
      local character = localPlayer.Character
      if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
          local spotIndex = findNearbyAvailableSpot(rootPart.Position)
          if spotIndex then
            -- Store the egg data for when user confirms hatch
            placedEggData = {
              id = selectedItem.itemId,
              eggType = selectedItem.itemData.eggType,
              spotIndex = spotIndex,
            }
            -- Show hatch preview UI
            HatchPreviewUI.show(selectedItem.itemId, selectedItem.itemData.eggType)
            SoundEffects.play("eggPlace")
            InventoryUI.clearSelection()
            -- Complete tutorial step if active
            if Tutorial.isActive() then
              Tutorial.completeStep("place_egg")
            end
            print("[Client] Egg placed, showing hatch preview")
          else
            SoundEffects.play("uiError")
            warn("[Client] No available spot nearby")
          end
        end
      end
    elseif actionType == "sell" then
      -- Sell egg via server
      local sellEggFunc = getFunction("SellEgg")
      if sellEggFunc then
        local result = sellEggFunc:InvokeServer(selectedItem.itemId)
        if result and result.success then
          SoundEffects.playMoneyCollect(result.sellPrice or 0)
          InventoryUI.clearSelection()
        else
          SoundEffects.play("uiError")
          warn("[Client] Egg sell failed:", result and result.error or "Unknown error")
        end
      end
    end
  elseif selectedItem.itemType == "chicken" then
    if actionType == "place" then
      -- Place chicken from inventory to coop
      local placeChickenFunc = getFunction("PlaceChicken")
      if placeChickenFunc then
        -- Find available spot near player
        local character = localPlayer.Character
        if character then
          local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
          if rootPart then
            local spotIndex = findNearbyAvailableSpot(rootPart.Position)
            if spotIndex then
              local result = placeChickenFunc:InvokeServer(selectedItem.itemId, spotIndex)
              if result and result.success then
                SoundEffects.play("chickenPlace")
                InventoryUI.clearSelection()
              else
                SoundEffects.play("uiError")
                warn("[Client] Place failed:", result and result.error or "Unknown error")
              end
            else
              SoundEffects.play("uiError")
              warn("[Client] No available spot nearby")
            end
          end
        end
      end
    elseif actionType == "sell" then
      -- Sell chicken from inventory via server
      local sellChickenFunc = getFunction("SellChicken")
      if sellChickenFunc then
        local result = sellChickenFunc:InvokeServer(selectedItem.itemId, true) -- true = from inventory
        if result and result.success then
          SoundEffects.playMoneyCollect(result.sellPrice or 0)
          InventoryUI.clearSelection()
        else
          SoundEffects.play("uiError")
          warn("[Client] Sell failed:", result and result.error or "Unknown error")
        end
      end
    end
  end
end)
print("[Client] InventoryUI callbacks wired")

-- Wire up HatchPreviewUI callbacks for egg hatching
HatchPreviewUI.onHatch(function(eggId: string, eggType: string)
  print("[Client] Hatch confirmed for egg:", eggId, eggType)
  
  if not placedEggData or placedEggData.id ~= eggId then
    warn("[Client] Placed egg data mismatch")
    return
  end
  
  -- Hatch egg via server with the spot index
  local hatchEggFunc = getFunction("HatchEgg")
  if hatchEggFunc then
    local result = hatchEggFunc:InvokeServer(eggId, placedEggData.spotIndex)
    if result and result.success then
      SoundEffects.playEggHatch(result.rarity or "Common")
      -- Complete tutorial step if active
      if Tutorial.isActive() then
        Tutorial.completeStep("hatch_egg")
      end
      print("[Client] Egg hatched successfully:", result.chickenType, result.rarity)
      
      -- Show the result screen with what they got
      HatchPreviewUI.showResult(result.chickenType, result.rarity)
    else
      SoundEffects.play("uiError")
      warn("[Client] Hatch failed:", result and result.error or "Unknown error")
    end
  end
  
  -- Clear placed egg data
  placedEggData = nil
end)

HatchPreviewUI.onCancel(function()
  print("[Client] Hatch cancelled")
  -- Clear placed egg data
  placedEggData = nil
end)
print("[Client] HatchPreviewUI callbacks wired")

-- Wire up Tutorial callbacks
Tutorial.onComplete(function()
  print("[Client] Tutorial completed")
  -- Notify server to mark tutorial as complete
  local completeTutorialEvent = getEvent("CompleteTutorial")
  if completeTutorialEvent then
    completeTutorialEvent:FireServer()
  end
end)

Tutorial.onSkip(function()
  print("[Client] Tutorial skipped")
  -- Notify server to mark tutorial as complete (skipped counts as complete)
  local completeTutorialEvent = getEvent("CompleteTutorial")
  if completeTutorialEvent then
    completeTutorialEvent:FireServer()
  end
end)

Tutorial.onStepComplete(function(stepId: string)
  print("[Client] Tutorial step completed:", stepId)
end)
print("[Client] Tutorial callbacks wired")

-- Wire up InventoryUI visibility callback for tutorial
InventoryUI.onVisibilityChanged(function(visible: boolean)
  if visible and Tutorial.isActive() then
    Tutorial.completeStep("inventory_intro")
  end
end)

-- Setup keyboard input for inventory toggle (I key)
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end
  
  if input.KeyCode == Enum.KeyCode.I then
    InventoryUI.toggle()
  end
end)
print("[Client] Inventory toggle key binding (I) set up")

--[[
	Updates lock timer display on the HUD if player has an active lock.
	Calculates remaining time from lockEndTime in player data.
]]
local function updateLockTimerDisplay()
  if not playerDataCache or not playerDataCache.lockEndTime then
    return
  end

  local currentTime = os.time()
  local lockEndTime = playerDataCache.lockEndTime

  if currentTime < lockEndTime then
    local remainingSeconds = lockEndTime - currentTime
    -- MainHUD could have a setLockTimer function - log for now
    -- TODO: MainHUD.setLockTimer(remainingSeconds) when MainHUD supports it
    if remainingSeconds > 0 and remainingSeconds % 10 == 0 then
      -- Log every 10 seconds to avoid spam
      print("[Client] Lock timer:", remainingSeconds, "seconds remaining")
    end
  end
end

--[[
	Updates proximity-based prompts based on player position.
	Shows pickup prompt when near a placed chicken (and not holding).
	Shows sell prompt when near a placed chicken with money (and not holding).
	Shows place prompt when holding and near an available spot.
]]
local function updateProximityPrompts()
  local character = localPlayer.Character
  if not character then
    return
  end

  local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not rootPart then
    return
  end

  local playerPosition = rootPart.Position

  -- Check if holding a chicken
  local isHoldingChicken = ChickenPickup.isHolding()

  if isHoldingChicken then
    -- When holding, check for available spots to place
    local availableSpot = findNearbyAvailableSpot(playerPosition)
    if availableSpot then
      ChickenPickup.showPlacePrompt()
    else
      ChickenPickup.hidePrompt()
    end
    ChickenSelling.hidePrompt()
  else
    -- When not holding, check for nearby chickens
    local chickenId, spotIndex, chickenType, _, accumulatedMoney =
      findNearbyPlacedChicken(playerPosition)

    if chickenId then
      isNearChicken = true
      nearestChickenId = chickenId
      nearestChickenType = chickenType

      -- Auto-collect money when near a chicken with at least $1 accumulated
      if accumulatedMoney and accumulatedMoney >= 1 then
        local currentTime = os.clock()
        local lastCollectTime = lastCollectedChickenTimes[chickenId] or 0
        
        -- Check cooldown to prevent spam
        if currentTime - lastCollectTime >= MONEY_COLLECTION_COOLDOWN then
          lastCollectedChickenTimes[chickenId] = currentTime
          
          -- Call server to collect money from this specific chicken
          local collectMoneyFunc = getFunction("CollectMoney")
          if collectMoneyFunc then
            -- Run in a separate thread to not block the game loop
            task.spawn(function()
              local result = collectMoneyFunc:InvokeServer(chickenId)
              if result and result.success and result.amountCollected and result.amountCollected > 0 then
                -- Reset client-side accumulated money to the remainder
                ChickenVisuals.resetAccumulatedMoney(chickenId, result.remainder or 0)
                
                -- Play collection sound and show visual effect
                SoundEffects.playMoneyCollect(result.amountCollected)
                local chickenPos = getChickenPosition(spotIndex)
                if chickenPos then
                  ChickenVisuals.createMoneyPopEffect({
                    amount = result.amountCollected,
                    position = chickenPos + Vector3.new(0, 2, 0),
                    isLarge = result.amountCollected >= 1000,
                  })
                end
                -- Complete tutorial step if active
                if Tutorial.isActive() then
                  Tutorial.completeStep("collect_money")
                end
              end
            end)
          end
        end
      end

      -- Show pickup prompt
      ChickenPickup.showPickupPrompt()

      -- Hide sell prompt (we auto-collect now)
      ChickenSelling.hidePrompt()
    else
      if isNearChicken then
        -- Was near, now not - hide prompts
        ChickenPickup.hidePrompt()
        ChickenSelling.hidePrompt()
      end
      isNearChicken = false
      nearestChickenId = nil
      nearestChickenType = nil
    end
  end
end

--[[
	Client game loop - runs every frame via Heartbeat.
	Handles periodic updates that need to be smooth or responsive.
]]
local gameLoopConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
  local currentTime = os.clock()

  -- Proximity check for prompts (throttled for performance)
  if currentTime - lastProximityCheckTime >= PROXIMITY_CHECK_INTERVAL then
    lastProximityCheckTime = currentTime
    updateProximityPrompts()
  end

  -- Lock timer display update (less frequent)
  if currentTime - lastLockTimerUpdateTime >= LOCK_TIMER_UPDATE_INTERVAL then
    lastLockTimerUpdateTime = currentTime
    updateLockTimerDisplay()
  end
end)

print("[Client] Client game loop started")
