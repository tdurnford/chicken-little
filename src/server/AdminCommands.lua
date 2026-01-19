--[[
	AdminCommands Module
	Handles admin commands for server management including kick, ban, and data reset.
	All admin actions are logged for accountability.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AdminConfig = require(Shared:WaitForChild("AdminConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

local AdminCommands = {}

-- Type definitions
export type AdminAction = "kick" | "ban" | "resetdata" | "giveitem" | "warn"

export type AdminLogEntry = {
  timestamp: number,
  adminUserId: number,
  adminName: string,
  action: AdminAction,
  targetUserId: number?,
  targetName: string?,
  details: string,
  success: boolean,
}

export type CommandResult = {
  success: boolean,
  message: string,
}

-- In-memory log storage (persists for session only)
local actionLog: { AdminLogEntry } = {}
local MAX_LOG_ENTRIES = 1000

-- Banned players (session-only, would need DataStore for persistence)
local bannedUserIds: { [number]: boolean } = {}

-- ProfileManager reference (set via init)
local ProfileManager: any = nil

-- Log an admin action
local function logAction(
  adminUserId: number,
  adminName: string,
  action: AdminAction,
  targetUserId: number?,
  targetName: string?,
  details: string,
  success: boolean
): ()
  local entry: AdminLogEntry = {
    timestamp = os.time(),
    adminUserId = adminUserId,
    adminName = adminName,
    action = action,
    targetUserId = targetUserId,
    targetName = targetName,
    details = details,
    success = success,
  }

  table.insert(actionLog, entry)

  -- Trim old entries if log is too large
  while #actionLog > MAX_LOG_ENTRIES do
    table.remove(actionLog, 1)
  end

  -- Print to server console for immediate visibility
  local targetStr = targetName and (" on " .. targetName) or ""
  local statusStr = success and "SUCCESS" or "FAILED"
  print(
    string.format(
      "[AdminLog] [%s] %s performed %s%s: %s",
      statusStr,
      adminName,
      action,
      targetStr,
      details
    )
  )
end

-- Validate admin has permission for action
local function validateAdmin(
  adminPlayer: Player,
  permission: AdminConfig.AdminPermission
): (boolean, string)
  local userId = adminPlayer.UserId

  if not AdminConfig.isAdmin(userId) then
    return false, "You are not an admin"
  end

  if not AdminConfig.hasPermission(userId, permission) then
    return false, "You don't have permission for this action"
  end

  return true, "Authorized"
end

-- Find player by name or partial name
local function findPlayer(nameOrPartial: string): Player?
  local lowerName = string.lower(nameOrPartial)

  -- Try exact match first
  for _, player in ipairs(Players:GetPlayers()) do
    if string.lower(player.Name) == lowerName then
      return player
    end
  end

  -- Try partial match
  for _, player in ipairs(Players:GetPlayers()) do
    if string.find(string.lower(player.Name), lowerName, 1, true) then
      return player
    end
  end

  return nil
end

-- Initialize the module with ProfileManager reference
function AdminCommands.init(profileManager: any): ()
  ProfileManager = profileManager
  print("[AdminCommands] Initialized")
end

-- Kick a player from the server
function AdminCommands.kick(adminPlayer: Player, targetName: string, reason: string?): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "kick")
  if not authorized then
    return { success = false, message = authMsg }
  end

  local targetPlayer = findPlayer(targetName)
  if not targetPlayer then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "kick",
      nil,
      targetName,
      "Player not found: " .. targetName,
      false
    )
    return { success = false, message = "Player not found: " .. targetName }
  end

  -- Don't allow kicking other admins
  if AdminConfig.isAdmin(targetPlayer.UserId) then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "kick",
      targetPlayer.UserId,
      targetPlayer.Name,
      "Cannot kick another admin",
      false
    )
    return { success = false, message = "Cannot kick another admin" }
  end

  local kickReason = reason or "Kicked by admin"
  local details = string.format("Reason: %s", kickReason)

  logAction(
    adminPlayer.UserId,
    adminPlayer.Name,
    "kick",
    targetPlayer.UserId,
    targetPlayer.Name,
    details,
    true
  )

  targetPlayer:Kick(kickReason)

  return { success = true, message = "Kicked " .. targetPlayer.Name }
end

-- Ban a player (session-only ban)
function AdminCommands.ban(adminPlayer: Player, targetName: string, reason: string?): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "ban")
  if not authorized then
    return { success = false, message = authMsg }
  end

  local targetPlayer = findPlayer(targetName)
  if not targetPlayer then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "ban",
      nil,
      targetName,
      "Player not found: " .. targetName,
      false
    )
    return { success = false, message = "Player not found: " .. targetName }
  end

  -- Don't allow banning other admins
  if AdminConfig.isAdmin(targetPlayer.UserId) then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "ban",
      targetPlayer.UserId,
      targetPlayer.Name,
      "Cannot ban another admin",
      false
    )
    return { success = false, message = "Cannot ban another admin" }
  end

  local banReason = reason or "Banned by admin"
  local details = string.format("Reason: %s", banReason)

  -- Add to banned list
  bannedUserIds[targetPlayer.UserId] = true

  logAction(
    adminPlayer.UserId,
    adminPlayer.Name,
    "ban",
    targetPlayer.UserId,
    targetPlayer.Name,
    details,
    true
  )

  -- Kick with ban message
  targetPlayer:Kick("You have been banned: " .. banReason)

  return { success = true, message = "Banned " .. targetPlayer.Name }
end

-- Reset a player's data
function AdminCommands.resetData(adminPlayer: Player, targetName: string): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "resetdata")
  if not authorized then
    return { success = false, message = authMsg }
  end

  local targetPlayer = findPlayer(targetName)
  if not targetPlayer then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "resetdata",
      nil,
      targetName,
      "Player not found: " .. targetName,
      false
    )
    return { success = false, message = "Player not found: " .. targetName }
  end

  -- Don't allow resetting other admin's data
  if AdminConfig.isAdmin(targetPlayer.UserId) and targetPlayer.UserId ~= adminPlayer.UserId then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "resetdata",
      targetPlayer.UserId,
      targetPlayer.Name,
      "Cannot reset another admin's data",
      false
    )
    return { success = false, message = "Cannot reset another admin's data" }
  end

  if not ProfileManager then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "resetdata",
      targetPlayer.UserId,
      targetPlayer.Name,
      "ProfileManager not initialized",
      false
    )
    return { success = false, message = "Data system not available" }
  end

  -- Create fresh default data
  local newData = PlayerData.createDefault()
  local success = ProfileManager.updateData(targetPlayer.UserId, newData)

  if not success then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "resetdata",
      targetPlayer.UserId,
      targetPlayer.Name,
      "Failed to update data cache",
      false
    )
    return { success = false, message = "Failed to reset data" }
  end

  -- ProfileService auto-saves on profile release, no explicit save needed
  local details = "Data reset successfully"
  logAction(
    adminPlayer.UserId,
    adminPlayer.Name,
    "resetdata",
    targetPlayer.UserId,
    targetPlayer.Name,
    details,
    true
  )

  return {
    success = true,
    message = "Reset data for " .. targetPlayer.Name,
  }
end

-- Give money to a player
function AdminCommands.giveMoney(
  adminPlayer: Player,
  targetName: string,
  amount: number
): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "giveitem")
  if not authorized then
    return { success = false, message = authMsg }
  end

  if amount <= 0 or amount > 1000000 then
    return { success = false, message = "Invalid amount (1-1000000)" }
  end

  local targetPlayer = findPlayer(targetName)
  if not targetPlayer then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "giveitem",
      nil,
      targetName,
      "Player not found: " .. targetName,
      false
    )
    return { success = false, message = "Player not found: " .. targetName }
  end

  if not ProfileManager then
    return { success = false, message = "Data system not available" }
  end

  local playerData = ProfileManager.getData(targetPlayer.UserId)
  if not playerData then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "giveitem",
      targetPlayer.UserId,
      targetPlayer.Name,
      "No player data found",
      false
    )
    return { success = false, message = "Player data not found" }
  end

  playerData.money = (playerData.money or 0) + amount
  ProfileManager.updateData(targetPlayer.UserId, playerData)

  local details = string.format("Gave $%d", amount)
  logAction(
    adminPlayer.UserId,
    adminPlayer.Name,
    "giveitem",
    targetPlayer.UserId,
    targetPlayer.Name,
    details,
    true
  )

  return { success = true, message = string.format("Gave $%d to %s", amount, targetPlayer.Name) }
end

-- Warn a player (sends a message)
function AdminCommands.warn(adminPlayer: Player, targetName: string, message: string): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "kick") -- Use kick permission for warn
  if not authorized then
    return { success = false, message = authMsg }
  end

  local targetPlayer = findPlayer(targetName)
  if not targetPlayer then
    logAction(
      adminPlayer.UserId,
      adminPlayer.Name,
      "warn",
      nil,
      targetName,
      "Player not found: " .. targetName,
      false
    )
    return { success = false, message = "Player not found: " .. targetName }
  end

  local details = string.format("Warning: %s", message)
  logAction(
    adminPlayer.UserId,
    adminPlayer.Name,
    "warn",
    targetPlayer.UserId,
    targetPlayer.Name,
    details,
    true
  )

  -- Note: In a full implementation, this would fire a RemoteEvent to show warning UI
  -- For now, we just log it
  return { success = true, message = "Warned " .. targetPlayer.Name }
end

-- Check if a user is banned
function AdminCommands.isBanned(userId: number): boolean
  return bannedUserIds[userId] == true
end

-- Unban a user
function AdminCommands.unban(adminPlayer: Player, userId: number): CommandResult
  local authorized, authMsg = validateAdmin(adminPlayer, "ban")
  if not authorized then
    return { success = false, message = authMsg }
  end

  if not bannedUserIds[userId] then
    return { success = false, message = "User is not banned" }
  end

  bannedUserIds[userId] = nil

  local details = string.format("Unbanned userId %d", userId)
  logAction(adminPlayer.UserId, adminPlayer.Name, "ban", userId, nil, details, true)

  return { success = true, message = "Unbanned user ID " .. tostring(userId) }
end

-- Get recent admin log entries
function AdminCommands.getLog(count: number?): { AdminLogEntry }
  local requestedCount = count or 50
  local result: { AdminLogEntry } = {}

  local startIndex = math.max(1, #actionLog - requestedCount + 1)
  for i = startIndex, #actionLog do
    table.insert(result, actionLog[i])
  end

  return result
end

-- Get log entries for a specific admin
function AdminCommands.getLogByAdmin(adminUserId: number, count: number?): { AdminLogEntry }
  local requestedCount = count or 50
  local result: { AdminLogEntry } = {}

  for i = #actionLog, 1, -1 do
    if actionLog[i].adminUserId == adminUserId then
      table.insert(result, 1, actionLog[i])
      if #result >= requestedCount then
        break
      end
    end
  end

  return result
end

-- Get list of currently banned user IDs
function AdminCommands.getBannedUsers(): { number }
  local result: { number } = {}
  for userId, _ in pairs(bannedUserIds) do
    table.insert(result, userId)
  end
  return result
end

-- Get online players list (for admin UI)
function AdminCommands.getOnlinePlayers(): { { userId: number, name: string, isAdmin: boolean } }
  local result: { { userId: number, name: string, isAdmin: boolean } } = {}

  for _, player in ipairs(Players:GetPlayers()) do
    table.insert(result, {
      userId = player.UserId,
      name = player.Name,
      isAdmin = AdminConfig.isAdmin(player.UserId),
    })
  end

  return result
end

-- Get admin status info for a player
function AdminCommands.getAdminStatus(player: Player): {
  isAdmin: boolean,
  permissions: { AdminConfig.AdminPermission },
}
  local userId = player.UserId
  return {
    isAdmin = AdminConfig.isAdmin(userId),
    permissions = AdminConfig.getPermissions(userId),
  }
end

return AdminCommands
