--[[
	AdminConfig Module
	Defines admin user IDs and permissions for server management.
	Add admin UserIds to the ADMIN_USER_IDS table to grant admin privileges.
]]

local AdminConfig = {}

-- Type definitions
export type AdminPermission = "kick" | "ban" | "resetdata" | "giveitem" | "all"

export type AdminEntry = {
  userId: number,
  name: string,
  permissions: { AdminPermission },
}

-- List of admin user IDs
-- Add your admin UserIds here
local ADMIN_ENTRIES: { AdminEntry } = {
  -- Example: { userId = 123456789, name = "GameOwner", permissions = { "all" } },
}

-- Quick lookup table for admin UserIds
local adminUserIdSet: { [number]: boolean } = {}
local adminPermissions: { [number]: { [AdminPermission]: boolean } } = {}

-- Build lookup tables from entries
for _, entry in ipairs(ADMIN_ENTRIES) do
  adminUserIdSet[entry.userId] = true
  adminPermissions[entry.userId] = {}

  for _, perm in ipairs(entry.permissions) do
    if perm == "all" then
      adminPermissions[entry.userId]["kick"] = true
      adminPermissions[entry.userId]["ban"] = true
      adminPermissions[entry.userId]["resetdata"] = true
      adminPermissions[entry.userId]["giveitem"] = true
      adminPermissions[entry.userId]["all"] = true
    else
      adminPermissions[entry.userId][perm] = true
    end
  end
end

-- Check if a user ID is an admin
function AdminConfig.isAdmin(userId: number): boolean
  return adminUserIdSet[userId] == true
end

-- Check if a user has a specific permission
function AdminConfig.hasPermission(userId: number, permission: AdminPermission): boolean
  local perms = adminPermissions[userId]
  if not perms then
    return false
  end
  return perms[permission] == true or perms["all"] == true
end

-- Get all permissions for an admin
function AdminConfig.getPermissions(userId: number): { AdminPermission }
  local perms = adminPermissions[userId]
  if not perms then
    return {}
  end

  local result: { AdminPermission } = {}
  for perm, hasIt in pairs(perms) do
    if hasIt then
      table.insert(result, perm)
    end
  end
  return result
end

-- Get admin name by userId
function AdminConfig.getAdminName(userId: number): string?
  for _, entry in ipairs(ADMIN_ENTRIES) do
    if entry.userId == userId then
      return entry.name
    end
  end
  return nil
end

-- Get count of configured admins
function AdminConfig.getAdminCount(): number
  return #ADMIN_ENTRIES
end

-- Get all admin entries (for display purposes)
function AdminConfig.getAdminEntries(): { AdminEntry }
  return table.clone(ADMIN_ENTRIES)
end

-- Validate that an admin entry is properly configured
function AdminConfig.validateEntry(entry: AdminEntry): boolean
  if type(entry.userId) ~= "number" or entry.userId <= 0 then
    return false
  end
  if type(entry.name) ~= "string" or #entry.name == 0 then
    return false
  end
  if type(entry.permissions) ~= "table" or #entry.permissions == 0 then
    return false
  end
  return true
end

return AdminConfig
