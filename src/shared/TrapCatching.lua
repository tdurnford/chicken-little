--[[
	TrapCatching Module
	Handles the mechanics of traps catching predators including probability
	calculation, catch attempts, and predator storage.
]]

local TrapCatching = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local TrapConfig = require(script.Parent.TrapConfig)
local TrapPlacement = require(script.Parent.TrapPlacement)
local PredatorConfig = require(script.Parent.PredatorConfig)

-- Type definitions
export type CatchResult = {
  success: boolean,
  caught: boolean,
  message: string,
  trapId: string?,
  predatorType: string?,
  rewardMoney: number?,
  catchProbability: number?,
}

export type CatchAttemptInfo = {
  trapId: string,
  trapType: string,
  predatorType: string,
  catchProbability: number,
  isReady: boolean,
}

-- Attempt to catch a predator with a specific trap
function TrapCatching.attemptCatch(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  predatorType: string,
  currentTime: number
): CatchResult
  -- Validate predator type
  local predatorConfig = PredatorConfig.get(predatorType)
  if not predatorConfig then
    return {
      success = false,
      caught = false,
      message = "Invalid predator type: " .. tostring(predatorType),
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Find the trap
  local trap = TrapPlacement.findTrap(playerData, trapId)
  if not trap then
    return {
      success = false,
      caught = false,
      message = "Trap not found",
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Check if trap is ready to catch
  if not TrapPlacement.isReadyToCatch(trap, currentTime) then
    local reason = trap.caughtPredator and "already has a caught predator" or "is on cooldown"
    return {
      success = false,
      caught = false,
      message = "Trap " .. reason,
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Calculate catch probability
  local catchProbability = TrapConfig.calculateCatchProbability(trap.trapType, predatorType)

  -- Roll for catch
  local roll = math.random(1, 100)
  local caught = roll <= catchProbability

  if caught then
    -- Set caught predator on trap
    TrapPlacement.setCaughtPredator(playerData, trapId, predatorType)

    return {
      success = true,
      caught = true,
      message = "Caught " .. predatorConfig.displayName .. "!",
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = predatorConfig.rewardMoney,
      catchProbability = catchProbability,
    }
  else
    -- Start cooldown on failed attempt
    TrapPlacement.startCooldown(playerData, trapId, currentTime)

    return {
      success = true,
      caught = false,
      message = predatorConfig.displayName .. " escaped! Trap on cooldown.",
      trapId = trapId,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = catchProbability,
    }
  end
end

-- Attempt to catch a predator with all available traps
function TrapCatching.attemptCatchWithAllTraps(
  playerData: PlayerData.PlayerDataSchema,
  predatorType: string,
  currentTime: number
): CatchResult
  -- Validate predator type
  local predatorConfig = PredatorConfig.get(predatorType)
  if not predatorConfig then
    return {
      success = false,
      caught = false,
      message = "Invalid predator type: " .. tostring(predatorType),
      trapId = nil,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Get all ready traps
  local readyTraps = TrapPlacement.getReadyTraps(playerData, currentTime)

  if #readyTraps == 0 then
    return {
      success = false,
      caught = false,
      message = "No traps available to catch predator",
      trapId = nil,
      predatorType = predatorType,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Sort traps by catch probability (highest first) for best chance
  table.sort(readyTraps, function(a, b)
    local probA = TrapConfig.calculateCatchProbability(a.trapType, predatorType)
    local probB = TrapConfig.calculateCatchProbability(b.trapType, predatorType)
    return probA > probB
  end)

  -- Try each trap in order until one catches or all fail
  for _, trap in ipairs(readyTraps) do
    local result = TrapCatching.attemptCatch(playerData, trap.id, predatorType, currentTime)
    if result.caught then
      return result
    end
  end

  -- All traps failed
  return {
    success = true,
    caught = false,
    message = predatorConfig.displayName .. " escaped all traps!",
    trapId = nil,
    predatorType = predatorType,
    rewardMoney = nil,
    catchProbability = nil,
  }
end

-- Collect reward from a caught predator and release it
function TrapCatching.collectCaughtPredator(
  playerData: PlayerData.PlayerDataSchema,
  trapId: string,
  currentTime: number
): CatchResult
  -- Find the trap
  local trap = TrapPlacement.findTrap(playerData, trapId)
  if not trap then
    return {
      success = false,
      caught = false,
      message = "Trap not found",
      trapId = trapId,
      predatorType = nil,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  -- Check if trap has a caught predator
  if not trap.caughtPredator then
    return {
      success = false,
      caught = false,
      message = "No predator caught in this trap",
      trapId = trapId,
      predatorType = nil,
      rewardMoney = nil,
      catchProbability = nil,
    }
  end

  local predatorType = trap.caughtPredator
  local predatorConfig = PredatorConfig.get(predatorType)
  local rewardMoney = predatorConfig and predatorConfig.rewardMoney or 0

  -- Add reward to player
  playerData.money = playerData.money + rewardMoney

  -- Clear the caught predator and start cooldown
  TrapPlacement.clearCaughtPredator(playerData, trapId)
  TrapPlacement.startCooldown(playerData, trapId, currentTime)

  return {
    success = true,
    caught = true,
    message = "Collected "
      .. rewardMoney
      .. " for "
      .. (predatorConfig and predatorConfig.displayName or predatorType),
    trapId = trapId,
    predatorType = predatorType,
    rewardMoney = rewardMoney,
    catchProbability = nil,
  }
end

-- Collect all caught predators from all traps
function TrapCatching.collectAllCaughtPredators(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): {
  totalReward: number,
  count: number,
  results: { CatchResult },
}
  local trapsWithPredators = TrapPlacement.getTrapsWithPredators(playerData)
  local results = {}
  local totalReward = 0
  local count = 0

  for _, trap in ipairs(trapsWithPredators) do
    local result = TrapCatching.collectCaughtPredator(playerData, trap.id, currentTime)
    table.insert(results, result)
    if result.success and result.rewardMoney then
      totalReward = totalReward + result.rewardMoney
      count = count + 1
    end
  end

  return {
    totalReward = totalReward,
    count = count,
    results = results,
  }
end

-- Get catch probability info for a trap against a predator
function TrapCatching.getCatchInfo(
  trap: PlayerData.TrapData,
  predatorType: string,
  currentTime: number
): CatchAttemptInfo?
  if not TrapConfig.isValidType(trap.trapType) then
    return nil
  end

  if not PredatorConfig.isValidType(predatorType) then
    return nil
  end

  return {
    trapId = trap.id,
    trapType = trap.trapType,
    predatorType = predatorType,
    catchProbability = TrapConfig.calculateCatchProbability(trap.trapType, predatorType),
    isReady = TrapPlacement.isReadyToCatch(trap, currentTime),
  }
end

-- Get catch info for all traps against a predator
function TrapCatching.getAllCatchInfo(
  playerData: PlayerData.PlayerDataSchema,
  predatorType: string,
  currentTime: number
): { CatchAttemptInfo }
  local results = {}

  for _, trap in ipairs(playerData.traps) do
    local info = TrapCatching.getCatchInfo(trap, predatorType, currentTime)
    if info then
      table.insert(results, info)
    end
  end

  -- Sort by catch probability descending
  table.sort(results, function(a, b)
    return a.catchProbability > b.catchProbability
  end)

  return results
end

-- Get the best trap for catching a specific predator
function TrapCatching.getBestTrapForPredator(
  playerData: PlayerData.PlayerDataSchema,
  predatorType: string,
  currentTime: number
): CatchAttemptInfo?
  local allInfo = TrapCatching.getAllCatchInfo(playerData, predatorType, currentTime)

  -- Find first ready trap (list is already sorted by probability)
  for _, info in ipairs(allInfo) do
    if info.isReady then
      return info
    end
  end

  return nil
end

-- Calculate combined catch probability with all ready traps
function TrapCatching.getCombinedCatchProbability(
  playerData: PlayerData.PlayerDataSchema,
  predatorType: string,
  currentTime: number
): number
  local readyTraps = TrapPlacement.getReadyTraps(playerData, currentTime)

  if #readyTraps == 0 then
    return 0
  end

  -- Calculate probability that at least one trap catches
  -- P(at least one) = 1 - P(all fail) = 1 - (1-p1)(1-p2)...(1-pn)
  local escapeProbability = 1

  for _, trap in ipairs(readyTraps) do
    local catchProb = TrapConfig.calculateCatchProbability(trap.trapType, predatorType) / 100
    escapeProbability = escapeProbability * (1 - catchProb)
  end

  return math.floor((1 - escapeProbability) * 100)
end

-- Check if player can catch a predator (has at least one ready trap)
function TrapCatching.canCatchPredator(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): boolean
  local readyTraps = TrapPlacement.getReadyTraps(playerData, currentTime)
  return #readyTraps > 0
end

-- Get count of currently caught predators
function TrapCatching.getCaughtPredatorCount(playerData: PlayerData.PlayerDataSchema): number
  return #TrapPlacement.getTrapsWithPredators(playerData)
end

-- Get total potential reward from all caught predators
function TrapCatching.getTotalCaughtReward(playerData: PlayerData.PlayerDataSchema): number
  local trapsWithPredators = TrapPlacement.getTrapsWithPredators(playerData)
  local total = 0

  for _, trap in ipairs(trapsWithPredators) do
    if trap.caughtPredator then
      local predatorConfig = PredatorConfig.get(trap.caughtPredator)
      if predatorConfig then
        total = total + predatorConfig.rewardMoney
      end
    end
  end

  return total
end

-- Get summary of trap catching status
function TrapCatching.getSummary(
  playerData: PlayerData.PlayerDataSchema,
  currentTime: number
): {
  totalTraps: number,
  readyTraps: number,
  trapsOnCooldown: number,
  caughtPredators: number,
  pendingReward: number,
}
  local placementSummary = TrapPlacement.getSummary(playerData, currentTime)

  return {
    totalTraps = placementSummary.totalTraps,
    readyTraps = placementSummary.readyTraps,
    trapsOnCooldown = placementSummary.trapsOnCooldown,
    caughtPredators = placementSummary.trapsWithPredators,
    pendingReward = TrapCatching.getTotalCaughtReward(playerData),
  }
end

-- Simulate catch attempts for testing
function TrapCatching.simulateCatches(
  trapType: string,
  predatorType: string,
  attempts: number
): { catches: number, escapes: number, catchRate: number }
  local catches = 0
  local catchProbability = TrapConfig.calculateCatchProbability(trapType, predatorType)

  for _ = 1, attempts do
    local roll = math.random(1, 100)
    if roll <= catchProbability then
      catches = catches + 1
    end
  end

  return {
    catches = catches,
    escapes = attempts - catches,
    catchRate = (catches / attempts) * 100,
  }
end

return TrapCatching
