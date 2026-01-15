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
local TweenService = game:GetService("TweenService")

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
local DamageUI = require(ClientModules:WaitForChild("DamageUI"))
local ChickenHealthBar = require(ClientModules:WaitForChild("ChickenHealthBar"))
local PredatorWarning = require(ClientModules:WaitForChild("PredatorWarning"))
local ShieldUI = require(ClientModules:WaitForChild("ShieldUI"))

-- Get shared modules for position calculations
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))
local WorldEgg = require(Shared:WaitForChild("WorldEgg"))
local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Local state cache for player data
local playerDataCache: { [string]: any } = {}

-- Track world eggs with their visual models and proximity prompts
local worldEggVisuals: { [string]: { model: Model, prompt: ProximityPrompt } } = {}

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

-- Initialize client systems
SoundEffects.initialize()
print("[Client] SoundEffects initialized")

-- Create Main HUD
MainHUD.create()
print("[Client] MainHUD created")

-- Create Inventory UI
local inventoryCreated = InventoryUI.create()
if not inventoryCreated then
  warn("[Client] InventoryUI creation FAILED")
end
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

-- Create Damage UI
DamageUI.initialize()
print("[Client] DamageUI initialized")

-- Create Predator Warning UI
PredatorWarning.initialize()
print("[Client] PredatorWarning initialized")

-- Create Shield UI using MainHUD's ScreenGui
local mainHudScreenGui = MainHUD.getScreenGui()
if mainHudScreenGui then
  ShieldUI.create(mainHudScreenGui)
  print("[Client] ShieldUI created")
else
  warn("[Client] Cannot create ShieldUI - no MainHUD ScreenGui")
end

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
local placedEggData: { id: string, eggType: string }? = nil

-- Request initial player data from server
local getPlayerDataFunc = getFunction("GetPlayerData")
if getPlayerDataFunc then
  local initialData = getPlayerDataFunc:InvokeServer()
  if initialData then
    playerDataCache = initialData
    MainHUD.updateFromPlayerData(initialData)
    InventoryUI.updateFromPlayerData(initialData)
    -- Update inventory item count badge on MainHUD
    if initialData.inventory then
      local eggCount = initialData.inventory.eggs and #initialData.inventory.eggs or 0
      local chickenCount = initialData.inventory.chickens and #initialData.inventory.chickens or 0
      MainHUD.setInventoryItemCount(eggCount + chickenCount)
    end

    print("[Client] Got initial data, sectionIndex =", initialData.sectionIndex)

    -- Build section visuals for player's assigned section
    if initialData.sectionIndex then
      SectionVisuals.buildSection(initialData.sectionIndex, {})
      print("[Client] Section visuals built for section", initialData.sectionIndex)

      -- Build the central store (shared by all players)
      SectionVisuals.buildCentralStore()
    else
      warn("[Client] No sectionIndex in player data - cannot build section visuals")
    end

    -- Note: Initial chicken visuals are created when ChickenPositionUpdated events arrive
    -- from the server with position data from the ChickenAI system

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
    -- Update inventory item count badge on MainHUD
    if data.inventory then
      local eggCount = data.inventory.eggs and #data.inventory.eggs or 0
      local chickenCount = data.inventory.chickens and #data.inventory.chickens or 0
      MainHUD.setInventoryItemCount(eggCount + chickenCount)
    end

    -- Update chicken count display on MainHUD
    if data.placedChickens then
      MainHUD.setChickenCount(#data.placedChickens, 15)
    end

    -- Update StoreUI with active power-ups
    if data.activePowerUps then
      local activePowerUpsMap: { [string]: number } = {}
      local currentTime = os.time()
      for _, powerUp in ipairs(data.activePowerUps) do
        if currentTime < powerUp.expiresAt then
          -- Get power-up type from ID
          local powerUpType = nil
          if string.find(powerUp.powerUpId, "HatchLuck") then
            powerUpType = "HatchLuck"
          elseif string.find(powerUp.powerUpId, "EggQuality") then
            powerUpType = "EggQuality"
          end
          if powerUpType then
            activePowerUpsMap[powerUpType] = powerUp.expiresAt
          end
        end
      end
      StoreUI.updateActivePowerUps(activePowerUpsMap)
    end

    -- Update owned weapons in StoreUI
    if data.ownedWeapons then
      StoreUI.updateOwnedWeapons(data.ownedWeapons)
    end

    -- Update ShieldUI with current shield state
    if data.shieldState then
      local status = AreaShield.getStatus(data.shieldState, os.time())
      ShieldUI.updateStatus(status)
    end

    -- Build section visuals if we have a section index but haven't built yet
    if data.sectionIndex and not SectionVisuals.getCurrentSection() then
      SectionVisuals.buildSection(data.sectionIndex, {})
      print("[Client] Section visuals built from PlayerDataChanged for section", data.sectionIndex)

      -- Build the central store (shared by all players)
      SectionVisuals.buildCentralStore()
    end

    -- Update chicken money indicators from placed chickens
    if data.placedChickens then
      for _, chicken in ipairs(data.placedChickens) do
        ChickenVisuals.updateMoney(chicken.id, chicken.accumulatedMoney or 0)
      end
    end
  end)
end

-- ChickenPlaced: Create chicken visual at position (free-roaming)
local chickenPlacedEvent = getEvent("ChickenPlaced")
if chickenPlacedEvent then
  chickenPlacedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chicken = eventData.chicken
    if not chicken then
      warn("[Client] ChickenPlaced: Invalid event data - missing chicken")
      return
    end

    -- Get position from event data or use section center as fallback
    local position: Vector3
    if eventData.position then
      local pos = eventData.position
      position = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
    else
      -- Use section center as fallback
      local sectionIndex = playerDataCache.sectionIndex or 1
      local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
      position = sectionCenter or Vector3.new(0, 5, 0)
    end

    local visualState = ChickenVisuals.create(chicken.id, chicken.chickenType, position, nil)
    SoundEffects.play("chickenPlace")

    -- Create health bar for the chicken
    if visualState and visualState.model then
      ChickenHealthBar.create(chicken.id, chicken.chickenType, visualState.model)
    end

    print("[Client] Chicken placed:", chicken.id)
  end)
end

-- ChickenPickedUp: Remove chicken visual
local chickenPickedUpEvent = getEvent("ChickenPickedUp")
if chickenPickedUpEvent then
  chickenPickedUpEvent.OnClientEvent:Connect(function(data: any)
    -- Handle both formats: string (chickenId) or table ({ chickenId, ... })
    local chickenId: string

    if type(data) == "string" then
      chickenId = data
    elseif type(data) == "table" then
      chickenId = data.chickenId
    else
      warn("[Client] ChickenPickedUp: Invalid data format")
      return
    end

    ChickenVisuals.destroy(chickenId)
    ChickenHealthBar.destroy(chickenId)
    SoundEffects.play("chickenPickup")
    print("[Client] Chicken picked up:", chickenId)
  end)
end

-- ChickenSold: Remove chicken visual and play sell sound
local chickenSoldEvent = getEvent("ChickenSold")
if chickenSoldEvent then
  chickenSoldEvent.OnClientEvent:Connect(function(chickenId: string, sellPrice: number)
    ChickenVisuals.destroy(chickenId)
    ChickenHealthBar.destroy(chickenId)
    SoundEffects.playMoneyCollect(sellPrice)
    print("[Client] Chicken sold:", chickenId, "for", sellPrice)
  end)
end

-- ChickenDamaged: Update chicken health bar and visual when damaged by predator
local chickenDamagedEvent = getEvent("ChickenDamaged")
if chickenDamagedEvent then
  chickenDamagedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local newHealth = eventData.newHealth
    local maxHealth = eventData.maxHealth

    if chickenId and newHealth then
      ChickenHealthBar.updateHealth(chickenId, newHealth)

      -- Update visual state to show reduced income indicator
      if maxHealth and maxHealth > 0 then
        local healthPercent = newHealth / maxHealth
        ChickenVisuals.updateHealthState(chickenId, healthPercent)
      end
    end
  end)
end

-- ChickenHealthChanged: Update chicken health bar and visual (regeneration)
local chickenHealthChangedEvent = getEvent("ChickenHealthChanged")
if chickenHealthChangedEvent then
  chickenHealthChangedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local newHealth = eventData.newHealth
    local maxHealth = eventData.maxHealth

    if chickenId and newHealth then
      ChickenHealthBar.updateHealth(chickenId, newHealth)

      -- Update visual state to restore color as health regenerates
      if maxHealth and maxHealth > 0 then
        local healthPercent = newHealth / maxHealth
        ChickenVisuals.updateHealthState(chickenId, healthPercent)
      end
    end
  end)
end

-- ChickenDied: Remove chicken visual and health bar when killed by predator
local chickenDiedEvent = getEvent("ChickenDied")
if chickenDiedEvent then
  chickenDiedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local killedBy = eventData.killedBy

    if chickenId then
      ChickenVisuals.destroy(chickenId)
      ChickenHealthBar.destroy(chickenId)
      SoundEffects.play("chickenPickup") -- Use pickup sound for death too
      print("[Client] Chicken killed by", killedBy or "predator", ":", chickenId)
    end
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

-- EggSpawned: Create collectible egg visual with proximity prompt
local eggSpawnedEvent = getEvent("EggSpawned")
if eggSpawnedEvent then
  eggSpawnedEvent.OnClientEvent:Connect(function(eggData: { [string]: any })
    local eggId = eggData.id
    local eggType = eggData.eggType
    local eggRarity = eggData.rarity
    local chickenId = eggData.chickenId
    local position = eggData.position

    -- Play laying animation on the chicken
    if chickenId then
      ChickenVisuals.playLayingAnimation(chickenId)
    end

    -- Create egg visual in world
    local eggPosition = Vector3.new(position.x, position.y, position.z)
    local eggVisualState = EggVisuals.create(eggId, eggType, eggPosition)

    if eggVisualState and eggVisualState.model then
      -- Add proximity prompt for collection
      local primaryPart = eggVisualState.model.PrimaryPart
      if primaryPart then
        local prompt = Instance.new("ProximityPrompt")
        prompt.ObjectText = "Egg"
        prompt.ActionText = "Collect"
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 8
        prompt.RequiresLineOfSight = false
        prompt.Parent = primaryPart

        -- Handle collection
        prompt.Triggered:Connect(function(playerWhoTriggered: Player)
          if playerWhoTriggered == localPlayer then
            local collectFunc = getFunction("CollectWorldEgg")
            if collectFunc then
              local result = collectFunc:InvokeServer(eggId)
              if result and result.success then
                SoundEffects.play("eggCollect")
                print("[Client] Collected egg:", eggId)
              else
                warn(
                  "[Client] Failed to collect egg:",
                  result and result.message or "Unknown error"
                )
              end
            end
          end
        end)

        -- Store reference for cleanup
        worldEggVisuals[eggId] = {
          model = eggVisualState.model,
          prompt = prompt,
        }
      end
    end

    SoundEffects.play("eggPlace")
    print("[Client] Egg spawned:", eggId, "from chicken", chickenId)
  end)
end

-- EggCollected: Clean up egg visual when collected
local eggCollectedEvent = getEvent("EggCollected")
if eggCollectedEvent then
  eggCollectedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local eggId = eventData.eggId

    -- Remove egg visual
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      EggVisuals.destroy(eggId)
      worldEggVisuals[eggId] = nil
    end

    print("[Client] Egg collected and added to inventory:", eggId)
  end)
end

-- EggDespawned: Clean up egg visual when despawned (expired)
local eggDespawnedEvent = getEvent("EggDespawned")
if eggDespawnedEvent then
  eggDespawnedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local eggId = eventData.eggId
    local reason = eventData.reason

    -- Remove egg visual
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      EggVisuals.destroy(eggId)
      worldEggVisuals[eggId] = nil
    end

    print("[Client] Egg despawned:", eggId, "reason:", reason)
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
-- Now receives predators from all sections (sectionIndex indicates which coop is being targeted)
local predatorSpawnedEvent = getEvent("PredatorSpawned")
if predatorSpawnedEvent then
  predatorSpawnedEvent.OnClientEvent:Connect(
    function(
      predatorId: string,
      predatorType: string,
      threatLevel: string,
      position: Vector3,
      sectionIndex: number?
    )
      local visualState = PredatorVisuals.create(predatorId, predatorType, threatLevel, position)
      -- Create health bar if visual was created successfully
      if visualState and visualState.model then
        PredatorHealthBar.create(predatorId, predatorType, threatLevel, visualState.model)
      end
      -- Start walking animation (predators now walk towards coop)
      PredatorVisuals.setAnimation(predatorId, "walking")
      -- Show predator warning with directional indicator and message
      PredatorWarning.show(predatorId, predatorType, threatLevel, position)
      SoundEffects.playPredatorAlert(threatLevel == "Deadly" or threatLevel == "Catastrophic")
      print(
        "[Client] Predator spawned:",
        predatorId,
        predatorType,
        threatLevel,
        "section:",
        sectionIndex or "unknown"
      )
    end
  )
end

-- PredatorPositionUpdated: Update predator visual position as it walks towards coop
local predatorPositionUpdatedEvent = getEvent("PredatorPositionUpdated")
if predatorPositionUpdatedEvent then
  predatorPositionUpdatedEvent.OnClientEvent:Connect(
    function(predatorId: string, newPosition: Vector3, hasReachedCoop: boolean)
      -- Update visual position
      PredatorVisuals.updatePosition(predatorId, newPosition)

      -- Update warning arrow direction
      PredatorWarning.updatePosition(predatorId, newPosition)

      -- Switch to attacking animation when reaching coop
      if hasReachedCoop then
        PredatorVisuals.setAnimation(predatorId, "attacking")
      end
    end
  )
end

-- PredatorDefeated: Play defeated animation, remove visual and health bar
local predatorDefeatedEvent = getEvent("PredatorDefeated")
if predatorDefeatedEvent then
  predatorDefeatedEvent.OnClientEvent:Connect(function(predatorId: string, byPlayer: boolean)
    PredatorHealthBar.destroy(predatorId)
    PredatorVisuals.playDefeatedAnimation(predatorId)
    -- Clear predator warning when defeated
    PredatorWarning.clear(predatorId)
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

-- RandomChickenDespawned: Chicken timed out and despawned
local randomChickenDespawnedEvent = getEvent("RandomChickenDespawned")
if randomChickenDespawnedEvent then
  randomChickenDespawnedEvent.OnClientEvent:Connect(function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    if not chickenId then
      warn("[Client] RandomChickenDespawned: Invalid event data")
      return
    end

    -- Destroy the visual
    ChickenVisuals.destroy(chickenId)

    -- Clear tracking if this was the nearby chicken
    if nearestRandomChickenId == chickenId then
      hideRandomChickenPrompt()
      isNearRandomChicken = false
      nearestRandomChickenId = nil
      nearestRandomChickenType = nil
    end

    print("[Client] Random chicken despawned:", chickenId)
  end)
end

-- RandomChickenPositionUpdated: Update random chicken position for walking animation
local randomChickenPositionEvent = getEvent("RandomChickenPositionUpdated")
if randomChickenPositionEvent then
  randomChickenPositionEvent.OnClientEvent:Connect(function(data: any)
    if not data or not data.id then
      return
    end
    local position = Vector3.new(data.position.x, data.position.y, data.position.z)
    local facingDirection =
      Vector3.new(data.facingDirection.x, data.facingDirection.y, data.facingDirection.z)
    ChickenVisuals.updatePosition(data.id, position, facingDirection, data.isIdle)
  end)
end

-- ChickenPositionUpdated: Update player-owned chicken positions for walking animation (batched)
local chickenPositionEvent = getEvent("ChickenPositionUpdated")
if chickenPositionEvent then
  chickenPositionEvent.OnClientEvent:Connect(function(data: any)
    if not data or not data.chickens then
      return
    end
    -- Process batched chicken position updates
    for _, chickenData in ipairs(data.chickens) do
      if chickenData.chickenId and chickenData.position and chickenData.facingDirection then
        local position =
          Vector3.new(chickenData.position.X, chickenData.position.Y, chickenData.position.Z)
        local facingDirection = Vector3.new(
          chickenData.facingDirection.X,
          chickenData.facingDirection.Y,
          chickenData.facingDirection.Z
        )
        ChickenVisuals.updatePosition(
          chickenData.chickenId,
          position,
          facingDirection,
          chickenData.isIdle
        )
      end
    end
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

-- StoreReplenished: Update store inventory display
local storeReplenishedEvent = getEvent("StoreReplenished")
if storeReplenishedEvent then
  storeReplenishedEvent.OnClientEvent:Connect(function(newInventory: any)
    -- Update local store inventory cache
    local Store = require(Shared:WaitForChild("Store"))
    Store.setStoreInventory(newInventory)
    -- Refresh the store UI if open
    StoreUI.refreshInventory()
    print("[Client] Store inventory replenished")
  end)
end

-- StoreInventoryUpdated: Update store UI after individual purchases
local storeInventoryUpdatedEvent = getEvent("StoreInventoryUpdated")
if storeInventoryUpdatedEvent then
  storeInventoryUpdatedEvent.OnClientEvent:Connect(function(data: any)
    -- Update item stock display after purchase
    if data.itemType and data.itemId and data.newStock ~= nil then
      StoreUI.updateItemStock(data.itemType, data.itemId, data.newStock)
    end
    -- Refresh full inventory if provided
    if data.inventory then
      local Store = require(Shared:WaitForChild("Store"))
      Store.setStoreInventory(data.inventory)
      StoreUI.refreshInventory()
    end
    print("[Client] Store inventory updated:", data.itemType, data.itemId, "stock:", data.newStock)
  end)
end

-- PlayerDamaged: Show damage number and update health bar
local playerDamagedEvent = getEvent("PlayerDamaged")
if playerDamagedEvent then
  playerDamagedEvent.OnClientEvent:Connect(function(data: any)
    DamageUI.onPlayerDamaged(data)
    SoundEffects.playHurt()
    print("[Client] Player damaged:", data.damage, "from", data.source)
  end)
end

-- PlayerKnockback: Show knockback effect and stun visuals
local playerKnockbackEvent = getEvent("PlayerKnockback")
if playerKnockbackEvent then
  playerKnockbackEvent.OnClientEvent:Connect(function(data: any)
    DamageUI.onPlayerKnockback(data)
    print("[Client] Player knocked back for", data.duration, "seconds")
  end)
end

-- PlayerHealthChanged: Update health bar during regeneration
local playerHealthChangedEvent = getEvent("PlayerHealthChanged")
if playerHealthChangedEvent then
  playerHealthChangedEvent.OnClientEvent:Connect(function(data: any)
    DamageUI.onPlayerHealthChanged(data)
  end)
end

-- ProtectionStatusChanged: Update protection timer display
local protectionStatusChangedEvent = getEvent("ProtectionStatusChanged")
if protectionStatusChangedEvent then
  protectionStatusChangedEvent.OnClientEvent:Connect(function(data: any)
    MainHUD.setProtectionStatus(data)
    if data.isProtected then
      print("[Client] Protection status: Protected for", data.remainingSeconds, "seconds")
    else
      print("[Client] Protection status: Protection expired")
    end
  end)
end

-- BankruptcyAssistance: Handle receiving assistance money when broke
local bankruptcyAssistanceEvent = getEvent("BankruptcyAssistance")
if bankruptcyAssistanceEvent then
  bankruptcyAssistanceEvent.OnClientEvent:Connect(function(data: any)
    SoundEffects.play("uiNotification")
    print("[Client] Bankruptcy assistance received: $" .. tostring(data.moneyAwarded))
    -- Show notification via MainHUD
    MainHUD.showBankruptcyAssistance(data)
  end)
end

-- ShieldActivated: Handle shield activation by any player
local shieldActivatedEvent = getEvent("ShieldActivated")
if shieldActivatedEvent then
  shieldActivatedEvent.OnClientEvent:Connect(
    function(userId: number, sectionIndex: number, shieldData: any)
      -- Update ShieldUI if this is our shield
      if userId == localPlayer.UserId then
        local status = AreaShield.getStatus({
          isActive = true,
          activatedTime = os.time(),
          expiresAt = shieldData.expiresAt,
          cooldownEndTime = shieldData.expiresAt + AreaShield.getConstants().shieldCooldown,
        }, os.time())
        ShieldUI.updateStatus(status)
        ShieldUI.showActivationFeedback(true, "Shield activated!")
        SoundEffects.play("uiNotification")
      end
      -- Visual effect for shield could be added here for all players to see
      print("[Client] Shield activated for user", userId, "in section", sectionIndex)
    end
  )
end

-- ShieldDeactivated: Handle shield expiration
local shieldDeactivatedEvent = getEvent("ShieldDeactivated")
if shieldDeactivatedEvent then
  shieldDeactivatedEvent.OnClientEvent:Connect(function(userId: number, sectionIndex: number)
    -- Update ShieldUI if this is our shield
    if userId == localPlayer.UserId then
      -- Shield expired, update to show cooldown state
      local cachedData = playerDataCache
      if cachedData and cachedData.shieldState then
        local status = AreaShield.getStatus(cachedData.shieldState, os.time())
        ShieldUI.updateStatus(status)
      end
    end
    print("[Client] Shield deactivated for user", userId, "in section", sectionIndex)
  end)
end

-- Wire ShieldUI activation callback to server
local activateShieldFunc = getFunction("ActivateShield")
ShieldUI.onActivate(function()
  if activateShieldFunc then
    local result = activateShieldFunc:InvokeServer()
    if result then
      if result.success then
        print("[Client] Shield activation successful:", result.message)
      else
        ShieldUI.showActivationFeedback(false, result.message)
        print("[Client] Shield activation failed:", result.message)
      end
    end
  end
end)

-- Track incapacitation state for movement control
local isIncapacitated = false
local incapacitatedEndTime = 0

-- PlayerIncapacitated: Handle being hit by another player's bat
local playerIncapacitatedEvent = getEvent("PlayerIncapacitated")
if playerIncapacitatedEvent then
  playerIncapacitatedEvent.OnClientEvent:Connect(function(data: any)
    DamageUI.onPlayerIncapacitated(data)
    SoundEffects.playKnockback()

    -- Disable player movement
    local character = localPlayer.Character
    if character then
      local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
      if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
      end

      -- Apply knockback force (throw player backward)
      local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
      if rootPart then
        -- Calculate knockback direction (backward from current look direction)
        local knockbackDirection = -rootPart.CFrame.LookVector
        local knockbackForce = 50 -- studs per second

        -- Create BodyVelocity for throw effect
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Name = "IncapKnockback"
        bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
        bodyVelocity.Velocity = knockbackDirection * knockbackForce + Vector3.new(0, 20, 0)
        bodyVelocity.Parent = rootPart

        -- Remove BodyVelocity after short duration
        task.delay(0.3, function()
          if bodyVelocity and bodyVelocity.Parent then
            bodyVelocity:Destroy()
          end
        end)
      end
    end

    -- Set incapacitated state
    isIncapacitated = true
    incapacitatedEndTime = os.clock() + data.duration

    -- Re-enable movement after duration
    task.delay(data.duration, function()
      isIncapacitated = false
      local char = localPlayer.Character
      if char then
        local hum = char:FindFirstChild("Humanoid") :: Humanoid?
        if hum then
          hum.WalkSpeed = 16 -- Default walk speed
          hum.JumpPower = 50 -- Default jump power
        end
      end
    end)

    print("[Client] Player incapacitated for", data.duration, "seconds by", data.attackerName)
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

-- Store interaction state
local STORE_INTERACTION_RANGE = 12 -- studs, matches ProximityPrompt MaxActivationDistance
local isNearStore = false
local storePromptConnected = false

--[[
	Helper function to find the nearest random chicken within claim range.
	Random chickens are not in the player's placedChickens list.
	Returns chickenId, chickenType, position or nil.
]]
local function findNearbyRandomChicken(playerPosition: Vector3): (string?, string?, Vector3?)
  local allChickens = ChickenVisuals.getAll()
  local nearestDistance = RANDOM_CHICKEN_CLAIM_RANGE
  local nearestId: string? = nil
  local nearestType: string? = nil
  local nearestPos: Vector3? = nil

  for chickenId, state in pairs(allChickens) do
    -- All chickens are now free-roaming, check if they're owned by checking playerDataCache
    local isOwnedChicken = false
    if playerDataCache and playerDataCache.placedChickens then
      for _, placed in ipairs(playerDataCache.placedChickens) do
        if placed.id == chickenId then
          isOwnedChicken = true
          break
        end
      end
    end

    -- Random chickens are not in the player's placedChickens list
    if not isOwnedChicken and state.position then
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
	Returns chickenId, chickenType, rarity, accumulatedMoney or nil.
]]
local function findNearbyPlacedChicken(
  playerPosition: Vector3
): (string?, string?, string?, number?)
  if not playerDataCache or not playerDataCache.placedChickens then
    return nil, nil, nil, nil
  end

  local pickupRange = ChickenPickup.getPickupRange()
  local nearestDistance = pickupRange
  local nearestChicken = nil

  for _, chicken in ipairs(playerDataCache.placedChickens) do
    -- Get position from the visual state (updated by ChickenPositionUpdated events)
    local visualState = ChickenVisuals.get(chicken.id)
    if visualState and visualState.position then
      local distance = (playerPosition - visualState.position).Magnitude
      if distance < nearestDistance then
        nearestDistance = distance
        nearestChicken = chicken
      end
    end
  end

  if nearestChicken then
    -- Get real-time accumulated money from ChickenVisuals, not stale cache
    local realTimeAccumulatedMoney = ChickenVisuals.getAccumulatedMoney(nearestChicken.id)
    return nearestChicken.id,
      nearestChicken.chickenType,
      nearestChicken.rarity,
      realTimeAccumulatedMoney
  end

  return nil, nil, nil, nil
end

--[[
	Helper function to find an available trap spot for the player.
	Returns the nearest available spot index, or nil if all spots are occupied.
	Traps can be placed from anywhere - we just pick the nearest available spot.
]]
local function findNearbyAvailableTrapSpot(playerPosition: Vector3): number?
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

  -- Get available trap spots
  local availableSpots = TrapPlacement.getAvailableSpots(playerDataCache)
  if #availableSpots == 0 then
    return nil
  end

  -- Find the nearest available spot (no distance limit - player can place from anywhere)
  local nearestSpot: number? = nil
  local nearestDistance = math.huge

  for _, spotIndex in ipairs(availableSpots) do
    local spotPos = PlayerSection.getTrapSpotPosition(spotIndex, sectionCenter)
    if spotPos then
      local spotVec = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
      local distance = (playerPosition - spotVec).Magnitude
      if distance < nearestDistance then
        nearestDistance = distance
        nearestSpot = spotIndex
      end
    end
  end

  return nearestSpot
end

-- Wire up ChickenPickup callbacks for proximity checking
ChickenPickup.create()
ChickenPickup.setGetNearbyChicken(function(position: Vector3): (string?, number?)
  local chickenId = findNearbyPlacedChicken(position)
  return chickenId, nil -- spotIndex no longer used
end)
ChickenPickup.setGetAvailableSpot(function(_position: Vector3): number?
  return nil -- No longer using spots for free-roaming chickens
end)
ChickenPickup.setGetPlayerData(function()
  return playerDataCache
end)

-- Wire up pickup callback - pickup chicken to inventory
ChickenPickup.setOnPickup(function(chickenId: string, _spotIndex: number)
  -- Call server to pick up chicken into inventory
  local pickupChickenFunc = getFunction("PickupChicken")
  if pickupChickenFunc then
    local result = pickupChickenFunc:InvokeServer(chickenId)
    if result and result.success then
      SoundEffects.play("chickenPickup")
      print("[Client] Chicken picked up to inventory:", chickenId)
    else
      SoundEffects.play("uiError")
      warn("[Client] Failed to pick up chicken:", result and result.message or "Unknown error")
    end
  end
end)

-- Wire up place callback - no longer used for free-roaming
ChickenPickup.setOnPlace(function(_chickenId: string, _newSpotIndex: number)
  -- Free-roaming chickens are placed directly via PlaceChicken, not moved
  warn("[Client] ChickenPickup.setOnPlace called but no longer used for free-roaming chickens")
end)

-- Wire up cancel callback
ChickenPickup.setOnCancel(function()
  SoundEffects.play("uiCancel")
  print("[Client] Pickup cancelled")
end)
print("[Client] ChickenPickup system initialized")

-- Wire up ChickenSelling callbacks for proximity checking
ChickenSelling.create()
ChickenSelling.setGetNearbyChicken(function(position: Vector3)
  local chickenId, chickenType, rarity, accumulatedMoney = findNearbyPlacedChicken(position)
  return chickenId, nil, chickenType, rarity, accumulatedMoney -- nil for spotIndex (deprecated)
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
      -- Show hatch preview for the egg (free-roaming, no spot needed)
      placedEggData = {
        id = selectedItem.itemId,
        eggType = selectedItem.itemData.eggType,
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
      -- Check chicken limit before attempting to place
      if MainHUD.isAtChickenLimit() then
        SoundEffects.play("uiError")
        warn("[Client] Cannot place chicken: Area is at maximum capacity (15 chickens)")
        return
      end

      -- Place chicken from inventory (free-roaming, no spot needed)
      local placeChickenFunc = getFunction("PlaceChicken")
      if placeChickenFunc then
        local result = placeChickenFunc:InvokeServer(selectedItem.itemId, nil) -- nil spotIndex = free-roaming
        if result and result.success then
          SoundEffects.play("chickenPlace")
          InventoryUI.clearSelection()
        elseif result and result.atLimit then
          SoundEffects.play("uiError")
          warn("[Client] Cannot place chicken:", result.message)
        else
          SoundEffects.play("uiError")
          warn("[Client] Place failed:", result and result.message or "Unknown error")
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
  elseif selectedItem.itemType == "trap" then
    if actionType == "place" then
      -- Check if trap is already placed
      if selectedItem.itemData.spotIndex and selectedItem.itemData.spotIndex > 0 then
        SoundEffects.play("uiError")
        warn("[Client] Trap is already placed at spot", selectedItem.itemData.spotIndex)
        return
      end

      -- Place trap from inventory to trap spot
      local placeTrapFunc = getFunction("PlaceTrap")
      if placeTrapFunc then
        -- Find available trap spot near player
        local character = localPlayer.Character
        if character then
          local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
          if rootPart then
            local spotIndex = findNearbyAvailableTrapSpot(rootPart.Position)
            if spotIndex then
              local result = placeTrapFunc:InvokeServer(selectedItem.itemId, spotIndex)
              if result and result.success then
                SoundEffects.play("trapPlace")
                InventoryUI.clearSelection()
                print("[Client] Trap placed at spot:", spotIndex)
              else
                SoundEffects.play("uiError")
                warn("[Client] Trap place failed:", result and result.message or "Unknown error")
              end
            else
              SoundEffects.play("uiError")
              warn("[Client] All trap spots are occupied (max 8 traps)")
            end
          end
        end
      end
    elseif actionType == "sell" then
      -- Sell trap via SellPredator remote (traps with caught predators return sell value)
      -- For unplaced traps, we just remove them without payment for now
      warn("[Client] Trap selling not implemented yet")
      SoundEffects.play("uiError")
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

  -- Check chicken limit before attempting to hatch with placement
  if MainHUD.isAtChickenLimit() then
    SoundEffects.play("uiError")
    warn("[Client] Cannot hatch egg: Area is at maximum capacity (15 chickens)")
    HatchPreviewUI.hide()
    placedEggData = nil
    return
  end

  -- Hatch egg via server (pass placement hint to place chicken in area)
  local hatchEggFunc = getFunction("HatchEgg")
  if hatchEggFunc then
    local result = hatchEggFunc:InvokeServer(eggId, 1) -- Pass 1 as placement hint to place in area
    if result and result.success then
      SoundEffects.playEggHatch(result.rarity or "Common")
      -- Complete tutorial step if active (place_egg completes tutorial)
      if Tutorial.isActive() then
        Tutorial.completeStep("place_egg")
      end
      print("[Client] Egg hatched successfully:", result.chickenType, result.rarity)

      -- Show the result screen with what they got
      HatchPreviewUI.showResult(result.chickenType, result.rarity)
    elseif result and result.atLimit then
      SoundEffects.play("uiError")
      warn("[Client] Cannot hatch egg:", result.message)
    else
      SoundEffects.play("uiError")
      warn("[Client] Hatch failed:", result and result.message or "Unknown error")
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

-- Wire up MainHUD inventory button to toggle InventoryUI
MainHUD.onInventoryClick(function()
  InventoryUI.toggle()
end)
print("[Client] MainHUD inventory button wired")

--[[
  Weapon Tool Handling
  Uses Roblox's native Tool system for weapon equipping.
  Weapons appear in the player's Backpack/Hotbar and are equipped by clicking or pressing number keys.
  Tool.Activated is used to trigger swings.
]]

-- Track currently equipped weapon tool
local equippedWeaponTool: Tool? = nil

-- Find the nearest predator targeting this player within weapon range
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

-- Swing animation constants
local SWING_DURATION = 0.15 -- Fast swing
local SWING_ANGLE = math.rad(80) -- 80 degree swing arc
local isSwinging = false

-- Play swing animation on the weapon tool
local function playSwingAnimation(tool: Tool): ()
  if isSwinging then
    return
  end

  local handle = tool:FindFirstChild("Handle") :: BasePart?
  if not handle then
    return
  end

  -- Find the character's right arm/grip to animate from
  local character = localPlayer.Character
  if not character then
    return
  end

  -- Use Motor6D for R15/R6 compatible animation
  local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
  if not rightHand then
    return
  end

  -- Find the RightGrip weld that attaches the tool to the hand
  local grip = rightHand:FindFirstChild("RightGrip") :: Motor6D?
  if not grip or not grip:IsA("Motor6D") then
    return
  end

  isSwinging = true

  -- Store original C1 offset
  local originalC1 = grip.C1

  -- Create swing animation by rotating the grip
  local swingC1 = originalC1 * CFrame.Angles(SWING_ANGLE, 0, 0)

  -- Swing forward
  local swingTween = TweenService:Create(
    grip,
    TweenInfo.new(SWING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { C1 = swingC1 }
  )
  swingTween:Play()
  swingTween.Completed:Wait()

  -- Swing back (return)
  local returnTween = TweenService:Create(
    grip,
    TweenInfo.new(SWING_DURATION * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
    { C1 = originalC1 }
  )
  returnTween:Play()
  returnTween.Completed:Wait()

  isSwinging = false
end

-- Handle weapon swing when Tool is activated (clicked)
local function onWeaponActivated(tool: Tool)
  local swingBatFunc = getFunction("SwingBat")
  if not swingBatFunc then
    warn("[Client] SwingBat RemoteFunction not found")
    return
  end

  -- Play swing sound immediately for responsiveness
  SoundEffects.playBatSwing("miss")

  -- Play swing animation asynchronously (doesn't block server call)
  task.spawn(playSwingAnimation, tool)

  -- Check for nearby predator targets
  local predatorId, _ = findNearbyPredator()

  local result
  if predatorId then
    result = swingBatFunc:InvokeServer("swing", "predator", predatorId)
    if result and result.success then
      -- Update health bar with remaining health
      if result.remainingHealth ~= nil then
        PredatorHealthBar.updateHealth(predatorId, result.remainingHealth)
      end
      -- Show floating damage number above predator
      if result.damage and result.damage > 0 then
        PredatorHealthBar.showDamageNumber(predatorId, result.damage)
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

-- Handle weapon equipped (via Roblox Tool system)
local function onWeaponEquipped(tool: Tool)
  equippedWeaponTool = tool
  local weaponType = tool:GetAttribute("WeaponType") or tool.Name
  print("[Client] Weapon equipped:", weaponType)
  SoundEffects.playBatSwing("swing")
end

-- Handle weapon unequipped (via Roblox Tool system)
local function onWeaponUnequipped(tool: Tool)
  if equippedWeaponTool == tool then
    equippedWeaponTool = nil
  end
  local weaponType = tool:GetAttribute("WeaponType") or tool.Name
  print("[Client] Weapon unequipped:", weaponType)
end

-- Setup handlers for a weapon Tool
local function setupWeaponTool(tool: Tool)
  -- Only setup if it's a weapon tool (has WeaponType attribute)
  if not tool:GetAttribute("WeaponType") then
    return
  end

  tool.Activated:Connect(function()
    onWeaponActivated(tool)
  end)

  tool.Equipped:Connect(function()
    onWeaponEquipped(tool)
  end)

  tool.Unequipped:Connect(function()
    onWeaponUnequipped(tool)
  end)

  print("[Client] Weapon tool setup:", tool.Name)
end

-- Watch for new weapon Tools added to Backpack
local function setupBackpackWatcher()
  local backpack = localPlayer:WaitForChild("Backpack", 10)
  if not backpack then
    warn("[Client] Backpack not found")
    return
  end

  -- Setup existing tools
  for _, child in ipairs(backpack:GetChildren()) do
    if child:IsA("Tool") then
      setupWeaponTool(child)
    end
  end

  -- Watch for new tools
  backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") then
      setupWeaponTool(child)
    end
  end)

  print("[Client] Backpack weapon watcher set up")
end

-- Also watch character for equipped tools (respawn handling)
local function setupCharacterToolWatcher()
  local function watchCharacter(character: Model)
    -- Setup existing equipped tools
    for _, child in ipairs(character:GetChildren()) do
      if child:IsA("Tool") then
        setupWeaponTool(child)
      end
    end

    -- Watch for newly equipped tools
    character.ChildAdded:Connect(function(child)
      if child:IsA("Tool") then
        setupWeaponTool(child)
      end
    end)
  end

  if localPlayer.Character then
    watchCharacter(localPlayer.Character)
  end

  localPlayer.CharacterAdded:Connect(function(character)
    watchCharacter(character)
    -- Re-setup backpack watcher on respawn
    task.defer(setupBackpackWatcher)
  end)
end

-- Initialize weapon tool system
setupBackpackWatcher()
setupCharacterToolWatcher()
print("[Client] Weapon Tool system initialized")

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
    -- Free-roaming chickens don't need spot placement
    ChickenPickup.hidePrompt()
    ChickenSelling.hidePrompt()
    hideRandomChickenPrompt()
    isNearRandomChicken = false
  else
    -- When not holding, check for nearby chickens
    local chickenId, chickenType, _, accumulatedMoney = findNearbyPlacedChicken(playerPosition)

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
                -- Get position from visual state
                local visualState = ChickenVisuals.get(chickenId)
                if visualState and visualState.position then
                  ChickenVisuals.createMoneyPopEffect({
                    amount = result.amountCollected,
                    position = visualState.position + Vector3.new(0, 2, 0),
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

  -- Check distance to store for fallback E key handling
  local store = SectionVisuals.getStore()
  if store then
    local storePart = store:FindFirstChildWhichIsA("BasePart", true)
    if storePart then
      local storeDistance = (playerPosition - storePart.Position).Magnitude
      isNearStore = storeDistance <= STORE_INTERACTION_RANGE
    end
  end
end

--[[
	Client game loop - runs every frame via Heartbeat.
	Handles periodic updates that need to be smooth or responsive.
]]
RunService.Heartbeat:Connect(function(deltaTime: number)
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
    -- Connect the Triggered event (fires when player activates the prompt)
    prompt.Triggered:Connect(function(playerWhoTriggered)
      if playerWhoTriggered == localPlayer then
        StoreUI.toggle()
        print("[Client] Store opened via ProximityPrompt.Triggered")
      end
    end)

    -- Track when prompt becomes visible/hidden for fallback E key handling
    prompt.PromptShown:Connect(function(playerToShowTo)
      if playerToShowTo == localPlayer then
        isNearStore = true
      end
    end)

    prompt.PromptHidden:Connect(function(playerHiddenFrom)
      if playerHiddenFrom == localPlayer then
        isNearStore = false
      end
    end)

    storePromptConnected = true
    print("[Client] Store prompt connected with Triggered, PromptShown, and PromptHidden events")
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

-- Wire up store Robux replenish callback
StoreUI.onReplenish(function()
  local replenishFunc = getFunction("ReplenishStoreWithRobux")
  if not replenishFunc then
    warn("[Client] ReplenishStoreWithRobux RemoteFunction not found")
    return
  end

  local result = replenishFunc:InvokeServer()
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Store replenish initiated:", result.message)
    else
      SoundEffects.play("uiError")
      warn("[Client] Store replenish failed:", result.message)
    end
  end
end)

-- Wire up store Robux item purchase callback
StoreUI.onRobuxPurchase(function(itemType: string, itemId: string)
  local buyItemFunc = getFunction("BuyItemWithRobux")
  if not buyItemFunc then
    warn("[Client] BuyItemWithRobux RemoteFunction not found")
    return
  end

  local result = buyItemFunc:InvokeServer(itemType, itemId)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Robux item purchase initiated:", result.message)
      -- Refresh inventory to show new item
      StoreUI.refreshInventory()
    else
      SoundEffects.play("uiError")
      warn("[Client] Robux item purchase failed:", result.message)
    end
  end
end)

-- Wire up store power-up purchase callback
StoreUI.onPowerUpPurchase(function(powerUpId: string)
  local buyPowerUpFunc = getFunction("BuyPowerUp")
  if not buyPowerUpFunc then
    warn("[Client] BuyPowerUp RemoteFunction not found")
    return
  end

  local result = buyPowerUpFunc:InvokeServer(powerUpId)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Power-up purchase initiated:", result.message)
      -- Refresh store to show active status
      StoreUI.refreshInventory()
    else
      SoundEffects.play("uiError")
      warn("[Client] Power-up purchase failed:", result.message)
    end
  end
end)

-- Wire up store trap/supply purchase callback
StoreUI.onTrapPurchase(function(trapType: string)
  print("[Client] onTrapPurchase callback invoked with trapType:", trapType)
  local buyTrapFunc = getFunction("BuyTrap")
  if not buyTrapFunc then
    warn("[Client] BuyTrap RemoteFunction not found")
    return
  end

  print("[Client] Invoking BuyTrap RemoteFunction")
  local result = buyTrapFunc:InvokeServer(trapType)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Trap purchased:", result.message)
      -- Refresh store UI
      StoreUI.refreshInventory()
    else
      SoundEffects.play("uiError")
      warn("[Client] Trap purchase failed:", result.message)
    end
  end
end)

StoreUI.onWeaponPurchase(function(weaponType: string)
  local buyWeaponFunc = getFunction("BuyWeapon")
  if not buyWeaponFunc then
    warn("[Client] BuyWeapon RemoteFunction not found")
    return
  end

  local result = buyWeaponFunc:InvokeServer(weaponType)
  if result then
    if result.success then
      SoundEffects.play("purchase")
      print("[Client] Weapon purchased:", result.message)
      -- Refresh store UI
      StoreUI.refreshInventory()
    else
      SoundEffects.play("uiError")
      warn("[Client] Weapon purchase failed:", result.message)
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

            -- Update local cache and UI with returned player data (immediate sync)
            if result.playerData then
              playerDataCache = result.playerData
              MainHUD.updateFromPlayerData(result.playerData)
              InventoryUI.updateFromPlayerData(result.playerData)
            end

            print("[Client] Claimed random chicken:", result.chicken and result.chicken.chickenType)
          else
            SoundEffects.play("uiError")
            warn("[Client] Failed to claim random chicken:", result and result.message)
          end
        end)
      end
    -- Fallback: If near store and ProximityPrompt didn't handle it, toggle store manually
    elseif isNearStore and not isNearChicken and not isNearRandomChicken then
      StoreUI.toggle()
      print("[Client] Store opened via fallback E key handler")
    end
  end
end)

print("[Client] Main client script fully initialized")
