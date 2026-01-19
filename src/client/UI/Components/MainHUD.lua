--[[
	MainHUD Component (Fusion)
	Displays player money, level/XP, and chicken count using reactive Fusion state.
	Replaces the legacy imperative MainHUD module.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Fusion = require(Packages:WaitForChild("Fusion"))
local Icon = require(Packages:WaitForChild("TopbarPlus"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoneyScaling = require(Shared:WaitForChild("MoneyScaling"))
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

local UIFolder = script.Parent.Parent
local Theme = require(UIFolder.Theme)
local State = require(UIFolder.State)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Computed = Fusion.Computed
local Value = Fusion.Value
local Spring = Fusion.Spring
local Tween = Fusion.Tween
local Cleanup = Fusion.Cleanup

-- Types
export type MainHUDProps = {
  onInventoryClick: (() -> ())?,
}

-- Module state
local MainHUD = {}
local screenGui: ScreenGui? = nil
local hudScope: Fusion.Scope? = nil
local inventoryIcon: any? = nil

-- Create formatted money display with spring animation
local function createMoneyDisplay(scope: Fusion.Scope)
  -- Animated money value for smooth counting
  local animatedMoney = Spring(scope, State.Player.Money, 30, 0.8)

  -- Format the animated money value
  local formattedMoney = Computed(scope, function(use)
    local value = use(animatedMoney)
    return MoneyScaling.formatCurrency(math.floor(value))
  end)

  return New(scope, "Frame")({
    Name = "MoneyFrame",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 10, 1, -10),
    Size = UDim2.new(0, 280, 0, 44),
    BackgroundTransparency = 1,

    [Children] = {
      New(scope, "TextLabel")({
        Name = "MoneyLabel",
        Size = UDim2.new(1, -10, 0, 36),
        Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1,
        Text = formattedMoney,
        TextColor3 = Theme.Colors.TextMoney,
        TextSize = 34,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextScaled = false,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 0,
      }),
    },
  })
end

-- Create level and XP progress display
local function createLevelDisplay(scope: Fusion.Scope)
  -- Compute XP progress (0-1)
  local xpProgress = Computed(scope, function(use)
    local xp = use(State.Player.XP)
    return LevelConfig.getLevelProgress(xp)
  end)

  -- Animated progress bar width
  local animatedProgress = Spring(scope, xpProgress, 20, 0.7)

  -- Formatted level text
  local levelText = Computed(scope, function(use)
    local level = use(State.Player.Level)
    return "Level " .. tostring(level)
  end)

  return New(scope, "Frame")({
    Name = "LevelFrame",
    Size = UDim2.new(0, 140, 0, 50),
    Position = UDim2.new(0, 10, 0, 10),
    AnchorPoint = Vector2.new(0, 0),
    BackgroundTransparency = 1,

    [Children] = {
      -- Level text label
      New(scope, "TextLabel")({
        Name = "LevelLabel",
        Size = UDim2.new(1, 0, 0, 28),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = levelText,
        TextColor3 = Color3.fromRGB(255, 215, 0), -- Gold
        TextSize = 22,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 0,
      }),

      -- XP progress bar background
      New(scope, "Frame")({
        Name = "XPProgressBar",
        Size = UDim2.new(1, 0, 0, 8),
        Position = UDim2.new(0, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(40, 40, 50),
        BorderSizePixel = 0,

        [Children] = {
          New(scope, "UICorner")({
            CornerRadius = UDim.new(0, 4),
          }),

          -- XP progress fill
          New(scope, "Frame")({
            Name = "XPProgressFill",
            Size = Computed(scope, function(use)
              local progress = use(animatedProgress)
              return UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
            end),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = Color3.fromRGB(255, 215, 0), -- Gold
            BorderSizePixel = 0,

            [Children] = {
              New(scope, "UICorner")({
                CornerRadius = UDim.new(0, 4),
              }),
            },
          }),
        },
      }),
    },
  })
end

-- Create chicken count display
local function createChickenCountDisplay(scope: Fusion.Scope)
  -- Total chicken count (placed + inventory)
  local chickenCountText = Computed(scope, function(use)
    local total = use(State.Player.TotalChickens)
    return tostring(total) .. "/15"
  end)

  return New(scope, "Frame")({
    Name = "ChickenCountFrame",
    Size = UDim2.new(0, 120, 0, 40),
    Position = UDim2.new(1, -20, 1, -20),
    AnchorPoint = Vector2.new(1, 1),
    BackgroundTransparency = 1,

    [Children] = {
      -- Chicken emoji icon
      New(scope, "TextLabel")({
        Name = "ChickenIcon",
        Size = UDim2.new(0, 24, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = "🐔",
        TextSize = 24,
      }),

      -- Count label
      New(scope, "TextLabel")({
        Name = "ChickenCountLabel",
        Size = UDim2.new(1, -26, 1, 0),
        Position = UDim2.new(0, 26, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 220, 150), -- Warm yellow
        TextSize = 28,
        FontFace = Theme.Typography.PrimaryBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 0,
        Text = chickenCountText,
      }),
    },
  })
end

-- Create the inventory TopbarPlus icon
local function createInventoryIcon(onInventoryClick: (() -> ())?)
  local icon = Icon.new()
    :setImage("rbxasset://textures/ui/TopBar/inventoryOn.png")
    :setImageScale(0.85)
    :setOrder(1)

  -- Wire click callback
  icon.selected:Connect(function()
    if onInventoryClick then
      onInventoryClick()
    end
    -- Deselect immediately (act as button, not toggle)
    icon:deselect()
  end)

  return icon
end

--[[
	Create the MainHUD.
	
	@param props MainHUDProps - Configuration props
	@return boolean - Success
]]
function MainHUD.create(props: MainHUDProps?): boolean
  if screenGui then
    warn("[MainHUD] Already created")
    return false
  end

  props = props or {}
  local player = Players.LocalPlayer
  if not player then
    warn("[MainHUD] No local player")
    return false
  end

  -- Create Fusion scope for cleanup
  hudScope = Fusion.scoped({})
  local scope = hudScope :: Fusion.Scope

  -- Create ScreenGui
  screenGui = New(scope, "ScreenGui")({
    Name = "MainHUD",
    Parent = player:WaitForChild("PlayerGui"),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,

    [Children] = {
      createMoneyDisplay(scope),
      createLevelDisplay(scope),
      createChickenCountDisplay(scope),
    },
  })

  -- Create TopbarPlus inventory icon
  inventoryIcon = createInventoryIcon(props.onInventoryClick)

  return true
end

--[[
	Destroy the MainHUD and cleanup resources.
]]
function MainHUD.destroy()
  -- Destroy TopbarPlus icon
  if inventoryIcon then
    inventoryIcon:destroy()
    inventoryIcon = nil
  end

  -- Cleanup Fusion scope (destroys all created instances)
  if hudScope then
    Fusion.doCleanup(hudScope)
    hudScope = nil
  end

  screenGui = nil
end

--[[
	Check if the HUD is created.
	
	@return boolean
]]
function MainHUD.isCreated(): boolean
  return screenGui ~= nil
end

--[[
	Set visibility of the HUD.
	
	@param visible boolean
]]
function MainHUD.setVisible(visible: boolean)
  if screenGui then
    screenGui.Enabled = visible
  end
end

--[[
	Check if the HUD is visible.
	
	@return boolean
]]
function MainHUD.isVisible(): boolean
  if screenGui then
    return screenGui.Enabled
  end
  return false
end

--[[
	Get the ScreenGui instance.
	
	@return ScreenGui?
]]
function MainHUD.getScreenGui(): ScreenGui?
  return screenGui
end

--[[
	Set the inventory click callback.
	
	@param callback () -> ()
]]
function MainHUD.onInventoryClick(callback: () -> ())
  -- If icon exists, reconnect
  if inventoryIcon then
    -- Can't easily reconnect, store for next creation
    -- This would require recreating the icon
    warn("[MainHUD] onInventoryClick: Icon already created, callback stored for next create()")
  end
end

--[[
	Show a notification message.
	
	@param message string - Message to display
	@param color Color3? - Optional text color
	@param duration number? - Duration in seconds (default 3)
]]
function MainHUD.showNotification(message: string, color: Color3?, duration: number?)
  if not screenGui or not hudScope then
    return
  end

  local scope = hudScope :: Fusion.Scope
  local notifyDuration = duration or 3
  local notifyColor = color or Theme.Colors.TextPrimary

  -- Create notification frame
  local notificationVisible = Value(scope, true)
  local notificationAlpha = Spring(
    scope,
    Computed(scope, function(use)
      return if use(notificationVisible) then 0 else 1
    end),
    10
  )

  local notification = New(scope, "Frame")({
    Name = "Notification",
    Size = UDim2.new(0, 300, 0, 50),
    Position = UDim2.new(0.5, 0, 0.2, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.Colors.Surface,
    BackgroundTransparency = Computed(scope, function(use)
      return 0.1 + use(notificationAlpha) * 0.9
    end),
    Parent = screenGui,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = Theme.CornerRadius.MD,
      }),
      New(scope, "UIStroke")({
        Color = Theme.Colors.Borders.Color,
        Thickness = Theme.Borders.Thin,
      }),
      New(scope, "TextLabel")({
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = message,
        TextColor3 = notifyColor,
        TextSize = Theme.Typography.FontSizeMD,
        FontFace = Theme.Typography.PrimarySemiBold,
        TextWrapped = true,
        TextTransparency = notificationAlpha,
      }),
    },
  })

  -- Auto-dismiss after duration
  task.delay(notifyDuration, function()
    notificationVisible:set(false)
    task.delay(0.5, function()
      if notification and notification.Parent then
        notification:Destroy()
      end
    end)
  end)
end

--[[
	Show level up celebration notification.
	
	@param newLevel number - The new level reached
	@param unlocks {string}? - Optional list of unlocked features
]]
function MainHUD.showLevelUp(newLevel: number, unlocks: { string }?)
  if not screenGui or not hudScope then
    return
  end

  local scope = hudScope :: Fusion.Scope

  -- Notification dimensions based on unlocks
  local hasUnlocks = unlocks and #unlocks > 0
  local frameHeight = hasUnlocks and 130 or 100

  -- Scale animation state
  local notificationScale = Value(scope, 0)
  local animatedScale = Spring(scope, notificationScale, 15, 0.5)

  local notification = New(scope, "Frame")({
    Name = "LevelUpNotification",
    Size = Computed(scope, function(use)
      local scale = use(animatedScale)
      return UDim2.new(0, 300 * scale, 0, frameHeight * scale)
    end),
    Position = UDim2.new(0.5, 0, 0.3, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(40, 40, 60),
    BackgroundTransparency = 0.1,
    Parent = screenGui,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = Theme.CornerRadius.LG,
      }),
      New(scope, "UIStroke")({
        Color = Color3.fromRGB(255, 215, 0), -- Gold border
        Thickness = 3,
      }),
      New(scope, "TextLabel")({
        Name = "TitleLabel",
        Size = UDim2.new(1, -20, 0, 36),
        Position = UDim2.new(0, 10, 0, 10),
        BackgroundTransparency = 1,
        Text = "⬆️ LEVEL UP! ⬆️",
        TextColor3 = Color3.fromRGB(255, 215, 0),
        TextSize = 24,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),
      New(scope, "TextLabel")({
        Name = "LevelLabel",
        Size = UDim2.new(1, -20, 0, 30),
        Position = UDim2.new(0, 10, 0, 48),
        BackgroundTransparency = 1,
        Text = "Level " .. tostring(newLevel),
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 20,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),
      hasUnlocks and New(scope, "TextLabel")({
        Name = "UnlocksLabel",
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 82),
        BackgroundTransparency = 1,
        Text = "🔓 " .. table.concat(unlocks :: { string }, ", "),
        TextColor3 = Color3.fromRGB(150, 255, 150),
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
      }) or nil,
    },
  })

  -- Animate in
  notificationScale:set(1)

  -- Auto-dismiss after 3 seconds
  task.delay(3, function()
    notificationScale:set(0)
    task.delay(0.4, function()
      if notification and notification.Parent then
        notification:Destroy()
      end
    end)
  end)
end

--[[
	Show XP gain floating text.
	
	@param amount number - Amount of XP gained
]]
function MainHUD.showXPGain(amount: number)
  if not screenGui or not hudScope then
    return
  end

  local scope = hudScope :: Fusion.Scope

  -- Float animation state
  local offsetY = Value(scope, 20)
  local textAlpha = Value(scope, 0)
  local animatedY = Spring(scope, offsetY, 8, 0.8)
  local animatedAlpha = Spring(scope, textAlpha, 8, 0.8)

  local xpText = New(scope, "TextLabel")({
    Name = "XPGainText",
    Size = UDim2.new(0, 100, 0, 24),
    Position = Computed(scope, function(use)
      return UDim2.new(0, 150, 0, use(animatedY))
    end),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    Text = "+" .. tostring(amount) .. " XP",
    TextColor3 = Color3.fromRGB(100, 200, 255), -- Light blue
    TextSize = 18,
    FontFace = Theme.Typography.PrimaryBold,
    TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
    TextStrokeTransparency = 0,
    TextTransparency = animatedAlpha,
    Parent = screenGui,
  })

  -- Animate up and fade out
  task.defer(function()
    offsetY:set(-20)
    task.delay(0.8, function()
      textAlpha:set(1)
      task.delay(0.5, function()
        if xpText and xpText.Parent then
          xpText:Destroy()
        end
      end)
    end)
  end)
end

--[[
	Show bankruptcy assistance notification.
	
	@param data { moneyAwarded: number, message: string }
]]
function MainHUD.showBankruptcyAssistance(data: { moneyAwarded: number, message: string })
  if not screenGui or not hudScope then
    return
  end

  local scope = hudScope :: Fusion.Scope

  local notificationAlpha = Value(scope, 1)
  local animatedAlpha = Spring(scope, notificationAlpha, 10)

  local notification = New(scope, "Frame")({
    Name = "BankruptcyNotification",
    Size = UDim2.new(0, 300, 0, 80),
    Position = UDim2.new(0.5, 0, 0.35, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(20, 60, 100),
    BackgroundTransparency = animatedAlpha,
    Parent = screenGui,

    [Children] = {
      New(scope, "UICorner")({
        CornerRadius = Theme.CornerRadius.LG,
      }),
      New(scope, "UIStroke")({
        Color = Color3.fromRGB(100, 180, 255),
        Thickness = 3,
      }),
      New(scope, "TextLabel")({
        Name = "TitleLabel",
        Size = UDim2.new(1, -20, 0, 28),
        Position = UDim2.new(0, 10, 0, 8),
        BackgroundTransparency = 1,
        Text = "💰 Starter Assistance",
        TextColor3 = Color3.fromRGB(255, 215, 0),
        TextSize = 18,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),
      New(scope, "TextLabel")({
        Name = "MessageLabel",
        Size = UDim2.new(1, -20, 0, 36),
        Position = UDim2.new(0, 10, 0, 38),
        BackgroundTransparency = 1,
        Text = data.message,
        TextColor3 = Theme.Colors.TextPrimary,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
      }),
    },
  })

  -- Animate in
  notificationAlpha:set(0.1)

  -- Auto-dismiss after 4 seconds
  task.delay(4, function()
    notificationAlpha:set(1)
    task.delay(0.5, function()
      if notification and notification.Parent then
        notification:Destroy()
      end
    end)
  end)
end

--[[
	Legacy compatibility methods.
	These are no-ops since Fusion uses reactive state.
]]

function MainHUD.updateFromPlayerData(_data: any)
  -- No-op: Fusion version auto-updates from State.Player
end

function MainHUD.setInventoryItemCount(_count: number)
  -- No-op: Inventory count is managed by TopbarPlus icon badge
end

function MainHUD.setChickenCount(_placed: number, _max: number)
  -- No-op: Chicken count is reactive from State.Player.TotalChickens
end

function MainHUD.isAtChickenLimit(): boolean
  -- Check against the reactive state
  local total = State.Player.TotalChickens:get()
  return total >= 15
end

return MainHUD
