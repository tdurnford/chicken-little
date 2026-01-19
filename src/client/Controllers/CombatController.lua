--[[
	CombatController
	Client-side Knit controller for managing combat interactions.
	
	Provides:
	- Weapon equipping and management
	- Attack handling
	- Shield activation and status
	- Combat state tracking
	- GoodSignal events for reactive UI updates
	- Connection to CombatService via Knit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Create the controller
local CombatController = Knit.CreateController({
  Name = "CombatController",
})

-- Local state
local equippedWeapon: string? = nil
local lastCombatState: any = nil

-- GoodSignal events for reactive UI
CombatController.WeaponEquipped = GoodSignal.new() -- Fires (weaponType: string)
CombatController.WeaponUnequipped = GoodSignal.new() -- Fires ()
CombatController.WeaponSwung = GoodSignal.new() -- Fires (weaponType: string)
CombatController.DamageDealt = GoodSignal.new() -- Fires (data: {targetType, targetId, damage, weaponType, incapacitated?})
CombatController.DamageTaken = GoodSignal.new() -- Fires (data: {damage, source, sourceType})
CombatController.KnockbackApplied = GoodSignal.new() -- Fires (data: {source, duration})
CombatController.ShieldActivated = GoodSignal.new() -- Fires (data: {duration, expiresAt})
CombatController.ShieldDeactivated = GoodSignal.new() -- Fires ()
CombatController.ShieldExpired = GoodSignal.new() -- Fires ()
CombatController.HealthChanged = GoodSignal.new() -- Fires (data: {health, maxHealth, damageDealt?, regenerated?, reset?})
CombatController.Incapacitated = GoodSignal.new() -- Fires (data: {duration, attackerId, attackerName, knockbackForce, knockbackDuration})
CombatController.CombatStateChanged = GoodSignal.new() -- Fires (data: {knockbackEnded?, health?})

-- Reference to the server service
local combatService = nil

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function CombatController:KnitInit()
  print("[CombatController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function CombatController:KnitStart()
  -- Get reference to server service
  combatService = Knit.GetService("CombatService")

  -- Connect to server signals
  combatService.WeaponEquipped:Connect(function(weaponType)
    equippedWeapon = weaponType
    self.WeaponEquipped:Fire(weaponType)
  end)

  combatService.WeaponUnequipped:Connect(function()
    equippedWeapon = nil
    self.WeaponUnequipped:Fire()
  end)

  combatService.WeaponSwung:Connect(function(weaponType)
    self.WeaponSwung:Fire(weaponType)
  end)

  combatService.DamageDealt:Connect(function(data)
    self.DamageDealt:Fire(data)
  end)

  combatService.DamageTaken:Connect(function(data)
    self.DamageTaken:Fire(data)
  end)

  combatService.KnockbackApplied:Connect(function(data)
    self.KnockbackApplied:Fire(data)
  end)

  combatService.ShieldActivated:Connect(function(data)
    self.ShieldActivated:Fire(data)
  end)

  combatService.ShieldDeactivated:Connect(function()
    self.ShieldDeactivated:Fire()
  end)

  combatService.ShieldExpired:Connect(function()
    self.ShieldExpired:Fire()
  end)

  combatService.HealthChanged:Connect(function(data)
    self.HealthChanged:Fire(data)
  end)

  combatService.Incapacitated:Connect(function(data)
    self.Incapacitated:Fire(data)
  end)

  combatService.CombatStateChanged:Connect(function(data)
    lastCombatState = data
    self.CombatStateChanged:Fire(data)
  end)

  print("[CombatController] Started")
end

-- =============================================================================
-- WEAPON METHODS
-- =============================================================================

--[[
	Equip a weapon.
	
	@param weaponType string - The weapon type to equip
	@return EquipResult
]]
function CombatController:EquipWeapon(weaponType: string)
  if not combatService then
    return {
      success = false,
      message = "Service not available",
    }
  end
  return combatService:EquipWeapon(weaponType)
end

--[[
	Get the currently equipped weapon.
	
	@return string? - The equipped weapon type or nil
]]
function CombatController:GetEquippedWeapon(): string?
  if not combatService then
    return equippedWeapon
  end
  return combatService:GetEquippedWeapon()
end

--[[
	Get locally cached equipped weapon (synchronous).
	
	@return string? - The equipped weapon type or nil
]]
function CombatController:GetCachedEquippedWeapon(): string?
  return equippedWeapon
end

--[[
	Get weapon configuration.
	
	@param weaponType string - The weapon type
	@return WeaponConfig?
]]
function CombatController:GetWeaponConfig(weaponType: string): any
  if not combatService then
    return nil
  end
  return combatService:GetWeaponConfig(weaponType)
end

--[[
	Get all weapon configurations.
	
	@return table - All weapon configs
]]
function CombatController:GetAllWeaponConfigs(): any
  if not combatService then
    return {}
  end
  return combatService:GetAllWeaponConfigs()
end

--[[
	Get purchasable weapons.
	
	@return table - Purchasable weapon configs
]]
function CombatController:GetPurchasableWeapons(): any
  if not combatService then
    return {}
  end
  return combatService:GetPurchasableWeapons()
end

--[[
	Get player's owned weapons.
	
	@return table - List of owned weapon types
]]
function CombatController:GetOwnedWeapons(): { string }
  if not combatService then
    return {}
  end
  return combatService:GetOwnedWeapons()
end

--[[
	Check if player owns a weapon.
	
	@param weaponType string - The weapon type
	@return boolean
]]
function CombatController:PlayerOwnsWeapon(weaponType: string): boolean
  if not combatService then
    return false
  end
  return combatService:PlayerOwnsWeapon(weaponType)
end

-- =============================================================================
-- ATTACK METHODS
-- =============================================================================

--[[
	Perform an attack with the equipped weapon.
	
	@param targetType string? - "predator" | "player" | nil
	@param targetId string? - Target identifier
	@return AttackResult
]]
function CombatController:Attack(targetType: string?, targetId: string?)
  if not combatService then
    return {
      success = false,
      message = "Service not available",
    }
  end
  return combatService:Attack(targetType, targetId)
end

-- =============================================================================
-- SHIELD METHODS
-- =============================================================================

--[[
	Activate the area shield.
	
	@return ShieldResult
]]
function CombatController:ActivateShield()
  if not combatService then
    return {
      success = false,
      message = "Service not available",
    }
  end
  return combatService:ActivateShield()
end

--[[
	Get shield status.
	
	@return ShieldStatus?
]]
function CombatController:GetShieldStatus(): any
  if not combatService then
    return nil
  end
  return combatService:GetShieldStatus()
end

-- =============================================================================
-- COMBAT STATE METHODS
-- =============================================================================

--[[
	Check if the player can move.
	
	@return boolean
]]
function CombatController:CanMove(): boolean
  if not combatService then
    return true
  end
  return combatService:CanMove()
end

--[[
	Get combat state.
	
	@return CombatState?
]]
function CombatController:GetCombatState(): any
  if not combatService then
    return nil
  end
  return combatService:GetCombatState()
end

--[[
	Get health display info for UI.
	
	@return HealthDisplayInfo?
]]
function CombatController:GetHealthDisplayInfo(): any
  if not combatService then
    return nil
  end
  return combatService:GetHealthDisplayInfo()
end

--[[
	Get combat constants for UI calculations.
	
	@return table - Combat constants
]]
function CombatController:GetCombatConstants(): any
  if not combatService then
    return {
      health = {},
      shield = {},
      incapacitate = {},
    }
  end
  return combatService:GetCombatConstants()
end

--[[
	Get locally cached combat state (synchronous).
	
	@return any - Last combat state update or nil
]]
function CombatController:GetCachedCombatState(): any
  return lastCombatState
end

return CombatController
