--[[
	Main Client Script
	Bootstraps Knit controllers and initializes client-side UI systems.
	
	Architecture:
	- KnitClient loads and starts all controllers (handle state/server communication)
	- Controller signals are connected to visual modules for rendering updates
	- UI modules handle rendering and user interaction
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- Get client modules
local ClientModules = script.Parent

-- Start Knit client first (loads and starts all controllers)
local KnitClient = require(ClientModules:WaitForChild("KnitClient"))
KnitClient.start()
print("[Client] KnitClient started")

-- Load visual modules (non-UI)
local SoundEffects = require(ClientModules:WaitForChild("SoundEffects"))
local ChickenVisuals = require(ClientModules:WaitForChild("ChickenVisuals"))
local PredatorVisuals = require(ClientModules:WaitForChild("PredatorVisuals"))
local EggVisuals = require(ClientModules:WaitForChild("EggVisuals"))
local ChickenSelling = require(ClientModules:WaitForChild("ChickenSelling"))
local MobileTouchControls = require(ClientModules:WaitForChild("MobileTouchControls"))
local SectionVisuals = require(ClientModules:WaitForChild("SectionVisuals"))
local TrapVisuals = require(ClientModules:WaitForChild("TrapVisuals"))

-- Load UI system (centralized initialization module)
local UI = require(ClientModules:WaitForChild("UI"))

-- Get UI components from centralized module
local MainHUD = UI.Components.MainHUD
local InventoryUI = UI.Components.InventoryUI
local StoreUI = UI.Components.StoreUI
local HatchPreviewUI = UI.Components.HatchPreviewUI
local TradeUI = UI.Components.TradeUI
local ShieldUI = UI.Components.ShieldUI
local DamageUI = UI.Components.DamageUI
local ChickenHealthBar = UI.Components.ChickenHealthBar
local PredatorHealthBar = UI.Components.PredatorHealthBar
local OfflineEarningsUI = UI.Components.OfflineEarningsUI
local Tutorial = UI.Components.Tutorial
local PredatorWarning = UI.Components.PredatorWarning

-- Get Knit for accessing controllers
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

-- Get shared modules for position calculations
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local BaseballBat = require(Shared:WaitForChild("BaseballBat"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))
local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))

-- Local player reference
local localPlayer = Players.LocalPlayer

-- Initialize client systems
SoundEffects.initialize()
print("[Client] SoundEffects initialized")

-- Initialize UI system (mounts all Fusion UI components)
local uiInitSuccess = UI.initialize()
if uiInitSuccess then
  print("[Client] UI system initialized successfully")
else
  warn("[Client] UI system initialized with some failures")
end

-- Get controllers for state management
local PlayerDataController = Knit.GetController("PlayerDataController")
local StoreController = Knit.GetController("StoreController")
local ChickenController = Knit.GetController("ChickenController")
local EggController = Knit.GetController("EggController")
local TrapController = Knit.GetController("TrapController")
local CombatController = Knit.GetController("CombatController")
local PredatorController = Knit.GetController("PredatorController")

-- Get MapService for section assignment
local MapService = Knit.GetService("MapService")

-- Listen to MapService's SectionAssigned signal directly
-- This ensures section visuals are built even if profile data is delayed
MapService.SectionAssigned:Connect(function(sectionIndex: number)
  print("[Client] Received SectionAssigned signal for section", sectionIndex)
  if not SectionVisuals.getCurrentSection() then
    SectionVisuals.buildSection(sectionIndex, {})
    print("[Client] Section visuals built from SectionAssigned for section", sectionIndex)
    SectionVisuals.buildCentralStore()
    print("[Client] Central store built")
  end
end)

-- Track placed egg for hatching flow
local placedEggData: { id: string, eggType: string }? = nil

-- World egg visuals tracking for proximity prompts
local worldEggVisuals: { [string]: { model: Model, prompt: ProximityPrompt } } = {}

-- Connect to PlayerDataController for reactive UI updates
PlayerDataController.DataLoaded:Connect(function(data)
  MainHUD.updateFromPlayerData(data)
  InventoryUI.updateFromPlayerData(data)
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

  -- Build section visuals for player's assigned section
  if data.sectionIndex then
    SectionVisuals.buildSection(data.sectionIndex, {})
    print("[Client] Section visuals built for section", data.sectionIndex)

    -- Build the central store (shared by all players)
    SectionVisuals.buildCentralStore()

    -- Create visuals for already-placed traps
    if data.traps then
      local sectionCenter = MapGeneration.getSectionPosition(data.sectionIndex)
      if sectionCenter then
        for _, trap in ipairs(data.traps) do
          if trap.spotIndex and trap.spotIndex >= 1 and trap.spotIndex <= 8 then
            local spotPos = PlayerSection.getTrapSpotPosition(trap.spotIndex, sectionCenter)
            if spotPos then
              local position = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
              TrapVisuals.create(trap.id, trap.trapType, position, trap.spotIndex)
              print("[Client] Restored trap visual:", trap.id, "at spot", trap.spotIndex)
            end
          end
        end
      end
    end
  end

  -- Update ShieldUI with current shield state
  if data.shieldState then
    local status = AreaShield.getStatus(data.shieldState, os.time())
    ShieldUI.updateStatus(status)
  end

  -- Update owned weapons in StoreUI
  if data.ownedWeapons then
    StoreUI.updateOwnedWeapons(data.ownedWeapons)
  end

  -- Start tutorial for new players who haven't completed it
  if Tutorial.shouldShowTutorial(data) then
    -- Set up callbacks to mark tutorial as complete
    Tutorial.onComplete(function()
      PlayerDataController:CompleteTutorial()
        :catch(function(err)
          warn("[Client] Failed to complete tutorial:", tostring(err))
        end)
      print("[Client] Tutorial completed")
    end)

    Tutorial.onSkip(function()
      PlayerDataController:CompleteTutorial()
        :catch(function(err)
          warn("[Client] Failed to complete tutorial:", tostring(err))
        end)
      print("[Client] Tutorial skipped")
    end)

    -- Start the tutorial
    Tutorial.start()
    print("[Client] Tutorial started for new player")
  end

  print("[Client] Initial player data loaded via controller")
end)

PlayerDataController.DataChanged:Connect(function(data)
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
    print("[Client] Section visuals built from DataChanged for section", data.sectionIndex)
    SectionVisuals.buildCentralStore()
  end
end)

--[[ Client Game Loop ]]

-- Configuration for game loop updates
local PROXIMITY_CHECK_INTERVAL = 0.1
local LOCK_TIMER_UPDATE_INTERVAL = 1.0
local SHIELD_TIMER_UPDATE_INTERVAL = 1.0
local MONEY_COLLECTION_COOLDOWN = 0.5

-- Tracking variables
local lastProximityCheckTime = 0
local lastLockTimerUpdateTime = 0
local lastShieldTimerUpdateTime = 0
local isNearChicken = false
local nearestChickenId: string? = nil
local nearestChickenType: string? = nil
local lastCollectedChickenTimes: { [string]: number } = {}

-- Store interaction state
local STORE_INTERACTION_RANGE = 12
local isNearStore = false
local CHICKEN_INTERACTION_RANGE = 10

--[[
	Helper function to find the nearest placed chicken within interaction range.
]]
local function findNearbyPlacedChicken(
  playerPosition: Vector3
): (string?, string?, string?, number?)
  local playerData = PlayerDataController:GetData()
  if not playerData or not playerData.placedChickens then
    return nil, nil, nil, nil
  end

  local nearestDistance = CHICKEN_INTERACTION_RANGE
  local nearestChicken = nil

  for _, chicken in ipairs(playerData.placedChickens) do
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
]]
local function findNearbyAvailableTrapSpot(playerPosition: Vector3): number?
  local playerData = PlayerDataController:GetData()
  if not playerData then
    return nil
  end

  -- Use playerData.sectionIndex first, fall back to SectionVisuals if data hasn't synced yet
  local sectionIndex = playerData.sectionIndex or SectionVisuals.getCurrentSection()
  if not sectionIndex then
    return nil
  end

  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    return nil
  end

  local availableSpots = TrapPlacement.getAvailableSpots(playerData)
  if #availableSpots == 0 then
    return nil
  end

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

-- Wire up ChickenSelling callbacks for proximity checking
ChickenSelling.create()
ChickenSelling.setGetNearbyChicken(function(position: Vector3)
  local chickenId, chickenType, rarity, accumulatedMoney = findNearbyPlacedChicken(position)
  return chickenId, nil, chickenType, rarity, accumulatedMoney
end)
ChickenSelling.setGetPlayerData(function()
  return PlayerDataController:GetData()
end)

-- Wire up server-side sale via ChickenController
ChickenSelling.setPerformServerSale(function(chickenId: string)
  -- Get chicken position before selling (visual will be destroyed after)
  local visualState = ChickenVisuals.get(chickenId)
  local chickenPosition = visualState and visualState.position

  local success, result = ChickenController:SellChicken(chickenId):await()
  if success and result and result.success then
    SoundEffects.playMoneyCollect(result.sellPrice or 0)
    -- Show money pop effect at chicken's last position
    if chickenPosition and result.sellPrice and result.sellPrice > 0 then
      ChickenVisuals.createMoneyPopEffect({
        amount = result.sellPrice,
        position = chickenPosition + Vector3.new(0, 2, 0),
        isLarge = result.sellPrice >= 1000,
      })
    end
    return { success = true, message = result.message, sellPrice = result.sellPrice }
  else
    SoundEffects.play("uiError")
    return { success = false, error = result and result.message or "Unknown error" }
  end
end)

-- Wire up ChickenVisuals sell prompt to trigger ChickenSelling confirmation
ChickenVisuals.setOnSellPromptTriggered(function(chickenId: string)
  local visualState = ChickenVisuals.get(chickenId)
  if visualState then
    ChickenSelling.startSell(
      chickenId,
      visualState.chickenType,
      visualState.rarity,
      visualState.accumulatedMoney
    )
  end
end)

-- Wire up ChickenVisuals claim prompt to handle collecting random chickens
-- TODO: Add ClaimRandomChicken to ChickenController when implemented on server
ChickenVisuals.setOnClaimPromptTriggered(function(chickenId: string)
  -- Feature not yet implemented - needs server-side RandomChickenService
  warn("[Client] ClaimRandomChicken feature not implemented yet")
  SoundEffects.play("uiError")
end)

print("[Client] ChickenSelling system initialized")

-- Initialize MobileTouchControls and wire up button actions
MobileTouchControls.create()
MobileTouchControls.setAction("cancel", function()
  if ChickenSelling.isConfirming() then
    ChickenSelling.touchCancel()
  end
end)
MobileTouchControls.setAction("sell", function()
  ChickenSelling.touchSell()
end)
MobileTouchControls.setAction("confirm", function()
  ChickenSelling.touchSell()
end)
print("[Client] MobileTouchControls initialized")

-- Wire InventoryUI callbacks for item actions
InventoryUI.onItemSelected(function(selectedItem)
  if selectedItem then
    print("[Client] Inventory item selected:", selectedItem.itemType, selectedItem.itemId)
  else
    print("[Client] Inventory selection cleared")
  end
end)

InventoryUI.onAction(function(actionType: string, selectedItem)
  print("[Client] Inventory action:", actionType, selectedItem.itemType, selectedItem.itemId)
  local playerData = PlayerDataController:GetData()

  if selectedItem.itemType == "eggs" then
    if actionType == "place" then
      -- Use playerData.sectionIndex first, fall back to SectionVisuals if data hasn't synced yet
      local sectionIndex = (playerData and playerData.sectionIndex) or SectionVisuals.getCurrentSection()
      if not sectionIndex then
        SoundEffects.play("uiError")
        warn("[Client] Cannot hatch egg: No section assigned")
        return
      end

      local character = localPlayer.Character
      local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
      if not rootPart then
        SoundEffects.play("uiError")
        warn("[Client] Cannot hatch egg: Player position not found")
        return
      end

      local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
      local isInOwnArea = PlayerSection.isPositionInSection(rootPart.Position, sectionCenter)
      if not isInOwnArea then
        SoundEffects.play("uiError")
        warn("[Client] Cannot hatch egg: You must be in your own area")
        return
      end

      placedEggData = { id = selectedItem.itemId, eggType = selectedItem.itemData.eggType }
      HatchPreviewUI.show(selectedItem.itemId, selectedItem.itemData.eggType)
      SoundEffects.play("eggPlace")
      InventoryUI.clearSelection()
      print("[Client] Egg placed, showing hatch preview")
    elseif actionType == "sell" then
      EggController:SellEgg(selectedItem.itemId)
        :andThen(function(result)
          if result and result.success then
            SoundEffects.playMoneyCollect(result.sellPrice or 0)
            InventoryUI.clearSelection()
          else
            SoundEffects.play("uiError")
            warn("[Client] Egg sell failed:", result and result.message or "Unknown error")
          end
        end)
        :catch(function(err)
          SoundEffects.play("uiError")
          warn("[Client] Egg sell failed:", tostring(err))
        end)
    end
  elseif selectedItem.itemType == "chickens" then
    if actionType == "place" then
      if MainHUD.isAtChickenLimit() then
        SoundEffects.play("uiError")
        warn("[Client] Cannot place chicken: Area is at maximum capacity (15 chickens)")
        return
      end

      ChickenController:PlaceChicken(selectedItem.itemId)
        :andThen(function(result)
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
        end)
        :catch(function(err)
          SoundEffects.play("uiError")
          warn("[Client] Place failed:", tostring(err))
        end)
    elseif actionType == "sell" then
      local success, result = ChickenController:SellChicken(selectedItem.itemId):await()
      if success and result and result.success then
        SoundEffects.playMoneyCollect(result.sellPrice or 0)
        -- Show money pop effect near player for inventory sales
        local character = localPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart and result.sellPrice and result.sellPrice > 0 then
          ChickenVisuals.createMoneyPopEffect({
            amount = result.sellPrice,
            position = rootPart.Position + Vector3.new(0, 3, 0),
            isLarge = result.sellPrice >= 1000,
          })
        end
        InventoryUI.clearSelection()
      else
        SoundEffects.play("uiError")
        warn("[Client] Sell failed:", result and result.error or "Unknown error")
      end
    end
  elseif selectedItem.itemType == "traps" then
    if actionType == "place" then
      if selectedItem.itemData.spotIndex and selectedItem.itemData.spotIndex > 0 then
        SoundEffects.play("uiError")
        warn("[Client] Trap is already placed at spot", selectedItem.itemData.spotIndex)
        return
      end

      local character = localPlayer.Character
      if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
          local spotIndex = findNearbyAvailableTrapSpot(rootPart.Position)
          if spotIndex then
            TrapController:PlaceTrapFromInventory(selectedItem.itemId, spotIndex)
              :andThen(function(result)
                if result and result.success then
                  SoundEffects.play("trapPlace")
                  InventoryUI.clearSelection()
                  print("[Client] Trap placed at spot:", spotIndex)
                else
                  SoundEffects.play("uiError")
                  warn("[Client] Trap place failed:", result and result.message or "Unknown error")
                end
              end)
              :catch(function(err)
                SoundEffects.play("uiError")
                warn("[Client] Trap place failed:", tostring(err))
              end)
          else
            SoundEffects.play("uiError")
            warn("[Client] All trap spots are occupied (max 8 traps)")
          end
        end
      end
    elseif actionType == "sell" then
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

  if MainHUD.isAtChickenLimit() then
    SoundEffects.play("uiError")
    warn("[Client] Cannot hatch egg: Area is at maximum capacity (15 chickens)")
    HatchPreviewUI.hide()
    placedEggData = nil
    return
  end

  local playerPosition = nil
  local character = localPlayer.Character
  if character then
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart then
      local pos = humanoidRootPart.Position
      playerPosition = { x = pos.X, y = pos.Y, z = pos.Z }
    end
  end

  local success, result = EggController:HatchEgg(eggId):await()
  if success and result and result.success then
    SoundEffects.playEggHatch(result.chickenRarity or "Common")
    print("[Client] Egg hatched successfully:", result.chickenType, result.chickenRarity)
    HatchPreviewUI.showResult(result.chickenType, result.chickenRarity)
  elseif success and result and result.atLimit then
    SoundEffects.play("uiError")
    warn("[Client] Cannot hatch egg:", result.message)
  else
    SoundEffects.play("uiError")
    warn("[Client] Hatch failed:", success and result and result.message or (not success and tostring(result)) or "Unknown error")
  end

  placedEggData = nil
end)

HatchPreviewUI.onCancel(function()
  print("[Client] Hatch cancelled")
  placedEggData = nil
end)
print("[Client] HatchPreviewUI callbacks wired")

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
]]

local equippedWeaponTool: Tool? = nil

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

local SWING_DURATION = 0.15
local SWING_ANGLE = math.rad(80)
local isSwinging = false

local function playSwingAnimation(tool: Tool): ()
  if isSwinging then
    return
  end

  local handle = tool:FindFirstChild("Handle") :: BasePart?
  if not handle then
    return
  end

  local character = localPlayer.Character
  if not character then
    return
  end

  local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
  if not rightHand then
    return
  end

  local grip = rightHand:FindFirstChild("RightGrip") :: Motor6D?
  if not grip or not grip:IsA("Motor6D") then
    return
  end

  isSwinging = true

  local originalC1 = grip.C1
  local swingC1 = originalC1 * CFrame.Angles(SWING_ANGLE, 0, 0)

  local swingTween = TweenService:Create(
    grip,
    TweenInfo.new(SWING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { C1 = swingC1 }
  )
  swingTween:Play()
  swingTween.Completed:Wait()

  local returnTween = TweenService:Create(
    grip,
    TweenInfo.new(SWING_DURATION * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
    { C1 = originalC1 }
  )
  returnTween:Play()
  returnTween.Completed:Wait()

  isSwinging = false
end

local function onWeaponActivated(tool: Tool)
  SoundEffects.playBatSwing("miss")
  task.spawn(playSwingAnimation, tool)

  -- CombatController is assigned later in the script, so check if it's available
  if not CombatController then
    warn("[Client] CombatController not yet initialized, skipping attack")
    return
  end

  local predatorId, _ = findNearbyPredator()

  if predatorId then
    CombatController:Attack("predator", predatorId)
      :andThen(function(result)
        if result and result.success then
          if result.remainingHealth ~= nil then
            PredatorHealthBar.updateHealth(predatorId, result.remainingHealth)
          end
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
      end)
      :catch(function(err)
        warn("[Client] Attack failed:", tostring(err))
      end)
  else
    CombatController:Attack(nil, nil)
      :andThen(function(result)
        if result and result.success then
          SoundEffects.playBatSwing("miss")
        end
      end)
      :catch(function(err)
        warn("[Client] Attack failed:", tostring(err))
      end)
  end
end

local function onWeaponEquipped(tool: Tool)
  equippedWeaponTool = tool
  local weaponType = tool:GetAttribute("WeaponType") or tool.Name
  print("[Client] Weapon equipped:", weaponType)
  SoundEffects.playBatSwing("swing")
end

local function onWeaponUnequipped(tool: Tool)
  if equippedWeaponTool == tool then
    equippedWeaponTool = nil
  end
  local weaponType = tool:GetAttribute("WeaponType") or tool.Name
  print("[Client] Weapon unequipped:", weaponType)
end

local function setupWeaponTool(tool: Tool)
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

local function setupBackpackWatcher()
  local backpack = localPlayer:WaitForChild("Backpack", 10)
  if not backpack then
    warn("[Client] Backpack not found")
    return
  end

  for _, child in ipairs(backpack:GetChildren()) do
    if child:IsA("Tool") then
      setupWeaponTool(child)
    end
  end

  backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") then
      setupWeaponTool(child)
    end
  end)

  print("[Client] Backpack weapon watcher set up")
end

local function setupCharacterToolWatcher()
  local function watchCharacter(character: Model)
    for _, child in ipairs(character:GetChildren()) do
      if child:IsA("Tool") then
        setupWeaponTool(child)
      end
    end

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
    task.defer(setupBackpackWatcher)
  end)
end

setupBackpackWatcher()
setupCharacterToolWatcher()
print("[Client] Weapon Tool system initialized")

--[[
	Updates lock timer display on the HUD if player has an active lock.
]]
local function updateLockTimerDisplay()
  local playerData = PlayerDataController:GetData()
  if not playerData or not playerData.lockEndTime then
    return
  end

  local currentTime = os.time()
  local lockEndTime = playerData.lockEndTime

  if currentTime < lockEndTime then
    local remainingSeconds = lockEndTime - currentTime
    if remainingSeconds > 0 and remainingSeconds % 10 == 0 then
      print("[Client] Lock timer:", remainingSeconds, "seconds remaining")
    end
  end
end

--[[
	Updates proximity-based prompts based on player position.
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

  if ChickenSelling.isConfirming() then
    MobileTouchControls.showSellConfirmContext()
    return
  end

  local chickenId, chickenType, _, accumulatedMoney = findNearbyPlacedChicken(playerPosition)

  if chickenId then
    isNearChicken = true
    nearestChickenId = chickenId
    nearestChickenType = chickenType

    if accumulatedMoney and accumulatedMoney >= 1 then
      local currentTime = os.clock()
      local lastCollectTime = lastCollectedChickenTimes[chickenId] or 0

      if currentTime - lastCollectTime >= MONEY_COLLECTION_COOLDOWN then
        lastCollectedChickenTimes[chickenId] = currentTime

        task.spawn(function()
          local success, result = ChickenController:CollectMoney(chickenId):await()
          if
            success
            and result
            and result.success
            and result.amountCollected
            and result.amountCollected > 0
          then
            ChickenVisuals.resetAccumulatedMoney(chickenId, result.remainder or 0)
            SoundEffects.playMoneyCollect(result.amountCollected)
            local visualState = ChickenVisuals.get(chickenId)
            if visualState and visualState.position then
              ChickenVisuals.createMoneyPopEffect({
                amount = result.amountCollected,
                position = visualState.position + Vector3.new(0, 2, 0),
                isLarge = result.amountCollected >= 1000,
              })
            end
            ChickenVisuals.updateSellPromptPrice(chickenId)
          end
        end)
      end
    end

    MobileTouchControls.showSellContext()
  else
    if isNearChicken then
      MobileTouchControls.hideAllButtons()
    end
    isNearChicken = false
    nearestChickenId = nil
    nearestChickenType = nil
  end

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
	Update shield timer display.
	Called periodically to decrement the cooldown/duration timer.
]]
local function updateShieldTimerDisplay()
  local playerData = PlayerDataController:GetData()
  if playerData and playerData.shieldState then
    local status = AreaShield.getStatus(playerData.shieldState, os.time())
    ShieldUI.updateStatus(status)
  end
end

--[[
	Client game loop - runs every frame via Heartbeat.
]]
RunService.Heartbeat:Connect(function(deltaTime: number)
  local currentTime = os.clock()

  if currentTime - lastProximityCheckTime >= PROXIMITY_CHECK_INTERVAL then
    lastProximityCheckTime = currentTime
    updateProximityPrompts()
  end

  if currentTime - lastLockTimerUpdateTime >= LOCK_TIMER_UPDATE_INTERVAL then
    lastLockTimerUpdateTime = currentTime
    updateLockTimerDisplay()
  end

  if currentTime - lastShieldTimerUpdateTime >= SHIELD_TIMER_UPDATE_INTERVAL then
    lastShieldTimerUpdateTime = currentTime
    updateShieldTimerDisplay()
  end
end)

print("[Client] Client game loop started")

--[[
	Store Interaction Setup
]]

local function setupStoreInteraction()
  local store = SectionVisuals.getStore()
  if not store then
    task.delay(1, setupStoreInteraction)
    return
  end

  local prompt = store:FindFirstChild("StorePrompt", true)
  if prompt and prompt:IsA("ProximityPrompt") then
    prompt.Triggered:Connect(function(playerWhoTriggered)
      if playerWhoTriggered == localPlayer then
        StoreUI.toggle()
        print("[Client] Store opened via ProximityPrompt.Triggered")
      end
    end)

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

    print("[Client] Store prompt connected")
  else
    warn("[Client] StorePrompt not found in store model")
  end
end

task.delay(0.5, setupStoreInteraction)

-- Wire up PredatorController signals to PredatorVisuals
PredatorController.PredatorSpawned:Connect(function(predatorId, predatorType, userId, position, targetPosition, threatLevel, health, targetChickenId)
  if PredatorVisuals then
    local visualState = PredatorVisuals.create(predatorId, predatorType, threatLevel, position)
    if visualState and visualState.model and PredatorHealthBar then
      PredatorHealthBar.create(predatorId, predatorType, threatLevel, visualState.model)
    end
    PredatorVisuals.setAnimation(predatorId, "walking")
  end
  if PredatorWarning then
    PredatorWarning.show(predatorId, predatorType, threatLevel, position)
  end
  if SoundEffects then
    SoundEffects.playPredatorAlert(threatLevel == "Deadly" or threatLevel == "Catastrophic")
  end
  print("[Client] Predator spawned:", predatorType, "at", position)
end)

PredatorController.PredatorPositionUpdated:Connect(function(predatorId, position, direction, behavior)
  if PredatorVisuals then
    PredatorVisuals.updatePosition(predatorId, position)
    if behavior == "attacking" then
      PredatorVisuals.setAnimation(predatorId, "attacking")
    end
  end
  if PredatorWarning then
    PredatorWarning.updatePosition(predatorId, position)
  end
end)

PredatorController.PredatorHealthUpdated:Connect(function(predatorId, health, maxHealth)
  if PredatorHealthBar then
    PredatorHealthBar.updateHealth(predatorId, health)
  end
end)

PredatorController.PredatorDefeated:Connect(function(predatorId, wasDefeated)
  if PredatorHealthBar then
    PredatorHealthBar.destroy(predatorId)
  end
  if PredatorVisuals then
    PredatorVisuals.playDefeatedAnimation(predatorId)
  end
  if PredatorWarning then
    PredatorWarning.clear(predatorId)
  end
  if wasDefeated and SoundEffects then
    SoundEffects.playBatSwing("predator")
  end
end)

PredatorController.PredatorAlert:Connect(function(alert)
  if SoundEffects then
    local isUrgent = alert.threatLevel == "Deadly" or alert.threatLevel == "Catastrophic"
    SoundEffects.playPredatorAlert(isUrgent)
  end
end)

-- Wire up ChickenController signals to ChickenVisuals
ChickenController.ChickenPlaced:Connect(function(data)
  local chicken = data.chicken
  local position = data.position
  if chicken and position and ChickenVisuals then
    local pos = Vector3.new(position.X or position.x or 0, position.Y or position.y or 0, position.Z or position.z or 0)
    local visualState = ChickenVisuals.create(chicken.id, chicken.chickenType, pos, true)
    if visualState then
      -- Initialize with accumulated money from server data
      if chicken.accumulatedMoney and chicken.accumulatedMoney > 0 then
        ChickenVisuals.updateMoney(chicken.id, chicken.accumulatedMoney)
      end
      if visualState.model and ChickenHealthBar then
        ChickenHealthBar.create(chicken.id, chicken.chickenType, visualState.model)
      end
    end
  end
  if SoundEffects then
    SoundEffects.play("chickenPlace")
  end
end)

ChickenController.ChickenPickedUp:Connect(function(data)
  local chickenId = data.chickenId
  if chickenId then
    if ChickenVisuals then
      ChickenVisuals.destroy(chickenId)
    end
    if ChickenHealthBar then
      ChickenHealthBar.destroy(chickenId)
    end
    if SoundEffects then
      SoundEffects.play("chickenPickup")
    end
  end
end)

ChickenController.ChickenSold:Connect(function(data)
  local chickenId = data.chickenId
  if chickenId then
    if ChickenVisuals then
      ChickenVisuals.destroy(chickenId)
    end
    if ChickenHealthBar then
      ChickenHealthBar.destroy(chickenId)
    end
  end
end)

-- Wire up EggController signals to EggVisuals
EggController.EggHatched:Connect(function(data)
  local eggId = data.eggId
  local rarity = data.chickenRarity or data.rarity or "Common"
  if eggId and EggVisuals then
    EggVisuals.playHatchAnimation(eggId)
  end
  if SoundEffects then
    SoundEffects.playEggHatch(rarity)
  end
end)

EggController.EggSpawned:Connect(function(data)
  local eggId = data.id
  local eggType = data.eggType
  local chickenId = data.chickenId
  local position = data.position

  -- Play chicken laying animation if we know which chicken laid it
  if chickenId and ChickenVisuals then
    ChickenVisuals.playLayingAnimation(chickenId)
  end

  -- Create egg visual with proximity prompt for collection
  if eggId and position and EggVisuals then
    local eggPosition = Vector3.new(position.x, position.y, position.z)
    local eggVisualState = EggVisuals.create(eggId, eggType, eggPosition)

    if eggVisualState and eggVisualState.model then
      local primaryPart = eggVisualState.model.PrimaryPart
      if primaryPart then
        local prompt = Instance.new("ProximityPrompt")
        prompt.ObjectText = "Egg"
        prompt.ActionText = "Collect"
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 8
        prompt.RequiresLineOfSight = false
        prompt.Parent = primaryPart

        prompt.Triggered:Connect(function(playerWhoTriggered: Player)
          if playerWhoTriggered == localPlayer then
            EggController:CollectWorldEgg(eggId)
              :andThen(function(result)
                if result and result.success then
                  if SoundEffects then
                    SoundEffects.play("eggCollect")
                  end
                end
              end)
              :catch(function(err)
                warn("[Client] CollectWorldEgg failed:", tostring(err))
              end)
          end
        end)

        -- Track for cleanup
        worldEggVisuals[eggId] = {
          model = eggVisualState.model,
          prompt = prompt,
        }
      end
    end
  end

  if SoundEffects then
    SoundEffects.play("eggPlace")
  end
end)

EggController.EggCollected:Connect(function(data)
  local eggId = data.eggId
  if eggId then
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      if EggVisuals then
        EggVisuals.destroy(eggId)
      end
      worldEggVisuals[eggId] = nil
    end
  end
end)

EggController.EggDespawned:Connect(function(data)
  local eggId = data.eggId
  if eggId then
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      if EggVisuals then
        EggVisuals.destroy(eggId)
      end
      worldEggVisuals[eggId] = nil
    end
  end
end)

-- Wire up TrapController signals to TrapVisuals
TrapController.TrapPlaced:Connect(function(trapId, trapType, userId, spotIndex)
  -- Get position from section (use SectionVisuals fallback if playerData not synced)
  local playerData = PlayerDataController:GetData()
  local sectionIndex = (playerData and playerData.sectionIndex) or SectionVisuals.getCurrentSection()
  if sectionIndex and TrapVisuals then
    local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
    if sectionCenter then
      local spotPos = PlayerSection.getTrapSpotPosition(spotIndex, sectionCenter)
      if spotPos then
        local position = Vector3.new(spotPos.x, spotPos.y, spotPos.z)
        TrapVisuals.create(trapId, trapType, position, spotIndex)
      end
    end
  end
  if SoundEffects then
    SoundEffects.play("trapPlace")
  end
end)

TrapController.TrapPickedUp:Connect(function(trapId, userId)
  if TrapVisuals then
    TrapVisuals.destroy(trapId)
  end
end)

TrapController.TrapCaught:Connect(function(trapId, predatorType, catchProbability)
  if TrapVisuals then
    TrapVisuals.updateStatus(trapId, false, true)
    TrapVisuals.playCaughtAnimation(trapId)
  end
  if SoundEffects then
    SoundEffects.play("trapCatch")
  end
end)

-- Wire up store purchase callback
StoreUI.onPurchase(function(eggType: string, quantity: number)
  StoreController:BuyEgg(eggType, quantity)
    :andThen(function(result)
      if result and result.success then
        SoundEffects.play("purchase")
        print("[Client] Purchased", quantity, "x", eggType, ":", result.message)
      else
        SoundEffects.play("uiError")
        warn("[Client] Purchase failed:", result and result.message or "Unknown error")
      end
    end)
    :catch(function(err)
      SoundEffects.play("uiError")
      warn("[Client] Purchase failed:", tostring(err))
    end)
end)

-- Wire up store Robux replenish callback
-- TODO: Add ReplenishStoreWithRobux to StoreController/StoreService when implemented
StoreUI.onReplenish(function()
  -- Feature not yet implemented - needs Robux product integration
  warn("[Client] ReplenishStoreWithRobux feature not implemented yet")
  SoundEffects.play("uiError")
end)

-- Wire up store Robux item purchase callback
-- TODO: Add BuyItemWithRobux to StoreController/StoreService when implemented
StoreUI.onRobuxPurchase(function(itemType: string, itemId: string)
  -- Feature not yet implemented - needs Robux product integration
  warn("[Client] BuyItemWithRobux feature not implemented yet")
  SoundEffects.play("uiError")
end)

-- Wire up store power-up purchase callback
-- TODO: Add BuyPowerUp to StoreController/StoreService when implemented
StoreUI.onPowerUpPurchase(function(powerUpId: string)
  -- Feature not yet implemented - needs power-up service
  warn("[Client] BuyPowerUp feature not implemented yet")
  SoundEffects.play("uiError")
end)

-- Wire up store trap/supply purchase callback
StoreUI.onTrapPurchase(function(trapType: string)
  print("[Client] onTrapPurchase callback invoked with trapType:", trapType)
  StoreController:BuyTrap(trapType)
    :andThen(function(result)
      if result and result.success then
        SoundEffects.play("purchase")
        print("[Client] Trap purchased:", result.message)
        StoreUI.refreshInventory()
      else
        SoundEffects.play("uiError")
        warn("[Client] Trap purchase failed:", result and result.message or "Unknown error")
      end
    end)
    :catch(function(err)
      SoundEffects.play("uiError")
      warn("[Client] Trap purchase failed:", tostring(err))
    end)
end)

StoreUI.onWeaponPurchase(function(weaponType: string)
  StoreController:BuyWeapon(weaponType)
    :andThen(function(result)
      if result and result.success then
        SoundEffects.play("purchase")
        print("[Client] Weapon purchased:", result.message)
        StoreUI.refreshInventory()
      else
        SoundEffects.play("uiError")
        warn("[Client] Weapon purchase failed:", result and result.message or "Unknown error")
      end
    end)
    :catch(function(err)
      SoundEffects.play("uiError")
      warn("[Client] Weapon purchase failed:", tostring(err))
    end)
end)

-- Wire ShieldUI activation callback to server
ShieldUI.onActivate(function()
  CombatController:ActivateShield()
    :andThen(function(result)
      if result and result.success then
        print("[Client] Shield activation successful:", result.message)
      else
        ShieldUI.showActivationFeedback(false, result and result.message or "Unknown error")
        print("[Client] Shield activation failed:", result and result.message or "Unknown error")
      end
    end)
    :catch(function(err)
      ShieldUI.showActivationFeedback(false, tostring(err))
      warn("[Client] Shield activation failed:", tostring(err))
    end)
end)

--[[
	Fallback E key handler for store interaction.
]]
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
  if gameProcessed then
    return
  end

  if input.KeyCode == Enum.KeyCode.E then
    if isNearStore and not isNearChicken then
      StoreUI.toggle()
      print("[Client] Store opened via fallback E key handler")
    end
  end
end)

print("[Client] Main client script fully initialized")
