--[[
	CageUpgrades Module
	Implements the cage upgrade system that extends lock duration
	and improves predator resistance per tier.
]]

local CageUpgrades = {}

-- Type definitions
export type UpgradeTierConfig = {
  tier: number,
  name: string,
  displayName: string,
  price: number,
  lockDurationMultiplier: number,
  predatorResistance: number,
  description: string,
}

export type UpgradeResult = {
  success: boolean,
  message: string,
  newTier: number?,
  newBalance: number?,
  lockDurationMultiplier: number?,
  predatorResistance: number?,
}

export type UpgradeInfo = {
  currentTier: number,
  currentTierName: string,
  nextTier: number?,
  nextTierName: string?,
  nextTierPrice: number?,
  canAffordNext: boolean,
  isMaxTier: boolean,
  lockDurationMultiplier: number,
  predatorResistance: number,
  lockDurationSeconds: number,
}

-- Cage upgrade tier configurations
-- Prices scale exponentially, bonuses increase with each tier
local UPGRADE_TIERS: { [number]: UpgradeTierConfig } = {
  [1] = {
    tier = 1,
    name = "Basic",
    displayName = "Basic Cage",
    price = 0,
    lockDurationMultiplier = 1.0,
    predatorResistance = 0.0,
    description = "Your starter cage. No special protection.",
  },
  [2] = {
    tier = 2,
    name = "Reinforced",
    displayName = "Reinforced Cage",
    price = 5000,
    lockDurationMultiplier = 1.5,
    predatorResistance = 0.10,
    description = "Stronger materials. 90 second locks, 10% predator resistance.",
  },
  [3] = {
    tier = 3,
    name = "Steel",
    displayName = "Steel Cage",
    price = 25000,
    lockDurationMultiplier = 2.0,
    predatorResistance = 0.20,
    description = "Solid steel construction. 120 second locks, 20% predator resistance.",
  },
  [4] = {
    tier = 4,
    name = "Titanium",
    displayName = "Titanium Cage",
    price = 100000,
    lockDurationMultiplier = 2.5,
    predatorResistance = 0.30,
    description = "Advanced titanium alloy. 150 second locks, 30% predator resistance.",
  },
  [5] = {
    tier = 5,
    name = "Fortress",
    displayName = "Fortress Cage",
    price = 500000,
    lockDurationMultiplier = 3.0,
    predatorResistance = 0.45,
    description = "Military-grade fortress. 180 second locks, 45% predator resistance.",
  },
  [6] = {
    tier = 6,
    name = "Ultimate",
    displayName = "Ultimate Cage",
    price = 2500000,
    lockDurationMultiplier = 4.0,
    predatorResistance = 0.60,
    description = "The ultimate protection. 240 second locks, 60% predator resistance.",
  },
}

local MAX_TIER = 6
local BASE_LOCK_DURATION = 60

-- Get configuration for a specific tier
function CageUpgrades.getTierConfig(tier: number): UpgradeTierConfig?
  return UPGRADE_TIERS[tier]
end

-- Get all tier configurations
function CageUpgrades.getAllTiers(): { UpgradeTierConfig }
  local tiers = {}
  for i = 1, MAX_TIER do
    table.insert(tiers, UPGRADE_TIERS[i])
  end
  return tiers
end

-- Get the maximum tier available
function CageUpgrades.getMaxTier(): number
  return MAX_TIER
end

-- Check if a tier is valid
function CageUpgrades.isValidTier(tier: number): boolean
  return tier >= 1 and tier <= MAX_TIER and UPGRADE_TIERS[tier] ~= nil
end

-- Get lock duration multiplier for a tier
function CageUpgrades.getLockDurationMultiplier(tier: number): number
  local config = UPGRADE_TIERS[tier]
  if config then
    return config.lockDurationMultiplier
  end
  return 1.0
end

-- Get predator resistance for a tier
function CageUpgrades.getPredatorResistance(tier: number): number
  local config = UPGRADE_TIERS[tier]
  if config then
    return config.predatorResistance
  end
  return 0.0
end

-- Get lock duration in seconds for a tier
function CageUpgrades.getLockDuration(tier: number): number
  local multiplier = CageUpgrades.getLockDurationMultiplier(tier)
  return BASE_LOCK_DURATION * multiplier
end

-- Get upgrade price for a specific tier
function CageUpgrades.getTierPrice(tier: number): number
  local config = UPGRADE_TIERS[tier]
  if config then
    return config.price
  end
  return 0
end

-- Get the price to upgrade from current tier to next tier
function CageUpgrades.getNextTierPrice(currentTier: number): number?
  local nextTier = currentTier + 1
  if nextTier > MAX_TIER then
    return nil
  end
  return CageUpgrades.getTierPrice(nextTier)
end

-- Check if player can afford the next tier
function CageUpgrades.canAffordNextTier(currentTier: number, money: number): boolean
  local price = CageUpgrades.getNextTierPrice(currentTier)
  if price == nil then
    return false
  end
  return money >= price
end

-- Check if at max tier
function CageUpgrades.isMaxTier(tier: number): boolean
  return tier >= MAX_TIER
end

-- Apply upgrade data to player data
local function applyUpgradeToPlayerData(playerData: any, newTier: number): ()
  local config = UPGRADE_TIERS[newTier]
  if config and playerData and playerData.upgrades then
    playerData.upgrades.cageTier = newTier
    playerData.upgrades.lockDurationMultiplier = config.lockDurationMultiplier
    playerData.upgrades.predatorResistance = config.predatorResistance
  end
end

-- Purchase upgrade to next tier
function CageUpgrades.purchaseUpgrade(playerData: any): UpgradeResult
  if not playerData or not playerData.upgrades then
    return {
      success = false,
      message = "Invalid player data",
    }
  end

  local currentTier = playerData.upgrades.cageTier or 1

  if currentTier >= MAX_TIER then
    return {
      success = false,
      message = "Already at maximum cage tier",
    }
  end

  local nextTier = currentTier + 1
  local price = CageUpgrades.getTierPrice(nextTier)

  if playerData.money < price then
    local config = UPGRADE_TIERS[nextTier]
    local tierName = config and config.displayName or ("Tier " .. tostring(nextTier))
    return {
      success = false,
      message = string.format("Insufficient funds. Need $%d for %s", price, tierName),
    }
  end

  -- Deduct money
  playerData.money = playerData.money - price

  -- Apply upgrade
  applyUpgradeToPlayerData(playerData, nextTier)

  local config = UPGRADE_TIERS[nextTier]
  return {
    success = true,
    message = string.format("Upgraded to %s!", config.displayName),
    newTier = nextTier,
    newBalance = playerData.money,
    lockDurationMultiplier = config.lockDurationMultiplier,
    predatorResistance = config.predatorResistance,
  }
end

-- Purchase a specific tier (skipping intermediate tiers is not allowed)
function CageUpgrades.purchaseSpecificTier(playerData: any, targetTier: number): UpgradeResult
  if not playerData or not playerData.upgrades then
    return {
      success = false,
      message = "Invalid player data",
    }
  end

  local currentTier = playerData.upgrades.cageTier or 1

  if not CageUpgrades.isValidTier(targetTier) then
    return {
      success = false,
      message = "Invalid target tier",
    }
  end

  if targetTier <= currentTier then
    return {
      success = false,
      message = "Cannot purchase a tier you already have or lower",
    }
  end

  if targetTier > currentTier + 1 then
    return {
      success = false,
      message = "Must upgrade one tier at a time",
    }
  end

  return CageUpgrades.purchaseUpgrade(playerData)
end

-- Get comprehensive upgrade info for UI
function CageUpgrades.getUpgradeInfo(playerData: any): UpgradeInfo
  local currentTier = 1
  local money = 0

  if playerData and playerData.upgrades then
    currentTier = playerData.upgrades.cageTier or 1
  end
  if playerData then
    money = playerData.money or 0
  end

  local currentConfig = UPGRADE_TIERS[currentTier]
  local nextTier = currentTier + 1
  local nextConfig = UPGRADE_TIERS[nextTier]
  local isMaxed = currentTier >= MAX_TIER

  return {
    currentTier = currentTier,
    currentTierName = currentConfig and currentConfig.displayName or "Unknown",
    nextTier = if isMaxed then nil else nextTier,
    nextTierName = if nextConfig then nextConfig.displayName else nil,
    nextTierPrice = if nextConfig then nextConfig.price else nil,
    canAffordNext = CageUpgrades.canAffordNextTier(currentTier, money),
    isMaxTier = isMaxed,
    lockDurationMultiplier = currentConfig and currentConfig.lockDurationMultiplier or 1.0,
    predatorResistance = currentConfig and currentConfig.predatorResistance or 0.0,
    lockDurationSeconds = CageUpgrades.getLockDuration(currentTier),
  }
end

-- Get display info for upgrade button UI
function CageUpgrades.getDisplayInfo(playerData: any): {
  buttonText: string,
  buttonEnabled: boolean,
  tierText: string,
  descriptionText: string,
  statsText: string,
}
  local info = CageUpgrades.getUpgradeInfo(playerData)

  local buttonText: string
  local buttonEnabled: boolean
  local tierText: string
  local descriptionText: string
  local statsText: string

  tierText = info.currentTierName

  local currentConfig = UPGRADE_TIERS[info.currentTier]
  descriptionText = currentConfig and currentConfig.description or ""

  statsText = string.format(
    "Lock: %ds | Resistance: %d%%",
    info.lockDurationSeconds,
    math.floor(info.predatorResistance * 100)
  )

  if info.isMaxTier then
    buttonText = "MAX TIER"
    buttonEnabled = false
  elseif info.canAffordNext then
    buttonText =
      string.format("Upgrade to %s ($%s)", info.nextTierName or "?", tostring(info.nextTierPrice))
    buttonEnabled = true
  else
    buttonText =
      string.format("Need $%s for %s", tostring(info.nextTierPrice), info.nextTierName or "?")
    buttonEnabled = false
  end

  return {
    buttonText = buttonText,
    buttonEnabled = buttonEnabled,
    tierText = tierText,
    descriptionText = descriptionText,
    statsText = statsText,
  }
end

-- Get comparison between current tier and next tier for UI
function CageUpgrades.getUpgradeComparison(currentTier: number): {
  currentLockDuration: number,
  nextLockDuration: number?,
  currentResistance: number,
  nextResistance: number?,
  lockDurationIncrease: number?,
  resistanceIncrease: number?,
}
  local currentConfig = UPGRADE_TIERS[currentTier]
  local nextConfig = UPGRADE_TIERS[currentTier + 1]

  local currentLock = CageUpgrades.getLockDuration(currentTier)
  local currentRes = currentConfig and currentConfig.predatorResistance or 0

  if not nextConfig then
    return {
      currentLockDuration = currentLock,
      nextLockDuration = nil,
      currentResistance = currentRes,
      nextResistance = nil,
      lockDurationIncrease = nil,
      resistanceIncrease = nil,
    }
  end

  local nextLock = CageUpgrades.getLockDuration(currentTier + 1)
  local nextRes = nextConfig.predatorResistance

  return {
    currentLockDuration = currentLock,
    nextLockDuration = nextLock,
    currentResistance = currentRes,
    nextResistance = nextRes,
    lockDurationIncrease = nextLock - currentLock,
    resistanceIncrease = nextRes - currentRes,
  }
end

-- Get all affordable upgrades for a given money amount
function CageUpgrades.getAffordableTiers(currentTier: number, money: number): { UpgradeTierConfig }
  local affordable = {}
  local nextTier = currentTier + 1

  -- Can only purchase one tier at a time
  if nextTier <= MAX_TIER then
    local config = UPGRADE_TIERS[nextTier]
    if config and money >= config.price then
      table.insert(affordable, config)
    end
  end

  return affordable
end

-- Calculate total cost to reach a target tier from current tier
function CageUpgrades.getTotalCostToTier(currentTier: number, targetTier: number): number
  if targetTier <= currentTier then
    return 0
  end

  local totalCost = 0
  for tier = currentTier + 1, targetTier do
    local config = UPGRADE_TIERS[tier]
    if config then
      totalCost = totalCost + config.price
    end
  end

  return totalCost
end

-- Validate upgrade configuration
function CageUpgrades.validateConfig(): { valid: boolean, errors: { string } }
  local errors = {}

  for tier = 1, MAX_TIER do
    local config = UPGRADE_TIERS[tier]
    if not config then
      table.insert(errors, string.format("Missing config for tier %d", tier))
    else
      if config.tier ~= tier then
        table.insert(errors, string.format("Tier %d has wrong tier value: %d", tier, config.tier))
      end
      if config.lockDurationMultiplier < 1 then
        table.insert(
          errors,
          string.format(
            "Tier %d has invalid lock multiplier: %f",
            tier,
            config.lockDurationMultiplier
          )
        )
      end
      if config.predatorResistance < 0 or config.predatorResistance > 1 then
        table.insert(
          errors,
          string.format(
            "Tier %d has invalid predator resistance: %f",
            tier,
            config.predatorResistance
          )
        )
      end
      if tier > 1 and config.price <= 0 then
        table.insert(errors, string.format("Tier %d has invalid price: %d", tier, config.price))
      end
    end
  end

  -- Check that values increase with tier
  for tier = 2, MAX_TIER do
    local prevConfig = UPGRADE_TIERS[tier - 1]
    local config = UPGRADE_TIERS[tier]
    if prevConfig and config then
      if config.lockDurationMultiplier <= prevConfig.lockDurationMultiplier then
        table.insert(
          errors,
          string.format("Tier %d lock multiplier should be greater than tier %d", tier, tier - 1)
        )
      end
      if config.predatorResistance < prevConfig.predatorResistance then
        table.insert(
          errors,
          string.format("Tier %d resistance should be >= tier %d", tier, tier - 1)
        )
      end
      if config.price <= prevConfig.price then
        table.insert(
          errors,
          string.format("Tier %d price should be greater than tier %d", tier, tier - 1)
        )
      end
    end
  end

  return {
    valid = #errors == 0,
    errors = errors,
  }
end

-- Get tier by name
function CageUpgrades.getTierByName(name: string): UpgradeTierConfig?
  for _, config in pairs(UPGRADE_TIERS) do
    if config.name == name or config.displayName == name then
      return config
    end
  end
  return nil
end

-- Get tier names as array (for UI dropdowns, etc.)
function CageUpgrades.getTierNames(): { string }
  local names = {}
  for tier = 1, MAX_TIER do
    local config = UPGRADE_TIERS[tier]
    if config then
      table.insert(names, config.displayName)
    end
  end
  return names
end

-- Get config constants
function CageUpgrades.getConfig(): { baseLockDuration: number, maxTier: number }
  return {
    baseLockDuration = BASE_LOCK_DURATION,
    maxTier = MAX_TIER,
  }
end

return CageUpgrades
