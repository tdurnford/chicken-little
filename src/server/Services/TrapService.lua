--[[
	TrapService
	Knit service that handles all trap-related server logic.
	
	Provides:
	- Trap placement and pickup
	- Trap catching mechanics
	- Caught predator collection
	- Event broadcasting for visual updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))
local TrapCatching = require(Shared:WaitForChild("TrapCatching"))
local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

-- Services will be retrieved after Knit starts
local PlayerDataService
local PredatorService

-- Create the service
local TrapService = Knit.CreateService({
  Name = "TrapService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    TrapPlaced = Knit.CreateSignal(), -- Fires to all clients when trap placed
    TrapPickedUp = Knit.CreateSignal(), -- Fires to all clients when trap removed
    TrapCaught = Knit.CreateSignal(), -- Fires to owner when predator caught
    TrapCooldownStarted = Knit.CreateSignal(), -- Fires to owner when trap cooldown starts
    TrapCooldownEnded = Knit.CreateSignal(), -- Fires to owner when trap ready again
    PredatorCollected = Knit.CreateSignal(), -- Fires to owner when predator sold from trap
  },
})

-- Server-side signals (for other services to listen to)
TrapService.TrapPlacedSignal = GoodSignal.new() -- (userId: number, trapId: string, trapType: string, spotIndex: number)
TrapService.TrapRemovedSignal = GoodSignal.new() -- (userId: number, trapId: string)
TrapService.PredatorCaughtSignal = GoodSignal.new() -- (userId: number, trapId: string, predatorType: string)
TrapService.PredatorCollectedSignal = GoodSignal.new() -- (userId: number, trapId: string, predatorType: string, reward: number)

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function TrapService:KnitInit()
  print("[TrapService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function TrapService:KnitStart()
  -- Get reference to other services
  PlayerDataService = Knit.GetService("PlayerDataService")
  PredatorService = Knit.GetService("PredatorService")

  print("[TrapService] Started")
end

--[[
	Get player data safely.
	@param userId number - The user ID
	@return PlayerDataSchema?
]]
function TrapService:_getPlayerData(userId: number): any
  if not PlayerDataService then
    return nil
  end
  return PlayerDataService:GetData(userId)
end

--[[
	Update player data safely.
	@param userId number - The user ID
	@param updateFn function - Update function
	@return boolean - Success
]]
function TrapService:_updatePlayerData(userId: number, updateFn: (any) -> any): boolean
  if not PlayerDataService then
    return false
  end
  return PlayerDataService:UpdateData(userId, updateFn) ~= nil
end

--[[
	Get trap configuration.
	@param trapType string - The trap type
	@return TrapTypeConfig?
]]
function TrapService:GetTrapConfig(trapType: string): TrapConfig.TrapTypeConfig?
  return TrapConfig.get(trapType)
end

--[[
	Get all trap configurations.
	@return {[string]: TrapTypeConfig}
]]
function TrapService:GetAllTrapConfigs(): { [string]: TrapConfig.TrapTypeConfig }
  return TrapConfig.getAll()
end

--[[
	Get traps sorted by tier and price.
	@return {TrapTypeConfig}
]]
function TrapService:GetAllTrapsSorted(): { TrapConfig.TrapTypeConfig }
  return TrapConfig.getAllSorted()
end

--[[
	Get affordable traps for a player's budget.
	@param money number - Player's money
	@return {TrapTypeConfig}
]]
function TrapService:GetAffordableTraps(money: number): { TrapConfig.TrapTypeConfig }
  return TrapConfig.getAffordableTraps(money)
end

--[[
	Get all placed traps for a player.
	@param userId number - The user ID
	@return {TrapData}
]]
function TrapService:GetPlacedTraps(userId: number): { any }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end
  return playerData.traps or {}
end

--[[
	Get trap state information.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@return TrapState?
]]
function TrapService:GetTrapState(userId: number, trapId: string): TrapPlacement.TrapState?
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  local trap = TrapPlacement.findTrap(playerData, trapId)
  if not trap then
    return nil
  end

  return TrapPlacement.getTrapState(trap, os.time())
end

--[[
	Get trap placement summary for a player.
	@param userId number - The user ID
	@return PlacementSummary
]]
function TrapService:GetTrapSummary(userId: number): any
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      totalTraps = 0,
      availableSpots = TrapPlacement.getMaxSpots(),
      readyTraps = 0,
      trapsWithPredators = 0,
      trapsOnCooldown = 0,
    }
  end

  return TrapPlacement.getSummary(playerData, os.time())
end

--[[
	Get trap catching summary for a player.
	@param userId number - The user ID
	@return CatchingSummary
]]
function TrapService:GetCatchingSummary(userId: number): any
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      totalTraps = 0,
      readyTraps = 0,
      trapsOnCooldown = 0,
      caughtPredators = 0,
      pendingReward = 0,
    }
  end

  return TrapCatching.getSummary(playerData, os.time())
end

--[[
	Get available trap spots for a player.
	@param userId number - The user ID
	@return {number}
]]
function TrapService:GetAvailableSpots(userId: number): { number }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end

  return TrapPlacement.getAvailableSpots(playerData)
end

--[[
	Get occupied trap spots for a player.
	@param userId number - The user ID
	@return {number}
]]
function TrapService:GetOccupiedSpots(userId: number): { number }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end

  return TrapPlacement.getOccupiedSpots(playerData)
end

--[[
	Check if a spot is available.
	@param userId number - The user ID
	@param spotIndex number - The spot index
	@return boolean
]]
function TrapService:IsSpotAvailable(userId: number, spotIndex: number): boolean
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return false
  end

  return TrapPlacement.isSpotAvailable(playerData, spotIndex)
end

--[[
	Get trap at a specific spot.
	@param userId number - The user ID
	@param spotIndex number - The spot index
	@return TrapData?
]]
function TrapService:GetTrapAtSpot(userId: number, spotIndex: number): any
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  return TrapPlacement.getTrapAtSpot(playerData, spotIndex)
end

--[[
	Check if player can place more of a trap type.
	@param userId number - The user ID
	@param trapType string - The trap type
	@return boolean
]]
function TrapService:CanPlaceMoreOfType(userId: number, trapType: string): boolean
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return false
  end

  return TrapPlacement.canPlaceMoreOfType(playerData, trapType)
end

--[[
	Get remaining placement slots for a trap type.
	@param userId number - The user ID
	@param trapType string - The trap type
	@return number
]]
function TrapService:GetRemainingSlots(userId: number, trapType: string): number
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return 0
  end

  return TrapPlacement.getRemainingSlots(playerData, trapType)
end

--[[
	Get all traps that are ready to catch.
	@param userId number - The user ID
	@return {TrapData}
]]
function TrapService:GetReadyTraps(userId: number): { any }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end

  return TrapPlacement.getReadyTraps(playerData, os.time())
end

--[[
	Get all traps with caught predators.
	@param userId number - The user ID
	@return {TrapData}
]]
function TrapService:GetTrapsWithPredators(userId: number): { any }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end

  return TrapPlacement.getTrapsWithPredators(playerData)
end

--[[
	Get traps on cooldown.
	@param userId number - The user ID
	@return {TrapData}
]]
function TrapService:GetTrapsOnCooldown(userId: number): { any }
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {}
  end

  return TrapPlacement.getTrapsOnCooldown(playerData, os.time())
end

--[[
	Check if player can catch a predator (has ready traps).
	@param userId number - The user ID
	@return boolean
]]
function TrapService:CanCatchPredator(userId: number): boolean
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return false
  end

  return TrapCatching.canCatchPredator(playerData, os.time())
end

--[[
	Get catch probability for a specific trap against a predator.
	@param trapType string - The trap type
	@param predatorType string - The predator type
	@return number
]]
function TrapService:GetCatchProbability(trapType: string, predatorType: string): number
  return TrapConfig.calculateCatchProbability(trapType, predatorType)
end

--[[
	Get combined catch probability with all ready traps.
	@param userId number - The user ID
	@param predatorType string - The predator type
	@return number
]]
function TrapService:GetCombinedCatchProbability(userId: number, predatorType: string): number
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return 0
  end

  return TrapCatching.getCombinedCatchProbability(playerData, predatorType, os.time())
end

--[[
	Get the best trap for catching a specific predator.
	@param userId number - The user ID
	@param predatorType string - The predator type
	@return CatchAttemptInfo?
]]
function TrapService:GetBestTrapForPredator(
  userId: number,
  predatorType: string
): TrapCatching.CatchAttemptInfo?
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  return TrapCatching.getBestTrapForPredator(playerData, predatorType, os.time())
end

--[[
	Get total pending reward from all caught predators.
	@param userId number - The user ID
	@return number
]]
function TrapService:GetTotalCaughtReward(userId: number): number
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return 0
  end

  return TrapCatching.getTotalCaughtReward(playerData)
end

--[[
	Place a new trap at a spot (purchases trap).
	@param userId number - The user ID
	@param trapType string - The trap type to place
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapService:PlaceTrap(
  userId: number,
  trapType: string,
  spotIndex: number
): TrapPlacement.PlacementResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
      trap = nil,
    }
  end

  local result: TrapPlacement.PlacementResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapPlacement.placeTrap(data, trapType, spotIndex)
    return data
  end)

  if not success then
    return {
      success = false,
      message = "Failed to update player data",
      trap = nil,
    }
  end

  if result.success and result.trap then
    -- Notify all clients
    self.Client.TrapPlaced:FireAll(result.trap.id, trapType, userId, spotIndex)

    -- Fire server signal
    self.TrapPlacedSignal:Fire(userId, result.trap.id, trapType, spotIndex)
  end

  return result
end

--[[
	Place an existing trap from inventory.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapService:PlaceTrapFromInventory(
  userId: number,
  trapId: string,
  spotIndex: number
): TrapPlacement.PlacementResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
      trap = nil,
    }
  end

  local result: TrapPlacement.PlacementResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapPlacement.placeTrapFromInventory(data, trapId, spotIndex)
    return data
  end)

  if not success then
    return {
      success = false,
      message = "Failed to update player data",
      trap = nil,
    }
  end

  if result.success and result.trap then
    -- Notify all clients
    self.Client.TrapPlaced:FireAll(result.trap.id, result.trap.trapType, userId, spotIndex)

    -- Fire server signal
    self.TrapPlacedSignal:Fire(userId, result.trap.id, result.trap.trapType, spotIndex)
  end

  return result
end

--[[
	Pick up (sell) a trap.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@return PlacementResult
]]
function TrapService:PickupTrap(userId: number, trapId: string): TrapPlacement.PlacementResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
      trap = nil,
    }
  end

  local result: TrapPlacement.PlacementResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapPlacement.pickupTrap(data, trapId)
    return data
  end)

  if not success then
    return {
      success = false,
      message = "Failed to update player data",
      trap = nil,
    }
  end

  if result.success then
    -- Notify all clients
    self.Client.TrapPickedUp:FireAll(trapId, userId)

    -- Fire server signal
    self.TrapRemovedSignal:Fire(userId, trapId)
  end

  return result
end

--[[
	Move a trap to a different spot.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@param newSpotIndex number - The new spot index
	@return PlacementResult
]]
function TrapService:MoveTrap(
  userId: number,
  trapId: string,
  newSpotIndex: number
): TrapPlacement.PlacementResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
      trap = nil,
    }
  end

  local result: TrapPlacement.PlacementResult
  local oldSpotIndex: number?
  local success = self:_updatePlayerData(userId, function(data)
    local trap = TrapPlacement.findTrap(data, trapId)
    oldSpotIndex = trap and trap.spotIndex
    result = TrapPlacement.moveTrap(data, trapId, newSpotIndex)
    return data
  end)

  if not success then
    return {
      success = false,
      message = "Failed to update player data",
      trap = nil,
    }
  end

  if result.success and result.trap then
    -- Notify clients of old position removal and new position
    if oldSpotIndex then
      self.Client.TrapPickedUp:FireAll(trapId, userId)
    end
    self.Client.TrapPlaced:FireAll(result.trap.id, result.trap.trapType, userId, newSpotIndex)
  end

  return result
end

--[[
	Attempt to catch a predator with a specific trap.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@param predatorType string - The predator type
	@return CatchResult
]]
function TrapService:AttemptCatch(
  userId: number,
  trapId: string,
  predatorType: string
): TrapCatching.CatchResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      caught = false,
      message = "Player data not found",
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local currentTime = os.time()
  local result: TrapCatching.CatchResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapCatching.attemptCatch(data, trapId, predatorType, currentTime)
    return data
  end)

  if not success then
    return {
      success = false,
      caught = false,
      message = "Failed to update player data",
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local player = Players:GetPlayerByUserId(userId)

  if result.caught then
    -- Notify owner
    if player then
      self.Client.TrapCaught:Fire(player, trapId, predatorType, result.catchProbability)
    end

    -- Fire server signal
    self.PredatorCaughtSignal:Fire(userId, trapId, predatorType)
  else
    -- Notify owner of cooldown start
    if player then
      local trapConfig = TrapConfig.get(
        playerData.traps
            and TrapPlacement.findTrap(playerData, trapId)
            and TrapPlacement.findTrap(playerData, trapId).trapType
          or ""
      )
      local cooldownDuration = trapConfig and trapConfig.cooldownSeconds or 60
      self.Client.TrapCooldownStarted:Fire(player, trapId, cooldownDuration)
    end
  end

  return result
end

--[[
	Attempt to catch a predator with all available traps.
	@param userId number - The user ID
	@param predatorType string - The predator type
	@return CatchResult
]]
function TrapService:AttemptCatchWithAllTraps(
  userId: number,
  predatorType: string
): TrapCatching.CatchResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      caught = false,
      message = "Player data not found",
      trapId = nil,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local currentTime = os.time()
  local result: TrapCatching.CatchResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapCatching.attemptCatchWithAllTraps(data, predatorType, currentTime)
    return data
  end)

  if not success then
    return {
      success = false,
      caught = false,
      message = "Failed to update player data",
      trapId = nil,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local player = Players:GetPlayerByUserId(userId)

  if result.caught and result.trapId then
    -- Notify owner
    if player then
      self.Client.TrapCaught:Fire(player, result.trapId, predatorType, result.catchProbability)
    end

    -- Fire server signal
    self.PredatorCaughtSignal:Fire(userId, result.trapId, predatorType)
  end

  return result
end

--[[
	Collect reward from a caught predator.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@return CatchResult
]]
function TrapService:CollectCaughtPredator(userId: number, trapId: string): TrapCatching.CatchResult
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      caught = false,
      message = "Player data not found",
      trapId = trapId,
      predatorType = nil,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local currentTime = os.time()
  local result: TrapCatching.CatchResult
  local success = self:_updatePlayerData(userId, function(data)
    result = TrapCatching.collectCaughtPredator(data, trapId, currentTime)
    return data
  end)

  if not success then
    return {
      success = false,
      caught = false,
      message = "Failed to update player data",
      trapId = trapId,
      predatorType = nil,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local player = Players:GetPlayerByUserId(userId)

  if result.success and result.rewardMoney then
    -- Notify owner
    if player then
      self.Client.PredatorCollected:Fire(player, trapId, result.predatorType, result.rewardMoney)
    end

    -- Fire server signal
    self.PredatorCollectedSignal:Fire(userId, trapId, result.predatorType, result.rewardMoney)
  end

  return result
end

--[[
	Collect all caught predators from all traps.
	@param userId number - The user ID
	@return {totalReward: number, count: number, results: {CatchResult}}
]]
function TrapService:CollectAllCaughtPredators(userId: number): {
  totalReward: number,
  count: number,
  results: { TrapCatching.CatchResult },
}
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      totalReward = 0,
      count = 0,
      results = {},
    }
  end

  local currentTime = os.time()
  local collectionResult: { totalReward: number, count: number, results: { TrapCatching.CatchResult } }
  local success = self:_updatePlayerData(userId, function(data)
    collectionResult = TrapCatching.collectAllCaughtPredators(data, currentTime)
    return data
  end)

  if not success then
    return {
      totalReward = 0,
      count = 0,
      results = {},
    }
  end

  local player = Players:GetPlayerByUserId(userId)

  -- Notify owner for each collected predator
  if player and collectionResult.count > 0 then
    for _, result in ipairs(collectionResult.results) do
      if result.success and result.rewardMoney then
        self.Client.PredatorCollected:Fire(
          player,
          result.trapId,
          result.predatorType,
          result.rewardMoney
        )
        self.PredatorCollectedSignal:Fire(
          userId,
          result.trapId,
          result.predatorType,
          result.rewardMoney
        )
      end
    end
  end

  return collectionResult
end

--[[
	Find a trap by ID.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@return TrapData?
]]
function TrapService:FindTrap(userId: number, trapId: string): any
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  return TrapPlacement.findTrap(playerData, trapId)
end

--[[
	Get trap info for display.
	@param userId number - The user ID
	@param trapId string - The trap ID
	@return TrapInfo?
]]
function TrapService:GetTrapInfo(userId: number, trapId: string): any
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  local trap = TrapPlacement.findTrap(playerData, trapId)
  if not trap then
    return nil
  end

  return TrapPlacement.getTrapInfo(trap)
end

--[[
	CLIENT: Place a trap at a spot.
	@param player Player - The player
	@param trapType string - The trap type
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapService.Client:PlaceTrap(
  player: Player,
  trapType: string,
  spotIndex: number
): TrapPlacement.PlacementResult
  local self = TrapService
  return self:PlaceTrap(player.UserId, trapType, spotIndex)
end

--[[
	CLIENT: Place an existing trap from inventory.
	@param player Player - The player
	@param trapId string - The trap ID
	@param spotIndex number - The spot index
	@return PlacementResult
]]
function TrapService.Client:PlaceTrapFromInventory(
  player: Player,
  trapId: string,
  spotIndex: number
): TrapPlacement.PlacementResult
  local self = TrapService
  return self:PlaceTrapFromInventory(player.UserId, trapId, spotIndex)
end

--[[
	CLIENT: Pick up a trap (sell).
	@param player Player - The player
	@param trapId string - The trap ID
	@return PlacementResult
]]
function TrapService.Client:PickupTrap(
  player: Player,
  trapId: string
): TrapPlacement.PlacementResult
  local self = TrapService
  return self:PickupTrap(player.UserId, trapId)
end

--[[
	CLIENT: Move a trap to a different spot.
	@param player Player - The player
	@param trapId string - The trap ID
	@param newSpotIndex number - The new spot index
	@return PlacementResult
]]
function TrapService.Client:MoveTrap(
  player: Player,
  trapId: string,
  newSpotIndex: number
): TrapPlacement.PlacementResult
  local self = TrapService
  return self:MoveTrap(player.UserId, trapId, newSpotIndex)
end

--[[
	CLIENT: Collect reward from a caught predator.
	@param player Player - The player
	@param trapId string - The trap ID
	@return CatchResult
]]
function TrapService.Client:CollectTrap(player: Player, trapId: string): TrapCatching.CatchResult
  local self = TrapService
  return self:CollectCaughtPredator(player.UserId, trapId)
end

--[[
	CLIENT: Collect all caught predators.
	@param player Player - The player
	@return {totalReward: number, count: number}
]]
function TrapService.Client:CollectAllTraps(player: Player): { totalReward: number, count: number }
  local self = TrapService
  local result = self:CollectAllCaughtPredators(player.UserId)
  return {
    totalReward = result.totalReward,
    count = result.count,
  }
end

--[[
	CLIENT: Get all placed traps.
	@param player Player - The player
	@return {TrapData}
]]
function TrapService.Client:GetPlacedTraps(player: Player): { any }
  local self = TrapService
  return self:GetPlacedTraps(player.UserId)
end

--[[
	CLIENT: Get trap summary.
	@param player Player - The player
	@return TrapSummary
]]
function TrapService.Client:GetTrapSummary(player: Player): any
  local self = TrapService
  return self:GetTrapSummary(player.UserId)
end

--[[
	CLIENT: Get catching summary.
	@param player Player - The player
	@return CatchingSummary
]]
function TrapService.Client:GetCatchingSummary(player: Player): any
  local self = TrapService
  return self:GetCatchingSummary(player.UserId)
end

--[[
	CLIENT: Get available spots.
	@param player Player - The player
	@return {number}
]]
function TrapService.Client:GetAvailableSpots(player: Player): { number }
  local self = TrapService
  return self:GetAvailableSpots(player.UserId)
end

--[[
	CLIENT: Get total pending reward.
	@param player Player - The player
	@return number
]]
function TrapService.Client:GetPendingReward(player: Player): number
  local self = TrapService
  return self:GetTotalCaughtReward(player.UserId)
end

--[[
	CLIENT: Get trap config by type.
	@param player Player - The player (unused, for consistency)
	@param trapType string - The trap type
	@return TrapTypeConfig?
]]
function TrapService.Client:GetTrapConfig(
  _player: Player,
  trapType: string
): TrapConfig.TrapTypeConfig?
  return TrapConfig.get(trapType)
end

--[[
	CLIENT: Get all trap configs.
	@param player Player - The player (unused, for consistency)
	@return {TrapTypeConfig}
]]
function TrapService.Client:GetAllTrapConfigs(_player: Player): { TrapConfig.TrapTypeConfig }
  return TrapConfig.getAllSorted()
end

--[[
	CLIENT: Get catch probability.
	@param player Player - The player (unused, for consistency)
	@param trapType string - The trap type
	@param predatorType string - The predator type
	@return number
]]
function TrapService.Client:GetCatchProbability(
  _player: Player,
  trapType: string,
  predatorType: string
): number
  return TrapConfig.calculateCatchProbability(trapType, predatorType)
end

--[[
	CLIENT: Check if can place more of a trap type.
	@param player Player - The player
	@param trapType string - The trap type
	@return boolean
]]
function TrapService.Client:CanPlaceMoreOfType(player: Player, trapType: string): boolean
  local self = TrapService
  return self:CanPlaceMoreOfType(player.UserId, trapType)
end

return TrapService
