--[[
	PredatorController.spec.lua
	Tests for the PredatorController client-side Knit controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local Knit = require(Packages:WaitForChild("Knit"))

  -- Get the controller (after Knit starts)
  local PredatorController

  describe("PredatorController", function()
    beforeAll(function()
      -- Wait for Knit to be ready and get controller
      PredatorController = Knit.GetController("PredatorController")
    end)

    describe("Initialization", function()
      it("should exist", function()
        expect(PredatorController).to.be.ok()
      end)

      it("should have correct name", function()
        expect(PredatorController.Name).to.equal("PredatorController")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have PredatorSpawned signal", function()
        expect(PredatorController.PredatorSpawned).to.be.ok()
        expect(PredatorController.PredatorSpawned.Fire).to.be.ok()
        expect(PredatorController.PredatorSpawned.Connect).to.be.ok()
      end)

      it("should have PredatorPositionUpdated signal", function()
        expect(PredatorController.PredatorPositionUpdated).to.be.ok()
        expect(PredatorController.PredatorPositionUpdated.Fire).to.be.ok()
      end)

      it("should have PredatorHealthUpdated signal", function()
        expect(PredatorController.PredatorHealthUpdated).to.be.ok()
        expect(PredatorController.PredatorHealthUpdated.Fire).to.be.ok()
      end)

      it("should have PredatorDefeated signal", function()
        expect(PredatorController.PredatorDefeated).to.be.ok()
        expect(PredatorController.PredatorDefeated.Fire).to.be.ok()
      end)

      it("should have PredatorTargetChanged signal", function()
        expect(PredatorController.PredatorTargetChanged).to.be.ok()
        expect(PredatorController.PredatorTargetChanged.Fire).to.be.ok()
      end)

      it("should have PredatorAlert signal", function()
        expect(PredatorController.PredatorAlert).to.be.ok()
        expect(PredatorController.PredatorAlert.Fire).to.be.ok()
      end)
    end)

    describe("Service Methods", function()
      it("should have AttackPredator method", function()
        expect(PredatorController.AttackPredator).to.be.ok()
        expect(typeof(PredatorController.AttackPredator)).to.equal("function")
      end)

      it("should have GetActivePredators method", function()
        expect(PredatorController.GetActivePredators).to.be.ok()
        expect(typeof(PredatorController.GetActivePredators)).to.equal("function")
      end)

      it("should have GetSpawnSummary method", function()
        expect(PredatorController.GetSpawnSummary).to.be.ok()
        expect(typeof(PredatorController.GetSpawnSummary)).to.equal("function")
      end)
    end)

    describe("Cache Methods", function()
      it("should have GetCachedPredators method", function()
        expect(PredatorController.GetCachedPredators).to.be.ok()
        expect(typeof(PredatorController.GetCachedPredators)).to.equal("function")
      end)

      it("should return table from GetCachedPredators", function()
        local predators = PredatorController:GetCachedPredators()
        expect(typeof(predators)).to.equal("table")
      end)

      it("should have GetCachedPredator method", function()
        expect(PredatorController.GetCachedPredator).to.be.ok()
        expect(typeof(PredatorController.GetCachedPredator)).to.equal("function")
      end)

      it("should return nil for non-existent predator", function()
        local predator = PredatorController:GetCachedPredator("non-existent-id")
        expect(predator).to.never.be.ok()
      end)

      it("should have GetActivePredatorCount method", function()
        expect(PredatorController.GetActivePredatorCount).to.be.ok()
        expect(typeof(PredatorController.GetActivePredatorCount)).to.equal("function")
      end)

      it("should return number from GetActivePredatorCount", function()
        local count = PredatorController:GetActivePredatorCount()
        expect(typeof(count)).to.equal("number")
        expect(count).to.be.near(0, 1000) -- Some reasonable range
      end)

      it("should have HasActivePredators method", function()
        expect(PredatorController.HasActivePredators).to.be.ok()
        expect(typeof(PredatorController.HasActivePredators)).to.equal("function")
      end)

      it("should return boolean from HasActivePredators", function()
        local hasPredators = PredatorController:HasActivePredators()
        expect(typeof(hasPredators)).to.equal("boolean")
      end)
    end)

    describe("Filter Methods", function()
      it("should have GetPredatorsByThreat method", function()
        expect(PredatorController.GetPredatorsByThreat).to.be.ok()
        expect(typeof(PredatorController.GetPredatorsByThreat)).to.equal("function")
      end)

      it("should return table from GetPredatorsByThreat", function()
        local predators = PredatorController:GetPredatorsByThreat("Minor")
        expect(typeof(predators)).to.equal("table")
      end)

      it("should have GetPredatorsTargetingChicken method", function()
        expect(PredatorController.GetPredatorsTargetingChicken).to.be.ok()
        expect(typeof(PredatorController.GetPredatorsTargetingChicken)).to.equal("function")
      end)

      it("should return table from GetPredatorsTargetingChicken", function()
        local predators = PredatorController:GetPredatorsTargetingChicken("some-chicken-id")
        expect(typeof(predators)).to.equal("table")
      end)
    end)

    describe("Default Return Values", function()
      it("should return safe defaults from GetSpawnSummary when service unavailable", function()
        -- This tests the fallback behavior
        local summary = PredatorController:GetSpawnSummary()
        expect(typeof(summary)).to.equal("table")
      end)
    end)
  end)
end
