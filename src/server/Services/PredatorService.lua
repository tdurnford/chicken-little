--[[
	PredatorService
	Knit service that handles all predator-related server logic.
	
	Provides:
	- Predator spawning with wave management
	- Predator AI movement and targeting
	- Predator combat (bat hits, damage)
	- Predator defeat and rewards
	- Event broadcasting for visual updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
local PredatorAI = require(Shared:WaitForChild("PredatorAI"))
local PredatorAttack = require(Shared:WaitForChild("PredatorAttack"))
local XPConfig = require(Shared:WaitForChild("XPConfig"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Services will be retrieved after Knit starts
local PlayerDataService
local MapService
local CombatService

-- Create the service
local PredatorService = Knit.CreateService({
  Name = "PredatorService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    PredatorSpawned = Knit.CreateSignal(), -- Fires to all clients when predator spawns
    PredatorPositionUpdated = Knit.CreateSignal(), -- Fires to all clients with position updates
    PredatorHealthUpdated = Knit.CreateSignal(), -- Fires to all clients when predator hit
    PredatorDefeated = Knit.CreateSignal(), -- Fires to all clients when predator defeated/escaped
    PredatorTargetChanged = Knit.CreateSignal(), -- Fires to all clients when predator re-targets
    PredatorAlert = Knit.CreateSignal(), -- Fires to owner with predator alerts
    ChickensLost = Knit.CreateSignal(), -- Fires to owner when chickens are lost to predator attack
  },
})

-- Server-side signals (for other services to listen to)
PredatorService.PredatorSpawnedSignal = GoodSignal.new() -- (userId: number, predator: PredatorInstance)
PredatorService.PredatorDefeatedSignal = GoodSignal.new() -- (userId: number, predatorId: string, reward: number)
PredatorService.PredatorEscapedSignal = GoodSignal.new() -- (userId: number, predatorId: string)
PredatorService.ChickenDamaged = GoodSignal.new() -- (userId: number, chickenId: string, damage: number, source: string)
PredatorService.ChickensLostSignal = GoodSignal.new() -- (userId: number, predatorId: string, chickenIds: {string}, totalValueLost: number)
PredatorService.XPAwarded = GoodSignal.new() -- (userId: number, amount: number, reason: string)

-- Per-player predator state tracking
local playerPredatorStates: {
  [number]: {
    spawnState: PredatorSpawning.SpawnState,
    aiState: PredatorAI.PredatorAIState,
    dayNightState: DayNightCycle.DayNightState?,
    lastCleanupTime: number,
  },
} =
  {}

-- Constants
local PREDATOR_CLEANUP_INTERVAL = 10 -- Seconds between cleanup passes
local PREDATOR_ATTACK_RANGE_STUDS = 15 -- Distance to coop for attacks

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function PredatorService:KnitInit()
  print("[PredatorService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function PredatorService:KnitStart()
  -- Get reference to PlayerDataService
  PlayerDataService = Knit.GetService("PlayerDataService")
  MapService = Knit.GetService("MapService")
  CombatService = Knit.GetService("CombatService")

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

  print("[PredatorService] Started")
end

--[[
	Update function called by GameLoopService every frame.
	Handles predator spawning and position updates for all players.
	@param deltaTime number - Time since last frame
]]
function PredatorService:Update(deltaTime: number)
  local currentTime = os.time()
  
  for _, player in ipairs(Players:GetPlayers()) do
    local userId = player.UserId
    local state = playerPredatorStates[userId]
    
    if state then
      -- 1. Check if we should spawn a predator
      if self:ShouldSpawn(userId) then
        -- Get player's section for spawn position
        local sectionIndex = MapService:GetPlayerSection(userId)
        if sectionIndex then
          local sectionPos = MapGeneration.getSectionPosition(sectionIndex)
          if sectionPos then
            local sectionCenter = Vector3.new(sectionPos.x, sectionPos.y, sectionPos.z)
            
            -- Get a target chicken if player has any
            local playerData = PlayerDataService and PlayerDataService:GetData(userId)
            local targetChickenId = nil
            local targetChickenPosition = nil
            
            if playerData and playerData.placedChickens and #playerData.placedChickens > 0 then
              -- Pick a random chicken to target
              local randomChicken = playerData.placedChickens[math.random(1, #playerData.placedChickens)]
              if randomChicken then
                targetChickenId = randomChicken.id
                -- If chicken has position data, use it
                if randomChicken.position then
                  targetChickenPosition = Vector3.new(
                    randomChicken.position.x or sectionPos.x,
                    randomChicken.position.y or sectionPos.y,
                    randomChicken.position.z or sectionPos.z
                  )
                else
                  -- Default to section center
                  targetChickenPosition = sectionCenter
                end
              end
            end
            
            -- Spawn the predator
            local result = self:SpawnPredator(userId, sectionCenter, targetChickenId, targetChickenPosition)
            if result.success then
              print(string.format("[PredatorService] %s for player %s", result.message, player.Name))
              
              -- Send alert to player
              if result.predator then
                self:SendAlert(userId, result.predator.id, "approaching")
              end
            end
          end
        end
      end
      
      -- 2. Update predator positions
      self:UpdatePredatorPositions(userId, deltaTime)
      
      -- 3. Check for predators entering section and update states
      for _, predator in ipairs(PredatorSpawning.getActivePredators(state.spawnState)) do
        self:CheckPredatorEnteredSection(userId, predator.id)
      end
      
      -- 4. Execute predator attacks on chickens (when in attacking state and interval elapsed)
      self:ExecutePredatorAttacks(userId, currentTime)
      
      -- 5. Apply predator damage to player (when predators are attacking and in range)
      self:ApplyPredatorDamageToPlayer(userId, deltaTime)
      
      -- 6. Periodic cleanup
      self:CleanupInactivePredators(userId)
    end
  end
end

--[[
	Initialize predator state for a player.
	@param userId number - The user ID
]]
function PredatorService:_initializePlayerState(userId: number)
  if playerPredatorStates[userId] then
    return -- Already initialized
  end

  -- Get player level from data for spawn state initialization
  local playerLevel = 1
  local playerData = PlayerDataService and PlayerDataService:GetData(userId)
  if playerData then
    playerLevel = playerData.level or 1
  end

  playerPredatorStates[userId] = {
    spawnState = PredatorSpawning.createSpawnState(playerLevel),
    aiState = PredatorAI.createState(),
    dayNightState = DayNightCycle.init(),
    lastCleanupTime = os.time(),
  }
end

--[[
	Cleanup predator state for a player.
	@param userId number - The user ID
]]
function PredatorService:_cleanupPlayerState(userId: number)
  playerPredatorStates[userId] = nil
end

--[[
	Get the spawn state for a player.
	@param userId number - The user ID
	@return SpawnState?
]]
function PredatorService:GetSpawnState(userId: number): PredatorSpawning.SpawnState?
  local state = playerPredatorStates[userId]
  return state and state.spawnState
end

--[[
	Get the AI state for a player.
	@param userId number - The user ID
	@return PredatorAIState?
]]
function PredatorService:GetAIState(userId: number): PredatorAI.PredatorAIState?
  local state = playerPredatorStates[userId]
  return state and state.aiState
end

--[[
	Get the day/night state for a player.
	@param userId number - The user ID
	@return DayNightState?
]]
function PredatorService:GetDayNightState(userId: number): DayNightCycle.DayNightState?
  local state = playerPredatorStates[userId]
  return state and state.dayNightState
end

--[[
	Set day/night state for a player (called by GameStateService).
	@param userId number - The user ID
	@param dayNightState DayNightState - The day/night state
]]
function PredatorService:SetDayNightState(
  userId: number,
  dayNightState: DayNightCycle.DayNightState
)
  local state = playerPredatorStates[userId]
  if state then
    state.dayNightState = dayNightState
  end
end

--[[
	Update player level in spawn state (called when player levels up).
	@param userId number - The user ID
	@param level number - The new level
]]
function PredatorService:UpdatePlayerLevel(userId: number, level: number)
  local state = playerPredatorStates[userId]
  if state then
    PredatorSpawning.setPlayerLevel(state.spawnState, level)
  end
end

--[[
	Get active predators for a player.
	@param userId number - The user ID
	@return {PredatorInstance}
]]
function PredatorService:GetActivePredators(userId: number): { PredatorSpawning.PredatorInstance }
  local state = playerPredatorStates[userId]
  if not state then
    return {}
  end
  return PredatorSpawning.getActivePredators(state.spawnState)
end

--[[
	Get predator position data.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@return PredatorPosition?
]]
function PredatorService:GetPredatorPosition(
  userId: number,
  predatorId: string
): PredatorAI.PredatorPosition?
  local state = playerPredatorStates[userId]
  if not state then
    return nil
  end
  return PredatorAI.getPosition(state.aiState, predatorId)
end

--[[
	Get spawn summary for UI display.
	@param userId number - The user ID
	@return SpawnSummary
]]
function PredatorService:GetSpawnSummary(userId: number): any
  local state = playerPredatorStates[userId]
  if not state then
    return {
      waveNumber = 0,
      activePredators = 0,
      maxPredators = 1,
      predatorsSpawned = 0,
      timeUntilNextSpawn = 60,
      difficultyMultiplier = 1,
      dominantThreat = "Minor",
      timeOfDayMultiplier = 1,
      playerLevel = 1,
    }
  end

  local timeMultiplier = 1
  if state.dayNightState then
    timeMultiplier = DayNightCycle.getPredatorSpawnMultiplier(state.dayNightState)
  end

  return PredatorSpawning.getSummary(state.spawnState, os.time(), timeMultiplier)
end

--[[
	Spawn a predator for a player (called by game loop).
	@param userId number - The user ID
	@param sectionCenter Vector3 - Center of player's section
	@param targetChickenId string? - Optional chicken to target
	@param targetChickenPosition Vector3? - Position of target chicken
	@return SpawnResult
]]
function PredatorService:SpawnPredator(
  userId: number,
  sectionCenter: Vector3,
  targetChickenId: string?,
  targetChickenPosition: Vector3?
): PredatorSpawning.SpawnResult
  local state = playerPredatorStates[userId]
  if not state then
    return {
      success = false,
      message = "Player state not found",
      predator = nil,
      nextSpawnTime = nil,
    }
  end

  local currentTime = os.time()
  local timeMultiplier = 1
  if state.dayNightState then
    timeMultiplier = DayNightCycle.getPredatorSpawnMultiplier(state.dayNightState)
  end

  -- Spawn the predator
  local playerId = tostring(userId)
  local result = PredatorSpawning.spawn(state.spawnState, currentTime, playerId, timeMultiplier)

  if result.success and result.predator then
    local predator = result.predator

    -- Update target chicken if provided
    if targetChickenId then
      PredatorSpawning.updateTargetChicken(state.spawnState, predator.id, targetChickenId)
    end

    -- Register with AI for walking behavior
    local predatorPosition = PredatorAI.registerPredator(
      state.aiState,
      predator.id,
      predator.predatorType,
      sectionCenter,
      targetChickenPosition
    )

    -- Get threat level for client notification
    local predatorConfig = PredatorConfig.get(predator.predatorType)
    local threatLevel = predatorConfig and predatorConfig.threatLevel or "Minor"

    -- Notify all clients
    self.Client.PredatorSpawned:FireAll(
      predator.id,
      predator.predatorType,
      userId,
      predatorPosition.currentPosition,
      predatorPosition.targetPosition,
      threatLevel,
      predator.health,
      targetChickenId
    )

    -- Fire server signal
    self.PredatorSpawnedSignal:Fire(userId, predator)
  end

  return result
end

--[[
	Force spawn a specific predator type (for events/testing).
	@param userId number - The user ID
	@param predatorType string - The type of predator to spawn
	@param sectionCenter Vector3 - Center of player's section
	@return SpawnResult
]]
function PredatorService:ForceSpawnPredator(
  userId: number,
  predatorType: string,
  sectionCenter: Vector3
): PredatorSpawning.SpawnResult
  local state = playerPredatorStates[userId]
  if not state then
    return {
      success = false,
      message = "Player state not found",
      predator = nil,
      nextSpawnTime = nil,
    }
  end

  local currentTime = os.time()
  local playerId = tostring(userId)
  local result = PredatorSpawning.forceSpawn(state.spawnState, predatorType, currentTime, playerId)

  if result.success and result.predator then
    local predator = result.predator

    -- Register with AI
    local predatorPosition =
      PredatorAI.registerPredator(state.aiState, predator.id, predator.predatorType, sectionCenter)

    -- Get threat level for client notification
    local predatorConfig = PredatorConfig.get(predator.predatorType)
    local threatLevel = predatorConfig and predatorConfig.threatLevel or "Minor"

    -- Notify all clients
    self.Client.PredatorSpawned:FireAll(
      predator.id,
      predator.predatorType,
      userId,
      predatorPosition.currentPosition,
      predatorPosition.targetPosition,
      threatLevel,
      predator.health,
      nil
    )

    -- Fire server signal
    self.PredatorSpawnedSignal:Fire(userId, predator)
  end

  return result
end

--[[
	Check if a spawn should occur for a player.
	@param userId number - The user ID
	@return boolean
]]
function PredatorService:ShouldSpawn(userId: number): boolean
  -- Check new player protection first - protected players can't have predators spawn
  if MapService:IsPlayerProtected(userId) then
    return false
  end

  local state = playerPredatorStates[userId]
  if not state then
    return false
  end

  local currentTime = os.time()
  local timeMultiplier = 1
  if state.dayNightState then
    timeMultiplier = DayNightCycle.getPredatorSpawnMultiplier(state.dayNightState)
  end

  return PredatorSpawning.shouldSpawn(state.spawnState, currentTime, timeMultiplier)
end

--[[
	Update predator AI positions (called by game loop).
	@param userId number - The user ID
	@param deltaTime number - Time since last update
	@return {[string]: PredatorPosition} - Updated positions
]]
function PredatorService:UpdatePredatorPositions(
  userId: number,
  deltaTime: number
): { [string]: PredatorAI.PredatorPosition }
  local state = playerPredatorStates[userId]
  if not state then
    return {}
  end

  local currentTime = os.time()
  local updatedPositions = PredatorAI.updateAll(state.aiState, deltaTime, currentTime)

  -- Notify clients of position updates
  for predatorId, position in pairs(updatedPositions) do
    self.Client.PredatorPositionUpdated:FireAll(
      predatorId,
      position.currentPosition,
      position.facingDirection,
      position.behaviorState
    )
  end

  return updatedPositions
end

--[[
	Update predator state to attacking when entering section.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@return boolean - True if state changed
]]
function PredatorService:CheckPredatorEnteredSection(userId: number, predatorId: string): boolean
  local state = playerPredatorStates[userId]
  if not state then
    return false
  end

  local predator = PredatorSpawning.findPredator(state.spawnState, predatorId)
  if not predator then
    return false
  end

  if predator.state ~= "spawning" and predator.state ~= "approaching" then
    return false
  end

  if PredatorAI.hasEnteredSection(state.aiState, predatorId) then
    PredatorSpawning.updatePredatorState(state.spawnState, predatorId, "attacking")
    return true
  elseif predator.state == "spawning" then
    PredatorSpawning.updatePredatorState(state.spawnState, predatorId, "approaching")
  end

  return false
end

--[[
	CLIENT: Attack a predator with a bat.
	@param player Player - The player attacking
	@param predatorId string - The predator to attack
	@return AttackResult
]]
function PredatorService.Client:AttackPredator(
  player: Player,
  predatorId: string
): {
  success: boolean,
  message: string,
  defeated: boolean,
  remainingHealth: number,
  reward: number?,
  xpAwarded: number?,
}
  local self = PredatorService
  local userId = player.UserId
  local state = playerPredatorStates[userId]

  if not state then
    return {
      success = false,
      message = "Player state not found",
      defeated = false,
      remainingHealth = 0,
      reward = nil,
      xpAwarded = nil,
    }
  end

  -- Apply bat hit
  local hitResult = PredatorSpawning.applyBatHit(state.spawnState, predatorId)

  if not hitResult.success then
    return {
      success = false,
      message = hitResult.message,
      defeated = false,
      remainingHealth = hitResult.remainingHealth,
      reward = nil,
      xpAwarded = nil,
    }
  end

  local predator = PredatorSpawning.findPredator(state.spawnState, predatorId)
  local maxHealth = predator and PredatorConfig.getBatHitsRequired(predator.predatorType) or 1

  -- Notify all clients of health update
  self.Client.PredatorHealthUpdated:FireAll(predatorId, hitResult.remainingHealth, maxHealth)

  local reward: number? = nil
  local xpAwarded: number? = nil

  if hitResult.defeated and predator then
    -- Get reward
    local config = PredatorConfig.get(predator.predatorType)
    reward = config and config.rewardMoney or 0

    -- Award money to player
    if reward > 0 then
      local playerData = PlayerDataService:GetData(userId)
      if playerData then
        PlayerDataService:UpdateData(userId, function(data)
          data.money = data.money + reward
          return data
        end)
      end
    end

    -- Award XP
    xpAwarded = XPConfig.calculatePredatorKillXP(predator.predatorType)
    if xpAwarded > 0 then
      self.XPAwarded:Fire(userId, xpAwarded, "Defeated " .. predator.predatorType)
    end

    -- Unregister from AI
    PredatorAI.unregisterPredator(state.aiState, predatorId)

    -- Notify all clients
    self.Client.PredatorDefeated:FireAll(predatorId, true) -- true = defeated

    -- Fire server signal
    self.PredatorDefeatedSignal:Fire(userId, predatorId, reward)
  end

  return {
    success = true,
    message = hitResult.message,
    defeated = hitResult.defeated,
    remainingHealth = hitResult.remainingHealth,
    reward = reward,
    xpAwarded = xpAwarded,
  }
end

--[[
	CLIENT: Get active predators for a player.
	@param player Player - The player
	@return {PredatorInfo}
]]
function PredatorService.Client:GetActivePredators(player: Player): { any }
  local self = PredatorService
  local userId = player.UserId
  local predators = self:GetActivePredators(userId)

  local result = {}
  for _, predator in ipairs(predators) do
    local info = PredatorSpawning.getPredatorInfo(predator)
    local position = self:GetPredatorPosition(userId, predator.id)
    table.insert(result, {
      id = predator.id,
      predatorType = predator.predatorType,
      displayName = info.displayName,
      threatLevel = info.threatLevel,
      state = predator.state,
      health = predator.health,
      maxHealth = info.maxHealth,
      position = position and position.currentPosition or nil,
      targetPosition = position and position.targetPosition or nil,
    })
  end

  return result
end

--[[
	CLIENT: Get spawn summary for UI.
	@param player Player - The player
	@return SpawnSummary
]]
function PredatorService.Client:GetSpawnSummary(player: Player): any
  local self = PredatorService
  return self:GetSpawnSummary(player.UserId)
end

--[[
	Mark a predator as caught (by trap).
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@return boolean
]]
function PredatorService:MarkPredatorCaught(userId: number, predatorId: string): boolean
  local state = playerPredatorStates[userId]
  if not state then
    return false
  end

  local success = PredatorSpawning.markCaught(state.spawnState, predatorId)
  if success then
    -- Unregister from AI
    PredatorAI.unregisterPredator(state.aiState, predatorId)

    -- Notify all clients
    self.Client.PredatorDefeated:FireAll(predatorId, true) -- true = caught
  end

  return success
end

--[[
	Mark a predator as escaped.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@return boolean
]]
function PredatorService:MarkPredatorEscaped(userId: number, predatorId: string): boolean
  local state = playerPredatorStates[userId]
  if not state then
    return false
  end

  local success = PredatorSpawning.markEscaped(state.spawnState, predatorId)
  if success then
    -- Unregister from AI
    PredatorAI.unregisterPredator(state.aiState, predatorId)

    -- Notify all clients
    self.Client.PredatorDefeated:FireAll(predatorId, false) -- false = escaped

    -- Fire server signal
    self.PredatorEscapedSignal:Fire(userId, predatorId)
  end

  return success
end

--[[
	Update target chicken for a predator.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@param chickenId string? - New target chicken ID
	@param chickenPosition Vector3? - Position of target chicken
]]
function PredatorService:UpdatePredatorTarget(
  userId: number,
  predatorId: string,
  chickenId: string?,
  chickenPosition: Vector3?
)
  local state = playerPredatorStates[userId]
  if not state then
    return
  end

  PredatorSpawning.updateTargetChicken(state.spawnState, predatorId, chickenId)

  if chickenPosition then
    PredatorAI.updateApproachTarget(state.aiState, predatorId, chickenPosition)
  end

  -- Notify clients
  self.Client.PredatorTargetChanged:FireAll(predatorId, chickenId)
end

--[[
	Send an alert to a player about a predator event.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@param alertType string - Type of alert
]]
function PredatorService:SendAlert(
  userId: number,
  predatorId: string,
  alertType: "approaching" | "attacking" | "escaped" | "defeated" | "caught"
)
  local state = playerPredatorStates[userId]
  if not state then
    return
  end

  local predator = PredatorSpawning.findPredator(state.spawnState, predatorId)
  if not predator then
    return
  end

  local alert = PredatorAttack.generateAlert(predator, alertType)

  local player = Players:GetPlayerByUserId(userId)
  if player then
    self.Client.PredatorAlert:Fire(player, alert)
  end
end

--[[
	Execute predator attacks on chickens for a player.
	Called during the game loop to check if attacking predators should steal chickens.
	@param userId number - The user ID
	@param currentTime number - Current time in seconds
]]
function PredatorService:ExecutePredatorAttacks(userId: number, currentTime: number)
  local state = playerPredatorStates[userId]
  if not state then
    return
  end

  local player = Players:GetPlayerByUserId(userId)
  if not player then
    return
  end

  -- Check new player protection - protected players' chickens don't get attacked
  if MapService:IsPlayerProtected(userId) then
    return
  end

  -- Get player data for attack execution
  local playerData = PlayerDataService and PlayerDataService:GetData(userId)
  if not playerData then
    return
  end

  -- Check each active predator for attack execution
  for _, predator in ipairs(PredatorSpawning.getActivePredators(state.spawnState)) do
    -- Only process predators in attacking state
    if predator.state == "attacking" then
      -- Check if predator should attack based on interval
      if PredatorSpawning.shouldAttack(state.spawnState, predator.id, currentTime) then
        -- Execute the attack
        local attackResult = PredatorAttack.executeAttack(
          playerData,
          state.spawnState,
          predator.id,
          currentTime
        )

        if attackResult.success then
          -- Update last attack time
          PredatorSpawning.setLastAttackTime(state.spawnState, predator.id, currentTime)

          -- Update player data with modified placedChickens (already modified by executeAttack)
          if attackResult.chickensLost > 0 then
            PlayerDataService:UpdateData(userId, function(data)
              data.placedChickens = playerData.placedChickens
              return data
            end)

            -- Send alert to player about the attack
            self:SendAlert(userId, predator.id, "attacking")

            -- Fire client event for UI feedback
            self.Client.ChickensLost:Fire(
              player,
              predator.id,
              attackResult.chickenIds,
              attackResult.chickensLost,
              attackResult.totalValueLost,
              attackResult.message
            )

            -- Fire server signal for other services
            self.ChickensLostSignal:Fire(
              userId,
              predator.id,
              attackResult.chickenIds,
              attackResult.totalValueLost
            )

            print(string.format(
              "[PredatorService] %s - %d chickens lost (value: %d)",
              attackResult.message,
              attackResult.chickensLost,
              attackResult.totalValueLost
            ))
          end

          -- Handle predator escape after attack
          if attackResult.predatorEscaped then
            -- Unregister from AI
            PredatorAI.unregisterPredator(state.aiState, predator.id)

            -- Send escape alert
            self:SendAlert(userId, predator.id, "escaped")

            -- Notify clients
            self.Client.PredatorDefeated:FireAll(predator.id, false) -- false = escaped

            -- Fire server signal
            self.PredatorEscapedSignal:Fire(userId, predator.id)
          end
        end
      end
    end
  end
end

--[[
	Apply predator damage to player.
	Called during the game loop when attacking predators are within range.
	@param userId number - The user ID
	@param deltaTime number - Time since last frame
]]
function PredatorService:ApplyPredatorDamageToPlayer(userId: number, deltaTime: number)
  local state = playerPredatorStates[userId]
  if not state then
    return
  end

  local player = Players:GetPlayerByUserId(userId)
  if not player then
    return
  end

  -- Check new player protection - protected players don't take predator damage
  if MapService:IsPlayerProtected(userId) then
    return
  end

  -- Check if CombatService is available
  if not CombatService then
    return
  end

  -- Check if player's shield is active (protected from damage)
  if CombatService:IsShieldActive(userId) then
    return
  end

  -- Get player's character position
  local character = player.Character
  if not character then
    return
  end
  local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
  if not humanoidRootPart then
    return
  end
  local playerPosition = humanoidRootPart.Position

  -- Check each active predator for damage application
  for _, predator in ipairs(PredatorSpawning.getActivePredators(state.spawnState)) do
    -- Only process predators in attacking state
    if predator.state == "attacking" then
      -- Get predator position
      local predatorPosition = PredatorAI.getPosition(state.aiState, predator.id)
      if predatorPosition and predatorPosition.currentPosition then
        -- Check if predator is within attack range of player
        local distance = (playerPosition - predatorPosition.currentPosition).Magnitude
        if distance <= PREDATOR_ATTACK_RANGE_STUDS then
          -- Apply damage to player
          local damageResult = CombatService:ApplyPredatorDamage(
            userId,
            predator.predatorType,
            deltaTime
          )

          if damageResult.success and damageResult.damageDealt > 0 then
            -- Log significant damage events
            if damageResult.wasKnockedBack then
              print(string.format(
                "[PredatorService] Player %s knocked back by %s",
                player.Name,
                predator.predatorType
              ))
            end
          end
        end
      end
    end
  end
end

--[[
	Periodic cleanup of inactive predators.
	@param userId number - The user ID
	@return number - Count of removed predators
]]
function PredatorService:CleanupInactivePredators(userId: number): number
  local state = playerPredatorStates[userId]
  if not state then
    return 0
  end

  local currentTime = os.time()
  if currentTime - state.lastCleanupTime < PREDATOR_CLEANUP_INTERVAL then
    return 0
  end

  state.lastCleanupTime = currentTime
  return PredatorSpawning.cleanup(state.spawnState)
end

--[[
	Get threatening predators for a player.
	@param userId number - The user ID
	@return {PredatorInstance}
]]
function PredatorService:GetThreateningPredators(
  userId: number
): { PredatorSpawning.PredatorInstance }
  local state = playerPredatorStates[userId]
  if not state then
    return {}
  end

  local playerId = tostring(userId)
  return PredatorAttack.getThreateningPredators(state.spawnState, playerId)
end

--[[
	Get threat summary for a player.
	@param userId number - The user ID
	@return ThreatSummary
]]
function PredatorService:GetThreatSummary(userId: number): any
  local state = playerPredatorStates[userId]
  if not state then
    return {
      totalThreats = 0,
      approachingCount = 0,
      attackingCount = 0,
      mostDangerousThreat = nil,
      timeUntilNextAttack = nil,
    }
  end

  local playerId = tostring(userId)
  return PredatorAttack.getThreatSummary(state.spawnState, playerId, os.time())
end

--[[
	Check if predator should despawn (no chickens to attack).
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@param hasChickens boolean - Whether player has chickens
	@param isEngagingPlayer boolean - Whether predator is engaging player
	@return boolean - True if should despawn
]]
function PredatorService:CheckPredatorShouldDespawn(
  userId: number,
  predatorId: string,
  hasChickens: boolean,
  isEngagingPlayer: boolean
): boolean
  local state = playerPredatorStates[userId]
  if not state then
    return false
  end

  local currentTime = os.time()
  local shouldDespawn = PredatorAI.updateChickenPresence(
    state.aiState,
    predatorId,
    hasChickens,
    currentTime,
    isEngagingPlayer
  )

  if shouldDespawn then
    self:MarkPredatorEscaped(userId, predatorId)
  end

  return shouldDespawn
end

--[[
	Find a predator by ID.
	@param userId number - The user ID
	@param predatorId string - The predator ID
	@return PredatorInstance?
]]
function PredatorService:FindPredator(
  userId: number,
  predatorId: string
): PredatorSpawning.PredatorInstance?
  local state = playerPredatorStates[userId]
  if not state then
    return nil
  end
  return PredatorSpawning.findPredator(state.spawnState, predatorId)
end

--[[
	Get predator config by type.
	@param predatorType string - The predator type
	@return PredatorTypeConfig?
]]
function PredatorService:GetPredatorConfig(predatorType: string): PredatorConfig.PredatorTypeConfig?
  return PredatorConfig.get(predatorType)
end

--[[
	Reset predator state for a player (for testing or new game).
	@param userId number - The user ID
]]
function PredatorService:ResetPredatorState(userId: number)
  local state = playerPredatorStates[userId]
  if not state then
    return
  end

  local playerLevel = 1
  local playerData = PlayerDataService and PlayerDataService:GetData(userId)
  if playerData then
    playerLevel = playerData.level or 1
  end

  PredatorSpawning.reset(state.spawnState, playerLevel)
  state.aiState = PredatorAI.createState()
end

return PredatorService
