--[[
	WeaponTool Module
	Creates proper Roblox Tool objects for weapons that use the native Backpack/Hotbar system.
	This allows weapons to be equipped via hotbar slots and provides standard Tool behavior.
]]

local WeaponTool = {}

-- Import dependencies
local WeaponConfig = require(script.Parent.WeaponConfig)

-- Type definitions
export type WeaponToolConfig = {
  weaponType: string,
  displayName: string,
  damage: number,
  swingCooldown: number,
  range: number,
}

-- Create the visual bat model for the Tool
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

-- Create weapon visual based on type
local function createWeaponVisual(weaponType: string): Part?
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

return WeaponTool
