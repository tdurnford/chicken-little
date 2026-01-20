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
local Promise = require(Packages:WaitForChild("Promise"))

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
	@return Promise<EquipResult>
]]
function CombatController:EquipWeapon(weaponType: string)
  if not combatService then
    return Promise.resolve({
      success = false,
      message = "Service not available",
    })
  end
  return combatService:EquipWeapon(weaponType)
    :catch(function(err)
      warn("[CombatController] EquipWeapon failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Get the currently equipped weapon.
	
	@return Promise<string?> - The equipped weapon type or nil
]]
function CombatController:GetEquippedWeapon()
  if not combatService then
    return Promise.resolve(equippedWeapon)
  end
  return combatService:GetEquippedWeapon()
    :catch(function(err)
      warn("[CombatController] GetEquippedWeapon failed:", tostring(err))
      return equippedWeapon
    end)
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
	@return Promise<WeaponConfig?>
]]
function CombatController:GetWeaponConfig(weaponType: string)
  if not combatService then
    return Promise.resolve(nil)
  end
  return combatService:GetWeaponConfig(weaponType)
    :catch(function(err)
      warn("[CombatController] GetWeaponConfig failed:", tostring(err))
      return nil
    end)
end

--[[
	Get all weapon configurations.
	
	@return Promise<table> - All weapon configs
]]
function CombatController:GetAllWeaponConfigs()
  if not combatService then
    return Promise.resolve({})
  end
  return combatService:GetAllWeaponConfigs()
    :catch(function(err)
      warn("[CombatController] GetAllWeaponConfigs failed:", tostring(err))
      return {}
    end)
end

--[[
	Get purchasable weapons.
	
	@return Promise<table> - Purchasable weapon configs
]]
function CombatController:GetPurchasableWeapons()
  if not combatService then
    return Promise.resolve({})
  end
  return combatService:GetPurchasableWeapons()
    :catch(function(err)
      warn("[CombatController] GetPurchasableWeapons failed:", tostring(err))
      return {}
    end)
end

--[[
	Get player's owned weapons.
	
	@return Promise<table> - List of owned weapon types
]]
function CombatController:GetOwnedWeapons()
  if not combatService then
    return Promise.resolve({})
  end
  return combatService:GetOwnedWeapons()
    :catch(function(err)
      warn("[CombatController] GetOwnedWeapons failed:", tostring(err))
      return {}
    end)
end

--[[
	Check if player owns a weapon.
	
	@param weaponType string - The weapon type
	@return Promise<boolean>
]]
function CombatController:PlayerOwnsWeapon(weaponType: string)
  if not combatService then
    return Promise.resolve(false)
  end
  return combatService:PlayerOwnsWeapon(weaponType)
    :catch(function(err)
      warn("[CombatController] PlayerOwnsWeapon failed:", tostring(err))
      return false
    end)
end

-- =============================================================================
-- ATTACK METHODS
-- =============================================================================

--[[
	Perform an attack with the equipped weapon.
	
	@param targetType string? - "predator" | "player" | nil
	@param targetId string? - Target identifier
	@return Promise<AttackResult>
]]
function CombatController:Attack(targetType: string?, targetId: string?)
  if not combatService then
    return Promise.resolve({
      success = false,
      message = "Service not available",
    })
  end
  return combatService:Attack(targetType, targetId)
    :catch(function(err)
      warn("[CombatController] Attack failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

-- =============================================================================
-- SHIELD METHODS
-- =============================================================================

--[[
	Activate the area shield.
	
	@return Promise<ShieldResult>
]]
function CombatController:ActivateShield()
  if not combatService then
    return Promise.resolve({
      success = false,
      message = "Service not available",
    })
  end
  return combatService:ActivateShield()
    :catch(function(err)
      warn("[CombatController] ActivateShield failed:", tostring(err))
      return { success = false, message = tostring(err) }
    end)
end

--[[
	Get shield status.
	
	@return Promise<ShieldStatus?>
]]
function CombatController:GetShieldStatus()
  if not combatService then
    return Promise.resolve(nil)
  end
  return combatService:GetShieldStatus()
    :catch(function(err)
      warn("[CombatController] GetShieldStatus failed:", tostring(err))
      return nil
    end)
end

-- =============================================================================
-- COMBAT STATE METHODS
-- =============================================================================

--[[
	Check if the player can move.
	
	@return Promise<boolean>
]]
function CombatController:CanMove()
  if not combatService then
    return Promise.resolve(true)
  end
  return combatService:CanMove()
    :catch(function(err)
      warn("[CombatController] CanMove failed:", tostring(err))
      return true
    end)
end

--[[
	Get combat state.
	
	@return Promise<CombatState?>
]]
function CombatController:GetCombatState()
  if not combatService then
    return Promise.resolve(nil)
  end
  return combatService:GetCombatState()
    :catch(function(err)
      warn("[CombatController] GetCombatState failed:", tostring(err))
      return nil
    end)
end

--[[
	Get health display info for UI.
	
	@return Promise<HealthDisplayInfo?>
]]
function CombatController:GetHealthDisplayInfo()
  if not combatService then
    return Promise.resolve(nil)
  end
  return combatService:GetHealthDisplayInfo()
    :catch(function(err)
      warn("[CombatController] GetHealthDisplayInfo failed:", tostring(err))
      return nil
    end)
end

--[[
	Get combat constants for UI calculations.
	
	@return Promise<table> - Combat constants
]]
function CombatController:GetCombatConstants()
  if not combatService then
    return Promise.resolve({
      health = {},
      shield = {},
      incapacitate = {},
    })
  end
  return combatService:GetCombatConstants()
    :catch(function(err)
      warn("[CombatController] GetCombatConstants failed:", tostring(err))
      return {
        health = {},
        shield = {},
        incapacitate = {},
      }
    end)
end

--[[
	Get locally cached combat state (synchronous).
	
	@return any - Last combat state update or nil
]]
function CombatController:GetCachedCombatState(): any
  return lastCombatState
end

return CombatController
