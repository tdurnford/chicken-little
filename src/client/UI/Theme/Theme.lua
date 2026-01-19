--[[
	Theme Module
	Centralized theme configuration for Fusion UI components.
	Contains color palette, typography, spacing, and other design tokens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))
local OnyxUI = require(Packages:WaitForChild("OnyxUI"))

local Theme = {}

-- Color palette based on existing game aesthetic
Theme.Colors = {
  -- Primary colors
  Primary = Color3.fromRGB(133, 187, 101), -- Money green (#85BB65)
  PrimaryDark = Color3.fromRGB(100, 150, 75),
  PrimaryLight = Color3.fromRGB(160, 210, 130),

  -- Secondary colors
  Secondary = Color3.fromRGB(70, 130, 180), -- Steel blue for UI accents
  SecondaryDark = Color3.fromRGB(50, 100, 150),
  SecondaryLight = Color3.fromRGB(100, 160, 210),

  -- Background colors
  Background = Color3.fromRGB(30, 30, 40), -- Dark background
  BackgroundLight = Color3.fromRGB(45, 45, 60),
  BackgroundDark = Color3.fromRGB(20, 20, 30),

  -- Surface colors (cards, panels)
  Surface = Color3.fromRGB(40, 40, 55),
  SurfaceLight = Color3.fromRGB(55, 55, 75),
  SurfaceDark = Color3.fromRGB(30, 30, 42),

  -- Text colors
  TextPrimary = Color3.fromRGB(255, 255, 255),
  TextSecondary = Color3.fromRGB(180, 180, 190),
  TextMuted = Color3.fromRGB(120, 120, 135),
  TextMoney = Color3.fromRGB(133, 187, 101), -- Money green

  -- Status colors
  Success = Color3.fromRGB(100, 255, 100), -- Bright green
  Warning = Color3.fromRGB(255, 200, 100), -- Orange/yellow
  Danger = Color3.fromRGB(255, 100, 100), -- Red
  Info = Color3.fromRGB(100, 180, 255), -- Light blue

  -- Game-specific colors
  Shield = Color3.fromRGB(100, 200, 255), -- Shield protection blue
  XP = Color3.fromRGB(180, 130, 255), -- Purple for XP/level
  Health = Color3.fromRGB(255, 80, 80), -- Health bar red
  HealthBackground = Color3.fromRGB(80, 40, 40),

  -- Flash colors for animations
  FlashGain = Color3.fromRGB(100, 255, 100), -- Green flash on gain
  FlashLoss = Color3.fromRGB(255, 100, 100), -- Red flash on loss
}

-- Typography settings
Theme.Typography = {
  -- Font families
  Primary = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular),
  PrimaryBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
  PrimarySemiBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),

  -- Font sizes
  FontSizeXS = 12,
  FontSizeSM = 14,
  FontSizeMD = 16,
  FontSizeLG = 20,
  FontSizeXL = 24,
  FontSize2XL = 32,
  FontSize3XL = 40,

  -- Line heights
  LineHeightTight = 1.1,
  LineHeightNormal = 1.4,
  LineHeightRelaxed = 1.6,
}

-- Spacing scale (in pixels)
Theme.Spacing = {
  XS = 4,
  SM = 8,
  MD = 12,
  LG = 16,
  XL = 24,
  XXL = 32,
  XXXL = 48,
}

-- Corner radius
Theme.CornerRadius = {
  None = UDim.new(0, 0),
  SM = UDim.new(0, 4),
  MD = UDim.new(0, 8),
  LG = UDim.new(0, 12),
  XL = UDim.new(0, 16),
  Full = UDim.new(0.5, 0), -- Circular/pill shape
}

-- Shadow/stroke settings
Theme.Borders = {
  None = 0,
  Thin = 1,
  Medium = 2,
  Thick = 3,

  Color = Color3.fromRGB(60, 60, 80),
  ColorLight = Color3.fromRGB(80, 80, 100),
  ColorDark = Color3.fromRGB(20, 20, 30),
}

-- Animation settings
Theme.Animation = {
  -- Durations (in seconds)
  Fast = 0.1,
  Normal = 0.2,
  Slow = 0.3,

  -- Easing styles
  EaseOut = Enum.EasingStyle.Quad,
  EaseInOut = Enum.EasingStyle.Sine,
  Bounce = Enum.EasingStyle.Back,
}

-- Z-Index layers
Theme.ZIndex = {
  Base = 1,
  Elevated = 10,
  Overlay = 100,
  Modal = 1000,
  Toast = 10000,
}

-- Transparency values
Theme.Transparency = {
  Opaque = 0,
  Subtle = 0.1,
  Light = 0.3,
  Medium = 0.5,
  Heavy = 0.7,
  MostlyTransparent = 0.9,
  Transparent = 1,
}

-- Create OnyxUI theme configuration
function Theme.createOnyxTheme()
  return OnyxUI.Themer.NewTheme({
    Colors = {
      Primary = {
        Main = Theme.Colors.Primary,
      },
      Secondary = {
        Main = Theme.Colors.Secondary,
      },
      Neutral = {
        Main = Theme.Colors.Background,
      },
      Success = {
        Main = Theme.Colors.Success,
      },
      Warning = {
        Main = Theme.Colors.Warning,
      },
      Error = {
        Main = Theme.Colors.Danger,
      },
    },
    CornerRadius = Theme.CornerRadius.MD,
    TextSize = Theme.Typography.FontSizeMD,
    Font = Theme.Typography.Primary,
    FontWeight = Enum.FontWeight.Regular,
  })
end

return Theme
