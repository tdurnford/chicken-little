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
local PredatorHealthBar = require(ClientModules:WaitForChild("PredatorHealthBar"))
local EggVisuals = require(ClientModules:WaitForChild("EggVisuals"))
local MainHUD = require(ClientModules:WaitForChild("MainHUD"))
local ChickenPickup = require(ClientModules:WaitForChild("ChickenPickup"))
local ChickenSelling = require(ClientModules:WaitForChild("ChickenSelling"))
local InventoryUI = require(ClientModules:WaitForChild("InventoryUI"))
local HatchPreviewUI = require(ClientModules:WaitForChild("HatchPreviewUI"))
local Tutorial = require(ClientModules:WaitForChild("Tutorial"))
local SectionVisuals = require(ClientModules:WaitForChild("SectionVisuals"))
local StoreUI = require(ClientModules:WaitForChild("StoreUI"))

-- Get shared modules for position calculations
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Local state cache for player data
local playerDataCache: { [string]: any } = {}

-- Local bat state for client-side tracking
local localBatState = BaseballBat.createBatState()

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

-- Create Store UI
StoreUI.create()
print("[Client] StoreUI created")

-- Create Tutorial UI
Tutorial.create()
print("[Client] Tutorial created")

-- Create Random Chicken Claim Prompt UI
local randomChickenPromptFrame: Frame? = nil
local randomChickenPromptLabel: TextLabel? = nil

local function createRandomChickenPromptUI()
  local screenGui = MainHUD.getScreenGui()
  if not screenGui then
    warn("[Client] Cannot create random chicken prompt - no ScreenGui")
    return
  end

  local frame = Instance.new("Frame")
  frame.Name = "RandomChickenClaimPrompt"
  frame.AnchorPoint = Vector2.new(0.5, 1)
  frame.Size = UDim2.new(0, 180, 0, 40)
  frame.Position = UDim2.new(0.5, 0, 0.85, -20)
  frame.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
  frame.BackgroundTransparency = 0.3
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.ZIndex = 8
  frame.Parent = screenGui

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = frame

  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 200, 100)
  stroke.Thickness = 2
  stroke.Parent = frame

  local label = Instance.new("TextLabel")
  label.Name = "PromptLabel"
  label.Size = UDim2.new(1, -8, 1, 0)
  label.Position = UDim2.new(0, 4, 0, 0)
  label.BackgroundTransparency = 1
  label.Text = "[E] Claim Chicken"
  label.TextSize = 16
  label.TextColor3 = Color3.fromRGB(255, 255, 255)
  label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  label.ZIndex = 9
  label.Parent = frame

  randomChickenPromptFrame = frame
  randomChickenPromptLabel = label
  print("[Client] Random chicken claim prompt created")
end

local function showRandomChickenPrompt(chickenType: string)
  if randomChickenPromptFrame and randomChickenPromptLabel then
    randomChickenPromptLabel.Text = "[E] Claim " .. chickenType
    randomChickenPromptFrame.Visible = true
  end
end

local function hideRandomChickenPrompt()
  if randomChickenPromptFrame then
    randomChickenPromptFrame.Visible = false
  end
end

-- Delay creation until after MainHUD is ready
task.delay(0.1, createRandomChickenPromptUI)

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

    -- Update StoreUI with initial money
    StoreUI.updateMoney(initialData.money or 0)

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
    -- Update StoreUI with money balance
    StoreUI.updateMoney(data.money or 0)

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

-- PredatorSpawned: Create predator visual and health bar
local predatorSpawnedEvent = getEvent("PredatorSpawned")
if predatorSpawnedEvent then
  predatorSpawnedEvent.OnClientEvent:Connect(
    function(predatorId: string, predatorType: string, threatLevel: string, position: Vector3)
      local visualState = PredatorVisuals.create(predatorId, predatorType, threatLevel, position)
      -- Create health bar if visual was created successfully
      if visualState and visualState.model then
        PredatorHealthBar.create(predatorId, predatorType, threatLevel, visualState.model)
      end
      SoundEffects.playPredatorAlert(threatLevel == "Deadly" or threatLevel == "Catastrophic")
      print("[Client] Predator spawned:", predatorId, predatorType, threatLevel)
    end
  )
end

-- PredatorDefeated: Play defeated animation, remove visual and health bar
local predatorDefeatedEvent = getEvent("PredatorDefeated")
if predatorDefeatedEvent then
  predatorDefeatedEvent.OnClientEvent:Connect(function(predatorId: string, byPlayer: boolean)
    PredatorHealthBar.destroy(predatorId)
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
      -- Destroy after a short delay for animation to play
      task.delay(0.5, function()
        ChickenVisuals.destroy(chickenId)
      end)
    end
    if claimedBy == localPlayer then
      SoundEffects.play("chickenClaim")
      -- Hide the claim prompt for claiming player
      hideRandomChickenPrompt()
      isNearRandomChicken = false
      nearestRandomChickenId = nil
      nearestRandomChickenType = nil
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

-- Random chicken claiming state
local RANDOM_CHICKEN_CLAIM_RANGE = 8 -- studs, same as server-side claim range
local isNearRandomChicken = false
local nearestRandomChickenId: string? = nil
local nearestRandomChickenType: string? = nil
local randomChickenClaimPrompt: TextLabel? = nil

--[[
	Helper function to find the nearest random chicken within claim range.
	Random chickens have spotIndex = nil in ChickenVisuals.
	Returns chickenId, chickenType, position or nil.
]]
local function findNearbyRandomChicken(playerPosition: Vector3): (string?, string?, Vector3?)
  local allChickens = ChickenVisuals.getAll()
  local nearestDistance = RANDOM_CHICKEN_CLAIM_RANGE
  local nearestId: string? = nil
  local nearestType: string? = nil
  local nearestPos: Vector3? = nil

  for chickenId, state in pairs(allChickens) do
    -- Random chickens have spotIndex = nil
    if state.spotIndex == nil and state.position then
      local distance = (playerPosition - state.position).Magnitude
      if distance < nearestDistance then
        nearestDistance = distance
        nearestId = chickenId
        nearestType = state.chickenType
        nearestPos = state.position
      end
    end
  end

  return nearestId, nearestType, nearestPos
end

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
      -- Complete tutorial step if active (place_egg completes tutorial)
      if Tutorial.isActive() then
        Tutorial.completeStep("place_egg")
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

-- Wire up InventoryUI visibility callback
InventoryUI.onVisibilityChanged(function(visible: boolean)
  -- Reserved for future tutorial steps if needed
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
  Baseball Bat Visual Management
  Creates and manages the visual bat model on the player's character.
]]

-- Current bat model reference
local batModel: Model? = nil

-- Create a simple bat visual attached to the player's right hand
local function createBatVisual()
  local character = localPlayer.Character
  if not character then
    return
  end

  local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
  if not rightHand then
    return
  end

  -- Remove existing bat if any
  if batModel then
    batModel:Destroy()
    batModel = nil
  end

  -- Create a simple bat model (cylinder + handle)
  local bat = Instance.new("Model")
  bat.Name = "BaseballBat"

  -- Bat barrel (main part)
  local barrel = Instance.new("Part")
  barrel.Name = "Barrel"
  barrel.Size = Vector3.new(0.4, 2.5, 0.4)
  barrel.BrickColor = BrickColor.new("Brown")
  barrel.Material = Enum.Material.Wood
  barrel.CanCollide = false
  barrel.Anchored = false
  barrel.Parent = bat

  -- Bat handle
  local handle = Instance.new("Part")
  handle.Name = "Handle"
  handle.Size = Vector3.new(0.25, 1.0, 0.25)
  handle.BrickColor = BrickColor.new("Dark orange")
  handle.Material = Enum.Material.Wood
  handle.CanCollide = false
  handle.Anchored = false
  handle.Parent = bat

  -- Weld handle to barrel
  local handleWeld = Instance.new("Weld")
  handleWeld.Part0 = barrel
  handleWeld.Part1 = handle
  handleWeld.C0 = CFrame.new(0, -1.75, 0)
  handleWeld.Parent = barrel

  -- Weld bat to right hand
  local handWeld = Instance.new("Weld")
  handWeld.Part0 = rightHand
  handWeld.Part1 = barrel
  handWeld.C0 = CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(90), 0, math.rad(90))
  handWeld.Parent = rightHand

  bat.PrimaryPart = barrel
  bat.Parent = character

  batModel = bat
  print("[Client] Bat visual created")
end

-- Remove the bat visual from the player
local function removeBatVisual()
  if batModel then
    batModel:Destroy()
    batModel = nil
    print("[Client] Bat visual removed")
  end
end

-- Play bat swing animation (visual only)
local function playBatSwingAnimation()
  -- For now, just play a sound effect
  -- A full implementation would animate the character's arm
  SoundEffects.playBatSwing("miss") -- Initial swing sound (before we know if we hit)
end

--[[
  Bat Equipment and Swing Handlers
  Handles Q key for equip toggle and left mouse button for swinging.
]]

-- Toggle bat equip when Q is pressed
local function toggleBatEquip()
  local swingBatFunc = getFunction("SwingBat")
  if not swingBatFunc then
    warn("[Client] SwingBat RemoteFunction not found")
    return
  end

  local result = swingBatFunc:InvokeServer("toggle")
  if result and result.success then
    localBatState.isEquipped = result.isEquipped
    if result.isEquipped then
      createBatVisual()
      SoundEffects.playBatSwing("swing") -- Use bat swing sound for equip
    else
      removeBatVisual()
      SoundEffects.playBatSwing("miss") -- Use miss sound for unequip (softer)
    end
    print("[Client] Bat equipped:", result.isEquipped)
  end
end

-- Find the nearest predator targeting this player within bat range
local function findNearbyPredator(): (string?, number?)
  local character = localPlayer.Character
  if not character then
    return nil, nil
  end

  local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not rootPart then
    return nil, nil
  end

  local playerPosition = rootPart.Position
  local batConfig = BaseballBat.getConfig()
  local bestDistance = batConfig.swingRangeStuds
  local bestPredatorId: string? = nil

  -- Look for predator models in workspace
  local predatorsFolder = game.Workspace:FindFirstChild("Predators")
  if predatorsFolder then
    for _, predator in ipairs(predatorsFolder:GetChildren()) do
      if predator:IsA("Model") and predator.PrimaryPart then
        local distance = (predator.PrimaryPart.Position - playerPosition).Magnitude
        if distance <= bestDistance then
          bestDistance = distance
          bestPredatorId = predator.Name
        end
      end
    end
  end

  return bestPredatorId, bestDistance
end

-- Swing the bat when left mouse button is clicked
local function swingBat()
  if not localBatState.isEquipped then
    return
  end

  local swingBatFunc = getFunction("SwingBat")
  if not swingBatFunc then
    warn("[Client] SwingBat RemoteFunction not found")
    return
  end

  -- Check if we can swing (client-side cooldown check)
  local currentTime = os.clock()
  if not BaseballBat.canSwing(localBatState, currentTime) then
    return
  end

  -- Play swing animation immediately for responsiveness
  playBatSwingAnimation()
  BaseballBat.performSwing(localBatState, currentTime)

  -- Check for nearby predator targets
  local predatorId, distance = findNearbyPredator()

  local result
  if predatorId then
    result = swingBatFunc:InvokeServer("swing", "predator", predatorId)
    if result and result.success then
      -- Update health bar with remaining health
      if result.remainingHealth ~= nil then
        PredatorHealthBar.updateHealth(predatorId, result.remainingHealth)
      end
      if result.defeated then
        SoundEffects.playBatSwing("predator")
        print("[Client] Predator defeated! Reward:", result.rewardMoney)
      else
        SoundEffects.playBatSwing("hit")
        print("[Client] Hit predator:", predatorId, "Damage:", result.damage)
      end
    end
  else
    -- Swing and miss
    result = swingBatFunc:InvokeServer("swing", nil, nil)
    if result and result.success then
      SoundEffects.playBatSwing("miss")
    end
  end
end

-- Setup keyboard input for bat toggle (Q key)
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.KeyCode == Enum.KeyCode.Q then
    toggleBatEquip()
  end
end)
print("[Client] Bat toggle key binding (Q) set up")

-- Setup mouse input for bat swing (Left Mouse Button)
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.UserInputType == Enum.UserInputType.MouseButton1 then
    swingBat()
  end
end)
print("[Client] Bat swing mouse binding (Left Click) set up")

-- Listen for other players equipping/unequipping bats
local batEquippedEvent = getEvent("BatEquipped")
if batEquippedEvent then
  batEquippedEvent.OnClientEvent:Connect(function(player: Player, isEquipped: boolean)
    if player == localPlayer then
      return -- Already handled locally
    end

    -- For other players, we would create/remove their bat visual here
    -- This is a simplified version - full implementation would track per-player bat models
    print("[Client] Player", player.Name, "bat equipped:", isEquipped)
  end)
end

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
    hideRandomChickenPrompt()
    isNearRandomChicken = false
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
              if
                result
                and result.success
                and result.amountCollected
                and result.amountCollected > 0
              then
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
              end
            end)
          end
        end
      end

      -- Show pickup prompt
      ChickenPickup.showPickupPrompt()

      -- Hide sell prompt (we auto-collect now)
      ChickenSelling.hidePrompt()

      -- Hide random chicken prompt when near placed chicken
      hideRandomChickenPrompt()
      isNearRandomChicken = false
      nearestRandomChickenId = nil
      nearestRandomChickenType = nil
    else
      if isNearChicken then
        -- Was near, now not - hide prompts
        ChickenPickup.hidePrompt()
        ChickenSelling.hidePrompt()
      end
      isNearChicken = false
      nearestChickenId = nil
      nearestChickenType = nil

      -- Check for nearby random chickens (only when not near placed chicken)
      local randomChickenId, randomChickenType, _ = findNearbyRandomChicken(playerPosition)
      if randomChickenId then
        isNearRandomChicken = true
        nearestRandomChickenId = randomChickenId
        nearestRandomChickenType = randomChickenType
        showRandomChickenPrompt(randomChickenType or "Chicken")
      else
        if isNearRandomChicken then
          hideRandomChickenPrompt()
        end
        isNearRandomChicken = false
        nearestRandomChickenId = nil
        nearestRandomChickenType = nil
      end
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

--[[
  Store Interaction Setup
  Wires the store proximity prompt to open the store UI.
]]

-- Wire up store prompt triggered event
local function setupStoreInteraction()
  local store = SectionVisuals.getStore()
  if not store then
    -- Store might not be built yet, wait and retry
    task.delay(1, setupStoreInteraction)
    return
  end

  -- Find the StorePrompt in the store model
  local prompt = store:FindFirstChild("StorePrompt", true)
  if prompt and prompt:IsA("ProximityPrompt") then
    prompt.Triggered:Connect(function(playerWhoTriggered)
      if playerWhoTriggered == localPlayer then
        StoreUI.toggle()
      end
    end)
    print("[Client] Store prompt connected")
  else
    warn("[Client] StorePrompt not found in store model")
  end
end

-- Setup store interaction after a delay to ensure store is built
task.delay(0.5, setupStoreInteraction)

-- Wire up store purchase callback
StoreUI.onPurchase(function(eggType: string, quantity: number)
  local buyEggFunc = getFunction("BuyEgg")
  if not buyEggFunc then
    warn("[Client] BuyEgg RemoteFunction not found")
    return
  end

  local result = buyEggFunc:InvokeServer(eggType, quantity)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Purchased", quantity, "x", eggType, ":", result.message)
      -- Complete tutorial step if active
      if Tutorial.isActive() then
        Tutorial.completeStep("buy_egg")
      end
    else
      SoundEffects.play("uiError")
      warn("[Client] Purchase failed:", result.message)
    end
  end
end)

-- Wire up store chicken purchase callback
StoreUI.onChickenPurchase(function(chickenType: string, quantity: number)
  local buyChickenFunc = getFunction("BuyChicken")
  if not buyChickenFunc then
    warn("[Client] BuyChicken RemoteFunction not found")
    return
  end

  local result = buyChickenFunc:InvokeServer(chickenType, quantity)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Purchased", quantity, "x", chickenType, ":", result.message)
    else
      SoundEffects.play("uiError")
      warn("[Client] Chicken purchase failed:", result.message)
    end
  end
end)

--[[
  Random Chicken Claim Input Handler
  Handles E key press to claim random chickens in the neutral zone.
]]
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.KeyCode == Enum.KeyCode.E then
    -- Only handle if near a random chicken and NOT near a placed chicken
    if isNearRandomChicken and nearestRandomChickenId and not isNearChicken then
      -- Claim the random chicken
      local claimFunc = getFunction("ClaimRandomChicken")
      if claimFunc then
        task.spawn(function()
          local result = claimFunc:InvokeServer()
          if result and result.success then
            -- Play success sound
            SoundEffects.play("chickenClaim")

            -- Destroy the visual (server will fire RandomChickenClaimed to do this)
            if nearestRandomChickenId then
              ChickenVisuals.destroy(nearestRandomChickenId)
            end

            -- Hide prompt
            hideRandomChickenPrompt()
            isNearRandomChicken = false
            nearestRandomChickenId = nil
            nearestRandomChickenType = nil

            print("[Client] Claimed random chicken:", result.chicken and result.chicken.chickenType)
          else
            SoundEffects.play("uiError")
            warn("[Client] Failed to claim random chicken:", result and result.message)
          end
        end)
      end
    end
  end
end)

print("[Client] Main client script fully initialized")
