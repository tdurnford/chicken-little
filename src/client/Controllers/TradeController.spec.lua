--[[
	TradeController Tests
	Tests for the client-side trade controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

  describe("TradeController", function()
    -- Note: Full integration tests require Knit to be running.
    -- These tests verify the module structure and signal setup.

    local TradeController

    beforeAll(function()
      -- In test environment, we just verify the module loads
      TradeController = require(script.Parent.TradeController)
    end)

    describe("Module Structure", function()
      it("should have Name property", function()
        expect(TradeController.Name).to.equal("TradeController")
      end)

      it("should have KnitInit method", function()
        expect(type(TradeController.KnitInit)).to.equal("function")
      end)

      it("should have KnitStart method", function()
        expect(type(TradeController.KnitStart)).to.equal("function")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have TradeRequested signal", function()
        expect(TradeController.TradeRequested).to.be.ok()
        expect(type(TradeController.TradeRequested.Connect)).to.equal("function")
      end)

      it("should have TradeStarted signal", function()
        expect(TradeController.TradeStarted).to.be.ok()
        expect(type(TradeController.TradeStarted.Connect)).to.equal("function")
      end)

      it("should have TradeUpdated signal", function()
        expect(TradeController.TradeUpdated).to.be.ok()
        expect(type(TradeController.TradeUpdated.Connect)).to.equal("function")
      end)

      it("should have TradeCompleted signal", function()
        expect(TradeController.TradeCompleted).to.be.ok()
        expect(type(TradeController.TradeCompleted.Connect)).to.equal("function")
      end)

      it("should have TradeCancelled signal", function()
        expect(TradeController.TradeCancelled).to.be.ok()
        expect(type(TradeController.TradeCancelled.Connect)).to.equal("function")
      end)

      it("should have TradeRequestDeclined signal", function()
        expect(TradeController.TradeRequestDeclined).to.be.ok()
        expect(type(TradeController.TradeRequestDeclined.Connect)).to.equal("function")
      end)
    end)

    describe("State Query Methods", function()
      it("should have IsInTrade method", function()
        expect(type(TradeController.IsInTrade)).to.equal("function")
      end)

      it("should have GetCurrentTradeId method", function()
        expect(type(TradeController.GetCurrentTradeId)).to.equal("function")
      end)

      it("should have GetCurrentTrade method", function()
        expect(type(TradeController.GetCurrentTrade)).to.equal("function")
      end)

      it("should have GetPendingRequest method", function()
        expect(type(TradeController.GetPendingRequest)).to.equal("function")
      end)

      it("should have GetTradePartnerInfo method", function()
        expect(type(TradeController.GetTradePartnerInfo)).to.equal("function")
      end)

      it("should return not in trade initially", function()
        expect(TradeController:IsInTrade()).to.equal(false)
      end)

      it("should return nil trade ID initially", function()
        expect(TradeController:GetCurrentTradeId()).to.equal(nil)
      end)
    end)

    describe("Trade Request Methods", function()
      it("should have RequestTrade method", function()
        expect(type(TradeController.RequestTrade)).to.equal("function")
      end)

      it("should have AcceptTrade method", function()
        expect(type(TradeController.AcceptTrade)).to.equal("function")
      end)

      it("should have DeclineTrade method", function()
        expect(type(TradeController.DeclineTrade)).to.equal("function")
      end)
    end)

    describe("Offer Management Methods", function()
      it("should have AddItemToOffer method", function()
        expect(type(TradeController.AddItemToOffer)).to.equal("function")
      end)

      it("should have RemoveItemFromOffer method", function()
        expect(type(TradeController.RemoveItemFromOffer)).to.equal("function")
      end)

      it("should have SetConfirmation method", function()
        expect(type(TradeController.SetConfirmation)).to.equal("function")
      end)

      it("should have ConfirmTrade method", function()
        expect(type(TradeController.ConfirmTrade)).to.equal("function")
      end)

      it("should have UnconfirmTrade method", function()
        expect(type(TradeController.UnconfirmTrade)).to.equal("function")
      end)

      it("should have CancelTrade method", function()
        expect(type(TradeController.CancelTrade)).to.equal("function")
      end)
    end)

    describe("Error Handling", function()
      it("should return safe defaults when service unavailable", function()
        -- Before KnitStart, service is nil
        local pending = TradeController:GetPendingRequest()
        expect(pending.hasPending).to.equal(false)

        local inTrade = TradeController:IsInTrade()
        expect(inTrade).to.equal(false)
      end)
    end)
  end)
end
