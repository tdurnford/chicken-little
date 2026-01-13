--[[
	CageLocking Module
	Implements the cage locking system that prevents other players
	from entering and stealing chickens for a limited duration.
]]

local CageLocking = {}

-- Type definitions
export type LockState = {
  isLocked: boolean,
  lockEndTime: number,
  lockCooldownEndTime: number,
  lastLockTime: number,
}

export type LockResult = {
  success: boolean,
  message: string,
  lockEndTime: number?,
  remainingDuration: number?,
}

export type LockStatus = {
  isLocked: boolean,
  remainingDuration: number,
  cooldownRemaining: number,
  canLock: boolean,
}

-- Configuration constants
local BASE_LOCK_DURATION = 60 -- 1 minute base lock duration
local LOCK_COOLDOWN = 120 -- 2 minute cooldown between locks

-- Create initial lock state for a cage
function CageLocking.createLockState(): LockState
  return {
    isLocked = false,
    lockEndTime = 0,
    lockCooldownEndTime = 0,
    lastLockTime = 0,
  }
end

-- Get the lock duration based on upgrade multiplier
function CageLocking.getLockDuration(lockDurationMultiplier: number): number
  return BASE_LOCK_DURATION * lockDurationMultiplier
end

-- Check if the lock cooldown has expired
function CageLocking.isCooldownExpired(lockState: LockState, currentTime: number): boolean
  return currentTime >= lockState.lockCooldownEndTime
end

-- Get remaining cooldown time
function CageLocking.getCooldownRemaining(lockState: LockState, currentTime: number): number
  local remaining = lockState.lockCooldownEndTime - currentTime
  return math.max(0, remaining)
end

-- Check if the cage is currently locked
function CageLocking.isLocked(lockState: LockState, currentTime: number): boolean
  if not lockState.isLocked then
    return false
  end
  -- Check if lock has expired
  if currentTime >= lockState.lockEndTime then
    return false
  end
  return true
end

-- Get remaining lock duration
function CageLocking.getRemainingDuration(lockState: LockState, currentTime: number): number
  if not CageLocking.isLocked(lockState, currentTime) then
    return 0
  end
  return math.max(0, lockState.lockEndTime - currentTime)
end

-- Check if the cage can be locked
function CageLocking.canLock(lockState: LockState, currentTime: number): boolean
  -- Cannot lock if already locked
  if CageLocking.isLocked(lockState, currentTime) then
    return false
  end
  -- Cannot lock if on cooldown
  if not CageLocking.isCooldownExpired(lockState, currentTime) then
    return false
  end
  return true
end

-- Activate the lock
function CageLocking.activateLock(
  lockState: LockState,
  lockDurationMultiplier: number,
  currentTime: number
): LockResult
  -- Check if can lock
  if CageLocking.isLocked(lockState, currentTime) then
    local remaining = CageLocking.getRemainingDuration(lockState, currentTime)
    return {
      success = false,
      message = string.format("Cage is already locked (%.0fs remaining)", remaining),
      lockEndTime = lockState.lockEndTime,
      remainingDuration = remaining,
    }
  end

  if not CageLocking.isCooldownExpired(lockState, currentTime) then
    local cooldownRemaining = CageLocking.getCooldownRemaining(lockState, currentTime)
    return {
      success = false,
      message = string.format("Lock on cooldown (%.0fs remaining)", cooldownRemaining),
      lockEndTime = nil,
      remainingDuration = nil,
    }
  end

  -- Calculate lock duration with multiplier
  local lockDuration = CageLocking.getLockDuration(lockDurationMultiplier)
  local lockEndTime = currentTime + lockDuration

  -- Activate the lock
  lockState.isLocked = true
  lockState.lockEndTime = lockEndTime
  lockState.lastLockTime = currentTime
  -- Set cooldown to start after lock expires
  lockState.lockCooldownEndTime = lockEndTime + LOCK_COOLDOWN

  return {
    success = true,
    message = string.format("Cage locked for %.0f seconds", lockDuration),
    lockEndTime = lockEndTime,
    remainingDuration = lockDuration,
  }
end

-- Deactivate the lock early (optional, for admin or special cases)
function CageLocking.deactivateLock(lockState: LockState, currentTime: number): LockResult
  if not lockState.isLocked then
    return {
      success = false,
      message = "Cage is not locked",
      lockEndTime = nil,
      remainingDuration = nil,
    }
  end

  lockState.isLocked = false
  -- Keep the cooldown active from when the lock was supposed to end
  -- This prevents rapid lock/unlock abuse

  return {
    success = true,
    message = "Cage unlocked",
    lockEndTime = nil,
    remainingDuration = nil,
  }
end

-- Update lock state (call this periodically to auto-expire locks)
function CageLocking.update(lockState: LockState, currentTime: number): boolean
  if lockState.isLocked and currentTime >= lockState.lockEndTime then
    lockState.isLocked = false
    return true -- Lock expired
  end
  return false -- No change
end

-- Check if a player can enter another player's cage
function CageLocking.canEnterCage(
  lockState: LockState,
  isOwner: boolean,
  currentTime: number
): boolean
  -- Owner can always enter their own cage
  if isOwner then
    return true
  end
  -- Other players cannot enter if locked
  return not CageLocking.isLocked(lockState, currentTime)
end

-- Get entry result with message (for UI feedback)
function CageLocking.tryEnterCage(
  lockState: LockState,
  isOwner: boolean,
  currentTime: number
): { allowed: boolean, message: string }
  if isOwner then
    return {
      allowed = true,
      message = "Welcome to your cage",
    }
  end

  if CageLocking.isLocked(lockState, currentTime) then
    local remaining = CageLocking.getRemainingDuration(lockState, currentTime)
    return {
      allowed = false,
      message = string.format("This cage is locked! (%.0fs remaining)", remaining),
    }
  end

  return {
    allowed = true,
    message = "Entering cage",
  }
end

-- Get full lock status for UI display
function CageLocking.getStatus(lockState: LockState, currentTime: number): LockStatus
  return {
    isLocked = CageLocking.isLocked(lockState, currentTime),
    remainingDuration = CageLocking.getRemainingDuration(lockState, currentTime),
    cooldownRemaining = CageLocking.getCooldownRemaining(lockState, currentTime),
    canLock = CageLocking.canLock(lockState, currentTime),
  }
end

-- Get display info for lock button UI
function CageLocking.getDisplayInfo(
  lockState: LockState,
  lockDurationMultiplier: number,
  currentTime: number
): {
  buttonText: string,
  buttonEnabled: boolean,
  statusText: string,
  lockDuration: number,
}
  local status = CageLocking.getStatus(lockState, currentTime)
  local lockDuration = CageLocking.getLockDuration(lockDurationMultiplier)

  local buttonText: string
  local buttonEnabled: boolean
  local statusText: string

  if status.isLocked then
    buttonText = string.format("LOCKED (%.0fs)", status.remainingDuration)
    buttonEnabled = false
    statusText = "Cage is protected"
  elseif status.cooldownRemaining > 0 then
    buttonText = string.format("Cooldown (%.0fs)", status.cooldownRemaining)
    buttonEnabled = false
    statusText = "Lock recharging..."
  else
    buttonText = string.format("Lock Cage (%.0fs)", lockDuration)
    buttonEnabled = true
    statusText = "Ready to lock"
  end

  return {
    buttonText = buttonText,
    buttonEnabled = buttonEnabled,
    statusText = statusText,
    lockDuration = lockDuration,
  }
end

-- Get configuration values
function CageLocking.getConfig(): { baseLockDuration: number, lockCooldown: number }
  return {
    baseLockDuration = BASE_LOCK_DURATION,
    lockCooldown = LOCK_COOLDOWN,
  }
end

-- Calculate lock duration for a specific cage tier
function CageLocking.getLockDurationForTier(cageTier: number): number
  -- Cage tier affects lock duration multiplier
  -- Tier 1: 1x, Tier 2: 1.5x, Tier 3: 2x, etc.
  local multiplier = 1 + (cageTier - 1) * 0.5
  return CageLocking.getLockDuration(multiplier)
end

-- Get lock info for serialization (to save with player data if needed)
function CageLocking.serialize(lockState: LockState): {
  lockEndTime: number,
  lockCooldownEndTime: number,
}
  return {
    lockEndTime = lockState.lockEndTime,
    lockCooldownEndTime = lockState.lockCooldownEndTime,
  }
end

-- Restore lock state from saved data
function CageLocking.deserialize(
  savedData: { lockEndTime: number?, lockCooldownEndTime: number? }
): LockState
  local state = CageLocking.createLockState()

  if savedData then
    state.lockEndTime = savedData.lockEndTime or 0
    state.lockCooldownEndTime = savedData.lockCooldownEndTime or 0
    -- isLocked will be determined by update() call with current time
  end

  return state
end

-- Validate lock state
function CageLocking.validateState(lockState: LockState): boolean
  if type(lockState) ~= "table" then
    return false
  end
  if type(lockState.isLocked) ~= "boolean" then
    return false
  end
  if type(lockState.lockEndTime) ~= "number" then
    return false
  end
  if type(lockState.lockCooldownEndTime) ~= "number" then
    return false
  end
  if type(lockState.lastLockTime) ~= "number" then
    return false
  end
  return true
end

-- Reset lock state (for testing or new game)
function CageLocking.reset(lockState: LockState): ()
  lockState.isLocked = false
  lockState.lockEndTime = 0
  lockState.lockCooldownEndTime = 0
  lockState.lastLockTime = 0
end

return CageLocking
