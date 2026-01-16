--[[
	SectionLabels Module
	Creates and manages "<PlayerName>'s Base" labels above each player's section.
	Labels are visible to all players in the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

local SectionLabels = {}

-- Configuration
local LABEL_HEIGHT_OFFSET = 20 -- Studs above section center
local LABEL_SIZE = UDim2.new(0, 300, 0, 60)
local LABEL_MAX_DISTANCE = 150 -- Maximum visibility distance in studs
local LABEL_FONT_SIZE = 42

-- Visual styling
local LABEL_COLORS = {
  textColor = Color3.fromRGB(255, 255, 255),
  strokeColor = Color3.fromRGB(40, 40, 40),
  backgroundColor = Color3.fromRGB(0, 0, 0),
}

-- State: sectionIndex -> { part: Part, label: BillboardGui }
local sectionLabels: { [number]: { part: Part, gui: BillboardGui } } = {}

-- Labels folder in workspace
local labelsFolder: Folder? = nil

-- Get or create the labels folder
local function getLabelsFolder(): Folder
  if labelsFolder and labelsFolder.Parent then
    return labelsFolder
  end

  labelsFolder = Instance.new("Folder")
  labelsFolder.Name = "SectionLabels"
  labelsFolder.Parent = workspace

  return labelsFolder
end

-- Create the label part and BillboardGui for a section
local function createLabel(
  sectionIndex: number,
  sectionCenter: PlayerSection.Vector3
): { part: Part, gui: BillboardGui }
  local folder = getLabelsFolder()

  -- Create anchor part (invisible, just for BillboardGui positioning)
  local anchorPart = Instance.new("Part")
  anchorPart.Name = "SectionLabel_" .. sectionIndex
  anchorPart.Size = Vector3.new(1, 1, 1)
  anchorPart.Position =
    Vector3.new(sectionCenter.x, sectionCenter.y + LABEL_HEIGHT_OFFSET, sectionCenter.z)
  anchorPart.Transparency = 1
  anchorPart.Anchored = true
  anchorPart.CanCollide = false
  anchorPart.CanQuery = false
  anchorPart.CanTouch = false
  anchorPart.Parent = folder

  -- Create BillboardGui
  local billboardGui = Instance.new("BillboardGui")
  billboardGui.Name = "BaseLabel"
  billboardGui.Size = LABEL_SIZE
  billboardGui.StudsOffset = Vector3.new(0, 0, 0)
  billboardGui.AlwaysOnTop = false
  billboardGui.MaxDistance = LABEL_MAX_DISTANCE
  billboardGui.LightInfluence = 0
  billboardGui.Adornee = anchorPart
  billboardGui.Parent = anchorPart

  -- Create background frame with rounded corners (now fully transparent - no visible background)
  local backgroundFrame = Instance.new("Frame")
  backgroundFrame.Name = "Background"
  backgroundFrame.Size = UDim2.new(1, 0, 1, 0)
  backgroundFrame.BackgroundColor3 = LABEL_COLORS.backgroundColor
  backgroundFrame.BackgroundTransparency = 1 -- Fully transparent, no visible background
  backgroundFrame.BorderSizePixel = 0
  backgroundFrame.Parent = billboardGui

  -- UICorner no longer needed since background is transparent, but keep for structure
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = backgroundFrame

  -- Create text label
  local textLabel = Instance.new("TextLabel")
  textLabel.Name = "PlayerName"
  textLabel.Size = UDim2.new(1, 0, 1, 0)
  textLabel.Position = UDim2.new(0, 0, 0, 0)
  textLabel.BackgroundTransparency = 1
  textLabel.Text = "Unclaimed"
  textLabel.TextColor3 = LABEL_COLORS.textColor
  textLabel.TextStrokeColor3 = LABEL_COLORS.strokeColor
  textLabel.TextStrokeTransparency = 0
  textLabel.TextScaled = false
  textLabel.TextSize = LABEL_FONT_SIZE
  textLabel.Font = Enum.Font.GothamBold
  textLabel.TextXAlignment = Enum.TextXAlignment.Center
  textLabel.TextYAlignment = Enum.TextYAlignment.Center
  textLabel.Parent = backgroundFrame

  -- Add padding around text for better readability
  local padding = Instance.new("UIPadding")
  padding.PaddingLeft = UDim.new(0, 12)
  padding.PaddingRight = UDim.new(0, 12)
  padding.PaddingTop = UDim.new(0, 8)
  padding.PaddingBottom = UDim.new(0, 8)
  padding.Parent = textLabel

  -- Start hidden since section is initially unassigned
  billboardGui.Enabled = false

  return { part = anchorPart, gui = billboardGui }
end

-- Update label text for a section
local function updateLabelText(sectionIndex: number, displayName: string?)
  local labelData = sectionLabels[sectionIndex]
  if not labelData then
    return
  end

  local backgroundFrame = labelData.gui:FindFirstChild("Background")
  if not backgroundFrame then
    return
  end

  local textLabel = backgroundFrame:FindFirstChild("PlayerName") :: TextLabel?
  if not textLabel then
    return
  end

  if displayName then
    textLabel.Text = displayName .. "'s Base"
    textLabel.TextColor3 = LABEL_COLORS.textColor
    labelData.gui.Enabled = true
  else
    -- Hide label for unassigned sections instead of showing "Unclaimed"
    labelData.gui.Enabled = false
  end
end

-- Initialize labels for all sections
function SectionLabels.initialize(mapState: MapGeneration.MapState)
  -- Clean up any existing labels
  SectionLabels.cleanup()

  -- Create labels for all sections
  local maxSections = MapGeneration.getMaxSections()
  for sectionIndex = 1, maxSections do
    local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
    if sectionCenter then
      sectionLabels[sectionIndex] = createLabel(sectionIndex, sectionCenter)
    end
  end

  -- Update labels for any already-assigned sections
  local assignments = MapGeneration.getActiveAssignments(mapState)
  for _, assignment in ipairs(assignments) do
    local player = Players:GetPlayerByUserId(tonumber(assignment.playerId) or 0)
    if player then
      updateLabelText(assignment.sectionIndex, player.DisplayName)
    end
  end

  print("[SectionLabels] Initialized labels for", maxSections, "sections")
end

-- Handle player joining - update their section label
function SectionLabels.onPlayerJoined(player: Player, sectionIndex: number)
  updateLabelText(sectionIndex, player.DisplayName)
  print(
    string.format(
      "[SectionLabels] Set label for section %d: %s's Base",
      sectionIndex,
      player.DisplayName
    )
  )
end

-- Handle player leaving - reset their section label
function SectionLabels.onPlayerLeft(sectionIndex: number)
  updateLabelText(sectionIndex, nil)
  print(string.format("[SectionLabels] Reset label for section %d to Unclaimed", sectionIndex))
end

-- Get current label text for a section
function SectionLabels.getLabelText(sectionIndex: number): string?
  local labelData = sectionLabels[sectionIndex]
  if not labelData then
    return nil
  end

  local backgroundFrame = labelData.gui:FindFirstChild("Background")
  if not backgroundFrame then
    return nil
  end

  local textLabel = backgroundFrame:FindFirstChild("PlayerName") :: TextLabel?
  if not textLabel then
    return nil
  end

  return textLabel.Text
end

-- Clean up all labels
function SectionLabels.cleanup()
  for sectionIndex, labelData in pairs(sectionLabels) do
    if labelData.part and labelData.part.Parent then
      labelData.part:Destroy()
    end
  end
  sectionLabels = {}

  if labelsFolder and labelsFolder.Parent then
    labelsFolder:Destroy()
    labelsFolder = nil
  end
end

return SectionLabels
