--[[
	WeaponConfig Module
	Defines all weapon types with their damage, swing speed, knockback force,
	purchase prices, and Robux prices for the weapons store.
]]

local WeaponConfig = {}

-- Weapon tiers ordered from lowest to highest
export type WeaponTier = "Basic" | "Standard" | "Premium"

-- Weapon configuration structure
export type WeaponTypeConfig = {
  name: string,
  displayName: string,
  tier: WeaponTier,
  tierLevel: number, -- 1-3 numeric tier for calculations
  price: number, -- In-game currency price
  robuxPrice: number, -- Robux price
  sellPrice: number, -- Sell value
  damage: number, -- Damage per hit to predators
  swingCooldownSeconds: number, -- Time between swings
  swingRangeStuds: number, -- Range of weapon swing
  knockbackForce: number, -- Force applied to knocked back players
  knockbackDuration: number, -- Duration of knockback effect
  description: string,
  icon: string, -- Emoji icon for UI
}

-- Tier level mapping for calculations
local TIER_LEVELS: { [WeaponTier]: number } = {
  Basic = 1,
  Standard = 2,
  Premium = 3,
}

-- All weapon configurations
local WEAPONS: { [string]: WeaponTypeConfig } = {
  -- Baseball Bat: Starter weapon, low damage, medium speed
  BaseballBat = {
    name = "BaseballBat",
    displayName = "Baseball Bat",
    tier = "Basic",
    tierLevel = 1,
    price = 0, -- Free starter weapon
    robuxPrice = 0,
    sellPrice = 0,
    damage = 1,
    swingCooldownSeconds = 0.5,
    swingRangeStuds = 8,
    knockbackForce = 50,
    knockbackDuration = 0.5,
    description = "Basic bat for warding off predators. Every player starts with one.",
    icon = "🏏",
  },

  -- Sword: Medium damage, faster swing
  Sword = {
    name = "Sword",
    displayName = "Knight's Sword",
    tier = "Standard",
    tierLevel = 2,
    price = 5000,
    robuxPrice = 75,
    sellPrice = 2000,
    damage = 2,
    swingCooldownSeconds = 0.4,
    swingRangeStuds = 10,
    knockbackForce = 60,
    knockbackDuration = 0.6,
    description = "Swift blade that deals more damage with faster swings.",
    icon = "⚔️",
  },

  -- Axe: High damage, slower swing
  Axe = {
    name = "Axe",
    displayName = "Battle Axe",
    tier = "Premium",
    tierLevel = 3,
    price = 25000,
    robuxPrice = 250,
    sellPrice = 10000,
    damage = 4,
    swingCooldownSeconds = 0.8,
    swingRangeStuds = 9,
    knockbackForce = 80,
    knockbackDuration = 0.8,
    description = "Heavy axe that deals massive damage but swings slower.",
    icon = "🪓",
  },
}

-- Tier colors for UI display
local TIER_COLORS: { [WeaponTier]: { r: number, g: number, b: number } } = {
  Basic = { r = 180, g = 180, b = 180 }, -- Gray
  Standard = { r = 50, g = 150, b = 255 }, -- Blue
  Premium = { r = 255, g = 165, b = 0 }, -- Gold
}

-- Get a specific weapon configuration
function WeaponConfig.get(weaponType: string): WeaponTypeConfig?
  return WEAPONS[weaponType]
end

-- Get all weapon configurations
function WeaponConfig.getAll(): { [string]: WeaponTypeConfig }
  return WEAPONS
end

-- Get all purchasable weapons (excludes free starter weapons)
function WeaponConfig.getPurchasable(): { WeaponTypeConfig }
  local purchasable = {}
  for _, config in pairs(WEAPONS) do
    if config.price > 0 or config.robuxPrice > 0 then
      table.insert(purchasable, config)
    end
  end
  -- Sort by tier level then price
  table.sort(purchasable, function(a, b)
    if a.tierLevel ~= b.tierLevel then
      return a.tierLevel < b.tierLevel
    end
    return a.price < b.price
  end)
  return purchasable
end

-- Get all weapons for store display (including starter)
function WeaponConfig.getAllForStore(): { WeaponTypeConfig }
  local weapons = {}
  for _, config in pairs(WEAPONS) do
    table.insert(weapons, config)
  end
  -- Sort by tier level then price
  table.sort(weapons, function(a, b)
    if a.tierLevel ~= b.tierLevel then
      return a.tierLevel < b.tierLevel
    end
    return a.price < b.price
  end)
  return weapons
end

-- Get tier level number from tier name
function WeaponConfig.getTierLevel(tier: WeaponTier): number
  return TIER_LEVELS[tier] or 1
end

-- Get tier color for UI
function WeaponConfig.getTierColor(tier: WeaponTier): { r: number, g: number, b: number }
  return TIER_COLORS[tier] or TIER_COLORS.Basic
end

-- Check if a weapon type is valid
function WeaponConfig.isValid(weaponType: string): boolean
  return WEAPONS[weaponType] ~= nil
end

-- Get the default/starter weapon
function WeaponConfig.getDefaultWeapon(): string
  return "BaseballBat"
end

-- Get weapon damage
function WeaponConfig.getDamage(weaponType: string): number
  local config = WEAPONS[weaponType]
  return config and config.damage or 1
end

-- Get weapon swing cooldown
function WeaponConfig.getSwingCooldown(weaponType: string): number
  local config = WEAPONS[weaponType]
  return config and config.swingCooldownSeconds or 0.5
end

-- Get weapon range
function WeaponConfig.getRange(weaponType: string): number
  local config = WEAPONS[weaponType]
  return config and config.swingRangeStuds or 8
end

-- Get knockback parameters for a weapon
function WeaponConfig.getKnockbackParams(weaponType: string): { force: number, duration: number }
  local config = WEAPONS[weaponType]
  if config then
    return {
      force = config.knockbackForce,
      duration = config.knockbackDuration,
    }
  end
  return { force = 50, duration = 0.5 }
end

-- Compare two weapons (returns positive if first is better overall)
function WeaponConfig.compare(weaponType1: string, weaponType2: string): number
  local config1 = WEAPONS[weaponType1]
  local config2 = WEAPONS[weaponType2]
  if not config1 then
    return -1
  end
  if not config2 then
    return 1
  end
  -- Compare by tier level first
  if config1.tierLevel ~= config2.tierLevel then
    return config1.tierLevel - config2.tierLevel
  end
  -- Then by damage
  return config1.damage - config2.damage
end

return WeaponConfig
