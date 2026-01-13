--[[
	TradeExchange Module
	Handles the actual exchange of eggs and chickens between players during trades.
	Manages item validation, locking, transfer, and edge case handling.
]]

local TradeExchange = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)

-- Type definitions
export type TradeItem = {
  itemType: "egg" | "chicken",
  itemId: string,
  itemData: any,
}

export type TradeOffer = {
  items: { TradeItem },
  confirmed: boolean,
}

export type TradeSession = {
  tradeId: string,
  player1Id: number,
  player2Id: number,
  player1Offer: TradeOffer,
  player2Offer: TradeOffer,
  status: "pending" | "locked" | "completed" | "cancelled",
  lockedItems: { [string]: boolean },
  startTime: number,
  lockTime: number?,
}

export type TransferResult = {
  success: boolean,
  message: string,
  player1ItemsReceived: { TradeItem }?,
  player2ItemsReceived: { TradeItem }?,
}

export type ValidationResult = {
  isValid: boolean,
  message: string,
  missingItems: { string }?,
}

export type LockResult = {
  success: boolean,
  message: string,
}

-- Configuration
local TRADE_TIMEOUT = 300 -- 5 minutes max trade duration
local LOCK_TIMEOUT = 10 -- 10 seconds to complete after locking

-- Storage for active trade sessions
local activeSessions: { [string]: TradeSession } = {}

-- Generate unique trade ID
function TradeExchange.generateTradeId(): string
  return "trade_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

-- Create a new trade session
function TradeExchange.createSession(player1Id: number, player2Id: number): TradeSession
  local session: TradeSession = {
    tradeId = TradeExchange.generateTradeId(),
    player1Id = player1Id,
    player2Id = player2Id,
    player1Offer = { items = {}, confirmed = false },
    player2Offer = { items = {}, confirmed = false },
    status = "pending",
    lockedItems = {},
    startTime = os.time(),
    lockTime = nil,
  }
  activeSessions[session.tradeId] = session
  return session
end

-- Get an active trade session by ID
function TradeExchange.getSession(tradeId: string): TradeSession?
  return activeSessions[tradeId]
end

-- Get active session for a player
function TradeExchange.getPlayerSession(playerId: number): TradeSession?
  for _, session in pairs(activeSessions) do
    if session.status ~= "completed" and session.status ~= "cancelled" then
      if session.player1Id == playerId or session.player2Id == playerId then
        return session
      end
    end
  end
  return nil
end

-- Check if an item is locked in any trade
function TradeExchange.isItemLocked(itemId: string): boolean
  for _, session in pairs(activeSessions) do
    if session.status == "locked" and session.lockedItems[itemId] then
      return true
    end
  end
  return false
end

-- Find item in player inventory (eggs or chickens)
local function findItemInInventory(
  playerDataSchema: PlayerData.PlayerDataSchema,
  itemId: string,
  itemType: "egg" | "chicken"
): (any?, number?)
  if itemType == "egg" then
    for i, egg in ipairs(playerDataSchema.inventory.eggs) do
      if egg.id == itemId then
        return egg, i
      end
    end
  elseif itemType == "chicken" then
    -- Check inventory chickens
    for i, chicken in ipairs(playerDataSchema.inventory.chickens) do
      if chicken.id == itemId then
        return chicken, i
      end
    end
    -- Check placed chickens
    for i, chicken in ipairs(playerDataSchema.placedChickens) do
      if chicken.id == itemId then
        return chicken, i
      end
    end
  end
  return nil, nil
end

-- Validate that a player owns all items in their offer
function TradeExchange.validateOffer(
  playerData: PlayerData.PlayerDataSchema,
  offer: TradeOffer
): ValidationResult
  local missingItems: { string } = {}

  for _, item in ipairs(offer.items) do
    local found = findItemInInventory(playerData, item.itemId, item.itemType)
    if not found then
      table.insert(missingItems, item.itemId)
    end
  end

  if #missingItems > 0 then
    return {
      isValid = false,
      message = string.format("Missing %d item(s) from inventory", #missingItems),
      missingItems = missingItems,
    }
  end

  return {
    isValid = true,
    message = "All items validated",
    missingItems = nil,
  }
end

-- Validate both offers in a trade session
function TradeExchange.validateSession(
  session: TradeSession,
  player1Data: PlayerData.PlayerDataSchema,
  player2Data: PlayerData.PlayerDataSchema
): ValidationResult
  -- Check session status
  if session.status == "completed" then
    return {
      isValid = false,
      message = "Trade already completed",
      missingItems = nil,
    }
  end

  if session.status == "cancelled" then
    return {
      isValid = false,
      message = "Trade was cancelled",
      missingItems = nil,
    }
  end

  -- Check timeout
  local currentTime = os.time()
  if currentTime - session.startTime > TRADE_TIMEOUT then
    return {
      isValid = false,
      message = "Trade session timed out",
      missingItems = nil,
    }
  end

  -- Validate player 1's offer
  local p1Result = TradeExchange.validateOffer(player1Data, session.player1Offer)
  if not p1Result.isValid then
    return {
      isValid = false,
      message = "Player 1: " .. p1Result.message,
      missingItems = p1Result.missingItems,
    }
  end

  -- Validate player 2's offer
  local p2Result = TradeExchange.validateOffer(player2Data, session.player2Offer)
  if not p2Result.isValid then
    return {
      isValid = false,
      message = "Player 2: " .. p2Result.message,
      missingItems = p2Result.missingItems,
    }
  end

  return {
    isValid = true,
    message = "Session is valid",
    missingItems = nil,
  }
end

-- Lock items during trade (prevents modification during confirmation)
function TradeExchange.lockItems(
  session: TradeSession,
  player1Data: PlayerData.PlayerDataSchema,
  player2Data: PlayerData.PlayerDataSchema
): LockResult
  -- First validate the session
  local validation = TradeExchange.validateSession(session, player1Data, player2Data)
  if not validation.isValid then
    return {
      success = false,
      message = validation.message,
    }
  end

  -- Check both players have confirmed
  if not session.player1Offer.confirmed or not session.player2Offer.confirmed then
    return {
      success = false,
      message = "Both players must confirm before locking",
    }
  end

  -- Lock all items from both offers
  session.lockedItems = {}

  for _, item in ipairs(session.player1Offer.items) do
    session.lockedItems[item.itemId] = true
  end

  for _, item in ipairs(session.player2Offer.items) do
    session.lockedItems[item.itemId] = true
  end

  session.status = "locked"
  session.lockTime = os.time()

  return {
    success = true,
    message = "Items locked for trade",
  }
end

-- Remove item from player's inventory
local function removeItemFromInventory(
  playerData: PlayerData.PlayerDataSchema,
  itemId: string,
  itemType: "egg" | "chicken"
): any?
  if itemType == "egg" then
    for i, egg in ipairs(playerData.inventory.eggs) do
      if egg.id == itemId then
        table.remove(playerData.inventory.eggs, i)
        return egg
      end
    end
  elseif itemType == "chicken" then
    -- Check inventory chickens first
    for i, chicken in ipairs(playerData.inventory.chickens) do
      if chicken.id == itemId then
        table.remove(playerData.inventory.chickens, i)
        return chicken
      end
    end
    -- Check placed chickens
    for i, chicken in ipairs(playerData.placedChickens) do
      if chicken.id == itemId then
        -- Remove from placed and clear spot
        local removedChicken = table.remove(playerData.placedChickens, i)
        removedChicken.spotIndex = nil
        return removedChicken
      end
    end
  end
  return nil
end

-- Add item to player's inventory
local function addItemToInventory(
  playerData: PlayerData.PlayerDataSchema,
  item: any,
  itemType: "egg" | "chicken"
)
  -- Generate new ID for the received item
  local newId = PlayerData.generateId()

  if itemType == "egg" then
    local newEgg: PlayerData.EggData = {
      id = newId,
      eggType = item.eggType,
      rarity = item.rarity,
    }
    table.insert(playerData.inventory.eggs, newEgg)
  elseif itemType == "chicken" then
    local newChicken: PlayerData.ChickenData = {
      id = newId,
      chickenType = item.chickenType,
      rarity = item.rarity,
      accumulatedMoney = 0, -- Reset accumulated money on trade
      lastEggTime = os.time(),
      spotIndex = nil, -- Goes to inventory, not placed
    }
    table.insert(playerData.inventory.chickens, newChicken)
  end
end

-- Execute the trade transfer
function TradeExchange.executeTransfer(
  session: TradeSession,
  player1Data: PlayerData.PlayerDataSchema,
  player2Data: PlayerData.PlayerDataSchema
): TransferResult
  -- Must be locked before executing
  if session.status ~= "locked" then
    return {
      success = false,
      message = "Trade must be locked before execution",
    }
  end

  -- Check lock timeout
  local currentTime = os.time()
  if session.lockTime and (currentTime - session.lockTime > LOCK_TIMEOUT) then
    session.status = "cancelled"
    session.lockedItems = {}
    return {
      success = false,
      message = "Trade lock expired",
    }
  end

  -- Validate one more time before transfer
  local validation = TradeExchange.validateSession(session, player1Data, player2Data)
  if not validation.isValid then
    session.status = "cancelled"
    session.lockedItems = {}
    return {
      success = false,
      message = validation.message,
    }
  end

  -- Collect items to transfer
  local player1ItemsToReceive: { TradeItem } = {}
  local player2ItemsToReceive: { TradeItem } = {}

  -- Remove items from player 1 and prepare for player 2
  for _, item in ipairs(session.player1Offer.items) do
    local removed = removeItemFromInventory(player1Data, item.itemId, item.itemType)
    if removed then
      table.insert(player2ItemsToReceive, {
        itemType = item.itemType,
        itemId = item.itemId,
        itemData = removed,
      })
    end
  end

  -- Remove items from player 2 and prepare for player 1
  for _, item in ipairs(session.player2Offer.items) do
    local removed = removeItemFromInventory(player2Data, item.itemId, item.itemType)
    if removed then
      table.insert(player1ItemsToReceive, {
        itemType = item.itemType,
        itemId = item.itemId,
        itemData = removed,
      })
    end
  end

  -- Add items to player 1 (from player 2's offer)
  for _, item in ipairs(player1ItemsToReceive) do
    addItemToInventory(player1Data, item.itemData, item.itemType)
  end

  -- Add items to player 2 (from player 1's offer)
  for _, item in ipairs(player2ItemsToReceive) do
    addItemToInventory(player2Data, item.itemData, item.itemType)
  end

  -- Complete the trade
  session.status = "completed"
  session.lockedItems = {}

  return {
    success = true,
    message = "Trade completed successfully",
    player1ItemsReceived = player1ItemsToReceive,
    player2ItemsReceived = player2ItemsToReceive,
  }
end

-- Cancel a trade session
function TradeExchange.cancelSession(session: TradeSession, reason: string?): boolean
  if session.status == "completed" then
    return false -- Cannot cancel completed trade
  end

  session.status = "cancelled"
  session.lockedItems = {}

  return true
end

-- Handle player disconnect during trade
function TradeExchange.handleDisconnect(playerId: number): TradeSession?
  local session = TradeExchange.getPlayerSession(playerId)
  if session then
    TradeExchange.cancelSession(session, "Player disconnected")
    return session
  end
  return nil
end

-- Add item to a player's offer in a session
function TradeExchange.addItemToOffer(
  session: TradeSession,
  playerId: number,
  item: TradeItem
): boolean
  if session.status ~= "pending" then
    return false -- Can only modify pending trades
  end

  -- Check if item is locked elsewhere
  if TradeExchange.isItemLocked(item.itemId) then
    return false
  end

  local offer: TradeOffer
  if playerId == session.player1Id then
    offer = session.player1Offer
  elseif playerId == session.player2Id then
    offer = session.player2Offer
  else
    return false
  end

  -- Check for duplicates
  for _, existingItem in ipairs(offer.items) do
    if existingItem.itemId == item.itemId then
      return false
    end
  end

  -- Reset confirmation when offer changes
  offer.confirmed = false
  table.insert(offer.items, item)
  return true
end

-- Remove item from a player's offer in a session
function TradeExchange.removeItemFromOffer(
  session: TradeSession,
  playerId: number,
  itemId: string
): boolean
  if session.status ~= "pending" then
    return false
  end

  local offer: TradeOffer
  if playerId == session.player1Id then
    offer = session.player1Offer
  elseif playerId == session.player2Id then
    offer = session.player2Offer
  else
    return false
  end

  for i, item in ipairs(offer.items) do
    if item.itemId == itemId then
      table.remove(offer.items, i)
      offer.confirmed = false
      return true
    end
  end

  return false
end

-- Set confirmation status for a player
function TradeExchange.setConfirmation(
  session: TradeSession,
  playerId: number,
  confirmed: boolean
): boolean
  if session.status ~= "pending" then
    return false
  end

  if playerId == session.player1Id then
    session.player1Offer.confirmed = confirmed
  elseif playerId == session.player2Id then
    session.player2Offer.confirmed = confirmed
  else
    return false
  end

  return true
end

-- Check if both players have confirmed
function TradeExchange.areBothConfirmed(session: TradeSession): boolean
  return session.player1Offer.confirmed and session.player2Offer.confirmed
end

-- Get offer for a specific player
function TradeExchange.getPlayerOffer(session: TradeSession, playerId: number): TradeOffer?
  if playerId == session.player1Id then
    return session.player1Offer
  elseif playerId == session.player2Id then
    return session.player2Offer
  end
  return nil
end

-- Get partner's offer for a specific player
function TradeExchange.getPartnerOffer(session: TradeSession, playerId: number): TradeOffer?
  if playerId == session.player1Id then
    return session.player2Offer
  elseif playerId == session.player2Id then
    return session.player1Offer
  end
  return nil
end

-- Get partner's player ID
function TradeExchange.getPartnerId(session: TradeSession, playerId: number): number?
  if playerId == session.player1Id then
    return session.player2Id
  elseif playerId == session.player2Id then
    return session.player1Id
  end
  return nil
end

-- Clean up expired sessions
function TradeExchange.cleanupExpiredSessions()
  local currentTime = os.time()
  local toRemove: { string } = {}

  for tradeId, session in pairs(activeSessions) do
    -- Remove completed or cancelled sessions after a delay
    if session.status == "completed" or session.status == "cancelled" then
      table.insert(toRemove, tradeId)
    -- Remove timed out pending sessions
    elseif currentTime - session.startTime > TRADE_TIMEOUT then
      session.status = "cancelled"
      table.insert(toRemove, tradeId)
    end
  end

  for _, tradeId in ipairs(toRemove) do
    activeSessions[tradeId] = nil
  end
end

-- Get session summary for debugging
function TradeExchange.getSummary(session: TradeSession): string
  local p1Items = #session.player1Offer.items
  local p2Items = #session.player2Offer.items
  local p1Confirmed = session.player1Offer.confirmed and "✓" or "✗"
  local p2Confirmed = session.player2Offer.confirmed and "✓" or "✗"

  return string.format(
    "Trade %s: P1(%d items, %s) <-> P2(%d items, %s) [%s]",
    session.tradeId,
    p1Items,
    p1Confirmed,
    p2Items,
    p2Confirmed,
    session.status
  )
end

-- Get active session count
function TradeExchange.getActiveSessionCount(): number
  local count = 0
  for _, session in pairs(activeSessions) do
    if session.status == "pending" or session.status == "locked" then
      count = count + 1
    end
  end
  return count
end

-- Reset all sessions (for testing)
function TradeExchange.resetAllSessions()
  activeSessions = {}
end

return TradeExchange
