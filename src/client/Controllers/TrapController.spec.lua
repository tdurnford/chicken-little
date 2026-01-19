--[[
	TrapController Tests
	Tests for the client-side trap controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

  describe("TrapController", function()
    -- Note: Full integration tests require Knit to be running.
    -- These tests verify the module structure and signal setup.

    local TrapController

    beforeAll(function()
      -- In test environment, we just verify the module loads
      TrapController = require(script.Parent.TrapController)
    end)

    describe("Module Structure", function()
      it("should have Name property", function()
        expect(TrapController.Name).to.equal("TrapController")
      end)

      it("should have KnitInit method", function()
        expect(type(TrapController.KnitInit)).to.equal("function")
      end)

      it("should have KnitStart method", function()
        expect(type(TrapController.KnitStart)).to.equal("function")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have TrapPlaced signal", function()
        expect(TrapController.TrapPlaced).to.be.ok()
        expect(type(TrapController.TrapPlaced.Connect)).to.equal("function")
      end)

      it("should have TrapPickedUp signal", function()
        expect(TrapController.TrapPickedUp).to.be.ok()
        expect(type(TrapController.TrapPickedUp.Connect)).to.equal("function")
      end)

      it("should have TrapCaught signal", function()
        expect(TrapController.TrapCaught).to.be.ok()
        expect(type(TrapController.TrapCaught.Connect)).to.equal("function")
      end)

      it("should have TrapCooldownStarted signal", function()
        expect(TrapController.TrapCooldownStarted).to.be.ok()
        expect(type(TrapController.TrapCooldownStarted.Connect)).to.equal("function")
      end)

      it("should have TrapCooldownEnded signal", function()
        expect(TrapController.TrapCooldownEnded).to.be.ok()
        expect(type(TrapController.TrapCooldownEnded.Connect)).to.equal("function")
      end)

      it("should have PredatorCollected signal", function()
        expect(TrapController.PredatorCollected).to.be.ok()
        expect(type(TrapController.PredatorCollected.Connect)).to.equal("function")
      end)
    end)

    describe("Cache Methods", function()
      it("should have GetCachedTraps method", function()
        expect(type(TrapController.GetCachedTraps)).to.equal("function")
      end)

      it("should have GetCachedTrap method", function()
        expect(type(TrapController.GetCachedTrap)).to.equal("function")
      end)

      it("should have GetCachedTrapCount method", function()
        expect(type(TrapController.GetCachedTrapCount)).to.equal("function")
      end)

      it("should have ClearCache method", function()
        expect(type(TrapController.ClearCache)).to.equal("function")
      end)

      it("should return empty cache initially", function()
        local traps = TrapController:GetCachedTraps()
        expect(type(traps)).to.equal("table")
      end)

      it("should return 0 trap count initially", function()
        TrapController:ClearCache()
        local count = TrapController:GetCachedTrapCount()
        expect(count).to.equal(0)
      end)
    end)

    describe("Query Methods", function()
      it("should have GetPlacedTraps method", function()
        expect(type(TrapController.GetPlacedTraps)).to.equal("function")
      end)

      it("should have GetTrapSummary method", function()
        expect(type(TrapController.GetTrapSummary)).to.equal("function")
      end)

      it("should have GetCatchingSummary method", function()
        expect(type(TrapController.GetCatchingSummary)).to.equal("function")
      end)

      it("should have GetAvailableSpots method", function()
        expect(type(TrapController.GetAvailableSpots)).to.equal("function")
      end)

      it("should have GetPendingReward method", function()
        expect(type(TrapController.GetPendingReward)).to.equal("function")
      end)

      it("should have GetTrapConfig method", function()
        expect(type(TrapController.GetTrapConfig)).to.equal("function")
      end)

      it("should have GetAllTrapConfigs method", function()
        expect(type(TrapController.GetAllTrapConfigs)).to.equal("function")
      end)

      it("should have GetCatchProbability method", function()
        expect(type(TrapController.GetCatchProbability)).to.equal("function")
      end)

      it("should have CanPlaceMoreOfType method", function()
        expect(type(TrapController.CanPlaceMoreOfType)).to.equal("function")
      end)
    end)

    describe("Action Methods", function()
      it("should have PlaceTrap method", function()
        expect(type(TrapController.PlaceTrap)).to.equal("function")
      end)

      it("should have PlaceTrapFromInventory method", function()
        expect(type(TrapController.PlaceTrapFromInventory)).to.equal("function")
      end)

      it("should have PickupTrap method", function()
        expect(type(TrapController.PickupTrap)).to.equal("function")
      end)

      it("should have MoveTrap method", function()
        expect(type(TrapController.MoveTrap)).to.equal("function")
      end)

      it("should have CollectTrap method", function()
        expect(type(TrapController.CollectTrap)).to.equal("function")
      end)

      it("should have CollectAllTraps method", function()
        expect(type(TrapController.CollectAllTraps)).to.equal("function")
      end)
    end)

    describe("Error Handling", function()
      it("should return safe defaults when service unavailable", function()
        -- Before KnitStart, service is nil
        local summary = TrapController:GetTrapSummary()
        expect(summary.totalTraps).to.equal(0)

        local reward = TrapController:GetPendingReward()
        expect(reward).to.equal(0)
      end)
    end)
  end)
end
