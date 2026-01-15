--[[
	Tutorial Module
	Guides new players through basic mechanics using visual arrows.
	Simplified to: Go to store -> Buy egg -> Place/hatch chicken -> Done
]]

local Tutorial = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Get shared modules path
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

-- Get client modules
local ClientModules = script.Parent
local SectionVisuals = require(ClientModules:WaitForChild("SectionVisuals"))

-- Type definitions
export type TutorialStep = {
  id: string,
  title: string,
  message: string,
  icon: string?,
  action: string?, -- Optional action description (e.g., "Press E")
  waitForAction: boolean?, -- Wait for player to complete action
  duration: number?, -- Auto-advance duration if no action required
  targetPosition: Vector3?, -- Position for arrow to point to
}

export type TutorialConfig = {
  steps: { TutorialStep },
  skipEnabled: boolean,
  autoAdvanceDelay: number,
}

export type TutorialState = {
  screenGui: ScreenGui?,
  mainFrame: Frame?,
  arrowPart: Part?,
  arrowBillboard: BillboardGui?,
  arrowUpdateConnection: RBXScriptConnection?,
  currentStepIndex: number,
  isActive: boolean,
  isPaused: boolean,
  onComplete: (() -> ())?,
  onSkip: (() -> ())?,
  onStepComplete: ((stepId: string) -> ())?,
  inputConnection: RBXScriptConnection?,
  advanceConnection: RBXScriptConnection?,
}

-- Get store position from map config
local function getStorePosition(): Vector3
  local config = MapGeneration.getConfig()
  return Vector3.new(config.originPosition.x, config.originPosition.y + 3, config.originPosition.z)
end

-- Get player's coop center position from their assigned section
local function getPlayerCoopCenter(): Vector3?
  local sectionIndex = SectionVisuals.getCurrentSection()
  if not sectionIndex then
    return nil
  end

  -- Get section position from MapGeneration
  local sectionPos = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionPos then
    return nil
  end

  -- Coop is offset towards back of section (matches COOP_OFFSET_Z in PlayerSection)
  local coopOffsetX = 0 -- centered
  local coopOffsetZ = -10 -- towards back of section

  -- Return coop center position (slightly elevated for arrow visibility)
  return Vector3.new(sectionPos.x + coopOffsetX, sectionPos.y + 3, sectionPos.z + coopOffsetZ)
end

-- Simplified tutorial steps: buy egg, place it, done
local TUTORIAL_STEPS: { TutorialStep } = {
  {
    id = "buy_egg",
    title = "Buy an Egg!",
    message = "Go to the store and buy your first egg.",
    icon = "🏪",
    action = "Press E at the store",
    waitForAction = true,
    targetPosition = getStorePosition(),
  },
  {
    id = "place_egg",
    title = "Place Your Egg!",
    message = "Walk to your coop and place the egg.",
    icon = "🥚",
    action = "Walk near a coop spot",
    waitForAction = true,
    -- targetPosition set dynamically based on player section
  },
  {
    id = "complete",
    title = "Great Job!",
    message = "Your chicken is hatching! Keep buying eggs and growing your farm.",
    icon = "🎉",
    duration = 4,
  },
}

-- Default configuration
local DEFAULT_CONFIG: TutorialConfig = {
  steps = TUTORIAL_STEPS,
  skipEnabled = true,
  autoAdvanceDelay = 4,
}

-- Animation settings
local FADE_IN_DURATION = 0.3
local SLIDE_IN_DURATION = 0.35
local STEP_TRANSITION_DURATION = 0.25

-- Module state
local state: TutorialState = {
  screenGui = nil,
  mainFrame = nil,
  arrowPart = nil,
  arrowBillboard = nil,
  arrowUpdateConnection = nil,
  currentStepIndex = 0,
  isActive = false,
  isPaused = false,
  onComplete = nil,
  onSkip = nil,
  onStepComplete = nil,
  inputConnection = nil,
  advanceConnection = nil,
}

local currentConfig: TutorialConfig = DEFAULT_CONFIG

-- Create the screen GUI
local function createScreenGui(player: Player): ScreenGui
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "TutorialUI"
  screenGui.ResetOnSpawn = false
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.IgnoreGuiInset = false
  screenGui.DisplayOrder = 100 -- Above most UIs
  screenGui.Parent = player:WaitForChild("PlayerGui")
  return screenGui
end

-- Create the main tutorial frame
local function createMainFrame(parent: ScreenGui): Frame
  local frame = Instance.new("Frame")
  frame.Name = "TutorialFrame"
  frame.AnchorPoint = Vector2.new(0.5, 1)
  frame.Position = UDim2.new(0.5, 0, 1, -20)
  frame.Size = UDim2.new(0, 450, 0, 140)
  frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
  frame.BackgroundTransparency = 0.1
  frame.BorderSizePixel = 0
  frame.Visible = false
  frame.Parent = parent

  -- Rounded corners
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 14)
  corner.Parent = frame

  -- Border stroke
  local stroke = Instance.new("UIStroke")
  stroke.Color = Color3.fromRGB(100, 180, 255)
  stroke.Thickness = 2
  stroke.Transparency = 0.3
  stroke.Parent = frame

  return frame
end

-- Create icon label
local function createIconLabel(parent: Frame): TextLabel
  local icon = Instance.new("TextLabel")
  icon.Name = "IconLabel"
  icon.Size = UDim2.new(0, 50, 0, 50)
  icon.Position = UDim2.new(0, 15, 0, 15)
  icon.BackgroundTransparency = 1
  icon.Text = "🐔"
  icon.TextSize = 36
  icon.TextColor3 = Color3.fromRGB(255, 255, 255)
  icon.Parent = parent
  return icon
end

-- Create title label
local function createTitleLabel(parent: Frame): TextLabel
  local title = Instance.new("TextLabel")
  title.Name = "TitleLabel"
  title.Size = UDim2.new(1, -90, 0, 28)
  title.Position = UDim2.new(0, 75, 0, 12)
  title.BackgroundTransparency = 1
  title.Text = "Tutorial"
  title.TextSize = 20
  title.TextColor3 = Color3.fromRGB(255, 255, 255)
  title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.TextTruncate = Enum.TextTruncate.AtEnd
  title.Parent = parent
  return title
end

-- Create message label
local function createMessageLabel(parent: Frame): TextLabel
  local message = Instance.new("TextLabel")
  message.Name = "MessageLabel"
  message.Size = UDim2.new(1, -90, 0, 48)
  message.Position = UDim2.new(0, 75, 0, 40)
  message.BackgroundTransparency = 1
  message.Text = ""
  message.TextSize = 14
  message.TextColor3 = Color3.fromRGB(200, 200, 220)
  message.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
  message.TextXAlignment = Enum.TextXAlignment.Left
  message.TextYAlignment = Enum.TextYAlignment.Top
  message.TextWrapped = true
  message.Parent = parent
  return message
end

-- Create action hint label
local function createActionLabel(parent: Frame): TextLabel
  local action = Instance.new("TextLabel")
  action.Name = "ActionLabel"
  action.Size = UDim2.new(1, -90, 0, 20)
  action.Position = UDim2.new(0, 75, 1, -30)
  action.BackgroundTransparency = 1
  action.Text = ""
  action.TextSize = 12
  action.TextColor3 = Color3.fromRGB(100, 180, 255)
  action.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  action.TextXAlignment = Enum.TextXAlignment.Left
  action.Parent = parent
  return action
end

-- Create skip button
local function createSkipButton(parent: Frame): TextButton
  local button = Instance.new("TextButton")
  button.Name = "SkipButton"
  button.Size = UDim2.new(0, 60, 0, 26)
  button.Position = UDim2.new(1, -70, 0, 10)
  button.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
  button.Text = "Skip"
  button.TextSize = 12
  button.TextColor3 = Color3.fromRGB(180, 180, 200)
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.Parent = parent

  local buttonCorner = Instance.new("UICorner")
  buttonCorner.CornerRadius = UDim.new(0, 6)
  buttonCorner.Parent = button

  button.MouseButton1Click:Connect(function()
    Tutorial.skip()
  end)

  return button
end

-- Create continue button (for steps without action requirement)
local function createContinueButton(parent: Frame): TextButton
  local button = Instance.new("TextButton")
  button.Name = "ContinueButton"
  button.Size = UDim2.new(0, 100, 0, 30)
  button.Position = UDim2.new(1, -115, 1, -45)
  button.BackgroundColor3 = Color3.fromRGB(80, 140, 200)
  button.Text = "Continue →"
  button.TextSize = 14
  button.TextColor3 = Color3.fromRGB(255, 255, 255)
  button.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
  button.BorderSizePixel = 0
  button.AutoButtonColor = true
  button.Visible = false
  button.Parent = parent

  local buttonCorner = Instance.new("UICorner")
  buttonCorner.CornerRadius = UDim.new(0, 8)
  buttonCorner.Parent = button

  button.MouseButton1Click:Connect(function()
    Tutorial.nextStep()
  end)

  return button
end

-- Create progress dots
local function createProgressDots(parent: Frame, totalSteps: number): Frame
  local container = Instance.new("Frame")
  container.Name = "ProgressDots"
  container.Size = UDim2.new(0, totalSteps * 14, 0, 10)
  container.Position = UDim2.new(0.5, 0, 1, -15)
  container.AnchorPoint = Vector2.new(0.5, 0)
  container.BackgroundTransparency = 1
  container.Parent = parent

  local layout = Instance.new("UIListLayout")
  layout.FillDirection = Enum.FillDirection.Horizontal
  layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  layout.Padding = UDim.new(0, 6)
  layout.Parent = container

  for i = 1, totalSteps do
    local dot = Instance.new("Frame")
    dot.Name = "Dot_" .. i
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    dot.BorderSizePixel = 0
    dot.Parent = container

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = dot
  end

  return container
end

-- Create 3D arrow that points to objectives
local function createArrowIndicator(): Part
  local player = Players.LocalPlayer
  local arrow = Instance.new("Part")
  arrow.Name = "TutorialArrow"
  arrow.Size = Vector3.new(2, 0.5, 3)
  arrow.Color = Color3.fromRGB(100, 180, 255)
  arrow.Material = Enum.Material.Neon
  arrow.Transparency = 0.3
  arrow.Anchored = true
  arrow.CanCollide = false
  arrow.CastShadow = false
  arrow.Parent = workspace

  -- Create a special mesh to make it look like an arrow
  local mesh = Instance.new("SpecialMesh")
  mesh.MeshType = Enum.MeshType.Wedge
  mesh.Scale = Vector3.new(1, 1, 1)
  mesh.Parent = arrow

  -- Add billboard with text above the arrow
  local billboard = Instance.new("BillboardGui")
  billboard.Name = "ArrowLabel"
  billboard.Size = UDim2.new(0, 200, 0, 50)
  billboard.StudsOffset = Vector3.new(0, 3, 0)
  billboard.AlwaysOnTop = true
  billboard.Parent = arrow

  local label = Instance.new("TextLabel")
  label.Name = "Text"
  label.Size = UDim2.new(1, 0, 1, 0)
  label.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
  label.BackgroundTransparency = 0.2
  label.TextColor3 = Color3.fromRGB(255, 255, 255)
  label.TextScaled = true
  label.Font = Enum.Font.GothamBold
  label.Text = "Go here!"
  label.Parent = billboard

  local labelCorner = Instance.new("UICorner")
  labelCorner.CornerRadius = UDim.new(0, 8)
  labelCorner.Parent = label

  state.arrowPart = arrow
  state.arrowBillboard = billboard
  return arrow
end

-- Update arrow position and rotation to point toward target
local function updateArrowPosition(targetPos: Vector3?)
  if not state.arrowPart then
    return
  end
  if not targetPos then
    state.arrowPart.Transparency = 1
    return
  end

  local player = Players.LocalPlayer
  local character = player and player.Character
  local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

  if not rootPart then
    state.arrowPart.Transparency = 1
    return
  end

  -- Position arrow above and in front of player
  local playerPos = rootPart.Position
  local direction = (targetPos - playerPos).Unit
  local arrowPos = playerPos + Vector3.new(0, 5, 0) + direction * 3

  -- Point arrow toward target (rotate around Y axis)
  local lookAt = CFrame.lookAt(arrowPos, targetPos)
  -- Rotate 90 degrees on X axis since wedge points "up" by default
  state.arrowPart.CFrame = lookAt * CFrame.Angles(math.rad(90), 0, 0)
  state.arrowPart.Transparency = 0.3
end

-- Start arrow update loop
local function startArrowUpdates()
  if state.arrowUpdateConnection then
    state.arrowUpdateConnection:Disconnect()
  end

  state.arrowUpdateConnection = RunService.Heartbeat:Connect(function()
    if not state.isActive or state.isPaused then
      return
    end

    local currentStep = currentConfig.steps[state.currentStepIndex]
    if currentStep and currentStep.targetPosition then
      updateArrowPosition(currentStep.targetPosition)
    else
      updateArrowPosition(nil)
    end
  end)
end

-- Stop arrow updates and hide arrow
local function stopArrowUpdates()
  if state.arrowUpdateConnection then
    state.arrowUpdateConnection:Disconnect()
    state.arrowUpdateConnection = nil
  end

  if state.arrowPart then
    state.arrowPart:Destroy()
    state.arrowPart = nil
  end
end

-- Set arrow label text
local function setArrowLabel(text: string)
  if not state.arrowPart then
    return
  end
  local billboard = state.arrowPart:FindFirstChild("ArrowLabel") :: BillboardGui?
  if billboard then
    local label = billboard:FindFirstChild("Text") :: TextLabel?
    if label then
      label.Text = text
    end
  end
end

-- Update progress dots
local function updateProgressDots(stepIndex: number)
  if not state.mainFrame then
    return
  end

  local dotsContainer = state.mainFrame:FindFirstChild("ProgressDots")
  if not dotsContainer then
    return
  end

  for i = 1, #currentConfig.steps do
    local dot = dotsContainer:FindFirstChild("Dot_" .. i)
    if dot then
      if i < stepIndex then
        dot.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
      elseif i == stepIndex then
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
      else
        dot.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
      end
    end
  end
end

-- Update UI for current step
local function updateStepUI(step: TutorialStep)
  if not state.mainFrame then
    return
  end

  local iconLabel = state.mainFrame:FindFirstChild("IconLabel") :: TextLabel?
  local titleLabel = state.mainFrame:FindFirstChild("TitleLabel") :: TextLabel?
  local messageLabel = state.mainFrame:FindFirstChild("MessageLabel") :: TextLabel?
  local actionLabel = state.mainFrame:FindFirstChild("ActionLabel") :: TextLabel?
  local continueButton = state.mainFrame:FindFirstChild("ContinueButton") :: TextButton?

  if iconLabel then
    iconLabel.Text = step.icon or "📖"
  end
  if titleLabel then
    titleLabel.Text = step.title
  end
  if messageLabel then
    messageLabel.Text = step.message
  end
  if actionLabel then
    if step.action then
      actionLabel.Text = "▶ " .. step.action
      actionLabel.Visible = true
    else
      actionLabel.Text = ""
      actionLabel.Visible = false
    end
  end
  if continueButton then
    -- Show continue button only for non-action steps
    continueButton.Visible = not step.waitForAction
  end

  -- Update arrow label based on step
  if step.targetPosition then
    setArrowLabel(step.title)
  end

  updateProgressDots(state.currentStepIndex)
end

-- Animate step transition
local function animateStepTransition(callback: () -> ())
  if not state.mainFrame then
    callback()
    return
  end

  -- Fade out current content
  local tweenOut = TweenService:Create(
    state.mainFrame,
    TweenInfo.new(STEP_TRANSITION_DURATION / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { BackgroundTransparency = 0.5 }
  )
  tweenOut:Play()

  tweenOut.Completed:Connect(function()
    callback()

    -- Fade in new content
    TweenService
      :Create(
        state.mainFrame,
        TweenInfo.new(STEP_TRANSITION_DURATION / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.1 }
      )
      :Play()
  end)
end

-- Show the tutorial frame
local function showFrame()
  if not state.mainFrame then
    return
  end

  state.mainFrame.Visible = true
  state.mainFrame.Position = UDim2.new(0.5, 0, 1, 150)

  TweenService:Create(
    state.mainFrame,
    TweenInfo.new(SLIDE_IN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Position = UDim2.new(0.5, 0, 1, -20) }
  ):Play()
end

-- Hide the tutorial frame
local function hideFrame(callback: (() -> ())?)
  if not state.mainFrame then
    if callback then
      callback()
    end
    return
  end

  local tween = TweenService:Create(
    state.mainFrame,
    TweenInfo.new(SLIDE_IN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
    { Position = UDim2.new(0.5, 0, 1, 150) }
  )
  tween:Play()

  tween.Completed:Connect(function()
    if state.mainFrame then
      state.mainFrame.Visible = false
    end
    if callback then
      callback()
    end
  end)
end

-- Setup auto-advance timer for non-action steps
local function setupAutoAdvance(duration: number)
  if state.advanceConnection then
    state.advanceConnection:Disconnect()
    state.advanceConnection = nil
  end

  local startTime = tick()
  state.advanceConnection = game:GetService("RunService").Heartbeat:Connect(function()
    if not state.isActive or state.isPaused then
      return
    end

    if tick() - startTime >= duration then
      if state.advanceConnection then
        state.advanceConnection:Disconnect()
        state.advanceConnection = nil
      end
      Tutorial.nextStep()
    end
  end)
end

-- Initialize the tutorial UI
function Tutorial.create(config: TutorialConfig?): boolean
  local player = Players.LocalPlayer
  if not player then
    warn("Tutorial: No LocalPlayer found")
    return false
  end

  -- Clean up existing UI
  Tutorial.destroy()

  currentConfig = config or DEFAULT_CONFIG

  -- Create UI elements
  state.screenGui = createScreenGui(player)
  state.mainFrame = createMainFrame(state.screenGui)

  createIconLabel(state.mainFrame)
  createTitleLabel(state.mainFrame)
  createMessageLabel(state.mainFrame)
  createActionLabel(state.mainFrame)

  if currentConfig.skipEnabled then
    createSkipButton(state.mainFrame)
  end

  createContinueButton(state.mainFrame)
  createProgressDots(state.mainFrame, #currentConfig.steps)

  -- Create 3D arrow indicator
  createArrowIndicator()

  state.isActive = false
  state.currentStepIndex = 0

  return true
end

-- Destroy the tutorial UI
function Tutorial.destroy()
  if state.inputConnection then
    state.inputConnection:Disconnect()
    state.inputConnection = nil
  end

  if state.advanceConnection then
    state.advanceConnection:Disconnect()
    state.advanceConnection = nil
  end

  -- Clean up arrow
  stopArrowUpdates()

  if state.screenGui then
    state.screenGui:Destroy()
  end

  state.screenGui = nil
  state.mainFrame = nil
  state.arrowPart = nil
  state.arrowBillboard = nil
  state.currentStepIndex = 0
  state.isActive = false
  state.isPaused = false
  state.onComplete = nil
  state.onSkip = nil
  state.onStepComplete = nil
end

-- Start the tutorial
function Tutorial.start()
  if not state.screenGui or not state.mainFrame then
    warn("Tutorial: UI not created. Call create() first.")
    return
  end

  if state.isActive then
    return
  end

  state.isActive = true
  state.isPaused = false
  state.currentStepIndex = 1

  -- Start arrow updates
  startArrowUpdates()

  local firstStep = currentConfig.steps[1]
  if firstStep then
    updateStepUI(firstStep)
    showFrame()

    if not firstStep.waitForAction and firstStep.duration then
      setupAutoAdvance(firstStep.duration)
    end
  end
end

-- Go to next step
function Tutorial.nextStep()
  if not state.isActive or state.isPaused then
    return
  end

  -- Notify step completion
  local currentStep = currentConfig.steps[state.currentStepIndex]
  if currentStep and state.onStepComplete then
    state.onStepComplete(currentStep.id)
  end

  state.currentStepIndex = state.currentStepIndex + 1

  if state.currentStepIndex > #currentConfig.steps then
    Tutorial.complete()
    return
  end

  local nextStep = currentConfig.steps[state.currentStepIndex]
  if nextStep then
    -- Dynamically set targetPosition for place_egg step
    if nextStep.id == "place_egg" and not nextStep.targetPosition then
      local coopCenter = getPlayerCoopCenter()
      if coopCenter then
        nextStep.targetPosition = coopCenter
      end
    end

    animateStepTransition(function()
      updateStepUI(nextStep)

      if not nextStep.waitForAction and nextStep.duration then
        setupAutoAdvance(nextStep.duration)
      end
    end)
  end
end

-- Complete a specific step (for external triggers)
function Tutorial.completeStep(stepId: string)
  if not state.isActive or state.isPaused then
    return
  end

  local currentStep = currentConfig.steps[state.currentStepIndex]
  if currentStep and currentStep.id == stepId and currentStep.waitForAction then
    Tutorial.nextStep()
  end
end

-- Skip the tutorial
function Tutorial.skip()
  if not state.isActive then
    return
  end

  state.isActive = false

  if state.advanceConnection then
    state.advanceConnection:Disconnect()
    state.advanceConnection = nil
  end

  -- Stop arrow updates
  stopArrowUpdates()

  hideFrame(function()
    if state.onSkip then
      state.onSkip()
    end
  end)
end

-- Complete the tutorial
function Tutorial.complete()
  if not state.isActive then
    return
  end

  state.isActive = false

  if state.advanceConnection then
    state.advanceConnection:Disconnect()
    state.advanceConnection = nil
  end

  -- Stop arrow updates
  stopArrowUpdates()

  hideFrame(function()
    if state.onComplete then
      state.onComplete()
    end
  end)
end

-- Pause the tutorial
function Tutorial.pause()
  state.isPaused = true
end

-- Resume the tutorial
function Tutorial.resume()
  state.isPaused = false
end

-- Check if tutorial is active
function Tutorial.isActive(): boolean
  return state.isActive
end

-- Check if tutorial is paused
function Tutorial.isPaused(): boolean
  return state.isPaused
end

-- Check if tutorial is created
function Tutorial.isCreated(): boolean
  return state.screenGui ~= nil and state.mainFrame ~= nil
end

-- Get current step index
function Tutorial.getCurrentStepIndex(): number
  return state.currentStepIndex
end

-- Get current step
function Tutorial.getCurrentStep(): TutorialStep?
  if state.currentStepIndex > 0 and state.currentStepIndex <= #currentConfig.steps then
    return currentConfig.steps[state.currentStepIndex]
  end
  return nil
end

-- Get total steps
function Tutorial.getTotalSteps(): number
  return #currentConfig.steps
end

-- Set callback for tutorial completion
function Tutorial.onComplete(callback: () -> ())
  state.onComplete = callback
end

-- Set callback for tutorial skip
function Tutorial.onSkip(callback: () -> ())
  state.onSkip = callback
end

-- Set callback for step completion
function Tutorial.onStepComplete(callback: (stepId: string) -> ())
  state.onStepComplete = callback
end

-- Check if player should see tutorial (new player detection)
function Tutorial.shouldShowTutorial(playerData: PlayerData.PlayerDataSchema?): boolean
  if not playerData then
    return true
  end
  return playerData.tutorialComplete ~= true
end

-- Get default tutorial steps
function Tutorial.getDefaultSteps(): { TutorialStep }
  local copy = {}
  for i, step in ipairs(TUTORIAL_STEPS) do
    copy[i] = {
      id = step.id,
      title = step.title,
      message = step.message,
      icon = step.icon,
      action = step.action,
      waitForAction = step.waitForAction,
      duration = step.duration,
    }
  end
  return copy
end

-- Get default configuration
function Tutorial.getDefaultConfig(): TutorialConfig
  return {
    steps = Tutorial.getDefaultSteps(),
    skipEnabled = DEFAULT_CONFIG.skipEnabled,
    autoAdvanceDelay = DEFAULT_CONFIG.autoAdvanceDelay,
  }
end

return Tutorial
