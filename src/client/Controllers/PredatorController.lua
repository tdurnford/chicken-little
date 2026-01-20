--[[
	PredatorController
	Client-side Knit controller for managing predator interactions.
	
	Provides:
	- Local cache of active predators
	- GoodSignal events for reactive UI updates
	- Connection to PredatorService via Knit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Create the controller
local PredatorController = Knit.CreateController({
  Name = "PredatorController",
})

-- Local cache of active predators
local activePredators: { [string]: any } = {}

-- GoodSignal events for reactive UI
PredatorController.PredatorSpawned = GoodSignal.new() -- Fires (predatorId, type, userId, position, targetPosition, threat, health, targetChickenId)
PredatorController.PredatorPositionUpdated = GoodSignal.new() -- Fires (predatorId, position, direction, behavior)
PredatorController.PredatorHealthUpdated = GoodSignal.new() -- Fires (predatorId, health, maxHealth)
PredatorController.PredatorDefeated = GoodSignal.new() -- Fires (predatorId, wasDefeated)
PredatorController.PredatorTargetChanged = GoodSignal.new() -- Fires (predatorId, chickenId)
PredatorController.PredatorAlert = GoodSignal.new() -- Fires (alert)

-- Reference to the server service
local predatorService = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function PredatorController:KnitInit()
  print("[PredatorController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function PredatorController:KnitStart()
  -- Get reference to server service
  predatorService = Knit.GetService("PredatorService")

  -- Connect to server signals
  predatorService.PredatorSpawned:Connect(
    function(
      predatorId,
      predatorType,
      userId,
      position,
      targetPosition,
      threat,
      health,
      targetChickenId
    )
      -- Cache the predator
      activePredators[predatorId] = {
        id = predatorId,
        predatorType = predatorType,
        userId = userId,
        position = position,
        targetPosition = targetPosition,
        threatLevel = threat,
        health = health,
        maxHealth = health,
        targetChickenId = targetChickenId,
        state = "spawning",
      }
      self.PredatorSpawned:Fire(
        predatorId,
        predatorType,
        userId,
        position,
        targetPosition,
        threat,
        health,
        targetChickenId
      )
    end
  )

  predatorService.PredatorPositionUpdated:Connect(
    function(predatorId, position, direction, behavior)
      -- Update cache
      if activePredators[predatorId] then
        activePredators[predatorId].position = position
        activePredators[predatorId].direction = direction
        activePredators[predatorId].behaviorState = behavior
      end
      self.PredatorPositionUpdated:Fire(predatorId, position, direction, behavior)
    end
  )

  predatorService.PredatorHealthUpdated:Connect(function(predatorId, health, maxHealth)
    -- Update cache
    if activePredators[predatorId] then
      activePredators[predatorId].health = health
      activePredators[predatorId].maxHealth = maxHealth
    end
    self.PredatorHealthUpdated:Fire(predatorId, health, maxHealth)
  end)

  predatorService.PredatorDefeated:Connect(function(predatorId, wasDefeated)
    -- Remove from cache
    activePredators[predatorId] = nil
    self.PredatorDefeated:Fire(predatorId, wasDefeated)
  end)

  predatorService.PredatorTargetChanged:Connect(function(predatorId, chickenId)
    -- Update cache
    if activePredators[predatorId] then
      activePredators[predatorId].targetChickenId = chickenId
    end
    self.PredatorTargetChanged:Fire(predatorId, chickenId)
  end)

  predatorService.PredatorAlert:Connect(function(alert)
    self.PredatorAlert:Fire(alert)
  end)

  print("[PredatorController] Started")
end

--[[
	Attack a predator with the equipped weapon.
	
	@param predatorId string - The predator's ID
	@return Promise<AttackResult>
]]
function PredatorController:AttackPredator(predatorId: string)
  if not predatorService then
    return Promise.resolve({
      success = false,
      message = "Service not available",
      defeated = false,
      remainingHealth = 0,
      reward = nil,
      xpAwarded = nil,
    })
  end
  return predatorService:AttackPredator(predatorId)
    :catch(function(err)
      warn("[PredatorController] AttackPredator failed:", tostring(err))
      return {
        success = false,
        message = tostring(err),
        defeated = false,
        remainingHealth = 0,
        reward = nil,
        xpAwarded = nil,
      }
    end)
end

--[[
	Get active predators for the local player.
	
	@return Promise<{PredatorInfo}>
]]
function PredatorController:GetActivePredators()
  if not predatorService then
    return Promise.resolve({})
  end
  return predatorService:GetActivePredators()
    :catch(function(err)
      warn("[PredatorController] GetActivePredators failed:", tostring(err))
      return {}
    end)
end

--[[
	Get spawn summary for UI display.
	
	@return Promise<SpawnSummary>
]]
function PredatorController:GetSpawnSummary()
  if not predatorService then
    return Promise.resolve({
      waveNumber = 0,
      activePredators = 0,
      maxPredators = 1,
      predatorsSpawned = 0,
      timeUntilNextSpawn = 60,
      difficultyMultiplier = 1,
      dominantThreat = "Minor",
      timeOfDayMultiplier = 1,
      playerLevel = 1,
    })
  end
  return predatorService:GetSpawnSummary()
    :catch(function(err)
      warn("[PredatorController] GetSpawnSummary failed:", tostring(err))
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
    end)
end

--[[
	Get all cached active predators.
	
	@return { [string]: PredatorData } - Map of predator ID to predator data
]]
function PredatorController:GetCachedPredators(): { [string]: any }
  return activePredators
end

--[[
	Get a specific predator from cache.
	
	@param predatorId string - The predator's ID
	@return PredatorData? - The predator data or nil
]]
function PredatorController:GetCachedPredator(predatorId: string): any?
  return activePredators[predatorId]
end

--[[
	Get the count of active predators.
	
	@return number - Number of active predators
]]
function PredatorController:GetActivePredatorCount(): number
  local count = 0
  for _ in pairs(activePredators) do
    count = count + 1
  end
  return count
end

--[[
	Check if there are any active predators.
	
	@return boolean - True if there are active predators
]]
function PredatorController:HasActivePredators(): boolean
  return next(activePredators) ~= nil
end

--[[
	Get predators by threat level.
	
	@param threatLevel string - "Minor" | "Moderate" | "Severe" | "Critical"
	@return { PredatorData } - List of predators with that threat level
]]
function PredatorController:GetPredatorsByThreat(threatLevel: string): { any }
  local result = {}
  for _, predator in pairs(activePredators) do
    if predator.threatLevel == threatLevel then
      table.insert(result, predator)
    end
  end
  return result
end

--[[
	Get predators targeting a specific chicken.
	
	@param chickenId string - The chicken's ID
	@return { PredatorData } - List of predators targeting that chicken
]]
function PredatorController:GetPredatorsTargetingChicken(chickenId: string): { any }
  local result = {}
  for _, predator in pairs(activePredators) do
    if predator.targetChickenId == chickenId then
      table.insert(result, predator)
    end
  end
  return result
end

return PredatorController
