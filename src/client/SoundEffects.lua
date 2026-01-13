--[[
	SoundEffects Module
	Manages all game sound effects including money collection, egg hatching,
	chicken placement, combat, and predator alerts.
	Supports muting and volume control.
]]

local SoundEffects = {}

-- Services
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Type definitions
export type SoundId = string

export type SoundCategory = "money" | "eggs" | "chickens" | "combat" | "predators" | "ui" | "ambient"

export type SoundConfig = {
  id: SoundId,
  name: string,
  category: SoundCategory,
  volume: number,
  pitch: number?,
  pitchVariance: number?,
  looped: boolean?,
}

export type SoundState = {
  isMuted: boolean,
  masterVolume: number,
  categoryVolumes: { [SoundCategory]: number },
  soundGroup: SoundGroup?,
  loadedSounds: { [string]: Sound },
  activeSounds: { [string]: Sound },
}

-- Sound asset IDs (placeholder IDs - replace with actual asset IDs)
local SOUND_IDS = {
  -- Money collection sounds
  moneyCollect = "rbxassetid://6895079853", -- Coin collect
  moneyCollectLarge = "rbxassetid://5628226610", -- Large money collect
  moneyCollectJackpot = "rbxassetid://4612373808", -- Jackpot/big win

  -- Egg sounds
  eggPlace = "rbxassetid://5853855836", -- Egg placed down
  eggShake = "rbxassetid://4590657391", -- Egg shaking/anticipation
  eggHatchCommon = "rbxassetid://4590628823", -- Common hatch crack
  eggHatchRare = "rbxassetid://6042053626", -- Rare hatch with sparkle
  eggHatchEpic = "rbxassetid://4612373808", -- Epic hatch fanfare
  eggHatchLegendary = "rbxassetid://5628226610", -- Legendary hatch fanfare
  eggHatchMythic = "rbxassetid://9063066381", -- Mythic hatch big fanfare

  -- Chicken sounds
  chickenPlace = "rbxassetid://5853855836", -- Chicken placed
  chickenPickup = "rbxassetid://5853855836", -- Chicken picked up
  chickenCluck = "rbxassetid://4590628823", -- Chicken cluck
  chickenSell = "rbxassetid://6895079853", -- Chicken sold (cash register)

  -- Combat sounds
  batSwing = "rbxassetid://4590657391", -- Bat swing whoosh
  batHit = "rbxassetid://5853855836", -- Bat hit impact
  batMiss = "rbxassetid://4590657391", -- Bat miss whoosh
  playerKnockback = "rbxassetid://5853855836", -- Player knocked back

  -- Predator sounds
  predatorSpawn = "rbxassetid://4590657391", -- Predator appears
  predatorAlert = "rbxassetid://9063066381", -- Alert/warning
  predatorApproaching = "rbxassetid://4590657391", -- Footsteps/approaching
  predatorAttack = "rbxassetid://5853855836", -- Predator attacks
  predatorDefeated = "rbxassetid://4612373808", -- Predator defeated fanfare
  predatorTrapped = "rbxassetid://5628226610", -- Predator caught in trap

  -- UI sounds
  buttonClick = "rbxassetid://6895079853", -- Button click
  menuOpen = "rbxassetid://5853855836", -- Menu open
  menuClose = "rbxassetid://5853855836", -- Menu close
  tradeRequest = "rbxassetid://4590657391", -- Trade notification
  tradeComplete = "rbxassetid://4612373808", -- Trade successful
  error = "rbxassetid://4590628823", -- Error beep
}

-- Default category volumes
local DEFAULT_CATEGORY_VOLUMES: { [SoundCategory]: number } = {
  money = 0.8,
  eggs = 1.0,
  chickens = 0.6,
  combat = 0.9,
  predators = 1.0,
  ui = 0.7,
  ambient = 0.5,
}

-- Sound configurations
local SOUND_CONFIGS: { [string]: SoundConfig } = {
  -- Money sounds
  moneyCollect = {
    id = SOUND_IDS.moneyCollect,
    name = "Money Collect",
    category = "money",
    volume = 0.5,
    pitchVariance = 0.1,
  },
  moneyCollectLarge = {
    id = SOUND_IDS.moneyCollectLarge,
    name = "Money Collect Large",
    category = "money",
    volume = 0.7,
  },
  moneyCollectJackpot = {
    id = SOUND_IDS.moneyCollectJackpot,
    name = "Money Jackpot",
    category = "money",
    volume = 0.9,
  },

  -- Egg sounds
  eggPlace = {
    id = SOUND_IDS.eggPlace,
    name = "Egg Place",
    category = "eggs",
    volume = 0.6,
  },
  eggShake = {
    id = SOUND_IDS.eggShake,
    name = "Egg Shake",
    category = "eggs",
    volume = 0.7,
    looped = true,
  },
  eggHatchCommon = {
    id = SOUND_IDS.eggHatchCommon,
    name = "Hatch Common",
    category = "eggs",
    volume = 0.7,
  },
  eggHatchRare = {
    id = SOUND_IDS.eggHatchRare,
    name = "Hatch Rare",
    category = "eggs",
    volume = 0.8,
  },
  eggHatchEpic = {
    id = SOUND_IDS.eggHatchEpic,
    name = "Hatch Epic",
    category = "eggs",
    volume = 0.9,
  },
  eggHatchLegendary = {
    id = SOUND_IDS.eggHatchLegendary,
    name = "Hatch Legendary",
    category = "eggs",
    volume = 1.0,
  },
  eggHatchMythic = {
    id = SOUND_IDS.eggHatchMythic,
    name = "Hatch Mythic",
    category = "eggs",
    volume = 1.0,
  },

  -- Chicken sounds
  chickenPlace = {
    id = SOUND_IDS.chickenPlace,
    name = "Chicken Place",
    category = "chickens",
    volume = 0.6,
  },
  chickenPickup = {
    id = SOUND_IDS.chickenPickup,
    name = "Chicken Pickup",
    category = "chickens",
    volume = 0.5,
  },
  chickenCluck = {
    id = SOUND_IDS.chickenCluck,
    name = "Chicken Cluck",
    category = "chickens",
    volume = 0.4,
    pitchVariance = 0.2,
  },
  chickenSell = {
    id = SOUND_IDS.chickenSell,
    name = "Chicken Sell",
    category = "chickens",
    volume = 0.7,
  },

  -- Combat sounds
  batSwing = {
    id = SOUND_IDS.batSwing,
    name = "Bat Swing",
    category = "combat",
    volume = 0.6,
    pitchVariance = 0.1,
  },
  batHit = {
    id = SOUND_IDS.batHit,
    name = "Bat Hit",
    category = "combat",
    volume = 0.8,
  },
  batMiss = {
    id = SOUND_IDS.batMiss,
    name = "Bat Miss",
    category = "combat",
    volume = 0.4,
    pitch = 1.2,
  },
  playerKnockback = {
    id = SOUND_IDS.playerKnockback,
    name = "Player Knockback",
    category = "combat",
    volume = 0.7,
  },

  -- Predator sounds
  predatorSpawn = {
    id = SOUND_IDS.predatorSpawn,
    name = "Predator Spawn",
    category = "predators",
    volume = 0.7,
  },
  predatorAlert = {
    id = SOUND_IDS.predatorAlert,
    name = "Predator Alert",
    category = "predators",
    volume = 1.0,
  },
  predatorApproaching = {
    id = SOUND_IDS.predatorApproaching,
    name = "Predator Approaching",
    category = "predators",
    volume = 0.5,
    looped = true,
  },
  predatorAttack = {
    id = SOUND_IDS.predatorAttack,
    name = "Predator Attack",
    category = "predators",
    volume = 0.9,
  },
  predatorDefeated = {
    id = SOUND_IDS.predatorDefeated,
    name = "Predator Defeated",
    category = "predators",
    volume = 0.9,
  },
  predatorTrapped = {
    id = SOUND_IDS.predatorTrapped,
    name = "Predator Trapped",
    category = "predators",
    volume = 0.8,
  },

  -- UI sounds
  buttonClick = {
    id = SOUND_IDS.buttonClick,
    name = "Button Click",
    category = "ui",
    volume = 0.4,
  },
  menuOpen = {
    id = SOUND_IDS.menuOpen,
    name = "Menu Open",
    category = "ui",
    volume = 0.5,
  },
  menuClose = {
    id = SOUND_IDS.menuClose,
    name = "Menu Close",
    category = "ui",
    volume = 0.4,
    pitch = 0.9,
  },
  tradeRequest = {
    id = SOUND_IDS.tradeRequest,
    name = "Trade Request",
    category = "ui",
    volume = 0.8,
  },
  tradeComplete = {
    id = SOUND_IDS.tradeComplete,
    name = "Trade Complete",
    category = "ui",
    volume = 0.9,
  },
  error = {
    id = SOUND_IDS.error,
    name = "Error",
    category = "ui",
    volume = 0.5,
  },
}

-- Module state
local state: SoundState = {
  isMuted = false,
  masterVolume = 1.0,
  categoryVolumes = table.clone(DEFAULT_CATEGORY_VOLUMES),
  soundGroup = nil,
  loadedSounds = {},
  activeSounds = {},
}

-- Create a SoundGroup for volume control
local function createSoundGroup(): SoundGroup
  local soundGroup = Instance.new("SoundGroup")
  soundGroup.Name = "GameSounds"
  soundGroup.Volume = 1.0
  soundGroup.Parent = SoundService
  return soundGroup
end

-- Get or create the sound group
local function getSoundGroup(): SoundGroup
  if not state.soundGroup then
    state.soundGroup = createSoundGroup()
  end
  return state.soundGroup
end

-- Calculate final volume for a sound
local function calculateVolume(config: SoundConfig): number
  if state.isMuted then
    return 0
  end
  local categoryVolume = state.categoryVolumes[config.category] or 1.0
  return config.volume * categoryVolume * state.masterVolume
end

-- Create or get a cached sound instance
local function getSound(soundName: string): Sound?
  local config = SOUND_CONFIGS[soundName]
  if not config then
    warn("SoundEffects: Unknown sound:", soundName)
    return nil
  end

  -- Check cache first
  if state.loadedSounds[soundName] then
    return state.loadedSounds[soundName]
  end

  -- Create new sound
  local sound = Instance.new("Sound")
  sound.Name = soundName
  sound.SoundId = config.id
  sound.Volume = calculateVolume(config)
  sound.Looped = config.looped or false
  sound.SoundGroup = getSoundGroup()

  if config.pitch then
    sound.PlaybackSpeed = config.pitch
  end

  -- Parent to PlayerGui for client-side playback
  local player = Players.LocalPlayer
  if player then
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
      sound.Parent = playerGui
    end
  end

  state.loadedSounds[soundName] = sound
  return sound
end

-- Apply pitch variance to a sound
local function applyPitchVariance(sound: Sound, config: SoundConfig): ()
  local basePitch = config.pitch or 1.0
  local variance = config.pitchVariance or 0
  if variance > 0 then
    local randomVariance = (math.random() - 0.5) * 2 * variance
    sound.PlaybackSpeed = basePitch + randomVariance
  else
    sound.PlaybackSpeed = basePitch
  end
end

-- Initialize the sound effects system
function SoundEffects.initialize(): ()
  getSoundGroup()
end

-- Play a sound effect
function SoundEffects.play(soundName: string): Sound?
  local config = SOUND_CONFIGS[soundName]
  if not config then
    warn("SoundEffects: Unknown sound:", soundName)
    return nil
  end

  local sound = getSound(soundName)
  if not sound then
    return nil
  end

  -- Update volume in case settings changed
  sound.Volume = calculateVolume(config)

  -- Apply pitch variance
  applyPitchVariance(sound, config)

  -- Stop if already playing (for non-looped sounds)
  if not config.looped and sound.IsPlaying then
    sound:Stop()
  end

  sound:Play()
  return sound
end

-- Play a sound with a specific volume multiplier
function SoundEffects.playWithVolume(soundName: string, volumeMultiplier: number): Sound?
  local config = SOUND_CONFIGS[soundName]
  if not config then
    return nil
  end

  local sound = getSound(soundName)
  if not sound then
    return nil
  end

  sound.Volume = calculateVolume(config) * math.clamp(volumeMultiplier, 0, 2)
  applyPitchVariance(sound, config)

  if not config.looped and sound.IsPlaying then
    sound:Stop()
  end

  sound:Play()
  return sound
end

-- Stop a looped sound
function SoundEffects.stop(soundName: string): ()
  local sound = state.loadedSounds[soundName]
  if sound and sound.IsPlaying then
    sound:Stop()
  end
end

-- Stop all sounds
function SoundEffects.stopAll(): ()
  for _, sound in pairs(state.loadedSounds) do
    if sound.IsPlaying then
      sound:Stop()
    end
  end
end

-- Play money collection sound based on amount
function SoundEffects.playMoneyCollect(amount: number): ()
  if amount >= 1000000000 then -- 1 billion+
    SoundEffects.play("moneyCollectJackpot")
  elseif amount >= 1000000 then -- 1 million+
    SoundEffects.play("moneyCollectLarge")
  else
    SoundEffects.play("moneyCollect")
  end
end

-- Play egg hatch sound based on rarity
function SoundEffects.playEggHatch(rarity: string): ()
  local soundMap = {
    Common = "eggHatchCommon",
    Uncommon = "eggHatchCommon",
    Rare = "eggHatchRare",
    Epic = "eggHatchEpic",
    Legendary = "eggHatchLegendary",
    Mythic = "eggHatchMythic",
  }
  local soundName = soundMap[rarity] or "eggHatchCommon"
  SoundEffects.play(soundName)
end

-- Start egg shake anticipation sound
function SoundEffects.startEggShake(): ()
  SoundEffects.play("eggShake")
end

-- Stop egg shake sound
function SoundEffects.stopEggShake(): ()
  SoundEffects.stop("eggShake")
end

-- Play bat swing sound
function SoundEffects.playBatSwing(hitType: "predator" | "player" | "miss"): ()
  SoundEffects.play("batSwing")
  task.delay(0.15, function()
    if hitType == "miss" then
      SoundEffects.play("batMiss")
    else
      SoundEffects.play("batHit")
    end
  end)
end

-- Play predator alert based on urgency
function SoundEffects.playPredatorAlert(urgent: boolean): ()
  if urgent then
    SoundEffects.play("predatorAlert")
  else
    SoundEffects.play("predatorSpawn")
  end
end

-- Set mute state
function SoundEffects.setMuted(muted: boolean): ()
  state.isMuted = muted
  getSoundGroup().Volume = muted and 0 or state.masterVolume
end

-- Toggle mute state
function SoundEffects.toggleMute(): boolean
  SoundEffects.setMuted(not state.isMuted)
  return state.isMuted
end

-- Check if muted
function SoundEffects.isMuted(): boolean
  return state.isMuted
end

-- Set master volume (0.0 to 1.0)
function SoundEffects.setMasterVolume(volume: number): ()
  state.masterVolume = math.clamp(volume, 0, 1)
  if not state.isMuted then
    getSoundGroup().Volume = state.masterVolume
  end
end

-- Get master volume
function SoundEffects.getMasterVolume(): number
  return state.masterVolume
end

-- Set category volume (0.0 to 1.0)
function SoundEffects.setCategoryVolume(category: SoundCategory, volume: number): ()
  state.categoryVolumes[category] = math.clamp(volume, 0, 1)
end

-- Get category volume
function SoundEffects.getCategoryVolume(category: SoundCategory): number
  return state.categoryVolumes[category] or 1.0
end

-- Reset all volumes to default
function SoundEffects.resetVolumes(): ()
  state.masterVolume = 1.0
  state.isMuted = false
  state.categoryVolumes = table.clone(DEFAULT_CATEGORY_VOLUMES)
  getSoundGroup().Volume = 1.0
end

-- Get all available sound names
function SoundEffects.getSoundNames(): { string }
  local names = {}
  for name, _ in pairs(SOUND_CONFIGS) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- Get sounds by category
function SoundEffects.getSoundsByCategory(category: SoundCategory): { string }
  local sounds = {}
  for name, config in pairs(SOUND_CONFIGS) do
    if config.category == category then
      table.insert(sounds, name)
    end
  end
  table.sort(sounds)
  return sounds
end

-- Get all categories
function SoundEffects.getCategories(): { SoundCategory }
  return { "money", "eggs", "chickens", "combat", "predators", "ui", "ambient" }
end

-- Preload sounds for smoother playback
function SoundEffects.preload(): ()
  for soundName, _ in pairs(SOUND_CONFIGS) do
    getSound(soundName)
  end
end

-- Cleanup resources
function SoundEffects.cleanup(): ()
  SoundEffects.stopAll()
  for _, sound in pairs(state.loadedSounds) do
    sound:Destroy()
  end
  state.loadedSounds = {}

  if state.soundGroup then
    state.soundGroup:Destroy()
    state.soundGroup = nil
  end
end

-- Get state summary for debugging
function SoundEffects.getSummary(): string
  local loadedCount = 0
  for _ in pairs(state.loadedSounds) do
    loadedCount = loadedCount + 1
  end

  return string.format(
    "SoundEffects: muted=%s, masterVol=%.2f, loaded=%d sounds",
    tostring(state.isMuted),
    state.masterVolume,
    loadedCount
  )
end

return SoundEffects
