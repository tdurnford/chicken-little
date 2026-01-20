--[[
	ClientEventRelay
	Handles the relay of server RemoteEvents to client visual modules.
	
	This module bridges the gap between server events and client visuals.
	Controllers handle state and methods, while this relay handles visual updates.
	
	Architecture:
	- Server fires RemoteEvent -> ClientEventRelay receives -> Fires to visual modules
	- Visual modules (ChickenVisuals, PredatorVisuals, etc.) handle rendering
	- Controllers handle state and server method calls
	
	Note: This is a transitional module. As services add more signals,
	this relay can be gradually deprecated in favor of controller signals.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

-- Remotes folder reference (loaded lazily in start())
local Remotes: Folder? = nil

-- Type definitions
export type EventRelayConfig = {
  soundEffects: any?,
  chickenVisuals: any?,
  chickenHealthBar: any?,
  predatorVisuals: any?,
  predatorHealthBar: any?,
  predatorWarning: any?,
  eggVisuals: any?,
  trapVisuals: any?,
  damageUI: any?,
  shieldUI: any?,
  mainHUD: any?,
  storeUI: any?,
  sectionVisuals: any?,
}

-- Internal state
local config: EventRelayConfig = {}
local worldEggVisuals: { [string]: { model: Model, prompt: ProximityPrompt } } = {}
local connections: { RBXScriptConnection } = {}

-- Module
local ClientEventRelay = {}

--[[
	Helper to get RemoteEvent safely
]]
local function getEvent(name: string): RemoteEvent?
  if not Remotes then
    return nil
  end
  local event = Remotes:FindFirstChild(name)
  if event and event:IsA("RemoteEvent") then
    return event :: RemoteEvent
  end
  return nil
end

--[[
	Helper to get RemoteFunction safely
]]
local function getFunction(name: string): RemoteFunction?
  if not Remotes then
    return nil
  end
  local func = Remotes:FindFirstChild(name)
  if func and func:IsA("RemoteFunction") then
    return func :: RemoteFunction
  end
  return nil
end

--[[
	Expose getFunction for modules that need to make server calls
]]
function ClientEventRelay.getFunction(name: string): RemoteFunction?
  return getFunction(name)
end

--[[
	Expose getEvent for modules that need direct access
]]
function ClientEventRelay.getEvent(name: string): RemoteEvent?
  return getEvent(name)
end

--[[
	Initialize the relay with visual module references.
	Must be called before start().
]]
function ClientEventRelay.configure(cfg: EventRelayConfig)
  config = cfg
end

--[[
	Connect to a RemoteEvent and store the connection for cleanup.
]]
local function connectEvent(eventName: string, handler: (...any) -> ())
  local event = getEvent(eventName)
  if event then
    local conn = event.OnClientEvent:Connect(handler)
    table.insert(connections, conn)
  else
    warn("[ClientEventRelay] Event not found:", eventName)
  end
end

--[[
	Start listening to all server events and relay to visual modules.
]]
function ClientEventRelay.start()
  -- Wait for Remotes folder if not already loaded
  if not Remotes then
    Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
  end
  
  if not Remotes then
    warn("[ClientEventRelay] Remotes folder not found after 30s timeout - server may not have initialized remotes yet")
    return
  end

  -- Chicken Events
  connectEvent("ChickenPlaced", function(eventData: { [string]: any })
    local chicken = eventData.chicken
    if not chicken then
      return
    end

    local position: Vector3
    if eventData.position then
      local pos = eventData.position
      position = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
    else
      position = Vector3.new(0, 5, 0)
    end

    if config.chickenVisuals then
      local visualState =
        config.chickenVisuals.create(chicken.id, chicken.chickenType, position, true)
      if visualState and visualState.model and config.chickenHealthBar then
        config.chickenHealthBar.create(chicken.id, chicken.chickenType, visualState.model)
      end
    end
    if config.soundEffects then
      config.soundEffects.play("chickenPlace")
    end
  end)

  connectEvent("ChickenPickedUp", function(data: any)
    local chickenId: string
    if type(data) == "string" then
      chickenId = data
    elseif type(data) == "table" then
      chickenId = data.chickenId
    else
      return
    end

    if config.chickenVisuals then
      config.chickenVisuals.destroy(chickenId)
    end
    if config.chickenHealthBar then
      config.chickenHealthBar.destroy(chickenId)
    end
    if config.soundEffects then
      config.soundEffects.play("chickenPickup")
    end
  end)

  connectEvent("ChickenSold", function(chickenId: string, sellPrice: number)
    if config.chickenVisuals then
      config.chickenVisuals.destroy(chickenId)
    end
    if config.chickenHealthBar then
      config.chickenHealthBar.destroy(chickenId)
    end
    if config.soundEffects then
      config.soundEffects.playMoneyCollect(sellPrice)
    end
  end)

  connectEvent("ChickenDamaged", function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local newHealth = eventData.newHealth
    local maxHealth = eventData.maxHealth

    if chickenId and newHealth then
      if config.chickenHealthBar then
        config.chickenHealthBar.updateHealth(chickenId, newHealth)
      end
      if maxHealth and maxHealth > 0 and config.chickenVisuals then
        config.chickenVisuals.updateHealthState(chickenId, newHealth / maxHealth)
      end
    end
  end)

  connectEvent("ChickenHealthChanged", function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    local newHealth = eventData.newHealth
    local maxHealth = eventData.maxHealth

    if chickenId and newHealth then
      if config.chickenHealthBar then
        config.chickenHealthBar.updateHealth(chickenId, newHealth)
      end
      if maxHealth and maxHealth > 0 and config.chickenVisuals then
        config.chickenVisuals.updateHealthState(chickenId, newHealth / maxHealth)
      end
    end
  end)

  connectEvent("ChickenDied", function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    if chickenId then
      if config.chickenVisuals then
        config.chickenVisuals.destroy(chickenId)
      end
      if config.chickenHealthBar then
        config.chickenHealthBar.destroy(chickenId)
      end
      if config.soundEffects then
        config.soundEffects.play("chickenPickup")
      end
    end
  end)

  connectEvent("ChickenPositionUpdated", function(data: any)
    if not data or not data.chickens then
      return
    end
    if config.chickenVisuals then
      for _, chickenData in ipairs(data.chickens) do
        if chickenData.chickenId and chickenData.position and chickenData.facingDirection then
          local position =
            Vector3.new(chickenData.position.X, chickenData.position.Y, chickenData.position.Z)
          local targetPosition = if chickenData.targetPosition
            then Vector3.new(
              chickenData.targetPosition.X,
              chickenData.targetPosition.Y,
              chickenData.targetPosition.Z
            )
            else nil
          local facingDirection = Vector3.new(
            chickenData.facingDirection.X,
            chickenData.facingDirection.Y,
            chickenData.facingDirection.Z
          )
          config.chickenVisuals.updatePosition(
            chickenData.chickenId,
            position,
            targetPosition,
            facingDirection,
            chickenData.walkSpeed,
            chickenData.isIdle
          )
        end
      end
    end
  end)

  -- Egg Events
  connectEvent("EggHatched", function(eggId: string, chickenType: string, rarity: string)
    if config.eggVisuals then
      config.eggVisuals.playHatchAnimation(eggId)
    end
    if config.soundEffects then
      config.soundEffects.playEggHatch(rarity)
    end
  end)

  connectEvent("EggSpawned", function(eggData: { [string]: any })
    local eggId = eggData.id
    local eggType = eggData.eggType
    local chickenId = eggData.chickenId
    local position = eggData.position

    if chickenId and config.chickenVisuals then
      config.chickenVisuals.playLayingAnimation(chickenId)
    end

    if config.eggVisuals then
      local eggPosition = Vector3.new(position.x, position.y, position.z)
      local eggVisualState = config.eggVisuals.create(eggId, eggType, eggPosition)

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
              local collectFunc = getFunction("CollectWorldEgg")
              if collectFunc then
                local result = collectFunc:InvokeServer(eggId)
                if result and result.success then
                  if config.soundEffects then
                    config.soundEffects.play("eggCollect")
                  end
                end
              end
            end
          end)

          worldEggVisuals[eggId] = {
            model = eggVisualState.model,
            prompt = prompt,
          }
        end
      end
    end

    if config.soundEffects then
      config.soundEffects.play("eggPlace")
    end
  end)

  connectEvent("EggCollected", function(eventData: { [string]: any })
    local eggId = eventData.eggId
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      if config.eggVisuals then
        config.eggVisuals.destroy(eggId)
      end
      worldEggVisuals[eggId] = nil
    end
  end)

  connectEvent("EggDespawned", function(eventData: { [string]: any })
    local eggId = eventData.eggId
    local eggVisual = worldEggVisuals[eggId]
    if eggVisual then
      if eggVisual.prompt then
        eggVisual.prompt:Destroy()
      end
      if config.eggVisuals then
        config.eggVisuals.destroy(eggId)
      end
      worldEggVisuals[eggId] = nil
    end
  end)

  -- Predator Events
  connectEvent(
    "PredatorSpawned",
    function(
      predatorId: string,
      predatorType: string,
      threatLevel: string,
      position: Vector3,
      sectionIndex: number?,
      targetChickenId: string?
    )
      if config.predatorVisuals then
        local visualState =
          config.predatorVisuals.create(predatorId, predatorType, threatLevel, position)
        if visualState and visualState.model and config.predatorHealthBar then
          config.predatorHealthBar.create(predatorId, predatorType, threatLevel, visualState.model)
        end
        config.predatorVisuals.setAnimation(predatorId, "walking")
      end
      if config.predatorWarning then
        config.predatorWarning.show(predatorId, predatorType, threatLevel, position)
      end
      if config.soundEffects then
        config.soundEffects.playPredatorAlert(
          threatLevel == "Deadly" or threatLevel == "Catastrophic"
        )
      end
    end
  )

  connectEvent(
    "PredatorPositionUpdated",
    function(predatorId: string, newPosition: Vector3, hasReachedCoop: boolean)
      if config.predatorVisuals then
        config.predatorVisuals.updatePosition(predatorId, newPosition)
        if hasReachedCoop then
          config.predatorVisuals.setAnimation(predatorId, "attacking")
        end
      end
      if config.predatorWarning then
        config.predatorWarning.updatePosition(predatorId, newPosition)
      end
    end
  )

  connectEvent(
    "PredatorHealthUpdated",
    function(predatorId: string, currentHealth: number, maxHealth: number, damage: number)
      if config.predatorHealthBar then
        config.predatorHealthBar.updateHealth(predatorId, currentHealth)
        if damage and damage > 0 then
          config.predatorHealthBar.showDamageNumber(predatorId, damage)
        end
      end
    end
  )

  connectEvent("PredatorDefeated", function(predatorId: string, byPlayer: boolean)
    if config.predatorHealthBar then
      config.predatorHealthBar.destroy(predatorId)
    end
    if config.predatorVisuals then
      config.predatorVisuals.playDefeatedAnimation(predatorId)
    end
    if config.predatorWarning then
      config.predatorWarning.clear(predatorId)
    end
    if byPlayer and config.soundEffects then
      config.soundEffects.playBatSwing("predator")
    end
  end)

  connectEvent("PredatorTargetChanged", function(predatorId: string, newTargetChickenId: string?)
    -- Target indicator removed per UI cleanup
  end)

  -- Money Events
  connectEvent("MoneyCollected", function(amount: number, position: Vector3?)
    if config.soundEffects then
      config.soundEffects.playMoneyCollect(amount)
    end
    if position and config.chickenVisuals then
      config.chickenVisuals.createMoneyPopEffect({
        amount = amount,
        position = position,
        isLarge = amount >= 1000,
      })
    end
  end)

  -- Trap Events
  connectEvent(
    "TrapPlaced",
    function(trapId: string, trapType: string, position: Vector3, spotIndex: number?)
      if config.trapVisuals then
        config.trapVisuals.create(trapId, trapType, position, spotIndex or 1)
      end
      if config.soundEffects then
        config.soundEffects.play("trapPlace")
      end
    end
  )

  connectEvent("TrapCaught", function(trapId: string, predatorId: string)
    if config.trapVisuals then
      config.trapVisuals.updateStatus(trapId, false, true)
      config.trapVisuals.playCaughtAnimation(trapId)
    end
    if config.predatorVisuals then
      config.predatorVisuals.playTrappedAnimation(predatorId)
    end
    if config.soundEffects then
      config.soundEffects.play("trapCatch")
    end
  end)

  -- Lock Events
  connectEvent("LockActivated", function(cageId: string, lockDuration: number)
    if config.soundEffects then
      config.soundEffects.play("lockActivate")
    end
  end)

  -- Trade Events
  connectEvent("TradeRequested", function(fromPlayer: Player, tradeId: string)
    if config.soundEffects then
      config.soundEffects.play("uiNotification")
    end
  end)

  connectEvent("TradeUpdated", function(tradeId: string, tradeData: { [string]: any })
    -- Trade UI updates handled by TradeController
  end)

  connectEvent("TradeCompleted", function(tradeId: string, success: boolean)
    if config.soundEffects then
      if success then
        config.soundEffects.play("tradeComplete")
      else
        config.soundEffects.play("uiError")
      end
    end
  end)

  -- Random Chicken Events
  connectEvent("RandomChickenSpawned", function(eventData: { [string]: any })
    local chicken = eventData.chicken
    if not chicken then
      return
    end

    if config.soundEffects then
      config.soundEffects.play("uiNotification")
    end
    if config.chickenVisuals then
      local pos = chicken.position
      local position = Vector3.new(pos.x, pos.y, pos.z)
      config.chickenVisuals.create(chicken.id, chicken.chickenType, position, false)
    end
  end)

  connectEvent("RandomChickenClaimed", function(chickenId: string, claimedBy: Player)
    if config.chickenVisuals then
      local chicken = config.chickenVisuals.get(chickenId)
      if chicken then
        config.chickenVisuals.playCelebrationAnimation(chickenId)
        task.delay(0.5, function()
          config.chickenVisuals.destroy(chickenId)
        end)
      end
    end
    if claimedBy == localPlayer and config.soundEffects then
      config.soundEffects.play("chickenClaim")
    end
  end)

  connectEvent("RandomChickenDespawned", function(eventData: { [string]: any })
    local chickenId = eventData.chickenId
    if chickenId and config.chickenVisuals then
      config.chickenVisuals.destroy(chickenId)
    end
  end)

  connectEvent("RandomChickenPositionUpdated", function(data: any)
    if not data or not data.id then
      return
    end
    if config.chickenVisuals then
      local position = Vector3.new(data.position.x, data.position.y, data.position.z)
      local targetPosition = if data.targetPosition
        then Vector3.new(data.targetPosition.x, data.targetPosition.y, data.targetPosition.z)
        else nil
      local facingDirection =
        Vector3.new(data.facingDirection.x, data.facingDirection.y, data.facingDirection.z)
      config.chickenVisuals.updatePosition(
        data.id,
        position,
        targetPosition,
        facingDirection,
        data.walkSpeed,
        data.isIdle
      )
    end
  end)

  -- Alert Events
  connectEvent("AlertTriggered", function(alertType: string, urgent: boolean)
    if config.soundEffects then
      config.soundEffects.playPredatorAlert(urgent)
    end
  end)

  -- Store Events
  connectEvent("StoreReplenished", function(newInventory: any)
    local Shared = ReplicatedStorage:WaitForChild("Shared")
    local Store = require(Shared:WaitForChild("Store"))
    Store.setStoreInventory(newInventory)
    if config.storeUI then
      config.storeUI.refreshInventory()
    end
  end)

  connectEvent("StoreInventoryUpdated", function(data: any)
    if config.storeUI then
      if data.itemType and data.itemId and data.newStock ~= nil then
        config.storeUI.updateItemStock(data.itemType, data.itemId, data.newStock)
      end
      if data.inventory then
        local Shared = ReplicatedStorage:WaitForChild("Shared")
        local Store = require(Shared:WaitForChild("Store"))
        Store.setStoreInventory(data.inventory)
        config.storeUI.refreshInventory()
      end
    end
  end)

  -- Player Damage/Combat Events
  connectEvent("PlayerDamaged", function(data: any)
    if config.damageUI then
      config.damageUI.onPlayerDamaged(data)
    end
    if config.soundEffects then
      config.soundEffects.playHurt()
    end
  end)

  connectEvent("PlayerKnockback", function(data: any)
    if config.damageUI then
      config.damageUI.onPlayerKnockback(data)
    end
  end)

  connectEvent("MoneyLost", function(data: any)
    if config.damageUI then
      config.damageUI.onMoneyLost(data)
    end
  end)

  connectEvent("PlayerHealthChanged", function(data: any)
    if config.damageUI then
      config.damageUI.onPlayerHealthChanged(data)
    end
  end)

  connectEvent("ProtectionStatusChanged", function(data: any)
    if config.mainHUD then
      config.mainHUD.setProtectionStatus(data)
    end
  end)

  connectEvent("BankruptcyAssistance", function(data: any)
    if config.soundEffects then
      config.soundEffects.play("uiNotification")
    end
    if config.mainHUD then
      config.mainHUD.showBankruptcyAssistance(data)
    end
  end)

  -- Shield Events
  connectEvent("ShieldActivated", function(userId: number, sectionIndex: number, shieldData: any)
    if userId == localPlayer.UserId then
      local Shared = ReplicatedStorage:WaitForChild("Shared")
      local AreaShield = require(Shared:WaitForChild("AreaShield"))
      local status = AreaShield.getStatus({
        isActive = true,
        activatedTime = os.time(),
        expiresAt = shieldData.expiresAt,
        cooldownEndTime = shieldData.expiresAt + AreaShield.getConstants().shieldCooldown,
      }, os.time())
      if config.shieldUI then
        config.shieldUI.updateStatus(status)
        config.shieldUI.showActivationFeedback(true, "Shield activated!")
      end
      if config.soundEffects then
        config.soundEffects.play("uiNotification")
      end
    end
  end)

  connectEvent("ShieldDeactivated", function(userId: number, sectionIndex: number)
    -- Shield UI update handled via PlayerDataController
  end)

  connectEvent("PlayerIncapacitated", function(data: any)
    if config.damageUI then
      config.damageUI.onPlayerIncapacitated(data)
    end
    if config.soundEffects then
      config.soundEffects.playKnockback()
    end

    -- Handle movement restriction
    local character = localPlayer.Character
    if character then
      local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
      if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
      end

      local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
      if rootPart then
        local knockbackDirection = -rootPart.CFrame.LookVector
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Name = "IncapKnockback"
        bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
        bodyVelocity.Velocity = knockbackDirection * 50 + Vector3.new(0, 20, 0)
        bodyVelocity.Parent = rootPart

        task.delay(0.3, function()
          if bodyVelocity and bodyVelocity.Parent then
            bodyVelocity:Destroy()
          end
        end)
      end
    end

    task.delay(data.duration, function()
      local char = localPlayer.Character
      if char then
        local hum = char:FindFirstChild("Humanoid") :: Humanoid?
        if hum then
          hum.WalkSpeed = 16
          hum.JumpPower = 50
        end
      end
    end)
  end)

  -- Nightfall Warning
  connectEvent("NightfallWarning", function(data: any)
    local timeOfDay = data.timeOfDay

    if config.soundEffects then
      if timeOfDay == "night" then
        config.soundEffects.playPredatorAlert(true)
      elseif timeOfDay == "dusk" then
        config.soundEffects.playPredatorAlert(false)
      else
        config.soundEffects.play("uiNotification")
      end
    end

    if config.mainHUD and config.mainHUD.showNotification then
      local color = Color3.fromRGB(255, 200, 100)
      if timeOfDay == "night" then
        color = Color3.fromRGB(255, 80, 80)
      elseif timeOfDay == "dawn" then
        color = Color3.fromRGB(150, 200, 255)
      end
      config.mainHUD.showNotification(data.message, color, 4)
    end
  end)

  -- XP/Level Events
  connectEvent("XPGained", function(amount: number, reason: string)
    if config.mainHUD then
      config.mainHUD.showXPGain(amount)
    end
    if config.soundEffects then
      config.soundEffects.play("xpGain")
    end
  end)

  connectEvent("LevelUp", function(newLevel: number, unlocks: { string })
    if config.mainHUD then
      config.mainHUD.showLevelUp(newLevel, unlocks)
    end
    if config.soundEffects then
      config.soundEffects.play("levelUp")
    end
  end)

  print("[ClientEventRelay] Started - listening to all server events")
end

--[[
	Stop the relay and disconnect all events.
]]
function ClientEventRelay.stop()
  for _, conn in ipairs(connections) do
    conn:Disconnect()
  end
  connections = {}
  print("[ClientEventRelay] Stopped")
end

return ClientEventRelay
