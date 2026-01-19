--[[
	CombatService
	Knit service that handles all combat-related server logic.
	
	Provides:
	- Weapon equipping and management
	- Attack/swing handling against predators and players
	- Damage calculations and knockback mechanics
	- Shield activation and deactivation
	- Combat state management
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatHealth = require(Shared:WaitForChild("CombatHealth"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local WeaponTool = require(Shared:WaitForChild("WeaponTool"))
local AreaShield = require(Shared:WaitForChild("AreaShield"))

-- Services will be retrieved after Knit starts
local PlayerDataService
local PredatorService

-- Player game states (combat states, weapon cooldowns, etc.)
-- Maps userId to their combat game state
local playerGameStates: { [number]: GameState } = {}

-- Type definitions
type GameState = {
  combatState: CombatHealth.CombatState,
  weaponCooldowns: { [string]: number }, -- Maps weaponType to lastSwingTime
  lastSwingTime: number,
}

-- Create the service
local CombatService = Knit.CreateService({
  Name = "CombatService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    WeaponEquipped = Knit.CreateSignal(), -- Fires to owner when weapon equipped
    WeaponUnequipped = Knit.CreateSignal(), -- Fires to owner when weapon unequipped
    WeaponSwung = Knit.CreateSignal(), -- Fires to nearby clients for visual sync
    DamageDealt = Knit.CreateSignal(), -- Fires to owner when damage dealt
    DamageTaken = Knit.CreateSignal(), -- Fires to owner when damage taken
    KnockbackApplied = Knit.CreateSignal(), -- Fires to target when knocked back
    ShieldActivated = Knit.CreateSignal(), -- Fires to owner when shield activated
    ShieldDeactivated = Knit.CreateSignal(), -- Fires to owner when shield deactivated
    ShieldExpired = Knit.CreateSignal(), -- Fires to owner when shield expires
    HealthChanged = Knit.CreateSignal(), -- Fires to owner when health changes
    Incapacitated = Knit.CreateSignal(), -- Fires to target when incapacitated by player
    CombatStateChanged = Knit.CreateSignal(), -- Fires to owner when entering/leaving combat
  },
})

-- Server-side signals (for other services to listen to)
CombatService.WeaponEquippedSignal = GoodSignal.new() -- (userId: number, weaponType: string)
CombatService.AttackPerformedSignal = GoodSignal.new() -- (attackerId: number, targetType: string, targetId: string?, damage: number)
CombatService.DamageDealtSignal = GoodSignal.new() -- (attackerId: number, targetId: string, damage: number, targetType: string)
CombatService.ShieldActivatedSignal = GoodSignal.new() -- (userId: number)
CombatService.ShieldDeactivatedSignal = GoodSignal.new() -- (userId: number)
CombatService.PlayerIncapacitatedSignal = GoodSignal.new() -- (victimId: number, attackerId: number)

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function CombatService:KnitInit()
  print("[CombatService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function CombatService:KnitStart()
  -- Get reference to other services
  PlayerDataService = Knit.GetService("PlayerDataService")

  -- Safely try to get PredatorService if available
  pcall(function()
    PredatorService = Knit.GetService("PredatorService")
  end)

  -- Setup player connections
  Players.PlayerAdded:Connect(function(player)
    self:_initializePlayerState(player.UserId)
  end)

  Players.PlayerRemoving:Connect(function(player)
    self:_cleanupPlayerState(player.UserId)
  end)

  -- Initialize states for existing players
  for _, player in ipairs(Players:GetPlayers()) do
    self:_initializePlayerState(player.UserId)
  end

  print("[CombatService] Started")
end

--[[
	Initialize combat state for a player.
	@param userId number - The user ID
]]
function CombatService:_initializePlayerState(userId: number)
  if playerGameStates[userId] then
    return -- Already initialized
  end

  playerGameStates[userId] = {
    combatState = CombatHealth.createState(),
    weaponCooldowns = {},
    lastSwingTime = 0,
  }
end

--[[
	Cleanup combat state for a player.
	@param userId number - The user ID
]]
function CombatService:_cleanupPlayerState(userId: number)
  playerGameStates[userId] = nil
end

--[[
	Get player game state.
	@param userId number - The user ID
	@return GameState?
]]
function CombatService:_getGameState(userId: number): GameState?
  return playerGameStates[userId]
end

--[[
	Get player data safely.
	@param userId number - The user ID
	@return PlayerDataSchema?
]]
function CombatService:_getPlayerData(userId: number): any
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
function CombatService:_updatePlayerData(userId: number, updateFn: (any) -> any): boolean
  if not PlayerDataService then
    return false
  end
  return PlayerDataService:UpdateData(userId, updateFn) ~= nil
end

--[[
	Find a player by user ID.
	@param userId number - The user ID
	@return Player?
]]
function CombatService:_findPlayer(userId: number): Player?
  for _, player in ipairs(Players:GetPlayers()) do
    if player.UserId == userId then
      return player
    end
  end
  return nil
end

-- =============================================================================
-- WEAPON METHODS
-- =============================================================================

--[[
	Get weapon configuration.
	@param weaponType string - The weapon type
	@return WeaponTypeConfig?
]]
function CombatService:GetWeaponConfig(weaponType: string): WeaponConfig.WeaponTypeConfig?
  return WeaponConfig.get(weaponType)
end

--[[
	Get all weapon configurations.
	@return table - All weapon configs
]]
function CombatService:GetAllWeaponConfigs(): { [string]: WeaponConfig.WeaponTypeConfig }
  return WeaponConfig.getAll()
end

--[[
	Get purchasable weapons.
	@return table - Purchasable weapon configs
]]
function CombatService:GetPurchasableWeapons(): { WeaponConfig.WeaponTypeConfig }
  return WeaponConfig.getPurchasable()
end

--[[
	Check if player owns a weapon.
	@param userId number - The user ID
	@param weaponType string - The weapon type
	@return boolean
]]
function CombatService:PlayerOwnsWeapon(userId: number, weaponType: string): boolean
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return false
  end

  -- Check inventory for weapon
  if playerData.inventory and playerData.inventory.weapons then
    for _, owned in ipairs(playerData.inventory.weapons) do
      if owned == weaponType then
        return true
      end
    end
  end

  -- Check if it's the default free weapon
  if weaponType == WeaponConfig.getDefaultWeapon() then
    return true
  end

  return false
end

--[[
	Get player's owned weapons.
	@param userId number - The user ID
	@return table - List of owned weapon types
]]
function CombatService:GetOwnedWeapons(userId: number): { string }
  local playerData = self:_getPlayerData(userId)
  if not playerData or not playerData.inventory or not playerData.inventory.weapons then
    return { WeaponConfig.getDefaultWeapon() }
  end

  local weapons = { WeaponConfig.getDefaultWeapon() }
  for _, weaponType in ipairs(playerData.inventory.weapons) do
    if not table.find(weapons, weaponType) then
      table.insert(weapons, weaponType)
    end
  end
  return weapons
end

--[[
	Equip a weapon for a player (gives Tool to backpack).
	@param player Player - The player
	@param weaponType string - The weapon type to equip
	@return EquipResult
]]
type EquipResult = {
  success: boolean,
  message: string,
  weaponType: string?,
}

function CombatService:EquipWeapon(player: Player, weaponType: string): EquipResult
  local userId = player.UserId

  -- Validate weapon type
  if not WeaponConfig.isValid(weaponType) then
    return {
      success = false,
      message = "Invalid weapon type: " .. tostring(weaponType),
    }
  end

  -- Check ownership
  if not self:PlayerOwnsWeapon(userId, weaponType) then
    return {
      success = false,
      message = "You don't own this weapon",
    }
  end

  -- Give the weapon Tool to player's backpack
  local tool = WeaponTool.giveToPlayer(player, weaponType)
  if not tool then
    return {
      success = false,
      message = "Failed to create weapon tool",
    }
  end

  -- Fire signals
  self.WeaponEquippedSignal:Fire(userId, weaponType)
  self.Client.WeaponEquipped:Fire(player, weaponType)

  return {
    success = true,
    message = "Weapon equipped: " .. weaponType,
    weaponType = weaponType,
  }
end

-- Client method: Equip weapon
function CombatService.Client:EquipWeapon(player: Player, weaponType: string): EquipResult
  return CombatService:EquipWeapon(player, weaponType)
end

--[[
	Get currently equipped weapon for a player.
	@param player Player - The player
	@return string? - Weapon type or nil
]]
function CombatService:GetEquippedWeapon(player: Player): string?
  local tool = WeaponTool.getEquippedWeapon(player)
  if tool then
    return WeaponTool.getWeaponType(tool)
  end
  return nil
end

-- Client method: Get equipped weapon
function CombatService.Client:GetEquippedWeapon(player: Player): string?
  return CombatService:GetEquippedWeapon(player)
end

--[[
	Restore all owned weapons to a player's backpack.
	@param player Player - The player
	@return number - Count of weapons restored
]]
function CombatService:RestoreOwnedWeapons(player: Player): number
  local ownedWeapons = self:GetOwnedWeapons(player.UserId)
  return WeaponTool.restoreOwnedWeapons(player, ownedWeapons)
end

-- =============================================================================
-- ATTACK METHODS
-- =============================================================================

--[[
	Perform an attack/swing with the equipped weapon.
	@param player Player - The attacking player
	@param targetType string? - "predator" | "player" | nil (miss)
	@param targetId string? - Target identifier
	@return AttackResult
]]
type AttackResult = {
  success: boolean,
  message: string,
  damage: number?,
  defeated: boolean?,
  rewardMoney: number?,
  remainingHealth: number?,
  wasKnockedBack: boolean?,
  incapacitated: boolean?,
}

function CombatService:Attack(player: Player, targetType: string?, targetId: string?): AttackResult
  local userId = player.UserId
  local gameState = self:_getGameState(userId)
  local currentTime = os.clock()

  if not gameState then
    return { success = false, message = "Game state not found" }
  end

  -- Check if player has a weapon Tool equipped
  local equippedTool = WeaponTool.getEquippedWeapon(player)
  if not equippedTool then
    return { success = false, message = "No weapon equipped" }
  end

  -- Get weapon type from the equipped tool
  local weaponType = WeaponTool.getWeaponType(equippedTool)
  if not weaponType then
    return { success = false, message = "Invalid weapon" }
  end

  -- Get weapon config
  local weaponConfig = WeaponConfig.get(weaponType)
  if not weaponConfig then
    return { success = false, message = "Unknown weapon type" }
  end

  -- Check cooldown
  local lastSwing = gameState.weaponCooldowns[weaponType] or 0
  local cooldown = weaponConfig.swingCooldownSeconds
  if currentTime - lastSwing < cooldown then
    local remaining = cooldown - (currentTime - lastSwing)
    return {
      success = false,
      message = string.format("Weapon on cooldown (%.1fs remaining)", remaining),
    }
  end

  -- Update cooldown
  gameState.weaponCooldowns[weaponType] = currentTime
  gameState.lastSwingTime = currentTime

  -- Fire swing visual to nearby clients
  self.Client.WeaponSwung:Fire(player, weaponType)

  -- Handle different target types
  if targetType == "predator" and targetId then
    return self:_attackPredator(player, weaponType, targetId)
  elseif targetType == "player" and targetId then
    return self:_attackPlayer(player, weaponType, targetId)
  else
    -- Miss (swing at nothing)
    self.AttackPerformedSignal:Fire(userId, "miss", nil, 0)
    return {
      success = true,
      message = "Swing missed",
      damage = 0,
    }
  end
end

-- Client method: Attack
function CombatService.Client:Attack(
  player: Player,
  targetType: string?,
  targetId: string?
): AttackResult
  return CombatService:Attack(player, targetType, targetId)
end

--[[
	Attack a predator.
	@param player Player - The attacking player
	@param weaponType string - The weapon type
	@param predatorId string - The predator ID
	@return AttackResult
]]
function CombatService:_attackPredator(
  player: Player,
  weaponType: string,
  predatorId: string
): AttackResult
  local userId = player.UserId
  local weaponConfig = WeaponConfig.get(weaponType)
  if not weaponConfig then
    return { success = false, message = "Invalid weapon" }
  end

  local damage = weaponConfig.damage

  -- Fire signal for other services to handle predator damage
  self.DamageDealtSignal:Fire(userId, predatorId, damage, "predator")
  self.AttackPerformedSignal:Fire(userId, "predator", predatorId, damage)

  -- Fire client signal for UI feedback
  self.Client.DamageDealt:Fire(player, {
    targetType = "predator",
    targetId = predatorId,
    damage = damage,
    weaponType = weaponType,
  })

  return {
    success = true,
    message = string.format("Hit predator for %d damage", damage),
    damage = damage,
  }
end

--[[
	Attack another player (knockback/incapacitate).
	@param player Player - The attacking player
	@param weaponType string - The weapon type
	@param targetUserId string - The target user ID as string
	@return AttackResult
]]
function CombatService:_attackPlayer(
  player: Player,
  weaponType: string,
  targetUserId: string
): AttackResult
  local userId = player.UserId
  local targetId = tonumber(targetUserId)
  if not targetId then
    return { success = false, message = "Invalid target" }
  end

  -- Can't attack yourself
  if targetId == userId then
    return { success = false, message = "Cannot attack yourself" }
  end

  -- Find target player
  local targetPlayer = self:_findPlayer(targetId)
  if not targetPlayer then
    return { success = false, message = "Target player not found" }
  end

  -- Get target's game state
  local targetGameState = self:_getGameState(targetId)
  if not targetGameState then
    return { success = false, message = "Target state not found" }
  end

  local currentTime = os.clock()

  -- Check if target is already incapacitated
  if CombatHealth.isIncapacitated(targetGameState.combatState, currentTime) then
    return { success = false, message = "Target is already incapacitated" }
  end

  -- Incapacitate the target
  local incapResult =
    CombatHealth.incapacitate(targetGameState.combatState, tostring(userId), currentTime)

  if not incapResult.success then
    return {
      success = false,
      message = incapResult.message,
    }
  end

  -- Get knockback parameters from weapon
  local knockbackParams = WeaponConfig.getKnockbackParams(weaponType)

  -- Fire signals
  self.PlayerIncapacitatedSignal:Fire(targetId, userId)
  self.AttackPerformedSignal:Fire(userId, "player", targetUserId, 0)

  -- Notify target player
  self.Client.Incapacitated:Fire(targetPlayer, {
    duration = incapResult.duration,
    attackerId = userId,
    attackerName = player.Name,
    knockbackForce = knockbackParams.force,
    knockbackDuration = knockbackParams.duration,
  })

  -- Notify attacker
  self.Client.DamageDealt:Fire(player, {
    targetType = "player",
    targetId = targetUserId,
    damage = 0,
    incapacitated = true,
    weaponType = weaponType,
  })

  return {
    success = true,
    message = "Player incapacitated!",
    incapacitated = true,
  }
end

-- =============================================================================
-- SHIELD METHODS
-- =============================================================================

--[[
	Activate the area shield for a player.
	@param player Player - The player
	@return ShieldResult
]]
function CombatService:ActivateShield(player: Player): AreaShield.ShieldResult
  local userId = player.UserId
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return {
      success = false,
      message = "Player data not found",
    }
  end

  -- Initialize shield state if not present
  if not playerData.shieldState then
    playerData.shieldState = AreaShield.createDefaultState()
  end

  local currentTime = os.time()
  local result = AreaShield.activate(playerData.shieldState, currentTime)

  if result.success then
    -- Save the updated shield state
    self:_updatePlayerData(userId, function(data)
      data.shieldState = playerData.shieldState
      return data
    end)

    -- Fire signals
    self.ShieldActivatedSignal:Fire(userId)
    self.Client.ShieldActivated:Fire(player, {
      duration = AreaShield.getConstants().shieldDuration,
      expiresAt = playerData.shieldState.expiresAt,
    })
  end

  return result
end

-- Client method: Activate shield
function CombatService.Client:ActivateShield(player: Player): AreaShield.ShieldResult
  return CombatService:ActivateShield(player)
end

--[[
	Get shield status for a player.
	@param userId number - The user ID
	@return ShieldStatus?
]]
type ShieldStatus = {
  isActive: boolean,
  isOnCooldown: boolean,
  canActivate: boolean,
  remainingDuration: number,
  remainingCooldown: number,
  durationTotal: number,
  cooldownTotal: number,
}

function CombatService:GetShieldStatus(userId: number): ShieldStatus?
  local playerData = self:_getPlayerData(userId)
  if not playerData then
    return nil
  end

  if not playerData.shieldState then
    -- Return default state
    return {
      isActive = false,
      isOnCooldown = false,
      canActivate = true,
      remainingDuration = 0,
      remainingCooldown = 0,
      durationTotal = AreaShield.getConstants().shieldDuration,
      cooldownTotal = AreaShield.getConstants().shieldCooldown,
    }
  end

  return AreaShield.getStatus(playerData.shieldState, os.time())
end

-- Client method: Get shield status
function CombatService.Client:GetShieldStatus(player: Player): ShieldStatus?
  return CombatService:GetShieldStatus(player.UserId)
end

--[[
	Check if player's shield is active.
	@param userId number - The user ID
	@return boolean
]]
function CombatService:IsShieldActive(userId: number): boolean
  local playerData = self:_getPlayerData(userId)
  if not playerData or not playerData.shieldState then
    return false
  end
  return AreaShield.isActive(playerData.shieldState, os.time())
end

-- =============================================================================
-- HEALTH/COMBAT STATE METHODS
-- =============================================================================

--[[
	Get combat state for a player.
	@param userId number - The user ID
	@return CombatState?
]]
function CombatService:GetCombatState(userId: number): CombatHealth.CombatState?
  local gameState = self:_getGameState(userId)
  if not gameState then
    return nil
  end
  return gameState.combatState
end

-- Client method: Get combat state
function CombatService.Client:GetCombatState(player: Player): CombatHealth.CombatState?
  return CombatService:GetCombatState(player.UserId)
end

--[[
	Get combat health display info for UI.
	@param userId number - The user ID
	@return HealthDisplayInfo?
]]
function CombatService:GetHealthDisplayInfo(userId: number): any
  local gameState = self:_getGameState(userId)
  if not gameState then
    return nil
  end
  return CombatHealth.getDisplayInfo(gameState.combatState, os.clock())
end

-- Client method: Get health display info
function CombatService.Client:GetHealthDisplayInfo(player: Player): any
  return CombatService:GetHealthDisplayInfo(player.UserId)
end

--[[
	Apply damage to a player from a predator.
	@param userId number - The user ID
	@param predatorType string - The predator type
	@param deltaTime number - Time since last damage tick
	@return DamageResult
]]
function CombatService:ApplyPredatorDamage(
  userId: number,
  predatorType: string,
  deltaTime: number
): CombatHealth.DamageResult
  local gameState = self:_getGameState(userId)
  if not gameState then
    return {
      success = false,
      damageDealt = 0,
      newHealth = 0,
      wasKnockedBack = false,
      message = "Game state not found",
    }
  end

  local currentTime = os.clock()
  local result =
    CombatHealth.applyDamage(gameState.combatState, predatorType, deltaTime, currentTime)

  if result.success then
    local player = self:_findPlayer(userId)
    if player then
      -- Fire health changed signal
      self.Client.HealthChanged:Fire(player, {
        health = result.newHealth,
        maxHealth = gameState.combatState.maxHealth,
        damageDealt = result.damageDealt,
        source = predatorType,
      })

      -- Fire damage taken signal
      self.Client.DamageTaken:Fire(player, {
        damage = result.damageDealt,
        source = predatorType,
        sourceType = "predator",
      })

      if result.wasKnockedBack then
        self.Client.KnockbackApplied:Fire(player, {
          source = predatorType,
          duration = CombatHealth.getConstants().knockbackDuration,
        })
      end
    end
  end

  return result
end

--[[
	Apply fixed damage to a player.
	@param userId number - The user ID
	@param damage number - Damage amount
	@param source string? - Damage source
	@return DamageResult
]]
function CombatService:ApplyFixedDamage(
  userId: number,
  damage: number,
  source: string?
): CombatHealth.DamageResult
  local gameState = self:_getGameState(userId)
  if not gameState then
    return {
      success = false,
      damageDealt = 0,
      newHealth = 0,
      wasKnockedBack = false,
      message = "Game state not found",
    }
  end

  local currentTime = os.clock()
  local result = CombatHealth.applyFixedDamage(gameState.combatState, damage, currentTime, source)

  if result.success then
    local player = self:_findPlayer(userId)
    if player then
      self.Client.HealthChanged:Fire(player, {
        health = result.newHealth,
        maxHealth = gameState.combatState.maxHealth,
        damageDealt = result.damageDealt,
        source = source or "Unknown",
      })

      self.Client.DamageTaken:Fire(player, {
        damage = result.damageDealt,
        source = source or "Unknown",
        sourceType = "fixed",
      })
    end
  end

  return result
end

--[[
	Update combat state (handles regeneration and knockback expiry).
	Should be called periodically by game loop.
	@param userId number - The user ID
	@param deltaTime number - Time since last update
]]
function CombatService:UpdateCombatState(userId: number, deltaTime: number)
  local gameState = self:_getGameState(userId)
  if not gameState then
    return
  end

  local currentTime = os.clock()
  local updateResult = CombatHealth.update(gameState.combatState, deltaTime, currentTime)

  if updateResult.healthChanged then
    local player = self:_findPlayer(userId)
    if player then
      self.Client.HealthChanged:Fire(player, {
        health = gameState.combatState.health,
        maxHealth = gameState.combatState.maxHealth,
        regenerated = updateResult.regenResult ~= nil,
      })
    end
  end

  if updateResult.knockbackEnded then
    local player = self:_findPlayer(userId)
    if player then
      self.Client.CombatStateChanged:Fire(player, {
        knockbackEnded = true,
        health = gameState.combatState.health,
      })
    end
  end
end

--[[
	Reset combat state (for respawn).
	@param userId number - The user ID
]]
function CombatService:ResetCombatState(userId: number)
  local gameState = self:_getGameState(userId)
  if not gameState then
    return
  end

  CombatHealth.reset(gameState.combatState)

  local player = self:_findPlayer(userId)
  if player then
    self.Client.HealthChanged:Fire(player, {
      health = gameState.combatState.health,
      maxHealth = gameState.combatState.maxHealth,
      reset = true,
    })
  end
end

--[[
	Check if player can move (not incapacitated or knocked back).
	@param userId number - The user ID
	@return boolean
]]
function CombatService:CanPlayerMove(userId: number): boolean
  local gameState = self:_getGameState(userId)
  if not gameState then
    return true
  end
  return CombatHealth.canMove(gameState.combatState, os.clock())
end

-- Client method: Check if can move
function CombatService.Client:CanMove(player: Player): boolean
  return CombatService:CanPlayerMove(player.UserId)
end

-- =============================================================================
-- CONFIG GETTERS (Client-exposed)
-- =============================================================================

-- Client method: Get weapon config
function CombatService.Client:GetWeaponConfig(
  player: Player,
  weaponType: string
): WeaponConfig.WeaponTypeConfig?
  return CombatService:GetWeaponConfig(weaponType)
end

-- Client method: Get all weapon configs
function CombatService.Client:GetAllWeaponConfigs(
  player: Player
): { [string]: WeaponConfig.WeaponTypeConfig }
  return CombatService:GetAllWeaponConfigs()
end

-- Client method: Get purchasable weapons
function CombatService.Client:GetPurchasableWeapons(
  player: Player
): { WeaponConfig.WeaponTypeConfig }
  return CombatService:GetPurchasableWeapons()
end

-- Client method: Get owned weapons
function CombatService.Client:GetOwnedWeapons(player: Player): { string }
  return CombatService:GetOwnedWeapons(player.UserId)
end

-- Client method: Check weapon ownership
function CombatService.Client:PlayerOwnsWeapon(player: Player, weaponType: string): boolean
  return CombatService:PlayerOwnsWeapon(player.UserId, weaponType)
end

-- Client method: Get combat constants
function CombatService.Client:GetCombatConstants(player: Player): any
  return {
    health = CombatHealth.getConstants(),
    shield = AreaShield.getConstants(),
    incapacitate = CombatHealth.getIncapacitateConstants(),
  }
end

return CombatService
