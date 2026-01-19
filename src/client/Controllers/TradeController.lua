--[[
	TradeController
	Client-side Knit controller for managing player trading.
	
	Provides:
	- Trade request/accept/decline via TradeService
	- Offer management (add/remove items, confirm)
	- GoodSignal events for reactive trade UI updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

-- Type for trade item
export type TradeItem = {
  itemType: string,
  itemId: string,
}

-- Create the controller
local TradeController = Knit.CreateController({
  Name = "TradeController",
})

-- GoodSignal events for reactive UI
TradeController.TradeRequested = GoodSignal.new() -- Fires (data: {fromPlayerId, fromPlayerName})
TradeController.TradeStarted = GoodSignal.new() -- Fires (data: {tradeId, player1Id, player1Name, player2Id, player2Name})
TradeController.TradeUpdated = GoodSignal.new() -- Fires (data: {tradeId, player1Offer, player2Offer, status})
TradeController.TradeCompleted = GoodSignal.new() -- Fires (data: {tradeId, success, itemsReceived})
TradeController.TradeCancelled = GoodSignal.new() -- Fires (data: {reason, cancelledBy})
TradeController.TradeRequestDeclined = GoodSignal.new() -- Fires (data: {fromPlayerId, fromPlayerName})

-- Reference to the server service
local tradeService = nil

-- Local state
local currentTradeId: string? = nil
local isInTrade: boolean = false

--[[
	Initialize the controller.
	Called automatically by Knit before Start.
]]
function TradeController:KnitInit()
  print("[TradeController] Initialized")
end

--[[
	Start the controller.
	Called automatically by Knit after all controllers are initialized.
]]
function TradeController:KnitStart()
  -- Get reference to server service
  tradeService = Knit.GetService("TradeService")

  -- Connect to server signals
  tradeService.TradeRequested:Connect(function(data)
    self.TradeRequested:Fire(data)
  end)

  tradeService.TradeStarted:Connect(function(data)
    currentTradeId = data.tradeId
    isInTrade = true
    self.TradeStarted:Fire(data)
  end)

  tradeService.TradeUpdated:Connect(function(data)
    self.TradeUpdated:Fire(data)
  end)

  tradeService.TradeCompleted:Connect(function(data)
    currentTradeId = nil
    isInTrade = false
    self.TradeCompleted:Fire(data)
  end)

  tradeService.TradeCancelled:Connect(function(data)
    currentTradeId = nil
    isInTrade = false
    self.TradeCancelled:Fire(data)
  end)

  tradeService.TradeRequestDeclined:Connect(function(data)
    self.TradeRequestDeclined:Fire(data)
  end)

  print("[TradeController] Started")
end

-- ============================================================================
-- State Query Methods
-- ============================================================================

--[[
	Check if currently in a trade.
	
	@return boolean
]]
function TradeController:IsInTrade(): boolean
  return isInTrade
end

--[[
	Get the current trade ID (synchronous).
	
	@return string?
]]
function TradeController:GetCurrentTradeId(): string?
  return currentTradeId
end

--[[
	Get the current trade session from server.
	
	@return TradeSession?
]]
function TradeController:GetCurrentTrade()
  if not tradeService then
    return nil
  end
  return tradeService:GetCurrentTrade()
end

--[[
	Check for pending trade request.
	
	@return { hasPending: boolean, fromPlayerId: number?, fromPlayerName: string? }
]]
function TradeController:GetPendingRequest()
  if not tradeService then
    return { hasPending = false }
  end
  return tradeService:GetPendingRequest()
end

--[[
	Get trade partner info for current trade.
	
	@return { partnerId: number?, partnerName: string? }?
]]
function TradeController:GetTradePartnerInfo()
  if not tradeService then
    return nil
  end
  return tradeService:GetTradePartnerInfo()
end

-- ============================================================================
-- Trade Request Methods
-- ============================================================================

--[[
	Request a trade with another player.
	
	@param targetPlayerId number - The target player's user ID
	@return { success: boolean, message: string }
]]
function TradeController:RequestTrade(targetPlayerId: number)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:RequestTrade(targetPlayerId)
end

--[[
	Accept an incoming trade request.
	
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string, tradeId: string? }
]]
function TradeController:AcceptTrade(fromPlayerId: number)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:AcceptTrade(fromPlayerId)
end

--[[
	Decline an incoming trade request.
	
	@param fromPlayerId number - The player who sent the request
	@return { success: boolean, message: string }
]]
function TradeController:DeclineTrade(fromPlayerId: number)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:DeclineTrade(fromPlayerId)
end

-- ============================================================================
-- Offer Management Methods
-- ============================================================================

--[[
	Add an item to your trade offer.
	
	@param item TradeItem - The item to add
	@return { success: boolean, message: string }
]]
function TradeController:AddItemToOffer(item: TradeItem)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:AddItemToOffer(item)
end

--[[
	Remove an item from your trade offer.
	
	@param itemId string - The item ID to remove
	@return { success: boolean, message: string }
]]
function TradeController:RemoveItemFromOffer(itemId: string)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:RemoveItemFromOffer(itemId)
end

--[[
	Set your confirmation status.
	
	@param confirmed boolean - Whether to confirm or unconfirm
	@return { success: boolean, message: string }
]]
function TradeController:SetConfirmation(confirmed: boolean)
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:SetConfirmation(confirmed)
end

--[[
	Confirm the trade (shorthand for SetConfirmation(true)).
	
	@return { success: boolean, message: string }
]]
function TradeController:ConfirmTrade()
  return self:SetConfirmation(true)
end

--[[
	Unconfirm the trade (shorthand for SetConfirmation(false)).
	
	@return { success: boolean, message: string }
]]
function TradeController:UnconfirmTrade()
  return self:SetConfirmation(false)
end

--[[
	Cancel the current trade.
	
	@return { success: boolean, message: string }
]]
function TradeController:CancelTrade()
  if not tradeService then
    return { success = false, message = "Service not available" }
  end
  return tradeService:CancelTrade()
end

return TradeController
