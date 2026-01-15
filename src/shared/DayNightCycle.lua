--[[
  DayNightCycle Module
  Manages day/night cycle with smooth lighting transitions.
  
  Time Periods:
  - Dawn: 5:00 - 7:00 (warm orange/pink)
  - Day: 7:00 - 18:00 (bright, clear)
  - Dusk: 18:00 - 20:00 (warm orange/pink)
  - Night: 20:00 - 5:00 (dark blue tint)
]]

local Lighting = game:GetService("Lighting")

local DayNightCycle = {}

-- Configuration
local FULL_CYCLE_MINUTES = 10 -- Real-world minutes for full 24-hour cycle
local SECONDS_PER_GAME_HOUR = (FULL_CYCLE_MINUTES * 60) / 24
local START_GAME_HOUR = 9 -- Start at 9:00 AM (during the day)

-- Time thresholds (in game hours, 0-24)
local TIME_DAWN_START = 5
local TIME_DAY_START = 7
local TIME_DUSK_START = 18
local TIME_NIGHT_START = 20

-- Lighting presets for each time period
local LIGHTING_PRESETS = {
  dawn = {
    Ambient = Color3.fromRGB(180, 140, 120),
    OutdoorAmbient = Color3.fromRGB(200, 160, 140),
    Brightness = 1.5,
    ColorShift_Top = Color3.fromRGB(255, 200, 150),
    ColorShift_Bottom = Color3.fromRGB(200, 150, 120),
  },
  day = {
    Ambient = Color3.fromRGB(150, 150, 150),
    OutdoorAmbient = Color3.fromRGB(180, 180, 180),
    Brightness = 2,
    ColorShift_Top = Color3.fromRGB(255, 255, 255),
    ColorShift_Bottom = Color3.fromRGB(200, 200, 200),
  },
  dusk = {
    Ambient = Color3.fromRGB(160, 140, 130),
    OutdoorAmbient = Color3.fromRGB(180, 160, 145),
    Brightness = 1.5,
    ColorShift_Top = Color3.fromRGB(255, 210, 170),
    ColorShift_Bottom = Color3.fromRGB(180, 160, 140),
  },
  night = {
    Ambient = Color3.fromRGB(120, 130, 160),
    OutdoorAmbient = Color3.fromRGB(100, 110, 140),
    Brightness = 1.0,
    ColorShift_Top = Color3.fromRGB(140, 160, 200),
    ColorShift_Bottom = Color3.fromRGB(100, 120, 160),
  },
}

-- ColorCorrection settings for each period
local COLOR_CORRECTION_PRESETS = {
  dawn = {
    Brightness = 0.02,
    Contrast = 0.05,
    Saturation = 0.1,
    TintColor = Color3.fromRGB(255, 240, 220),
  },
  day = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255, 255, 255) },
  dusk = {
    Brightness = 0.01,
    Contrast = 0.03,
    Saturation = 0.08,
    TintColor = Color3.fromRGB(255, 240, 220),
  },
  night = {
    Brightness = 0,
    Contrast = 0.05,
    Saturation = -0.05,
    TintColor = Color3.fromRGB(210, 220, 255),
  },
}

-- Bloom settings for each period
local BLOOM_PRESETS = {
  dawn = { Intensity = 0.8, Size = 20, Threshold = 0.9 },
  day = { Intensity = 0.3, Size = 15, Threshold = 1 },
  dusk = { Intensity = 1.0, Size = 24, Threshold = 0.85 },
  night = { Intensity = 0.2, Size = 10, Threshold = 1.2 },
}

-- State type
export type DayNightState = {
  startTime: number, -- os.time() when cycle started
  colorCorrection: ColorCorrectionEffect?,
  bloom: BloomEffect?,
}

-- Lerp helper for numbers
local function lerpNumber(a: number, b: number, t: number): number
  return a + (b - a) * t
end

-- Lerp helper for Color3
local function lerpColor3(a: Color3, b: Color3, t: number): Color3
  return Color3.new(lerpNumber(a.R, b.R, t), lerpNumber(a.G, b.G, t), lerpNumber(a.B, b.B, t))
end

-- Get current game time (0-24) from server time
function DayNightCycle.getGameTime(state: DayNightState): number
  local elapsedSeconds = os.time() - state.startTime
  local gameHours = (elapsedSeconds / SECONDS_PER_GAME_HOUR) % 24
  return gameHours
end

-- Determine the current time period
function DayNightCycle.getTimeOfDay(state: DayNightState): string
  local gameTime = DayNightCycle.getGameTime(state)

  if gameTime >= TIME_NIGHT_START or gameTime < TIME_DAWN_START then
    return "night"
  elseif gameTime >= TIME_DUSK_START then
    return "dusk"
  elseif gameTime >= TIME_DAY_START then
    return "day"
  else
    return "dawn"
  end
end

-- Helper functions for time checks
function DayNightCycle.isNight(state: DayNightState): boolean
  return DayNightCycle.getTimeOfDay(state) == "night"
end

function DayNightCycle.isDawn(state: DayNightState): boolean
  return DayNightCycle.getTimeOfDay(state) == "dawn"
end

function DayNightCycle.isDusk(state: DayNightState): boolean
  return DayNightCycle.getTimeOfDay(state) == "dusk"
end

function DayNightCycle.isDay(state: DayNightState): boolean
  return DayNightCycle.getTimeOfDay(state) == "day"
end

-- Get transition factor between two periods (0 = at start of period, 1 = at end)
local function getTransitionFactor(gameTime: number): (string, string, number)
  local fromPeriod: string
  local toPeriod: string
  local factor: number

  if gameTime >= TIME_NIGHT_START then
    -- Night (20-24) - no transition, stable night
    fromPeriod = "night"
    toPeriod = "night"
    factor = 0
  elseif gameTime >= TIME_DUSK_START then
    -- Dusk to Night transition (18-20)
    fromPeriod = "dusk"
    toPeriod = "night"
    factor = (gameTime - TIME_DUSK_START) / (TIME_NIGHT_START - TIME_DUSK_START)
  elseif gameTime >= TIME_DAY_START then
    -- Day to Dusk transition (last 2 hours of day: 16-18)
    if gameTime >= 16 then
      fromPeriod = "day"
      toPeriod = "dusk"
      factor = (gameTime - 16) / (TIME_DUSK_START - 16)
    else
      fromPeriod = "day"
      toPeriod = "day"
      factor = 0
    end
  elseif gameTime >= TIME_DAWN_START then
    -- Dawn to Day transition (5-7)
    fromPeriod = "dawn"
    toPeriod = "day"
    factor = (gameTime - TIME_DAWN_START) / (TIME_DAY_START - TIME_DAWN_START)
  else
    -- Night to Dawn transition (4-5, last hour of night)
    if gameTime >= 4 then
      fromPeriod = "night"
      toPeriod = "dawn"
      factor = (gameTime - 4) / (TIME_DAWN_START - 4)
    else
      fromPeriod = "night"
      toPeriod = "night"
      factor = 0
    end
  end

  return fromPeriod, toPeriod, factor
end

-- Initialize the day/night cycle state
function DayNightCycle.init(): DayNightState
  -- Offset start time so we begin at START_GAME_HOUR instead of midnight
  local startOffset = START_GAME_HOUR * SECONDS_PER_GAME_HOUR
  local state: DayNightState = {
    startTime = os.time() - startOffset,
    colorCorrection = nil,
    bloom = nil,
  }

  -- Create or find ColorCorrection effect
  local colorCorrection = Lighting:FindFirstChild("DayNightColorCorrection")
  if not colorCorrection then
    colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Name = "DayNightColorCorrection"
    colorCorrection.Parent = Lighting
  end
  state.colorCorrection = colorCorrection :: ColorCorrectionEffect

  -- Create or find Bloom effect
  local bloom = Lighting:FindFirstChild("DayNightBloom")
  if not bloom then
    bloom = Instance.new("BloomEffect")
    bloom.Name = "DayNightBloom"
    bloom.Parent = Lighting
  end
  state.bloom = bloom :: BloomEffect

  return state
end

-- Update lighting based on current time (call each frame or at regular intervals)
function DayNightCycle.update(state: DayNightState): ()
  local gameTime = DayNightCycle.getGameTime(state)

  -- Update ClockTime
  Lighting.ClockTime = gameTime

  -- Get transition info
  local fromPeriod, toPeriod, factor = getTransitionFactor(gameTime)
  local fromLighting = LIGHTING_PRESETS[fromPeriod]
  local toLighting = LIGHTING_PRESETS[toPeriod]

  -- Interpolate lighting properties
  Lighting.Ambient = lerpColor3(fromLighting.Ambient, toLighting.Ambient, factor)
  Lighting.OutdoorAmbient =
    lerpColor3(fromLighting.OutdoorAmbient, toLighting.OutdoorAmbient, factor)
  Lighting.Brightness = lerpNumber(fromLighting.Brightness, toLighting.Brightness, factor)
  Lighting.ColorShift_Top =
    lerpColor3(fromLighting.ColorShift_Top, toLighting.ColorShift_Top, factor)
  Lighting.ColorShift_Bottom =
    lerpColor3(fromLighting.ColorShift_Bottom, toLighting.ColorShift_Bottom, factor)

  -- Update ColorCorrection
  if state.colorCorrection then
    local fromCC = COLOR_CORRECTION_PRESETS[fromPeriod]
    local toCC = COLOR_CORRECTION_PRESETS[toPeriod]
    state.colorCorrection.Brightness = lerpNumber(fromCC.Brightness, toCC.Brightness, factor)
    state.colorCorrection.Contrast = lerpNumber(fromCC.Contrast, toCC.Contrast, factor)
    state.colorCorrection.Saturation = lerpNumber(fromCC.Saturation, toCC.Saturation, factor)
    state.colorCorrection.TintColor = lerpColor3(fromCC.TintColor, toCC.TintColor, factor)
  end

  -- Update Bloom
  if state.bloom then
    local fromBloom = BLOOM_PRESETS[fromPeriod]
    local toBloom = BLOOM_PRESETS[toPeriod]
    state.bloom.Intensity = lerpNumber(fromBloom.Intensity, toBloom.Intensity, factor)
    state.bloom.Size = lerpNumber(fromBloom.Size, toBloom.Size, factor)
    state.bloom.Threshold = lerpNumber(fromBloom.Threshold, toBloom.Threshold, factor)
  end
end

-- Get spawn rate multiplier for predators based on time of day
function DayNightCycle.getPredatorSpawnMultiplier(state: DayNightState): number
  local timeOfDay = DayNightCycle.getTimeOfDay(state)
  local multipliers = {
    day = 0.5,
    dawn = 0.75,
    dusk = 1.25,
    night = 2.0,
  }
  return multipliers[timeOfDay] or 1.0
end

-- Get current time info for syncing to clients
function DayNightCycle.getTimeInfo(
  state: DayNightState
): { gameTime: number, timeOfDay: string, isNight: boolean }
  return {
    gameTime = DayNightCycle.getGameTime(state),
    timeOfDay = DayNightCycle.getTimeOfDay(state),
    isNight = DayNightCycle.isNight(state),
  }
end

return DayNightCycle
