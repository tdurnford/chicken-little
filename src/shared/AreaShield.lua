--[[
	AreaShield Module
	Handles area shield activation, duration tracking, and cooldown management.
	Players can activate a shield that blocks predators and other players
	from entering their section for a limited duration.
]]

local AreaShield = {}

-- Type definitions
export type ShieldState = {
  isActive: boolean,
  activatedTime: number?, -- os.time() when shield was activated
  expiresAt: number?, -- os.time() when shield will expire
  cooldownEndTime: number?, -- os.time() when cooldown ends (can reactivate)
}

export type ShieldResult = {
  success: boolean,
  message: string,
  shieldState: ShieldState?,
}

-- Configuration constants
local SHIELD_DURATION = 60 -- Shield lasts 60 seconds
local SHIELD_COOLDOWN = 300 -- 5 minute cooldown before reuse

-- Create default shield state
function AreaShield.createDefaultState(): ShieldState
  return {
    isActive = false,
    activatedTime = nil,
    expiresAt = nil,
    cooldownEndTime = nil,
  }
end

-- Check if shield is currently active
function AreaShield.isActive(shieldState: ShieldState, currentTime: number?): boolean
  if not shieldState.isActive then
    return false
  end

  local now = currentTime or os.time()
  if shieldState.expiresAt and now >= shieldState.expiresAt then
    -- Shield has expired
    return false
  end

  return true
end

-- Check if shield is on cooldown
function AreaShield.isOnCooldown(shieldState: ShieldState, currentTime: number?): boolean
  if not shieldState.cooldownEndTime then
    return false
  end

  local now = currentTime or os.time()
  return now < shieldState.cooldownEndTime
end

-- Get remaining shield duration in seconds
function AreaShield.getRemainingDuration(shieldState: ShieldState, currentTime: number?): number
  if not AreaShield.isActive(shieldState, currentTime) then
    return 0
  end

  local now = currentTime or os.time()
  if not shieldState.expiresAt then
    return 0
  end

  return math.max(0, shieldState.expiresAt - now)
end

-- Get remaining cooldown in seconds
function AreaShield.getRemainingCooldown(shieldState: ShieldState, currentTime: number?): number
  if not shieldState.cooldownEndTime then
    return 0
  end

  local now = currentTime or os.time()
  return math.max(0, shieldState.cooldownEndTime - now)
end

-- Activate the shield
function AreaShield.activate(shieldState: ShieldState, currentTime: number?): ShieldResult
  local now = currentTime or os.time()

  -- Check if shield is already active
  if AreaShield.isActive(shieldState, now) then
    local remaining = AreaShield.getRemainingDuration(shieldState, now)
    return {
      success = false,
      message = string.format(
        "Shield is already active! %d seconds remaining.",
        math.floor(remaining)
      ),
      shieldState = shieldState,
    }
  end

  -- Check if on cooldown
  if AreaShield.isOnCooldown(shieldState, now) then
    local cooldown = AreaShield.getRemainingCooldown(shieldState, now)
    local mins = math.floor(cooldown / 60)
    local secs = math.floor(cooldown % 60)
    return {
      success = false,
      message = string.format("Shield on cooldown! Available in %d:%02d", mins, secs),
      shieldState = shieldState,
    }
  end

  -- Activate the shield
  shieldState.isActive = true
  shieldState.activatedTime = now
  shieldState.expiresAt = now + SHIELD_DURATION
  shieldState.cooldownEndTime = now + SHIELD_DURATION + SHIELD_COOLDOWN

  return {
    success = true,
    message = string.format("Shield activated! Protected for %d seconds.", SHIELD_DURATION),
    shieldState = shieldState,
  }
end

-- Deactivate the shield (called when shield expires or manually)
function AreaShield.deactivate(shieldState: ShieldState): ShieldState
  shieldState.isActive = false
  shieldState.activatedTime = nil
  shieldState.expiresAt = nil
  -- Keep cooldownEndTime so player must wait before reactivating
  return shieldState
end

-- Update shield state (call periodically to check expiration)
function AreaShield.update(
  shieldState: ShieldState,
  currentTime: number?
): {
  wasActive: boolean,
  isNowActive: boolean,
  expired: boolean,
}
  local now = currentTime or os.time()
  local wasActive = shieldState.isActive

  -- Check if shield should expire
  if shieldState.isActive and shieldState.expiresAt and now >= shieldState.expiresAt then
    AreaShield.deactivate(shieldState)
  end

  local isNowActive = shieldState.isActive

  return {
    wasActive = wasActive,
    isNowActive = isNowActive,
    expired = wasActive and not isNowActive,
  }
end

-- Check if a player can enter a shielded section
function AreaShield.canPlayerEnter(
  shieldState: ShieldState,
  isOwner: boolean,
  currentTime: number?
): boolean
  -- Owner can always enter their own section
  if isOwner then
    return true
  end

  -- If shield is not active, anyone can enter
  if not AreaShield.isActive(shieldState, currentTime) then
    return true
  end

  -- Shield is active, non-owners cannot enter
  return false
end

-- Check if predators can spawn/attack in a shielded section
function AreaShield.canPredatorSpawn(shieldState: ShieldState, currentTime: number?): boolean
  -- If shield is active, predators cannot spawn
  return not AreaShield.isActive(shieldState, currentTime)
end

-- Get shield status for UI display
function AreaShield.getStatus(
  shieldState: ShieldState,
  currentTime: number?
): {
  isActive: boolean,
  isOnCooldown: boolean,
  canActivate: boolean,
  remainingDuration: number,
  remainingCooldown: number,
  durationTotal: number,
  cooldownTotal: number,
}
  local now = currentTime or os.time()
  local isActive = AreaShield.isActive(shieldState, now)
  local isOnCooldown = AreaShield.isOnCooldown(shieldState, now)

  return {
    isActive = isActive,
    isOnCooldown = isOnCooldown,
    canActivate = not isActive and not isOnCooldown,
    remainingDuration = AreaShield.getRemainingDuration(shieldState, now),
    remainingCooldown = AreaShield.getRemainingCooldown(shieldState, now),
    durationTotal = SHIELD_DURATION,
    cooldownTotal = SHIELD_COOLDOWN,
  }
end

-- Get configuration constants
function AreaShield.getConstants(): {
  shieldDuration: number,
  shieldCooldown: number,
}
  return {
    shieldDuration = SHIELD_DURATION,
    shieldCooldown = SHIELD_COOLDOWN,
  }
end

-- Validate shield state structure
function AreaShield.validate(shieldState: any): boolean
  if type(shieldState) ~= "table" then
    return false
  end

  if type(shieldState.isActive) ~= "boolean" then
    return false
  end

  -- Optional number fields
  if shieldState.activatedTime ~= nil and type(shieldState.activatedTime) ~= "number" then
    return false
  end

  if shieldState.expiresAt ~= nil and type(shieldState.expiresAt) ~= "number" then
    return false
  end

  if shieldState.cooldownEndTime ~= nil and type(shieldState.cooldownEndTime) ~= "number" then
    return false
  end

  return true
end

return AreaShield
