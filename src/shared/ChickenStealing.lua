--[[
	ChickenStealing Module
	Handles the mechanics of stealing chickens from other players' coops.
	Integrates with CageLocking to check lock status and ChickenPlacement
	to transfer chickens between players.
]]

local ChickenStealing = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local ChickenPlacement = require(script.Parent.ChickenPlacement)
local CageLocking = require(script.Parent.CageLocking)

-- Type definitions
export type StealState = {
  isAttempting: boolean,
  targetChickenId: string?,
  targetOwnerId: number?,
  startTime: number,
  requiredDuration: number,
}

export type StealResult = {
  success: boolean,
  message: string,
  chickenId: string?,
  chickenType: string?,
  chickenRarity: string?,
}

export type StealCheckResult = {
  canSteal: boolean,
  reason: string,
}

export type StealProgressInfo = {
  isActive: boolean,
  progress: number, -- 0-1
  remainingTime: number,
  targetChickenId: string?,
}

-- Configuration constants
local STEAL_DURATION = 3 -- Seconds to complete a steal
local STEAL_RANGE = 8 -- Studs within which stealing is possible

-- Create initial steal state
function ChickenStealing.createStealState(): StealState
  return {
    isAttempting = false,
    targetChickenId = nil,
    targetOwnerId = nil,
    startTime = 0,
    requiredDuration = STEAL_DURATION,
  }
end

-- Get configuration values
function ChickenStealing.getConfig(): { stealDuration: number, stealRange: number }
  return {
    stealDuration = STEAL_DURATION,
    stealRange = STEAL_RANGE,
  }
end

-- Check if a player can attempt to steal from a coop
-- Returns StealCheckResult with reason
function ChickenStealing.canStealFromCoop(
  lockState: CageLocking.LockState,
  isOwner: boolean,
  currentTime: number
): StealCheckResult
  -- Cannot steal from own coop
  if isOwner then
    return {
      canSteal = false,
      reason = "Cannot steal from your own coop",
    }
  end

  -- Check if coop is locked
  if CageLocking.isLocked(lockState, currentTime) then
    local remaining = CageLocking.getRemainingDuration(lockState, currentTime)
    return {
      canSteal = false,
      reason = string.format("Coop is locked (%.0fs remaining)", remaining),
    }
  end

  return {
    canSteal = true,
    reason = "Coop is unlocked",
  }
end

-- Check if a specific chicken can be stolen
function ChickenStealing.canStealChicken(
  targetPlayerData: PlayerData.PlayerDataSchema,
  chickenId: string,
  lockState: CageLocking.LockState,
  currentTime: number
): StealCheckResult
  -- Check lock status (assuming not owner since we're stealing)
  local coopCheck = ChickenStealing.canStealFromCoop(lockState, false, currentTime)
  if not coopCheck.canSteal then
    return coopCheck
  end

  -- Find the chicken in placed chickens
  local chicken = ChickenPlacement.findPlacedChicken(targetPlayerData, chickenId)
  if not chicken then
    return {
      canSteal = false,
      reason = "Chicken not found in coop",
    }
  end

  return {
    canSteal = true,
    reason = "Chicken can be stolen",
  }
end

-- Start a steal attempt
function ChickenStealing.startSteal(
  stealState: StealState,
  targetChickenId: string,
  targetOwnerId: number,
  currentTime: number
): StealResult
  if stealState.isAttempting then
    return {
      success = false,
      message = "Already attempting to steal a chicken",
      chickenId = stealState.targetChickenId,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  stealState.isAttempting = true
  stealState.targetChickenId = targetChickenId
  stealState.targetOwnerId = targetOwnerId
  stealState.startTime = currentTime
  stealState.requiredDuration = STEAL_DURATION

  return {
    success = true,
    message = string.format("Started stealing... (%.1fs)", STEAL_DURATION),
    chickenId = targetChickenId,
    chickenType = nil,
    chickenRarity = nil,
  }
end

-- Cancel a steal attempt
function ChickenStealing.cancelSteal(stealState: StealState): StealResult
  if not stealState.isAttempting then
    return {
      success = false,
      message = "Not currently stealing",
      chickenId = nil,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  local chickenId = stealState.targetChickenId

  -- Reset state
  stealState.isAttempting = false
  stealState.targetChickenId = nil
  stealState.targetOwnerId = nil
  stealState.startTime = 0

  return {
    success = true,
    message = "Steal attempt cancelled",
    chickenId = chickenId,
    chickenType = nil,
    chickenRarity = nil,
  }
end

-- Check if steal is complete (enough time has passed)
function ChickenStealing.isStealComplete(stealState: StealState, currentTime: number): boolean
  if not stealState.isAttempting then
    return false
  end
  local elapsed = currentTime - stealState.startTime
  return elapsed >= stealState.requiredDuration
end

-- Get steal progress (0-1)
function ChickenStealing.getStealProgress(stealState: StealState, currentTime: number): number
  if not stealState.isAttempting then
    return 0
  end
  local elapsed = currentTime - stealState.startTime
  return math.clamp(elapsed / stealState.requiredDuration, 0, 1)
end

-- Get remaining time for steal
function ChickenStealing.getRemainingTime(stealState: StealState, currentTime: number): number
  if not stealState.isAttempting then
    return 0
  end
  local elapsed = currentTime - stealState.startTime
  return math.max(0, stealState.requiredDuration - elapsed)
end

-- Get steal progress info for UI display
function ChickenStealing.getProgressInfo(
  stealState: StealState,
  currentTime: number
): StealProgressInfo
  return {
    isActive = stealState.isAttempting,
    progress = ChickenStealing.getStealProgress(stealState, currentTime),
    remainingTime = ChickenStealing.getRemainingTime(stealState, currentTime),
    targetChickenId = stealState.targetChickenId,
  }
end

-- Complete the steal and transfer the chicken
-- This modifies both player data structures
-- Note: Streak behavior for stealing the pot:
--   - Thief's potStreak stays the same (no increase, no reset)
--   - Target's potStreak stays the same (they didn't lose by having chicken stolen)
-- The player who "captures the pot" (collects accumulated money) gets their streak increased
function ChickenStealing.completeSteal(
  stealState: StealState,
  targetPlayerData: PlayerData.PlayerDataSchema,
  thiefPlayerData: PlayerData.PlayerDataSchema,
  lockState: CageLocking.LockState,
  currentTime: number
): StealResult
  -- Verify steal is in progress
  if not stealState.isAttempting then
    return {
      success = false,
      message = "No steal in progress",
      chickenId = nil,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  -- Verify steal timer is complete
  if not ChickenStealing.isStealComplete(stealState, currentTime) then
    local remaining = ChickenStealing.getRemainingTime(stealState, currentTime)
    return {
      success = false,
      message = string.format("Steal not complete (%.1fs remaining)", remaining),
      chickenId = stealState.targetChickenId,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  -- Re-verify lock status (could have changed during steal)
  if CageLocking.isLocked(lockState, currentTime) then
    ChickenStealing.cancelSteal(stealState)
    return {
      success = false,
      message = "Coop was locked during steal attempt",
      chickenId = stealState.targetChickenId,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  local targetChickenId = stealState.targetChickenId
  if not targetChickenId then
    ChickenStealing.cancelSteal(stealState)
    return {
      success = false,
      message = "No target chicken specified",
      chickenId = nil,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  -- Find the chicken in target's placed chickens
  local chicken, placedIndex = ChickenPlacement.findPlacedChicken(targetPlayerData, targetChickenId)
  if not chicken or not placedIndex then
    ChickenStealing.cancelSteal(stealState)
    return {
      success = false,
      message = "Chicken no longer in coop",
      chickenId = targetChickenId,
      chickenType = nil,
      chickenRarity = nil,
    }
  end

  -- Store chicken info for return value
  local chickenType = chicken.chickenType
  local chickenRarity = chicken.rarity

  -- Remove chicken from target's placed chickens
  table.remove(targetPlayerData.placedChickens, placedIndex)

  -- Create new chicken data for thief's inventory (without spot)
  local stolenChicken: PlayerData.ChickenData = {
    id = PlayerData.generateId(), -- Generate new ID for thief
    chickenType = chickenType,
    rarity = chickenRarity,
    accumulatedMoney = 0, -- Reset accumulated money
    lastEggTime = currentTime,
    spotIndex = nil, -- Goes to inventory, not placed
  }

  -- Add to thief's inventory
  table.insert(thiefPlayerData.inventory.chickens, stolenChicken)

  -- Reset steal state
  stealState.isAttempting = false
  stealState.targetChickenId = nil
  stealState.targetOwnerId = nil
  stealState.startTime = 0

  return {
    success = true,
    message = "Successfully stole chicken!",
    chickenId = stolenChicken.id,
    chickenType = chickenType,
    chickenRarity = chickenRarity,
  }
end

-- Check if player is currently attempting a steal
function ChickenStealing.isAttempting(stealState: StealState): boolean
  return stealState.isAttempting
end

-- Get the target chicken ID being stolen
function ChickenStealing.getTargetChickenId(stealState: StealState): string?
  return stealState.targetChickenId
end

-- Get the target owner ID
function ChickenStealing.getTargetOwnerId(stealState: StealState): number?
  return stealState.targetOwnerId
end

-- Update steal state (for use in game loop)
-- Returns true if steal was completed this frame
function ChickenStealing.update(stealState: StealState, currentTime: number): boolean
  if not stealState.isAttempting then
    return false
  end

  -- Check if steal timer completed
  if ChickenStealing.isStealComplete(stealState, currentTime) then
    return true
  end

  return false
end

-- Get display text for steal action
function ChickenStealing.getActionPrompt(
  stealState: StealState,
  lockState: CageLocking.LockState?,
  isOwner: boolean,
  currentTime: number
): { text: string, enabled: boolean }
  -- Currently stealing
  if stealState.isAttempting then
    local progress = ChickenStealing.getStealProgress(stealState, currentTime)
    local remaining = ChickenStealing.getRemainingTime(stealState, currentTime)
    return {
      text = string.format("Stealing... %.1fs [Esc] Cancel", remaining),
      enabled = true,
    }
  end

  -- Own coop
  if isOwner then
    return {
      text = "",
      enabled = false,
    }
  end

  -- Check lock status
  if lockState and CageLocking.isLocked(lockState, currentTime) then
    local remaining = CageLocking.getRemainingDuration(lockState, currentTime)
    return {
      text = string.format("🔒 Locked (%.0fs)", remaining),
      enabled = false,
    }
  end

  -- Ready to steal
  return {
    text = "[E] Steal Chicken",
    enabled = true,
  }
end

-- Validate steal state
function ChickenStealing.validateState(stealState: StealState): boolean
  if type(stealState) ~= "table" then
    return false
  end
  if type(stealState.isAttempting) ~= "boolean" then
    return false
  end
  if stealState.targetChickenId ~= nil and type(stealState.targetChickenId) ~= "string" then
    return false
  end
  if stealState.targetOwnerId ~= nil and type(stealState.targetOwnerId) ~= "number" then
    return false
  end
  if type(stealState.startTime) ~= "number" then
    return false
  end
  if type(stealState.requiredDuration) ~= "number" then
    return false
  end
  return true
end

-- Reset steal state
function ChickenStealing.reset(stealState: StealState): ()
  stealState.isAttempting = false
  stealState.targetChickenId = nil
  stealState.targetOwnerId = nil
  stealState.startTime = 0
  stealState.requiredDuration = STEAL_DURATION
end

-- Get summary for debugging/UI
function ChickenStealing.getSummary(
  stealState: StealState,
  currentTime: number
): {
  isAttempting: boolean,
  progress: number,
  remainingTime: number,
  targetChickenId: string?,
  targetOwnerId: number?,
}
  return {
    isAttempting = stealState.isAttempting,
    progress = ChickenStealing.getStealProgress(stealState, currentTime),
    remainingTime = ChickenStealing.getRemainingTime(stealState, currentTime),
    targetChickenId = stealState.targetChickenId,
    targetOwnerId = stealState.targetOwnerId,
  }
end

return ChickenStealing
