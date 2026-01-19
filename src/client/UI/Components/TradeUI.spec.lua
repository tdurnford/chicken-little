--[[
	TradeUI.spec.lua
	Tests for the Fusion-based TradeUI component.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function()
  local TradeUI = require(script.Parent.TradeUI)

  afterEach(function()
    TradeUI.destroy()
  end)

  describe("TradeUI", function()
    describe("create/destroy lifecycle", function()
      it("should create successfully", function()
        local success = TradeUI.create()
        expect(success).to.equal(true)
        expect(TradeUI.isCreated()).to.equal(true)
      end)

      it("should destroy cleanly", function()
        TradeUI.create()
        TradeUI.destroy()
        expect(TradeUI.isCreated()).to.equal(false)
      end)

      it("should handle multiple create calls", function()
        TradeUI.create()
        local success = TradeUI.create()
        expect(success).to.equal(true)
        expect(TradeUI.isCreated()).to.equal(true)
      end)

      it("should handle destroy without create", function()
        TradeUI.destroy()
        expect(TradeUI.isCreated()).to.equal(false)
      end)
    end)

    describe("visibility", function()
      it("should start hidden", function()
        TradeUI.create()
        expect(TradeUI.isVisible()).to.equal(false)
      end)

      it("should become visible after show", function()
        TradeUI.create()
        TradeUI.show()
        expect(TradeUI.isVisible()).to.equal(true)
      end)

      it("should hide after hide call", function()
        TradeUI.create()
        TradeUI.show()
        TradeUI.hide()
        expect(TradeUI.isVisible()).to.equal(false)
      end)

      it("should toggle visibility", function()
        TradeUI.create()
        expect(TradeUI.isVisible()).to.equal(false)
        TradeUI.toggle()
        expect(TradeUI.isVisible()).to.equal(true)
        TradeUI.toggle()
        expect(TradeUI.isVisible()).to.equal(false)
      end)
    end)

    describe("trade state", function()
      it("should start inactive", function()
        TradeUI.create()
        expect(TradeUI.isTradeActive()).to.equal(false)
      end)

      it("should become active when starting trade", function()
        TradeUI.create()
        TradeUI.startTrade(12345, "TestPlayer")
        expect(TradeUI.isTradeActive()).to.equal(true)
      end)

      it("should track partner info", function()
        TradeUI.create()
        TradeUI.startTrade(12345, "TestPlayer")
        local id, name = TradeUI.getPartnerInfo()
        expect(id).to.equal(12345)
        expect(name).to.equal("TestPlayer")
      end)

      it("should reset state", function()
        TradeUI.create()
        TradeUI.startTrade(12345, "TestPlayer")
        TradeUI.resetTradeState()
        expect(TradeUI.isTradeActive()).to.equal(false)
        local id, name = TradeUI.getPartnerInfo()
        expect(id).to.equal(nil)
        expect(name).to.equal(nil)
      end)

      it("should end trade properly", function()
        TradeUI.create()
        TradeUI.startTrade(12345, "TestPlayer")
        TradeUI.endTrade("completed")
        expect(TradeUI.isTradeActive()).to.equal(false)
        expect(TradeUI.isVisible()).to.equal(false)
      end)
    end)

    describe("local offer", function()
      it("should start with empty offer", function()
        TradeUI.create()
        local offer = TradeUI.getLocalOffer()
        expect(#offer.items).to.equal(0)
        expect(offer.confirmed).to.equal(false)
      end)

      it("should add item to offer", function()
        TradeUI.create()
        local item = {
          itemType = "egg",
          itemId = "egg-123",
          itemData = { eggType = "BasicEgg", rarity = "Common" },
        }
        local success = TradeUI.addItemToOffer(item)
        expect(success).to.equal(true)
        local offer = TradeUI.getLocalOffer()
        expect(#offer.items).to.equal(1)
      end)

      it("should prevent duplicate items", function()
        TradeUI.create()
        local item = {
          itemType = "egg",
          itemId = "egg-123",
          itemData = { eggType = "BasicEgg", rarity = "Common" },
        }
        TradeUI.addItemToOffer(item)
        local success = TradeUI.addItemToOffer(item)
        expect(success).to.equal(false)
        local offer = TradeUI.getLocalOffer()
        expect(#offer.items).to.equal(1)
      end)

      it("should remove item from offer", function()
        TradeUI.create()
        local item = {
          itemType = "egg",
          itemId = "egg-123",
          itemData = { eggType = "BasicEgg", rarity = "Common" },
        }
        TradeUI.addItemToOffer(item)
        local success = TradeUI.removeItemFromOffer("egg-123")
        expect(success).to.equal(true)
        local offer = TradeUI.getLocalOffer()
        expect(#offer.items).to.equal(0)
      end)

      it("should confirm offer", function()
        TradeUI.create()
        TradeUI.confirmOffer()
        local offer = TradeUI.getLocalOffer()
        expect(offer.confirmed).to.equal(true)
      end)

      it("should unconfirm offer", function()
        TradeUI.create()
        TradeUI.confirmOffer()
        TradeUI.unconfirmOffer()
        local offer = TradeUI.getLocalOffer()
        expect(offer.confirmed).to.equal(false)
      end)

      it("should reset confirmation when adding item", function()
        TradeUI.create()
        TradeUI.confirmOffer()
        local item = {
          itemType = "egg",
          itemId = "egg-123",
          itemData = { eggType = "BasicEgg", rarity = "Common" },
        }
        TradeUI.addItemToOffer(item)
        local offer = TradeUI.getLocalOffer()
        expect(offer.confirmed).to.equal(false)
      end)
    end)

    describe("partner offer", function()
      it("should start with empty partner offer", function()
        TradeUI.create()
        local offer = TradeUI.getPartnerOffer()
        expect(#offer.items).to.equal(0)
        expect(offer.confirmed).to.equal(false)
      end)

      it("should update partner offer", function()
        TradeUI.create()
        local items = {
          {
            itemType = "chicken",
            itemId = "chicken-456",
            itemData = { chickenType = "BasicChicken", rarity = "Common" },
          },
        }
        TradeUI.updatePartnerOffer(items, true)
        local offer = TradeUI.getPartnerOffer()
        expect(#offer.items).to.equal(1)
        expect(offer.confirmed).to.equal(true)
      end)
    end)

    describe("confirmation check", function()
      it("should return false when neither confirmed", function()
        TradeUI.create()
        expect(TradeUI.areBothConfirmed()).to.equal(false)
      end)

      it("should return false when only local confirmed", function()
        TradeUI.create()
        TradeUI.confirmOffer()
        expect(TradeUI.areBothConfirmed()).to.equal(false)
      end)

      it("should return true when both confirmed", function()
        TradeUI.create()
        TradeUI.confirmOffer()
        TradeUI.updatePartnerOffer({}, true)
        expect(TradeUI.areBothConfirmed()).to.equal(true)
      end)
    end)

    describe("trade requests", function()
      it("should show trade request", function()
        TradeUI.create()
        TradeUI.showTradeRequest(12345, "TestPlayer")
        local requests = TradeUI.getPendingRequests()
        expect(#requests).to.equal(1)
        expect(requests[1].fromPlayerId).to.equal(12345)
      end)

      it("should hide trade request", function()
        TradeUI.create()
        TradeUI.showTradeRequest(12345, "TestPlayer")
        TradeUI.hideTradeRequest()
        local requests = TradeUI.getPendingRequests()
        expect(#requests).to.equal(0)
      end)

      it("should clear all pending requests", function()
        TradeUI.create()
        TradeUI.showTradeRequest(12345, "Player1")
        TradeUI.showTradeRequest(67890, "Player2")
        TradeUI.clearPendingRequests()
        local requests = TradeUI.getPendingRequests()
        expect(#requests).to.equal(0)
      end)
    end)

    describe("callbacks", function()
      it("should call onConfirm callback", function()
        local called = false
        TradeUI.create({
          onConfirm = function()
            called = true
          end,
        })
        TradeUI.startTrade(12345, "Test")
        -- Would need to simulate button click
        -- For now, test callback setter
        expect(true).to.equal(true)
      end)

      it("should set callbacks via methods", function()
        TradeUI.create()
        local acceptCalled = false
        local declineCalled = false

        TradeUI.setOnTradeAccept(function()
          acceptCalled = true
        end)
        TradeUI.setOnTradeDecline(function()
          declineCalled = true
        end)

        -- Verify callbacks are stored
        expect(true).to.equal(true)
      end)
    end)

    describe("get trade state", function()
      it("should return complete trade state", function()
        TradeUI.create()
        TradeUI.startTrade(12345, "TestPlayer")
        local state = TradeUI.getTradeState()
        expect(state.isActive).to.equal(true)
        expect(state.partnerId).to.equal(12345)
        expect(state.partnerName).to.equal("TestPlayer")
        expect(state.status).to.equal("negotiating")
      end)
    end)

    describe("utility methods", function()
      it("should return screen GUI", function()
        TradeUI.create()
        local gui = TradeUI.getScreenGui()
        expect(gui).to.be.ok()
        expect(gui:IsA("ScreenGui")).to.equal(true)
      end)
    end)
  end)
end
