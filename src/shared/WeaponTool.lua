--[[
	WeaponTool Module
	Creates proper Roblox Tool objects for weapons that use the native Backpack/Hotbar system.
	This allows weapons to be equipped via hotbar slots and provides standard Tool behavior.
	
	Weapons can use 3D models from the Roblox marketplace (via modelAssetId in WeaponConfig)
	or fall back to programmatically-created models.
]]

local WeaponTool = {}

-- Import dependencies
local WeaponConfig = require(script.Parent.WeaponConfig)

-- Services
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

-- Type definitions
export type WeaponToolConfig = {
  weaponType: string,
  displayName: string,
  damage: number,
  swingCooldown: number,
  range: number,
}

-- Try to load a 3D model from Roblox asset ID
local function loadModelFromAsset(assetId: number): Part?
  -- InsertService only works on server
  if not RunService:IsServer() then
    return nil
  end

  local success, result = pcall(function()
    return InsertService:LoadAsset(assetId)
  end)

  if not success or not result then
    warn("[WeaponTool] Failed to load asset:", assetId, result)
    return nil
  end

  -- The loaded asset is a Model container; find the actual model inside
  local model = result:FindFirstChildWhichIsA("Model") or result:FindFirstChildWhichIsA("BasePart")
  if not model then
    -- Try to find any child that could be the weapon
    for _, child in ipairs(result:GetChildren()) do
      if child:IsA("Model") or child:IsA("BasePart") then
        model = child
        break
      end
    end
  end

  if not model then
    warn("[WeaponTool] No model found in asset:", assetId)
    result:Destroy()
    return nil
  end

  -- Extract the model from the container
  model.Parent = nil
  result:Destroy()

  -- Find or create the Handle part (required for Tool)
  local handle: Part?
  if model:IsA("Model") then
    handle = model:FindFirstChild("Handle") :: Part?
    if not handle then
      -- Look for any part named Handle or the PrimaryPart
      handle = model.PrimaryPart :: Part?
      if not handle then
        -- Use the first BasePart as handle
        handle = model:FindFirstChildWhichIsA("BasePart") :: Part?
      end
      if handle then
        handle.Name = "Handle"
      end
    end

    -- Ensure all parts are properly configured for Tool usage
    for _, part in ipairs(model:GetDescendants()) do
      if part:IsA("BasePart") then
        part.CanCollide = false
        part.Anchored = false
      end
    end

    -- If model has multiple parts, weld them to handle and return handle with children
    if handle then
      -- Move all non-handle parts to be children of handle
      for _, child in ipairs(model:GetChildren()) do
        if child ~= handle then
          child.Parent = handle
        end
      end
      model:Destroy()
      return handle
    end
  elseif model:IsA("BasePart") then
    model.Name = "Handle"
    model.CanCollide = false
    model.Anchored = false
    return model :: Part
  end

  return nil
end

-- Create the visual bat model for the Tool (fallback programmatic version)
local function createBatModel(): { handle: Part, barrel: Part }
  -- Bat handle (this will be the Tool's Handle - required by Roblox)
  local handle = Instance.new("Part")
  handle.Name = "Handle" -- Must be named "Handle" for Roblox Tool system
  handle.Size = Vector3.new(0.3, 1.2, 0.3)
  handle.BrickColor = BrickColor.new("Dark orange")
  handle.Material = Enum.Material.Wood
  handle.CanCollide = false
  handle.Anchored = false

  -- Bat barrel (main hitting part)
  local barrel = Instance.new("Part")
  barrel.Name = "Barrel"
  barrel.Size = Vector3.new(0.4, 2.5, 0.4)
  barrel.BrickColor = BrickColor.new("Brown")
  barrel.Material = Enum.Material.Wood
  barrel.CanCollide = false
  barrel.Anchored = false

  -- Weld barrel to handle
  local weld = Instance.new("Weld")
  weld.Part0 = handle
  weld.Part1 = barrel
  weld.C0 = CFrame.new(0, 1.85, 0) -- Barrel above handle
  weld.Parent = handle

  barrel.Parent = handle -- Barrel is child of handle for organization

  return {
    handle = handle,
    barrel = barrel,
  }
end

-- Create the visual sword model for the Tool
local function createSwordModel(): { handle: Part }
  local handle = Instance.new("Part")
  handle.Name = "Handle"
  handle.Size = Vector3.new(0.2, 1.0, 0.2)
  handle.BrickColor = BrickColor.new("Dark stone grey")
  handle.Material = Enum.Material.Metal
  handle.CanCollide = false
  handle.Anchored = false

  -- Blade
  local blade = Instance.new("Part")
  blade.Name = "Blade"
  blade.Size = Vector3.new(0.1, 3.0, 0.4)
  blade.BrickColor = BrickColor.new("Medium stone grey")
  blade.Material = Enum.Material.Metal
  blade.CanCollide = false
  blade.Anchored = false

  -- Weld blade to handle
  local weld = Instance.new("Weld")
  weld.Part0 = handle
  weld.Part1 = blade
  weld.C0 = CFrame.new(0, 2.0, 0)
  weld.Parent = handle

  blade.Parent = handle

  return {
    handle = handle,
  }
end

-- Create the visual axe model for the Tool
local function createAxeModel(): { handle: Part }
  local handle = Instance.new("Part")
  handle.Name = "Handle"
  handle.Size = Vector3.new(0.25, 2.0, 0.25)
  handle.BrickColor = BrickColor.new("Reddish brown")
  handle.Material = Enum.Material.Wood
  handle.CanCollide = false
  handle.Anchored = false

  -- Axe head
  local axeHead = Instance.new("Part")
  axeHead.Name = "AxeHead"
  axeHead.Size = Vector3.new(0.15, 0.8, 1.2)
  axeHead.BrickColor = BrickColor.new("Medium stone grey")
  axeHead.Material = Enum.Material.Metal
  axeHead.CanCollide = false
  axeHead.Anchored = false

  -- Weld axe head to handle
  local weld = Instance.new("Weld")
  weld.Part0 = handle
  weld.Part1 = axeHead
  weld.C0 = CFrame.new(0, 1.3, 0.4)
  weld.Parent = handle

  axeHead.Parent = handle

  return {
    handle = handle,
  }
end

-- Create weapon visual based on type (tries 3D model first, falls back to programmatic)
local function createWeaponVisual(weaponType: string): Part?
  local config = WeaponConfig.get(weaponType)

  -- Try to load 3D model from asset if available
  if config and config.modelAssetId then
    local assetHandle = loadModelFromAsset(config.modelAssetId)
    if assetHandle then
      print("[WeaponTool] Loaded 3D model for:", weaponType, "from asset:", config.modelAssetId)
      return assetHandle
    end
    -- Fall through to programmatic creation if asset loading failed
    print("[WeaponTool] Asset load failed, using programmatic model for:", weaponType)
  end

  -- Fallback to programmatic models
  if weaponType == "BaseballBat" then
    local model = createBatModel()
    return model.handle
  elseif weaponType == "Sword" then
    local model = createSwordModel()
    return model.handle
  elseif weaponType == "Axe" then
    local model = createAxeModel()
    return model.handle
  end
  return nil
end

-- Create a Roblox Tool for a weapon type
function WeaponTool.create(weaponType: string): Tool?
  local config = WeaponConfig.get(weaponType)
  if not config then
    warn("[WeaponTool] Invalid weapon type:", weaponType)
    return nil
  end

  -- Create the Tool instance
  local tool = Instance.new("Tool")
  tool.Name = weaponType
  tool.RequiresHandle = true
  tool.CanBeDropped = false -- Players can't drop weapons

  -- Set Tool tip for UI display
  tool.ToolTip = config.displayName

  -- Create the weapon visual (handle is required)
  local handle = createWeaponVisual(weaponType)
  if not handle then
    warn("[WeaponTool] Failed to create visual for:", weaponType)
    tool:Destroy()
    return nil
  end
  handle.Parent = tool

  -- Store weapon config as attributes for easy access
  tool:SetAttribute("WeaponType", weaponType)
  tool:SetAttribute("Damage", config.damage)
  tool:SetAttribute("SwingCooldown", config.swingCooldownSeconds)
  tool:SetAttribute("Range", config.swingRangeStuds)
  tool:SetAttribute("DisplayName", config.displayName)

  return tool
end

-- Give a weapon Tool to a player's Backpack
function WeaponTool.giveToPlayer(player: Player, weaponType: string): Tool?
  local backpack = player:FindFirstChild("Backpack")
  if not backpack then
    warn("[WeaponTool] Player has no Backpack:", player.Name)
    return nil
  end

  -- Check if player already has this weapon in Backpack or equipped
  local existing = backpack:FindFirstChild(weaponType)
  if existing then
    return existing :: Tool
  end

  -- Also check if it's currently equipped (in character)
  local character = player.Character
  if character then
    local equipped = character:FindFirstChild(weaponType)
    if equipped and equipped:IsA("Tool") then
      return equipped :: Tool
    end
  end

  -- Create and give the tool
  local tool = WeaponTool.create(weaponType)
  if not tool then
    return nil
  end

  tool.Parent = backpack
  print("[WeaponTool] Gave", weaponType, "to", player.Name)
  return tool
end

-- Remove a weapon Tool from a player
function WeaponTool.removeFromPlayer(player: Player, weaponType: string): boolean
  local backpack = player:FindFirstChild("Backpack")
  local character = player.Character

  local removed = false

  -- Check Backpack
  if backpack then
    local tool = backpack:FindFirstChild(weaponType)
    if tool then
      tool:Destroy()
      removed = true
    end
  end

  -- Check Character (if equipped)
  if character then
    local tool = character:FindFirstChild(weaponType)
    if tool then
      tool:Destroy()
      removed = true
    end
  end

  if removed then
    print("[WeaponTool] Removed", weaponType, "from", player.Name)
  end
  return removed
end

-- Check if a player has a weapon Tool
function WeaponTool.playerHasTool(player: Player, weaponType: string): boolean
  local backpack = player:FindFirstChild("Backpack")
  local character = player.Character

  if backpack and backpack:FindFirstChild(weaponType) then
    return true
  end

  if character and character:FindFirstChild(weaponType) then
    return true
  end

  return false
end

-- Get the currently equipped weapon Tool for a player
function WeaponTool.getEquippedWeapon(player: Player): Tool?
  local character = player.Character
  if not character then
    return nil
  end

  for _, child in ipairs(character:GetChildren()) do
    if child:IsA("Tool") and child:GetAttribute("WeaponType") then
      return child
    end
  end

  return nil
end

-- Get the weapon type of an equipped tool
function WeaponTool.getWeaponType(tool: Tool): string?
  return tool:GetAttribute("WeaponType")
end

-- Restore all owned weapons to a player's Backpack
function WeaponTool.restoreOwnedWeapons(player: Player, ownedWeapons: { string }): number
  local count = 0
  for _, weaponType in ipairs(ownedWeapons) do
    if WeaponConfig.isValid(weaponType) then
      local tool = WeaponTool.giveToPlayer(player, weaponType)
      if tool then
        count = count + 1
      end
    end
  end
  return count
end

-- Check if a weapon type uses a 3D model asset
function WeaponTool.uses3DModel(weaponType: string): boolean
  local config = WeaponConfig.get(weaponType)
  return config ~= nil and config.modelAssetId ~= nil
end

-- Get the model asset ID for a weapon (nil if using programmatic model)
function WeaponTool.getModelAssetId(weaponType: string): number?
  local config = WeaponConfig.get(weaponType)
  return config and config.modelAssetId
end

return WeaponTool
