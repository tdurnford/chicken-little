--[[
	DamageUI Module
	Displays damage numbers floating up from the player and
	shows the combat health bar when taking damage.
]]

local DamageUI = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Local player reference
local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui? = nil

-- UI container for damage numbers
local damageContainer: ScreenGui? = nil
local healthBar: Frame? = nil
local healthBarFill: Frame? = nil
local healthBarText: TextLabel? = nil

-- Constants
local DAMAGE_NUMBER_LIFETIME = 1.5 -- Seconds for damage number to float and fade
local DAMAGE_NUMBER_RISE = 50 -- Pixels to rise
local HEALTH_BAR_VISIBLE_DURATION = 3 -- Seconds to show health bar after damage
local HEALTH_BAR_FADE_DURATION = 0.5 -- Fade out duration

-- State
local healthBarHideTime = 0
local isHealthBarVisible = false

-- Initialize the damage UI container
function DamageUI.initialize()
  playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

  -- Create main screen GUI for damage numbers
  damageContainer = Instance.new("ScreenGui")
  damageContainer.Name = "DamageUI"
  damageContainer.ResetOnSpawn = false
  damageContainer.IgnoreGuiInset = true
  damageContainer.DisplayOrder = 100
  damageContainer.Parent = playerGui

  -- Create health bar container
  local healthBarContainer = Instance.new("Frame")
  healthBarContainer.Name = "HealthBarContainer"
  healthBarContainer.Size = UDim2.new(0, 200, 0, 30)
  healthBarContainer.Position = UDim2.new(0.5, -100, 0, 80)
  healthBarContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
  healthBarContainer.BorderSizePixel = 0
  healthBarContainer.Visible = false
  healthBarContainer.Parent = damageContainer

  -- Add corner rounding
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 6)
  corner.Parent = healthBarContainer

  -- Create health bar background
  local healthBarBg = Instance.new("Frame")
  healthBarBg.Name = "Background"
  healthBarBg.Size = UDim2.new(1, -8, 1, -8)
  healthBarBg.Position = UDim2.new(0, 4, 0, 4)
  healthBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
  healthBarBg.BorderSizePixel = 0
  healthBarBg.Parent = healthBarContainer

  local bgCorner = Instance.new("UICorner")
  bgCorner.CornerRadius = UDim.new(0, 4)
  bgCorner.Parent = healthBarBg

  -- Create health bar fill
  healthBarFill = Instance.new("Frame")
  healthBarFill.Name = "Fill"
  healthBarFill.Size = UDim2.new(1, 0, 1, 0)
  healthBarFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
  healthBarFill.BorderSizePixel = 0
  healthBarFill.Parent = healthBarBg

  local fillCorner = Instance.new("UICorner")
  fillCorner.CornerRadius = UDim.new(0, 4)
  fillCorner.Parent = healthBarFill

  -- Create health text
  healthBarText = Instance.new("TextLabel")
  healthBarText.Name = "HealthText"
  healthBarText.Size = UDim2.new(1, 0, 1, 0)
  healthBarText.BackgroundTransparency = 1
  healthBarText.Text = "100/100"
  healthBarText.TextColor3 = Color3.fromRGB(255, 255, 255)
  healthBarText.TextStrokeTransparency = 0.5
  healthBarText.Font = Enum.Font.GothamBold
  healthBarText.TextSize = 14
  healthBarText.Parent = healthBarContainer

  healthBar = healthBarContainer

  print("[DamageUI] Initialized")
end

-- Get color based on health percent
local function getHealthColor(percent: number): Color3
  if percent > 0.6 then
    return Color3.fromRGB(50, 200, 50) -- Green
  elseif percent > 0.3 then
    return Color3.fromRGB(255, 200, 50) -- Yellow
  else
    return Color3.fromRGB(220, 50, 50) -- Red
  end
end

-- Show a damage number floating up
function DamageUI.showDamageNumber(damage: number, source: string?)
  if not damageContainer then
    return
  end

  -- Create damage number label
  local damageLabel = Instance.new("TextLabel")
  damageLabel.Name = "DamageNumber"
  damageLabel.Size = UDim2.new(0, 100, 0, 30)
  -- Position near center of screen with random horizontal offset
  local xOffset = math.random(-50, 50)
  damageLabel.Position = UDim2.new(0.5, xOffset - 50, 0.4, 0)
  damageLabel.BackgroundTransparency = 1
  damageLabel.Text = string.format("-%.0f", damage)
  damageLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
  damageLabel.TextStrokeTransparency = 0.3
  damageLabel.TextStrokeColor3 = Color3.fromRGB(50, 0, 0)
  damageLabel.Font = Enum.Font.GothamBold
  damageLabel.TextSize = 24
  damageLabel.TextScaled = false
  damageLabel.Parent = damageContainer

  -- Animate floating up and fading out
  local startPos = damageLabel.Position
  local endPos = UDim2.new(
    startPos.X.Scale,
    startPos.X.Offset,
    startPos.Y.Scale,
    startPos.Y.Offset - DAMAGE_NUMBER_RISE
  )

  local tweenInfo =
    TweenInfo.new(DAMAGE_NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

  local moveTween = TweenService:Create(damageLabel, tweenInfo, {
    Position = endPos,
    TextTransparency = 1,
    TextStrokeTransparency = 1,
  })

  moveTween:Play()
  moveTween.Completed:Connect(function()
    damageLabel:Destroy()
  end)
end

-- Show knockback effect
function DamageUI.showKnockback(duration: number, source: string?)
  if not damageContainer then
    return
  end

  -- Create knockback overlay
  local overlay = Instance.new("Frame")
  overlay.Name = "KnockbackOverlay"
  overlay.Size = UDim2.new(1, 0, 1, 0)
  overlay.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
  overlay.BackgroundTransparency = 0.7
  overlay.BorderSizePixel = 0
  overlay.Parent = damageContainer

  -- Create "STUNNED!" text
  local stunnedText = Instance.new("TextLabel")
  stunnedText.Name = "StunnedText"
  stunnedText.Size = UDim2.new(0, 300, 0, 60)
  stunnedText.Position = UDim2.new(0.5, -150, 0.4, -30)
  stunnedText.BackgroundTransparency = 1
  stunnedText.Text = "STUNNED!"
  stunnedText.TextColor3 = Color3.fromRGB(255, 255, 255)
  stunnedText.TextStrokeTransparency = 0
  stunnedText.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
  stunnedText.Font = Enum.Font.GothamBold
  stunnedText.TextSize = 48
  stunnedText.Parent = damageContainer

  -- Fade out after duration
  task.delay(duration * 0.7, function()
    local fadeInfo = TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local overlayFade = TweenService:Create(overlay, fadeInfo, { BackgroundTransparency = 1 })
    local textFade = TweenService:Create(
      stunnedText,
      fadeInfo,
      { TextTransparency = 1, TextStrokeTransparency = 1 }
    )

    overlayFade:Play()
    textFade:Play()

    overlayFade.Completed:Connect(function()
      overlay:Destroy()
      stunnedText:Destroy()
    end)
  end)
end

-- Update health bar display
function DamageUI.updateHealthBar(health: number, maxHealth: number, showBar: boolean?)
  if not healthBar or not healthBarFill or not healthBarText then
    return
  end

  local percent = health / maxHealth
  healthBarFill.Size = UDim2.new(percent, 0, 1, 0)
  healthBarFill.BackgroundColor3 = getHealthColor(percent)
  healthBarText.Text = string.format("%.0f/%.0f", health, maxHealth)

  -- Show health bar if taking damage or explicitly requested
  if showBar ~= false then
    healthBar.Visible = true
    isHealthBarVisible = true
    healthBarHideTime = os.clock() + HEALTH_BAR_VISIBLE_DURATION
  end
end

-- Hide health bar (for when at full health)
function DamageUI.hideHealthBar()
  if healthBar then
    healthBar.Visible = false
    isHealthBarVisible = false
  end
end

-- Update function to be called each frame (handles health bar auto-hide)
function DamageUI.update()
  if isHealthBarVisible and os.clock() >= healthBarHideTime then
    -- Fade out health bar
    if healthBar then
      local fadeInfo =
        TweenInfo.new(HEALTH_BAR_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
      local fade = TweenService:Create(healthBar, fadeInfo, {})
      fade:Play()
      fade.Completed:Connect(function()
        if os.clock() >= healthBarHideTime then
          healthBar.Visible = false
        end
      end)
    end
    isHealthBarVisible = false
  end
end

-- Handle PlayerDamaged event from server
function DamageUI.onPlayerDamaged(data: {
  damage: number,
  newHealth: number,
  maxHealth: number,
  source: string?,
})
  DamageUI.showDamageNumber(data.damage, data.source)
  DamageUI.updateHealthBar(data.newHealth, data.maxHealth, true)
end

-- Handle PlayerKnockback event from server
function DamageUI.onPlayerKnockback(data: { duration: number, source: string? })
  DamageUI.showKnockback(data.duration, data.source)
end

-- Handle PlayerHealthChanged event from server (for regen updates)
function DamageUI.onPlayerHealthChanged(data: {
  health: number,
  maxHealth: number,
  isKnockedBack: boolean,
  inCombat: boolean,
})
  DamageUI.updateHealthBar(data.health, data.maxHealth, data.inCombat)

  -- Hide bar when at full health and not in combat
  if data.health >= data.maxHealth and not data.inCombat then
    DamageUI.hideHealthBar()
  end
end

-- Cleanup function
function DamageUI.cleanup()
  if damageContainer then
    damageContainer:Destroy()
    damageContainer = nil
  end
  healthBar = nil
  healthBarFill = nil
  healthBarText = nil
end

return DamageUI
