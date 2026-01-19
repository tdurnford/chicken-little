--[[
	TradeService
	Knit service that handles all player trading server logic.
	
	Provides:
	- Trade request handling
	- Offer management (add/remove items, confirmation)
	- Trade completion with atomic item transfer
	- Event broadcasting for trade UI updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TradeExchange = require(Shared:WaitForChild("TradeExchange"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

-- Services will be retrieved after Knit starts
local PlayerDataService

-- Type aliases for convenience
type TradeSession = TradeExchange.TradeSession
type TradeItem = TradeExchange.TradeItem
type TradeOffer = TradeExchange.TradeOffer
type ValidationResult = TradeExchange.ValidationResult
type TransferResult = TradeExchange.TransferResult

-- Pending trade requests: { [requestedPlayerId]: { fromPlayerId: number, timestamp: number } }
local pendingRequests: { [number]: { fromPlayerId: number, timestamp: number } } = {}
local REQUEST_TIMEOUT = 30 -- Seconds until trade request expires

-- Create the service
local TradeService = Knit.CreateService({
  Name = "TradeService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    TradeRequested = Knit.CreateSignal(), -- Fires to recipient with trade request info
    TradeStarted = Knit.CreateSignal(), -- Fires to both players when trade begins
    TradeUpdated = Knit.CreateSignal(), -- Fires to both players when offer changes
    TradeCompleted = Knit.CreateSignal(), -- Fires to both players when trade finishes
    TradeCancelled = Knit.CreateSignal(), -- Fires to both players when trade is cancelled
    TradeRequestDeclined = Knit.CreateSignal(), -- Fires to requester when declined
  },
})

-- Server-side signals (for other services to listen to)
TradeService.TradeStartedSignal = GoodSignal.new() -- (player1Id: number, player2Id: number, tradeId: string)
TradeService.TradeCompletedSignal = GoodSignal.new() -- (player1Id: number, player2Id: number, result: TransferResult)
TradeService.TradeCancelledSignal = GoodSignal.new() -- (player1Id: number, player2Id: number, reason: string)
TradeService.ItemTransferredSignal = GoodSignal.new() -- (fromPlayerId: number, toPlayerId: number, item: TradeItem)

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function TradeService:KnitInit()
  print("[TradeService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function TradeService:KnitStart()
  -- Get reference to PlayerDataService
  PlayerDataService = Knit.GetService("PlayerDataService")

  -- Setup player disconnect handling
  Players.PlayerRemoving:Connect(function(player)
    self:_handlePlayerDisconnect(player.UserId)
  end)

  print("[TradeService] Started")
end

-- ============================================================================
-- Client Methods
-- ============================================================================

--[[
	CLIENT: Request a trade with another player.
	
	@param player Player - The player requesting
	@param targetPlayerId number - The target player's user ID
	@return { success: boolean, message: string }
]]
function TradeService.Client:RequestTrade(
  player: Player,
  targetPlayerId: number
): { success: boolean, message: string }
  return TradeService:RequestTrade(player.UserId, targetPlayerId)
end

--[[
	CLIENT: Accept an incoming trade request.
	
	@param player Player - The player accepting
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string, tradeId: string? }
]]
function TradeService.Client:AcceptTrade(
  player: Player,
  fromPlayerId: number
): { success: boolean, message: string, tradeId: string? }
  return TradeService:AcceptTrade(player.UserId, fromPlayerId)
end

--[[
	CLIENT: Decline an incoming trade request.
	
	@param player Player - The player declining
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string }
]]
function TradeService.Client:DeclineTrade(
  player: Player,
  fromPlayerId: number
): { success: boolean, message: string }
  return TradeService:DeclineTrade(player.UserId, fromPlayerId)
end

--[[
	CLIENT: Add an item to the player's trade offer.
	
	@param player Player - The player adding
	@param item TradeItem - The item to add
	@return { success: boolean, message: string }
]]
function TradeService.Client:AddItemToOffer(
  player: Player,
  item: TradeItem
): { success: boolean, message: string }
  return TradeService:AddItemToOffer(player.UserId, item)
end

--[[
	CLIENT: Remove an item from the player's trade offer.
	
	@param player Player - The player removing
	@param itemId string - The item ID to remove
	@return { success: boolean, message: string }
]]
function TradeService.Client:RemoveItemFromOffer(
  player: Player,
  itemId: string
): { success: boolean, message: string }
  return TradeService:RemoveItemFromOffer(player.UserId, itemId)
end

--[[
	CLIENT: Set the player's confirmation status.
	
	@param player Player - The player confirming
	@param confirmed boolean - Whether to confirm or unconfirm
	@return { success: boolean, message: string }
]]
function TradeService.Client:SetConfirmation(
  player: Player,
  confirmed: boolean
): { success: boolean, message: string }
  return TradeService:SetConfirmation(player.UserId, confirmed)
end

--[[
	CLIENT: Cancel the current trade.
	
	@param player Player - The player cancelling
	@return { success: boolean, message: string }
]]
function TradeService.Client:CancelTrade(player: Player): { success: boolean, message: string }
  return TradeService:CancelTrade(player.UserId)
end

--[[
	CLIENT: Get the player's current trade session.
	
	@param player Player - The requesting player
	@return TradeSession?
]]
function TradeService.Client:GetCurrentTrade(player: Player): TradeSession?
  return TradeService:GetCurrentTrade(player.UserId)
end

--[[
	CLIENT: Check if player has a pending trade request.
	
	@param player Player - The requesting player
	@return { hasPending: boolean, fromPlayerId: number?, fromPlayerName: string? }
]]
function TradeService.Client:GetPendingRequest(player: Player): {
  hasPending: boolean,
  fromPlayerId: number?,
  fromPlayerName: string?,
}
  return TradeService:GetPendingRequest(player.UserId)
end

--[[
	CLIENT: Get partner info for the current trade.
	
	@param player Player - The requesting player
	@return { partnerId: number?, partnerName: string? }?
]]
function TradeService.Client:GetTradePartnerInfo(
  player: Player
): { partnerId: number?, partnerName: string? }?
  return TradeService:GetTradePartnerInfo(player.UserId)
end

-- ============================================================================
-- Server Methods
-- ============================================================================

--[[
	SERVER: Request a trade with another player.
	
	@param fromPlayerId number - The player requesting
	@param targetPlayerId number - The target player's user ID
	@return { success: boolean, message: string }
]]
function TradeService:RequestTrade(
  fromPlayerId: number,
  targetPlayerId: number
): { success: boolean, message: string }
  -- Validate players
  if fromPlayerId == targetPlayerId then
    return { success = false, message = "Cannot trade with yourself" }
  end

  local fromPlayer = Players:GetPlayerByUserId(fromPlayerId)
  local targetPlayer = Players:GetPlayerByUserId(targetPlayerId)

  if not fromPlayer then
    return { success = false, message = "Player not found" }
  end

  if not targetPlayer then
    return { success = false, message = "Target player not found or left the game" }
  end

  -- Check if requester is already in a trade
  local existingSession = TradeExchange.getPlayerSession(fromPlayerId)
  if existingSession then
    return { success = false, message = "You are already in a trade" }
  end

  -- Check if target is already in a trade
  local targetSession = TradeExchange.getPlayerSession(targetPlayerId)
  if targetSession then
    return { success = false, message = "Target player is already in a trade" }
  end

  -- Check for existing pending request to target
  if
    pendingRequests[targetPlayerId]
    and pendingRequests[targetPlayerId].fromPlayerId == fromPlayerId
  then
    return { success = false, message = "Trade request already pending" }
  end

  -- Create pending request
  pendingRequests[targetPlayerId] = {
    fromPlayerId = fromPlayerId,
    timestamp = os.time(),
  }

  -- Notify target player
  self.Client.TradeRequested:Fire(targetPlayer, {
    fromPlayerId = fromPlayerId,
    fromPlayerName = fromPlayer.Name,
  })

  return { success = true, message = "Trade request sent" }
end

--[[
	SERVER: Accept an incoming trade request.
	
	@param acceptingPlayerId number - The player accepting
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string, tradeId: string? }
]]
function TradeService:AcceptTrade(
  acceptingPlayerId: number,
  fromPlayerId: number
): { success: boolean, message: string, tradeId: string? }
  -- Check for pending request
  local request = pendingRequests[acceptingPlayerId]
  if not request or request.fromPlayerId ~= fromPlayerId then
    return { success = false, message = "No pending request from that player" }
  end

  -- Check if request expired
  if os.time() - request.timestamp > REQUEST_TIMEOUT then
    pendingRequests[acceptingPlayerId] = nil
    return { success = false, message = "Trade request expired" }
  end

  -- Validate players still exist
  local acceptingPlayer = Players:GetPlayerByUserId(acceptingPlayerId)
  local fromPlayer = Players:GetPlayerByUserId(fromPlayerId)

  if not acceptingPlayer or not fromPlayer then
    pendingRequests[acceptingPlayerId] = nil
    return { success = false, message = "Player left the game" }
  end

  -- Check neither player is now in a trade
  if TradeExchange.getPlayerSession(acceptingPlayerId) then
    pendingRequests[acceptingPlayerId] = nil
    return { success = false, message = "You are already in a trade" }
  end

  if TradeExchange.getPlayerSession(fromPlayerId) then
    pendingRequests[acceptingPlayerId] = nil
    return { success = false, message = "Other player is now in a trade" }
  end

  -- Clear the pending request
  pendingRequests[acceptingPlayerId] = nil

  -- Create the trade session
  local session = TradeExchange.createSession(fromPlayerId, acceptingPlayerId)

  -- Notify both players
  local tradeInfo = {
    tradeId = session.tradeId,
    player1Id = fromPlayerId,
    player1Name = fromPlayer.Name,
    player2Id = acceptingPlayerId,
    player2Name = acceptingPlayer.Name,
  }

  self.Client.TradeStarted:Fire(fromPlayer, tradeInfo)
  self.Client.TradeStarted:Fire(acceptingPlayer, tradeInfo)

  -- Fire server signal
  self.TradeStartedSignal:Fire(fromPlayerId, acceptingPlayerId, session.tradeId)

  return { success = true, message = "Trade started", tradeId = session.tradeId }
end

--[[
	SERVER: Decline an incoming trade request.
	
	@param decliningPlayerId number - The player declining
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string }
]]
function TradeService:DeclineTrade(
  decliningPlayerId: number,
  fromPlayerId: number
): { success: boolean, message: string }
  -- Check for pending request
  local request = pendingRequests[decliningPlayerId]
  if not request or request.fromPlayerId ~= fromPlayerId then
    return { success = false, message = "No pending request from that player" }
  end

  -- Clear the pending request
  pendingRequests[decliningPlayerId] = nil

  -- Notify the requester
  local fromPlayer = Players:GetPlayerByUserId(fromPlayerId)
  local decliningPlayer = Players:GetPlayerByUserId(decliningPlayerId)

  if fromPlayer and decliningPlayer then
    self.Client.TradeRequestDeclined:Fire(fromPlayer, {
      fromPlayerId = decliningPlayerId,
      fromPlayerName = decliningPlayer.Name,
    })
  end

  return { success = true, message = "Trade request declined" }
end

--[[
	SERVER: Add an item to the player's trade offer.
	
	@param playerId number - The player adding
	@param item TradeItem - The item to add
	@return { success: boolean, message: string }
]]
function TradeService:AddItemToOffer(
  playerId: number,
  item: TradeItem
): { success: boolean, message: string }
  local session = TradeExchange.getPlayerSession(playerId)
  if not session then
    return { success = false, message = "Not in a trade" }
  end

  -- Validate player owns the item
  local playerData = PlayerDataService:GetData(playerId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local tempOffer: TradeOffer = { items = { item }, confirmed = false }
  local validation = TradeExchange.validateOffer(playerData, tempOffer)
  if not validation.isValid then
    return { success = false, message = "You don't own this item" }
  end

  -- Add to offer
  local added = TradeExchange.addItemToOffer(session, playerId, item)
  if not added then
    return { success = false, message = "Could not add item (already in offer or trade locked)" }
  end

  -- Notify both players of update
  self:_broadcastTradeUpdate(session)

  return { success = true, message = "Item added to offer" }
end

--[[
	SERVER: Remove an item from the player's trade offer.
	
	@param playerId number - The player removing
	@param itemId string - The item ID to remove
	@return { success: boolean, message: string }
]]
function TradeService:RemoveItemFromOffer(
  playerId: number,
  itemId: string
): { success: boolean, message: string }
  local session = TradeExchange.getPlayerSession(playerId)
  if not session then
    return { success = false, message = "Not in a trade" }
  end

  local removed = TradeExchange.removeItemFromOffer(session, playerId, itemId)
  if not removed then
    return { success = false, message = "Could not remove item (not in offer or trade locked)" }
  end

  -- Notify both players of update
  self:_broadcastTradeUpdate(session)

  return { success = true, message = "Item removed from offer" }
end

--[[
	SERVER: Set the player's confirmation status.
	
	@param playerId number - The player confirming
	@param confirmed boolean - Whether to confirm or unconfirm
	@return { success: boolean, message: string }
]]
function TradeService:SetConfirmation(
  playerId: number,
  confirmed: boolean
): { success: boolean, message: string }
  local session = TradeExchange.getPlayerSession(playerId)
  if not session then
    return { success = false, message = "Not in a trade" }
  end

  local set = TradeExchange.setConfirmation(session, playerId, confirmed)
  if not set then
    return { success = false, message = "Could not set confirmation (trade locked)" }
  end

  -- Notify both players of update
  self:_broadcastTradeUpdate(session)

  -- Check if both confirmed - attempt to complete trade
  if TradeExchange.areBothConfirmed(session) then
    local result = self:_completeTrade(session)
    if not result.success then
      -- Reset confirmations on failure
      TradeExchange.setConfirmation(session, session.player1Id, false)
      TradeExchange.setConfirmation(session, session.player2Id, false)
      self:_broadcastTradeUpdate(session)
      return { success = false, message = result.message }
    end
  end

  return { success = true, message = confirmed and "Trade confirmed" or "Confirmation removed" }
end

--[[
	SERVER: Cancel the current trade.
	
	@param playerId number - The player cancelling
	@return { success: boolean, message: string }
]]
function TradeService:CancelTrade(playerId: number): { success: boolean, message: string }
  local session = TradeExchange.getPlayerSession(playerId)
  if not session then
    return { success = false, message = "Not in a trade" }
  end

  -- Get partner ID before cancelling
  local partnerId = TradeExchange.getPartnerId(session, playerId)

  -- Cancel the session
  local cancelled = TradeExchange.cancelSession(session, "Player cancelled")
  if not cancelled then
    return { success = false, message = "Could not cancel trade" }
  end

  -- Notify both players
  local player = Players:GetPlayerByUserId(playerId)
  local partnerPlayer = partnerId and Players:GetPlayerByUserId(partnerId)

  local cancelInfo = {
    reason = "Player cancelled",
    cancelledBy = playerId,
  }

  if player then
    self.Client.TradeCancelled:Fire(player, cancelInfo)
  end

  if partnerPlayer then
    self.Client.TradeCancelled:Fire(partnerPlayer, cancelInfo)
  end

  -- Fire server signal
  if partnerId then
    self.TradeCancelledSignal:Fire(playerId, partnerId, "Player cancelled")
  end

  return { success = true, message = "Trade cancelled" }
end

--[[
	SERVER: Get the player's current trade session.
	
	@param playerId number - The player's user ID
	@return TradeSession?
]]
function TradeService:GetCurrentTrade(playerId: number): TradeSession?
  return TradeExchange.getPlayerSession(playerId)
end

--[[
	SERVER: Check if player has a pending trade request.
	
	@param playerId number - The player's user ID
	@return { hasPending: boolean, fromPlayerId: number?, fromPlayerName: string? }
]]
function TradeService:GetPendingRequest(playerId: number): {
  hasPending: boolean,
  fromPlayerId: number?,
  fromPlayerName: string?,
}
  local request = pendingRequests[playerId]
  if not request then
    return { hasPending = false }
  end

  -- Check if expired
  if os.time() - request.timestamp > REQUEST_TIMEOUT then
    pendingRequests[playerId] = nil
    return { hasPending = false }
  end

  local fromPlayer = Players:GetPlayerByUserId(request.fromPlayerId)
  return {
    hasPending = true,
    fromPlayerId = request.fromPlayerId,
    fromPlayerName = fromPlayer and fromPlayer.Name or "Unknown",
  }
end

--[[
	SERVER: Get partner info for the current trade.
	
	@param playerId number - The player's user ID
	@return { partnerId: number?, partnerName: string? }?
]]
function TradeService:GetTradePartnerInfo(
  playerId: number
): { partnerId: number?, partnerName: string? }?
  local session = TradeExchange.getPlayerSession(playerId)
  if not session then
    return nil
  end

  local partnerId = TradeExchange.getPartnerId(session, playerId)
  if not partnerId then
    return nil
  end

  local partnerPlayer = Players:GetPlayerByUserId(partnerId)
  return {
    partnerId = partnerId,
    partnerName = partnerPlayer and partnerPlayer.Name or "Unknown",
  }
end

--[[
	SERVER: Check if an item is locked in any active trade.
	
	@param itemId string - The item ID to check
	@return boolean
]]
function TradeService:IsItemLocked(itemId: string): boolean
  return TradeExchange.isItemLocked(itemId)
end

--[[
	SERVER: Get active trade count.
	
	@return number
]]
function TradeService:GetActiveTradeCount(): number
  return TradeExchange.getActiveSessionCount()
end

--[[
	SERVER: Cleanup expired sessions.
	Call this periodically from the game loop.
]]
function TradeService:CleanupExpiredSessions()
  TradeExchange.cleanupExpiredSessions()

  -- Also cleanup expired pending requests
  local currentTime = os.time()
  local toRemove: { number } = {}

  for playerId, request in pairs(pendingRequests) do
    if currentTime - request.timestamp > REQUEST_TIMEOUT then
      table.insert(toRemove, playerId)
    end
  end

  for _, playerId in ipairs(toRemove) do
    pendingRequests[playerId] = nil
  end
end

-- ============================================================================
-- Private Methods
-- ============================================================================

--[[
	PRIVATE: Complete a trade when both players have confirmed.
	
	@param session TradeSession - The trade session
	@return TransferResult
]]
function TradeService:_completeTrade(session: TradeSession): TransferResult
  -- Get player data for both players
  local player1Data = PlayerDataService:GetData(session.player1Id)
  local player2Data = PlayerDataService:GetData(session.player2Id)

  if not player1Data or not player2Data then
    return { success = false, message = "Player data not found" }
  end

  -- Lock items first
  local lockResult = TradeExchange.lockItems(session, player1Data, player2Data)
  if not lockResult.success then
    return { success = false, message = lockResult.message }
  end

  -- Execute the transfer
  local result = TradeExchange.executeTransfer(session, player1Data, player2Data)

  if result.success then
    -- Update player data
    PlayerDataService:UpdateData(session.player1Id, player1Data)
    PlayerDataService:UpdateData(session.player2Id, player2Data)

    -- Notify both players
    local player1 = Players:GetPlayerByUserId(session.player1Id)
    local player2 = Players:GetPlayerByUserId(session.player2Id)

    local completionInfo = {
      tradeId = session.tradeId,
      success = true,
      player1ItemsReceived = result.player1ItemsReceived,
      player2ItemsReceived = result.player2ItemsReceived,
    }

    if player1 then
      self.Client.TradeCompleted:Fire(player1, completionInfo)
    end

    if player2 then
      self.Client.TradeCompleted:Fire(player2, completionInfo)
    end

    -- Fire server signals
    self.TradeCompletedSignal:Fire(session.player1Id, session.player2Id, result)

    -- Fire item transfer signals for each item
    if result.player1ItemsReceived then
      for _, item in ipairs(result.player1ItemsReceived) do
        self.ItemTransferredSignal:Fire(session.player2Id, session.player1Id, item)
      end
    end

    if result.player2ItemsReceived then
      for _, item in ipairs(result.player2ItemsReceived) do
        self.ItemTransferredSignal:Fire(session.player1Id, session.player2Id, item)
      end
    end
  end

  return result
end

--[[
	PRIVATE: Broadcast trade update to both players.
	
	@param session TradeSession - The trade session
]]
function TradeService:_broadcastTradeUpdate(session: TradeSession)
  local player1 = Players:GetPlayerByUserId(session.player1Id)
  local player2 = Players:GetPlayerByUserId(session.player2Id)

  local updateInfo = {
    tradeId = session.tradeId,
    player1Offer = session.player1Offer,
    player2Offer = session.player2Offer,
    status = session.status,
  }

  if player1 then
    self.Client.TradeUpdated:Fire(player1, updateInfo)
  end

  if player2 then
    self.Client.TradeUpdated:Fire(player2, updateInfo)
  end
end

--[[
	PRIVATE: Handle player disconnect during trade.
	
	@param playerId number - The disconnecting player's user ID
]]
function TradeService:_handlePlayerDisconnect(playerId: number)
  -- Handle active trade
  local session = TradeExchange.handleDisconnect(playerId)
  if session then
    local partnerId = TradeExchange.getPartnerId(session, playerId)
    if partnerId then
      local partnerPlayer = Players:GetPlayerByUserId(partnerId)
      if partnerPlayer then
        self.Client.TradeCancelled:Fire(partnerPlayer, {
          reason = "Partner disconnected",
          cancelledBy = playerId,
        })
      end

      self.TradeCancelledSignal:Fire(playerId, partnerId, "Player disconnected")
    end
  end

  -- Clear any pending requests to this player
  pendingRequests[playerId] = nil

  -- Clear any pending requests from this player
  for targetId, request in pairs(pendingRequests) do
    if request.fromPlayerId == playerId then
      pendingRequests[targetId] = nil
    end
  end
end

return TradeService
