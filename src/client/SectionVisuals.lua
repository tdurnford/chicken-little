--[[
	SectionVisuals Module
	Creates visual representations of player sections including:
	- Ground/floor
	- Coop spots (placement areas for chickens/eggs)
	- Section boundaries
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))

local SectionVisuals = {}

-- Visual configuration
local COLORS = {
  ground = Color3.fromRGB(76, 153, 76), -- Grass green
  coopFloor = Color3.fromRGB(139, 90, 43), -- Brown wood
  spotAvailable = Color3.fromRGB(100, 200, 100), -- Light green (available)
  spotOccupied = Color3.fromRGB(200, 100, 100), -- Light red (occupied)
  spotHighlight = Color3.fromRGB(255, 255, 150), -- Yellow highlight
  boundary = Color3.fromRGB(120, 80, 40), -- Fence brown
  coopBorder = Color3.fromRGB(80, 60, 30), -- Dark brown border
}

local TRANSPARENCY = {
  ground = 0,
  coopFloor = 0,
  spot = 0.3,
  spotBorder = 0,
  boundary = 0.3,
}

-- State
local sectionFolder: Folder? = nil
local spotParts: { [number]: BasePart } = {}
local currentSectionIndex: number? = nil
local storeInstance: Model? = nil

-- Create a part with common properties
local function createPart(
  name: string,
  size: Vector3,
  position: Vector3,
  color: Color3,
  transparency: number?
): Part
  local part = Instance.new("Part")
  part.Name = name
  part.Size = size
  part.Position = position
  part.Color = color
  part.Transparency = transparency or 0
  part.Anchored = true
  part.CanCollide = true
  part.Material = Enum.Material.SmoothPlastic
  part.TopSurface = Enum.SurfaceType.Smooth
  part.BottomSurface = Enum.SurfaceType.Smooth
  return part
end

-- Create the ground for a section
local function createGround(sectionCenter: PlayerSection.Vector3, parent: Instance)
  local sectionSize = PlayerSection.getSectionSize()

  local ground = createPart(
    "Ground",
    Vector3.new(sectionSize.x, 1, sectionSize.z),
    Vector3.new(sectionCenter.x, sectionCenter.y - 0.5, sectionCenter.z),
    COLORS.ground,
    TRANSPARENCY.ground
  )
  ground.Material = Enum.Material.Grass
  ground.Parent = parent

  return ground
end

-- Create the coop floor area
local function createCoopFloor(sectionCenter: PlayerSection.Vector3, parent: Instance)
  local coopSize = PlayerSection.getCoopSize()
  local coopCenter = PlayerSection.getCoopCenter(sectionCenter)

  local coopFloor = createPart(
    "CoopFloor",
    Vector3.new(coopSize.x + 4, 0.2, coopSize.z + 4),
    Vector3.new(coopCenter.x, sectionCenter.y + 0.1, coopCenter.z),
    COLORS.coopFloor,
    TRANSPARENCY.coopFloor
  )
  coopFloor.Material = Enum.Material.Wood
  coopFloor.Parent = parent

  -- Add border/outline
  local border = Instance.new("SelectionBox")
  border.Name = "CoopBorder"
  border.Adornee = coopFloor
  border.Color3 = COLORS.coopBorder
  border.LineThickness = 0.05
  border.Parent = coopFloor

  return coopFloor
end

-- Create a single coop spot visual
local function createSpotVisual(
  spotData: PlayerSection.SpotData,
  parent: Instance,
  occupied: boolean
): Part
  local color = occupied and COLORS.spotOccupied or COLORS.spotAvailable

  local spot = createPart(
    "Spot_" .. spotData.index,
    Vector3.new(spotData.size - 0.5, 0.3, spotData.size - 0.5),
    Vector3.new(spotData.position.x, spotData.position.y + 0.2, spotData.position.z),
    color,
    TRANSPARENCY.spot
  )
  spot.Material = Enum.Material.Neon
  spot.CanCollide = false

  -- Add number label
  local billboardGui = Instance.new("BillboardGui")
  billboardGui.Name = "SpotLabel"
  billboardGui.Size = UDim2.new(0, 40, 0, 40)
  billboardGui.StudsOffset = Vector3.new(0, 1.5, 0)
  billboardGui.AlwaysOnTop = false
  billboardGui.Parent = spot

  local label = Instance.new("TextLabel")
  label.Name = "Number"
  label.Size = UDim2.new(1, 0, 1, 0)
  label.BackgroundTransparency = 1
  label.Text = tostring(spotData.index)
  label.TextColor3 = Color3.new(1, 1, 1)
  label.TextScaled = true
  label.Font = Enum.Font.GothamBold
  label.Parent = billboardGui

  spot.Parent = parent

  return spot
end

-- Create all coop spots
local function createAllSpots(
  sectionCenter: PlayerSection.Vector3,
  parent: Instance,
  occupiedSpots: { [number]: boolean }?
)
  local spots = PlayerSection.getAllSpots(sectionCenter)
  local occupied = occupiedSpots or {}

  for _, spotData in ipairs(spots) do
    local isOccupied = occupied[spotData.index] or false
    local spotPart = createSpotVisual(spotData, parent, isOccupied)
    spotParts[spotData.index] = spotPart
  end
end

-- Create boundary walls (low fences)
local function createBoundaries(sectionCenter: PlayerSection.Vector3, parent: Instance)
  local boundaries = PlayerSection.getBoundaries(sectionCenter)

  for _, boundary in ipairs(boundaries) do
    -- Create a low fence instead of full wall
    local fenceHeight = 3
    local fence = createPart(
      "Fence_" .. boundary.side,
      Vector3.new(boundary.size.x, fenceHeight, boundary.size.z),
      Vector3.new(boundary.position.x, sectionCenter.y + fenceHeight / 2, boundary.position.z),
      COLORS.boundary,
      TRANSPARENCY.boundary
    )
    fence.Material = Enum.Material.WoodPlanks
    fence.Parent = parent
  end
end

-- Create spawn point marker
local function createSpawnMarker(sectionCenter: PlayerSection.Vector3, parent: Instance)
  local spawnPoint = PlayerSection.getSpawnPoint(sectionCenter)

  local marker = createPart(
    "SpawnMarker",
    Vector3.new(4, 0.2, 4),
    Vector3.new(spawnPoint.x, sectionCenter.y + 0.1, spawnPoint.z),
    Color3.fromRGB(100, 150, 255),
    0.5
  )
  marker.Material = Enum.Material.Neon
  marker.CanCollide = false
  marker.Shape = Enum.PartType.Cylinder
  marker.Orientation = Vector3.new(0, 0, 90)
  marker.Parent = parent

  return marker
end

-- Build the complete section visuals
function SectionVisuals.buildSection(sectionIndex: number, occupiedSpots: { [number]: boolean }?)
  -- Clear existing visuals
  SectionVisuals.clear()

  -- Get section position
  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if not sectionCenter then
    warn("[SectionVisuals] Invalid section index:", sectionIndex)
    return
  end

  currentSectionIndex = sectionIndex

  -- Create folder to hold all section parts
  sectionFolder = Instance.new("Folder")
  sectionFolder.Name = "PlayerSection_" .. sectionIndex
  sectionFolder.Parent = workspace

  -- Create all visual elements
  createGround(sectionCenter, sectionFolder)
  createCoopFloor(sectionCenter, sectionFolder)
  createAllSpots(sectionCenter, sectionFolder, occupiedSpots)
  createBoundaries(sectionCenter, sectionFolder)
  createSpawnMarker(sectionCenter, sectionFolder)

  print(string.format("[SectionVisuals] Built section %d visuals", sectionIndex))
end

-- Update spot occupancy visual
function SectionVisuals.updateSpotOccupancy(spotIndex: number, occupied: boolean)
  local spotPart = spotParts[spotIndex]
  if spotPart then
    spotPart.Color = occupied and COLORS.spotOccupied or COLORS.spotAvailable
  end
end

-- Update all spots based on placed chickens
function SectionVisuals.updateAllSpots(placedChickens: { { spotIndex: number? } }?)
  local occupied: { [number]: boolean } = {}

  if placedChickens then
    for _, chicken in ipairs(placedChickens) do
      if chicken.spotIndex then
        occupied[chicken.spotIndex] = true
      end
    end
  end

  for spotIndex, spotPart in pairs(spotParts) do
    local isOccupied = occupied[spotIndex] or false
    spotPart.Color = isOccupied and COLORS.spotOccupied or COLORS.spotAvailable
  end
end

-- Highlight a specific spot (for placement preview)
function SectionVisuals.highlightSpot(spotIndex: number?)
  for index, spotPart in pairs(spotParts) do
    if spotIndex and index == spotIndex then
      spotPart.Color = COLORS.spotHighlight
    else
      -- Reset to normal color (assume available for now)
      spotPart.Color = COLORS.spotAvailable
    end
  end
end

-- Get the current section index
function SectionVisuals.getCurrentSection(): number?
  return currentSectionIndex
end

-- Clear all section visuals
function SectionVisuals.clear()
  if sectionFolder then
    sectionFolder:Destroy()
    sectionFolder = nil
  end
  spotParts = {}
  currentSectionIndex = nil
end

-- Build the central store (only once per map)
function SectionVisuals.buildCentralStore()
  -- Only build once
  if storeInstance then
    return storeInstance
  end

  -- Look for the marketplace model in ReplicatedStorage or workspace
  local storeModel = ReplicatedStorage:FindFirstChild("ShopStandStoreMarketStallDisplayProps")
    or workspace:FindFirstChild("ShopStandStoreMarketStallDisplayProps")

  if not storeModel then
    warn("[SectionVisuals] Store model not found - ShopStandStoreMarketStallDisplayProps")
    return nil
  end

  -- Clone the model
  local storeClone = storeModel:Clone()
  storeClone.Name = "CentralStore"

  -- Position the store at the center of the map (origin)
  -- This is between all the player sections
  local config = MapGeneration.getConfig()
  local storePosition =
    Vector3.new(config.originPosition.x, config.originPosition.y + 3, config.originPosition.z)

  if storeClone:IsA("Model") and storeClone.PrimaryPart then
    storeClone:SetPrimaryPartCFrame(CFrame.new(storePosition))
  elseif storeClone:IsA("Model") then
    -- If no PrimaryPart, try to move by finding first BasePart
    local firstPart = storeClone:FindFirstChildWhichIsA("BasePart", true)
    if firstPart then
      local offset = storePosition - firstPart.Position
      for _, part in ipairs(storeClone:GetDescendants()) do
        if part:IsA("BasePart") then
          part.Position = part.Position + offset
        end
      end
    end
  end

  storeClone.Parent = workspace

  -- Add proximity prompt for interaction to the first part we find
  local counterPart = storeClone:FindFirstChildWhichIsA("BasePart", true)
  if counterPart then
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "StorePrompt"
    prompt.ActionText = "Shop"
    prompt.ObjectText = "Store"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.Parent = counterPart
  end

  -- Add store sign above the stall
  local signBoard = Instance.new("Part")
  signBoard.Name = "SignBoard"
  signBoard.Size = Vector3.new(8, 2.5, 0.3)
  signBoard.Position = Vector3.new(storePosition.X, storePosition.Y + 7, storePosition.Z)
  signBoard.Color = Color3.fromRGB(255, 215, 0)
  signBoard.Material = Enum.Material.SmoothPlastic
  signBoard.Anchored = true
  signBoard.CanCollide = false
  signBoard.Parent = storeClone

  -- Add sign text (front)
  local signGui = Instance.new("SurfaceGui")
  signGui.Name = "SignText"
  signGui.Face = Enum.NormalId.Front
  signGui.Parent = signBoard

  local signLabel = Instance.new("TextLabel")
  signLabel.Name = "Label"
  signLabel.Size = UDim2.new(1, 0, 1, 0)
  signLabel.BackgroundTransparency = 1
  signLabel.Text = "🏪 STORE"
  signLabel.TextColor3 = Color3.fromRGB(80, 40, 0)
  signLabel.TextScaled = true
  signLabel.Font = Enum.Font.GothamBold
  signLabel.Parent = signGui

  -- Add sign text (back)
  local signGuiBack = Instance.new("SurfaceGui")
  signGuiBack.Name = "SignTextBack"
  signGuiBack.Face = Enum.NormalId.Back
  signGuiBack.Parent = signBoard

  local signLabelBack = Instance.new("TextLabel")
  signLabelBack.Name = "Label"
  signLabelBack.Size = UDim2.new(1, 0, 1, 0)
  signLabelBack.BackgroundTransparency = 1
  signLabelBack.Text = "🏪 STORE"
  signLabelBack.TextColor3 = Color3.fromRGB(80, 40, 0)
  signLabelBack.TextScaled = true
  signLabelBack.Font = Enum.Font.GothamBold
  signLabelBack.Parent = signGuiBack

  storeInstance = storeClone
  print("[SectionVisuals] Central store built at map origin")

  return storeClone
end

-- Get the store instance
function SectionVisuals.getStore(): Model?
  return storeInstance
end

return SectionVisuals
