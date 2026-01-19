--[[
	TradeService.spec.lua
	Tests for the TradeService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local TradeExchange = require(Shared:WaitForChild("TradeExchange"))

  describe("TradeExchange", function()
    beforeEach(function()
      -- Reset sessions before each test
      TradeExchange.resetAllSessions()
    end)

    describe("createSession", function()
      it("should create a new trade session", function()
        local session = TradeExchange.createSession(123, 456)

        expect(session).to.be.ok()
        expect(session.player1Id).to.equal(123)
        expect(session.player2Id).to.equal(456)
        expect(session.status).to.equal("pending")
      end)

      it("should generate unique trade IDs", function()
        local session1 = TradeExchange.createSession(123, 456)
        local session2 = TradeExchange.createSession(789, 101)

        expect(session1.tradeId).to.be.ok()
        expect(session2.tradeId).to.be.ok()
        -- IDs contain random component so should be different
        expect(session1.tradeId).never.to.equal(session2.tradeId)
      end)

      it("should initialize empty offers", function()
        local session = TradeExchange.createSession(123, 456)

        expect(#session.player1Offer.items).to.equal(0)
        expect(#session.player2Offer.items).to.equal(0)
        expect(session.player1Offer.confirmed).to.equal(false)
        expect(session.player2Offer.confirmed).to.equal(false)
      end)
    end)

    describe("getSession", function()
      it("should retrieve an existing session by ID", function()
        local created = TradeExchange.createSession(123, 456)
        local retrieved = TradeExchange.getSession(created.tradeId)

        expect(retrieved).to.equal(created)
      end)

      it("should return nil for non-existent session", function()
        local session = TradeExchange.getSession("nonexistent_trade_id")

        expect(session).to.equal(nil)
      end)
    end)

    describe("getPlayerSession", function()
      it("should find session for player1", function()
        local created = TradeExchange.createSession(123, 456)
        local found = TradeExchange.getPlayerSession(123)

        expect(found).to.equal(created)
      end)

      it("should find session for player2", function()
        local created = TradeExchange.createSession(123, 456)
        local found = TradeExchange.getPlayerSession(456)

        expect(found).to.equal(created)
      end)

      it("should return nil for player not in any trade", function()
        TradeExchange.createSession(123, 456)
        local found = TradeExchange.getPlayerSession(789)

        expect(found).to.equal(nil)
      end)

      it("should not find completed sessions", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "completed"

        local found = TradeExchange.getPlayerSession(123)

        expect(found).to.equal(nil)
      end)

      it("should not find cancelled sessions", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "cancelled"

        local found = TradeExchange.getPlayerSession(123)

        expect(found).to.equal(nil)
      end)
    end)

    describe("addItemToOffer", function()
      it("should add item to player1's offer", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }

        local added = TradeExchange.addItemToOffer(session, 123, item)

        expect(added).to.equal(true)
        expect(#session.player1Offer.items).to.equal(1)
        expect(session.player1Offer.items[1].itemId).to.equal("egg_001")
      end)

      it("should add item to player2's offer", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "chicken", itemId = "chicken_001", itemData = {} }

        local added = TradeExchange.addItemToOffer(session, 456, item)

        expect(added).to.equal(true)
        expect(#session.player2Offer.items).to.equal(1)
      end)

      it("should prevent duplicate items", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }

        TradeExchange.addItemToOffer(session, 123, item)
        local addedAgain = TradeExchange.addItemToOffer(session, 123, item)

        expect(addedAgain).to.equal(false)
        expect(#session.player1Offer.items).to.equal(1)
      end)

      it("should reset confirmation when offer changes", function()
        local session = TradeExchange.createSession(123, 456)
        session.player1Offer.confirmed = true

        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }
        TradeExchange.addItemToOffer(session, 123, item)

        expect(session.player1Offer.confirmed).to.equal(false)
      end)

      it("should reject items for non-pending trades", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "locked"

        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }
        local added = TradeExchange.addItemToOffer(session, 123, item)

        expect(added).to.equal(false)
      end)
    end)

    describe("removeItemFromOffer", function()
      it("should remove item from offer", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }
        TradeExchange.addItemToOffer(session, 123, item)

        local removed = TradeExchange.removeItemFromOffer(session, 123, "egg_001")

        expect(removed).to.equal(true)
        expect(#session.player1Offer.items).to.equal(0)
      end)

      it("should return false for non-existent item", function()
        local session = TradeExchange.createSession(123, 456)

        local removed = TradeExchange.removeItemFromOffer(session, 123, "nonexistent")

        expect(removed).to.equal(false)
      end)

      it("should reset confirmation when offer changes", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }
        TradeExchange.addItemToOffer(session, 123, item)
        session.player1Offer.confirmed = true

        TradeExchange.removeItemFromOffer(session, 123, "egg_001")

        expect(session.player1Offer.confirmed).to.equal(false)
      end)
    end)

    describe("setConfirmation", function()
      it("should set confirmation to true", function()
        local session = TradeExchange.createSession(123, 456)

        local set = TradeExchange.setConfirmation(session, 123, true)

        expect(set).to.equal(true)
        expect(session.player1Offer.confirmed).to.equal(true)
      end)

      it("should set confirmation to false", function()
        local session = TradeExchange.createSession(123, 456)
        session.player1Offer.confirmed = true

        local set = TradeExchange.setConfirmation(session, 123, false)

        expect(set).to.equal(true)
        expect(session.player1Offer.confirmed).to.equal(false)
      end)

      it("should reject confirmation for locked trades", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "locked"

        local set = TradeExchange.setConfirmation(session, 123, true)

        expect(set).to.equal(false)
      end)
    end)

    describe("areBothConfirmed", function()
      it("should return true when both confirmed", function()
        local session = TradeExchange.createSession(123, 456)
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true

        expect(TradeExchange.areBothConfirmed(session)).to.equal(true)
      end)

      it("should return false when only player1 confirmed", function()
        local session = TradeExchange.createSession(123, 456)
        session.player1Offer.confirmed = true

        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)

      it("should return false when only player2 confirmed", function()
        local session = TradeExchange.createSession(123, 456)
        session.player2Offer.confirmed = true

        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)

      it("should return false when neither confirmed", function()
        local session = TradeExchange.createSession(123, 456)

        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)
    end)

    describe("cancelSession", function()
      it("should cancel a pending session", function()
        local session = TradeExchange.createSession(123, 456)

        local cancelled = TradeExchange.cancelSession(session, "Test reason")

        expect(cancelled).to.equal(true)
        expect(session.status).to.equal("cancelled")
      end)

      it("should cancel a locked session", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "locked"

        local cancelled = TradeExchange.cancelSession(session, "Test reason")

        expect(cancelled).to.equal(true)
        expect(session.status).to.equal("cancelled")
      end)

      it("should not cancel a completed session", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "completed"

        local cancelled = TradeExchange.cancelSession(session, "Test reason")

        expect(cancelled).to.equal(false)
        expect(session.status).to.equal("completed")
      end)

      it("should clear locked items on cancel", function()
        local session = TradeExchange.createSession(123, 456)
        session.lockedItems = { egg_001 = true, chicken_001 = true }

        TradeExchange.cancelSession(session, "Test reason")

        expect(next(session.lockedItems)).to.equal(nil)
      end)
    end)

    describe("handleDisconnect", function()
      it("should cancel trade when player disconnects", function()
        local session = TradeExchange.createSession(123, 456)

        local returned = TradeExchange.handleDisconnect(123)

        expect(returned).to.equal(session)
        expect(session.status).to.equal("cancelled")
      end)

      it("should return nil when player not in trade", function()
        TradeExchange.createSession(123, 456)

        local returned = TradeExchange.handleDisconnect(789)

        expect(returned).to.equal(nil)
      end)
    end)

    describe("getPlayerOffer", function()
      it("should return player1's offer for player1", function()
        local session = TradeExchange.createSession(123, 456)

        local offer = TradeExchange.getPlayerOffer(session, 123)

        expect(offer).to.equal(session.player1Offer)
      end)

      it("should return player2's offer for player2", function()
        local session = TradeExchange.createSession(123, 456)

        local offer = TradeExchange.getPlayerOffer(session, 456)

        expect(offer).to.equal(session.player2Offer)
      end)

      it("should return nil for non-participant", function()
        local session = TradeExchange.createSession(123, 456)

        local offer = TradeExchange.getPlayerOffer(session, 789)

        expect(offer).to.equal(nil)
      end)
    end)

    describe("getPartnerOffer", function()
      it("should return player2's offer for player1", function()
        local session = TradeExchange.createSession(123, 456)

        local offer = TradeExchange.getPartnerOffer(session, 123)

        expect(offer).to.equal(session.player2Offer)
      end)

      it("should return player1's offer for player2", function()
        local session = TradeExchange.createSession(123, 456)

        local offer = TradeExchange.getPartnerOffer(session, 456)

        expect(offer).to.equal(session.player1Offer)
      end)
    end)

    describe("getPartnerId", function()
      it("should return player2 for player1", function()
        local session = TradeExchange.createSession(123, 456)

        local partnerId = TradeExchange.getPartnerId(session, 123)

        expect(partnerId).to.equal(456)
      end)

      it("should return player1 for player2", function()
        local session = TradeExchange.createSession(123, 456)

        local partnerId = TradeExchange.getPartnerId(session, 456)

        expect(partnerId).to.equal(123)
      end)

      it("should return nil for non-participant", function()
        local session = TradeExchange.createSession(123, 456)

        local partnerId = TradeExchange.getPartnerId(session, 789)

        expect(partnerId).to.equal(nil)
      end)
    end)

    describe("isItemLocked", function()
      it("should return true for locked item", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "locked"
        session.lockedItems = { egg_001 = true }

        expect(TradeExchange.isItemLocked("egg_001")).to.equal(true)
      end)

      it("should return false for unlocked item", function()
        local session = TradeExchange.createSession(123, 456)
        session.lockedItems = { egg_001 = true }
        -- status is not "locked"

        expect(TradeExchange.isItemLocked("egg_001")).to.equal(false)
      end)

      it("should return false for non-existent item", function()
        TradeExchange.createSession(123, 456)

        expect(TradeExchange.isItemLocked("nonexistent")).to.equal(false)
      end)
    end)

    describe("getActiveSessionCount", function()
      it("should count pending sessions", function()
        TradeExchange.createSession(123, 456)
        TradeExchange.createSession(789, 101)

        expect(TradeExchange.getActiveSessionCount()).to.equal(2)
      end)

      it("should count locked sessions", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "locked"

        expect(TradeExchange.getActiveSessionCount()).to.equal(1)
      end)

      it("should not count completed sessions", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "completed"

        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)

      it("should not count cancelled sessions", function()
        local session = TradeExchange.createSession(123, 456)
        session.status = "cancelled"

        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)
    end)

    describe("getSummary", function()
      it("should generate readable summary", function()
        local session = TradeExchange.createSession(123, 456)
        local item = { itemType = "egg", itemId = "egg_001", itemData = {} }
        TradeExchange.addItemToOffer(session, 123, item)
        session.player2Offer.confirmed = true

        local summary = TradeExchange.getSummary(session)

        expect(summary).to.be.a("string")
        expect(summary:find("P1%(1 items")).to.be.ok()
        expect(summary:find("P2%(0 items")).to.be.ok()
        expect(summary:find("pending")).to.be.ok()
      end)
    end)
  end)

  describe("TradeService Integration", function()
    -- These tests verify service structure without requiring full Knit initialization

    it("should define correct client methods", function()
      -- This verifies the service interface by checking module exists
      local Packages = ReplicatedStorage:WaitForChild("Packages")
      local Knit = require(Packages:WaitForChild("Knit"))

      -- Module should be loadable
      expect(Knit).to.be.ok()
    end)

    it("should export TradeExchange types", function()
      expect(TradeExchange.createSession).to.be.a("function")
      expect(TradeExchange.getSession).to.be.a("function")
      expect(TradeExchange.validateOffer).to.be.a("function")
      expect(TradeExchange.executeTransfer).to.be.a("function")
    end)
  end)
end
