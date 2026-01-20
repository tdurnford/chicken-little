--[[
	HatchPreviewUI Component (Fusion)
	Shows a preview of the 3 possible chickens with probabilities before hatching an egg.
	Displays when player selects an egg to hatch, with E key binding and hatch button.
	Also displays hatch results with celebratory animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared:WaitForChild("EggConfig"))
local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
local EggHatching = require(Shared:WaitForChild("EggHatching"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local Cleanup = Fusion.Cleanup

-- Types
export type PreviewConfig = {
  anchorPoint: Vector2?,
  position: UDim2?,
  size: UDim2?,
  backgroundColor: Color3?,
}

export type HatchPreviewUIProps = {
  onHatch: ((eggId: string, eggType: string) -> ())?,
  onCancel: (() -> ())?,
}

-- Rarity colors for visual distinction
local RARITY_COLORS: { [string]: Color3 } = {
  Common = Color3.fromRGB(180, 180, 180),
  Uncommon = Color3.fromRGB(100, 200, 100),
  Rare = Color3.fromRGB(100, 150, 255),
  Epic = Color3.fromRGB(180, 100, 255),
  Legendary = Color3.fromRGB(255, 180, 50),
  Mythic = Color3.fromRGB(255, 100, 150),
}

-- Default configuration
local DEFAULT_CONFIG: PreviewConfig = {
  anchorPoint = Vector2.new(0.5, 0.5),
  position = UDim2.new(0.5, 0, 0.5, 0),
  size = UDim2.new(0, 420, 0, 380),
  backgroundColor = Theme.Colors.Background,
}

-- Animation durations
local FADE_DURATION = 0.3
local SCALE_DURATION = 0.25

-- Module state
local HatchPreviewUI = {}
local screenGui: ScreenGui? = nil
local previewScope: Fusion.Scope? = nil
local isVisible: Fusion.Value<boolean>? = nil
local currentEggId: Fusion.Value<string?>? = nil
local currentEggType: Fusion.Value<string?>? = nil
local showingResult: Fusion.Value<boolean>? = nil
local resultChickenType: Fusion.Value<string?>? = nil
local resultRarity: Fusion.Value<string?>? = nil
local backdropTransparency: Fusion.Value<number>? = nil
local frameScale: Fusion.Value<number>? = nil
local inputConnection: RBXScriptConnection? = nil
local cachedCallbacks: HatchPreviewUIProps = {}

-- Helper: Get display name for egg
local function getEggDisplayName(eggType: string): string
  local config = EggConfig.get(eggType)
  return config and config.displayName or eggType
end

-- Helper: Get chicken config
local function getChickenConfig(chickenType: string)
  return ChickenConfig.get(chickenType)
end

-- Create outcome card component
local function createOutcomeCard(
  scope: Fusion.Scope,
  chickenType: string,
  probability: number,
  index: number
): Frame
  local chickenConfig = getChickenConfig(chickenType)
  if not chickenConfig then
    return New(scope, "Frame")({ Size = UDim2.new(0, 0, 0, 0) })
  end

  local rarity = chickenConfig.rarity
  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

  local cardWidth = 110
  local cardSpacing = 16
  local totalWidth = (cardWidth * 3) + (cardSpacing * 2)
  local startX = (420 - totalWidth) / 2
  local xPosition = startX + ((index - 1) * (cardWidth + cardSpacing))

  return New(scope, "Frame")({
    Name = "OutcomeCard_" .. index,
    Size = UDim2.new(0, cardWidth, 0, 160),
    Position = UDim2.new(0, xPosition, 0, 88),
    BackgroundColor3 = Theme.Colors.SurfaceLight,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,

    [Children] = {
      New(scope, "UICorner")({ CornerRadius = UDim.new(0, 12) }),
      New(scope, "UIStroke")({
        Color = rarityColor,
        Thickness = 2,
        Transparency = 0.3,
      }),

      -- Chicken icon
      New(scope, "TextLabel")({
        Name = "Icon",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 10),
        BackgroundTransparency = 1,
        Text = "🐔",
        TextSize = 36,
        TextColor3 = rarityColor,
      }),

      -- Chicken name
      New(scope, "TextLabel")({
        Name = "NameLabel",
        Size = UDim2.new(1, -8, 0, 32),
        Position = UDim2.new(0, 4, 0, 60),
        BackgroundTransparency = 1,
        Text = chickenConfig.displayName,
        TextScaled = true,
        TextWrapped = true,
        TextColor3 = Theme.Colors.TextPrimary,
        FontFace = Theme.Typography.PrimaryBold,
      }),

      -- Rarity label
      New(scope, "TextLabel")({
        Name = "RarityLabel",
        Size = UDim2.new(1, -8, 0, 18),
        Position = UDim2.new(0, 4, 0, 94),
        BackgroundTransparency = 1,
        Text = rarity,
        TextSize = 12,
        TextColor3 = rarityColor,
        FontFace = Theme.Typography.PrimarySemiBold,
      }),

      -- Probability display
      New(scope, "Frame")({
        Name = "ProbabilityFrame",
        Size = UDim2.new(1, -16, 0, 28),
        Position = UDim2.new(0, 8, 1, -36),
        BackgroundColor3 = Theme.Colors.BackgroundDark,
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
          New(scope, "TextLabel")({
            Name = "ProbabilityLabel",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = probability .. "%",
            TextSize = 16,
            TextColor3 = Color3.fromRGB(255, 220, 100),
            FontFace = Theme.Typography.PrimaryBold,
          }),
        },
      }),
    },
  })
end

-- Create preview content (shows possible hatches)
local function createPreviewContent(scope: Fusion.Scope, eggType: string): Frame
  local eggConfig = EggConfig.get(eggType)
  if not eggConfig then
    return New(scope, "Frame")({ Size = UDim2.new(0, 0, 0, 0) })
  end

  local outcomeCards = {}
  for i, outcome in ipairs(eggConfig.hatchOutcomes) do
    table.insert(
      outcomeCards,
      createOutcomeCard(scope, outcome.chickenType, outcome.probability, i)
    )
  end

  return New(scope, "Frame")({
    Name = "PreviewContent",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,

    [Children] = {
      -- Header
      New(scope, "TextLabel")({
        Name = "Header",
        Size = UDim2.new(1, -24, 0, 40),
        Position = UDim2.new(0, 12, 0, 12),
        BackgroundTransparency = 1,
        Text = "🥚 " .. eggConfig.displayName,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 24,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),

      -- Subtitle
      New(scope, "TextLabel")({
        Name = "Subtitle",
        Size = UDim2.new(1, -24, 0, 24),
        Position = UDim2.new(0, 12, 0, 52),
        BackgroundTransparency = 1,
        Text = "Possible Hatches",
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 14,
        FontFace = Theme.Typography.Primary,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),

      -- Outcome cards container
      New(scope, "Frame")({
        Name = "OutcomesContainer",
        Size = UDim2.new(1, 0, 0, 180),
        Position = UDim2.new(0, 0, 0, 80),
        BackgroundTransparency = 1,
        [Children] = outcomeCards,
      }),

      -- Hatch button
      New(scope, "TextButton")({
        Name = "HatchButton",
        Size = UDim2.new(0, 180, 0, 50),
        Position = UDim2.new(0.5, -90, 1, -120),
        BackgroundColor3 = Color3.fromRGB(80, 180, 80),
        Text = "🐣 Hatch [E]",
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 18,
        FontFace = Theme.Typography.PrimaryBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 10) }),
        },

        [OnEvent("MouseButton1Click")] = function()
          HatchPreviewUI.confirmHatch()
        end,
      }),

      -- Cancel button
      New(scope, "TextButton")({
        Name = "CancelButton",
        Size = UDim2.new(0, 180, 0, 40),
        Position = UDim2.new(0.5, -90, 1, -60),
        BackgroundColor3 = Theme.Colors.Surface,
        Text = "Cancel",
        TextColor3 = Theme.Colors.TextSecondary,
        TextSize = 14,
        FontFace = Theme.Typography.PrimarySemiBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 8) }),
        },

        [OnEvent("MouseButton1Click")] = function()
          HatchPreviewUI.cancel()
        end,
      }),
    },
  })
end

-- Create result content (shows hatched chicken)
local function createResultContent(scope: Fusion.Scope, chickenType: string, rarity: string): Frame
  local chickenConfig = getChickenConfig(chickenType)
  if not chickenConfig then
    return New(scope, "Frame")({ Size = UDim2.new(0, 0, 0, 0) })
  end

  local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
  local moneyPerSecond = chickenConfig.moneyPerSecond or 1
  local cardSize = 160

  return New(scope, "Frame")({
    Name = "ResultContent",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,

    [Children] = {
      -- Header
      New(scope, "TextLabel")({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 15),
        BackgroundTransparency = 1,
        Text = "You Got!",
        TextSize = 24,
        TextColor3 = Color3.fromRGB(255, 220, 100),
        FontFace = Theme.Typography.PrimaryBold,
      }),

      -- Large chicken card
      New(scope, "Frame")({
        Name = "ResultCard",
        Size = UDim2.new(0, cardSize, 0, cardSize + 40),
        Position = UDim2.new(0.5, -cardSize / 2, 0, 65),
        BackgroundColor3 = Theme.Colors.SurfaceLight,
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 12) }),
          New(scope, "UIStroke")({
            Color = rarityColor,
            Thickness = 3,
            Transparency = 0,
          }),

          -- Large chicken emoji
          New(scope, "TextLabel")({
            Name = "Icon",
            Size = UDim2.new(1, 0, 0, 80),
            Position = UDim2.new(0, 0, 0, 15),
            BackgroundTransparency = 1,
            Text = "🐔",
            TextSize = 64,
            TextColor3 = rarityColor,
          }),

          -- Chicken name
          New(scope, "TextLabel")({
            Name = "NameLabel",
            Size = UDim2.new(1, -10, 0, 36),
            Position = UDim2.new(0, 5, 0, 95),
            BackgroundTransparency = 1,
            Text = chickenConfig.displayName,
            TextScaled = true,
            TextWrapped = true,
            TextColor3 = Theme.Colors.TextPrimary,
            FontFace = Theme.Typography.PrimaryBold,
          }),

          -- Rarity badge
          New(scope, "Frame")({
            Name = "RarityBadge",
            Size = UDim2.new(0, 100, 0, 28),
            Position = UDim2.new(0.5, -50, 0, 135),
            BackgroundColor3 = rarityColor,
            BorderSizePixel = 0,

            [Children] = {
              New(scope, "UICorner")({ CornerRadius = UDim.new(0, 6) }),
              New(scope, "TextLabel")({
                Name = "RarityLabel",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = rarity,
                TextSize = 14,
                TextColor3 = Theme.Colors.TextPrimary,
                FontFace = Theme.Typography.PrimaryBold,
              }),
            },
          }),
        },
      }),

      -- Stats display
      New(scope, "Frame")({
        Name = "StatsFrame",
        Size = UDim2.new(0, 180, 0, 50),
        Position = UDim2.new(0.5, -90, 0, 280),
        BackgroundColor3 = Theme.Colors.BackgroundDark,
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 8) }),
          New(scope, "TextLabel")({
            Name = "StatsLabel",
            Size = UDim2.new(1, -10, 1, 0),
            Position = UDim2.new(0, 5, 0, 0),
            BackgroundTransparency = 1,
            Text = string.format("💰 $%.2f/sec", moneyPerSecond),
            TextSize = 16,
            TextColor3 = Theme.Colors.Success,
            FontFace = Theme.Typography.PrimarySemiBold,
          }),
        },
      }),

      -- Dismiss button
      New(scope, "TextButton")({
        Name = "DismissButton",
        Size = UDim2.new(0, 160, 0, 45),
        Position = UDim2.new(0.5, -80, 1, -60),
        BackgroundColor3 = Theme.Colors.Secondary,
        Text = "Continue",
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 18,
        FontFace = Theme.Typography.PrimaryBold,
        BorderSizePixel = 0,
        AutoButtonColor = true,

        [Children] = {
          New(scope, "UICorner")({ CornerRadius = UDim.new(0, 10) }),
        },

        [OnEvent("MouseButton1Click")] = function()
          HatchPreviewUI.hide()
        end,
      }),
    },
  })
end

-- Setup keyboard bindings
local function setupKeyBinding()
  if inputConnection then
    inputConnection:Disconnect()
  end

  inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
      return
    end

    if input.KeyCode == Enum.KeyCode.E then
      if isVisible and Fusion.peek(isVisible) and currentEggId and Fusion.peek(currentEggId) then
        if not (showingResult and Fusion.peek(showingResult)) then
          HatchPreviewUI.confirmHatch()
        end
      end
    elseif input.KeyCode == Enum.KeyCode.Escape then
      if isVisible and Fusion.peek(isVisible) then
        HatchPreviewUI.cancel()
      end
    end
  end)
end

-- Animate popup appearing
local function animateIn()
  if not backdropTransparency or not frameScale then
    return
  end

  -- Set to visible immediately
  frameScale:set(1)
  backdropTransparency:set(0.6)
end

-- Animate popup disappearing
local function animateOut(callback: () -> ())
  if not backdropTransparency or not frameScale then
    callback()
    return
  end

  -- Hide immediately
  frameScale:set(0)
  backdropTransparency:set(1)
  callback()
end

-- Initialize the preview UI
function HatchPreviewUI.create(props: HatchPreviewUIProps?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("HatchPreviewUI: No LocalPlayer found")
    return false
  end

  -- Clean up existing
  HatchPreviewUI.destroy()

  -- Store callbacks
  if props then
    cachedCallbacks = props
  end

  -- Create Fusion scope
  previewScope = Fusion.scoped({})

  -- Create reactive state
  isVisible = Value(previewScope, false)
  currentEggId = Value(previewScope, nil :: string?)
  currentEggType = Value(previewScope, nil :: string?)
  showingResult = Value(previewScope, false)
  resultChickenType = Value(previewScope, nil :: string?)
  resultRarity = Value(previewScope, nil :: string?)
  backdropTransparency = Value(previewScope, 1)
  frameScale = Value(previewScope, 0)

  -- Create computed content
  local contentFrame = Computed(previewScope, function(use)
    local eggType = use(currentEggType)
    local isResult = use(showingResult)
    local chickenType = use(resultChickenType)
    local rarity = use(resultRarity)

    if isResult and chickenType and rarity then
      return createResultContent(previewScope, chickenType, rarity)
    elseif eggType then
      return createPreviewContent(previewScope, eggType)
    end
    return nil
  end)

  -- Create computed frame size
  local computedSize = Computed(previewScope, function(use)
    local scale = use(frameScale)
    return UDim2.new(0, 420 * scale, 0, 380 * scale)
  end)

  -- Create screen GUI with Fusion
  screenGui = New(previewScope, "ScreenGui")({
    Name = "HatchPreviewUI",
    Parent = player:WaitForChild("PlayerGui"),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,
    DisplayOrder = 99,
    Enabled = Computed(previewScope, function(use)
      return use(isVisible)
    end),

    [Children] = {
      -- Backdrop
      New(previewScope, "Frame")({
        Name = "Backdrop",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = Computed(previewScope, function(use)
          return use(backdropTransparency)
        end),
        BorderSizePixel = 0,
        ZIndex = 1,

        [Children] = {
          New(previewScope, "TextButton")({
            Name = "ClickDetector",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 1,

            [OnEvent("MouseButton1Click")] = function()
              HatchPreviewUI.cancel()
            end,
          }),
        },
      }),

      -- Main popup frame
      New(previewScope, "Frame")({
        Name = "HatchPreviewPopup",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = computedSize,
        BackgroundColor3 = Theme.Colors.Background,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        ZIndex = 2,

        [Children] = {
          New(previewScope, "UICorner")({ CornerRadius = UDim.new(0, 16) }),
          New(previewScope, "UIStroke")({
            Color = Color3.fromRGB(255, 220, 100),
            Thickness = 2,
            Transparency = 0.3,
          }),
          contentFrame,
        },
      }),
    },
  })

  -- Setup key bindings
  setupKeyBinding()

  return true
end

-- Destroy the preview UI
function HatchPreviewUI.destroy()
  if inputConnection then
    inputConnection:Disconnect()
    inputConnection = nil
  end

  if previewScope then
    Fusion.doCleanup(previewScope)
    previewScope = nil
  end

  screenGui = nil
  isVisible = nil
  currentEggId = nil
  currentEggType = nil
  showingResult = nil
  resultChickenType = nil
  resultRarity = nil
  backdropTransparency = nil
  frameScale = nil
  cachedCallbacks = {}
end

-- Show the preview for a specific egg
function HatchPreviewUI.show(eggId: string, eggType: string)
  if not previewScope then
    warn("HatchPreviewUI: UI not created. Call create() first.")
    return
  end

  -- Validate egg type
  if not EggConfig.isValidType(eggType) then
    warn("HatchPreviewUI: Invalid egg type: " .. eggType)
    return
  end

  -- Set state
  if currentEggId then
    currentEggId:set(eggId)
  end
  if currentEggType then
    currentEggType:set(eggType)
  end
  if showingResult then
    showingResult:set(false)
  end
  if isVisible then
    isVisible:set(true)
  end

  -- Animate in
  animateIn()
end

-- Hide the preview
function HatchPreviewUI.hide()
  if not isVisible then
    return
  end

  animateOut(function()
    if isVisible then
      isVisible:set(false)
    end
    if currentEggId then
      currentEggId:set(nil)
    end
    if currentEggType then
      currentEggType:set(nil)
    end
    if showingResult then
      showingResult:set(false)
    end
    if resultChickenType then
      resultChickenType:set(nil)
    end
    if resultRarity then
      resultRarity:set(nil)
    end
  end)
end

-- Confirm the hatch and trigger callback
function HatchPreviewUI.confirmHatch()
  if not currentEggId or not currentEggType then
    return
  end

  local eggId = Fusion.peek(currentEggId)
  local eggType = Fusion.peek(currentEggType)

  if not eggId or not eggType then
    return
  end

  -- Call callback (which will show result UI via showResult)
  if cachedCallbacks.onHatch then
    cachedCallbacks.onHatch(eggId, eggType)
  end

  -- Don't hide here - the result UI will be shown by showResult()
  -- and will be dismissed when user clicks the dismiss button
end

-- Cancel without hatching
function HatchPreviewUI.cancel()
  if cachedCallbacks.onCancel then
    cachedCallbacks.onCancel()
  end
  HatchPreviewUI.hide()
end

-- Show the result of a successful hatch
function HatchPreviewUI.showResult(chickenType: string, rarity: string, onDismiss: (() -> ())?)
  if not previewScope then
    HatchPreviewUI.create()
  end

  -- Check if already visible (transitioning from preview to result)
  local alreadyVisible = isVisible and Fusion.peek(isVisible)

  -- Set result state
  if resultChickenType then
    resultChickenType:set(chickenType)
  end
  if resultRarity then
    resultRarity:set(rarity)
  end
  if showingResult then
    showingResult:set(true)
  end
  if isVisible then
    isVisible:set(true)
  end

  -- Only animate in if not already visible
  if not alreadyVisible then
    animateIn()
  end
end

-- Check if preview is visible
function HatchPreviewUI.isVisible(): boolean
  return isVisible ~= nil and Fusion.peek(isVisible) == true
end

-- Check if preview is created
function HatchPreviewUI.isCreated(): boolean
  return screenGui ~= nil and previewScope ~= nil
end

-- Get current egg being previewed
function HatchPreviewUI.getCurrentEgg(): (string?, string?)
  if not currentEggId or not currentEggType then
    return nil, nil
  end
  return Fusion.peek(currentEggId), Fusion.peek(currentEggType)
end

-- Set callback for when hatch is confirmed
function HatchPreviewUI.onHatch(callback: (eggId: string, eggType: string) -> ())
  cachedCallbacks.onHatch = callback
end

-- Set callback for when preview is cancelled
function HatchPreviewUI.onCancel(callback: () -> ())
  cachedCallbacks.onCancel = callback
end

-- Get the screen GUI
function HatchPreviewUI.getScreenGui(): ScreenGui?
  return screenGui
end

-- Get hatch preview data for an egg type (convenience wrapper)
function HatchPreviewUI.getPreviewData(eggType: string): { EggConfig.HatchOutcome }?
  return EggHatching.getHatchPreview(eggType)
end

-- Get rarity colors (for external use)
function HatchPreviewUI.getRarityColors(): { [string]: Color3 }
  local copy = {}
  for rarity, color in pairs(RARITY_COLORS) do
    copy[rarity] = color
  end
  return copy
end

-- Get default configuration
function HatchPreviewUI.getDefaultConfig(): PreviewConfig
  local copy = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    copy[key] = value
  end
  return copy
end

return HatchPreviewUI
