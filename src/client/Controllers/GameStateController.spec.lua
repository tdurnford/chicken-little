--[[
	GameStateController Tests
	Tests for the client-side game state controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

  describe("GameStateController", function()
    -- Note: Full integration tests require Knit to be running.
    -- These tests verify the module structure and signal setup.

    local GameStateController

    beforeAll(function()
      -- In test environment, we just verify the module loads
      GameStateController = require(script.Parent.GameStateController)
    end)

    describe("Module Structure", function()
      it("should have Name property", function()
        expect(GameStateController.Name).to.equal("GameStateController")
      end)

      it("should have KnitInit method", function()
        expect(type(GameStateController.KnitInit)).to.equal("function")
      end)

      it("should have KnitStart method", function()
        expect(type(GameStateController.KnitStart)).to.equal("function")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have TimeChanged signal", function()
        expect(GameStateController.TimeChanged).to.be.ok()
        expect(type(GameStateController.TimeChanged.Connect)).to.equal("function")
      end)

      it("should have PeriodChanged signal", function()
        expect(GameStateController.PeriodChanged).to.be.ok()
        expect(type(GameStateController.PeriodChanged.Connect)).to.equal("function")
      end)

      it("should have NightStarted signal", function()
        expect(GameStateController.NightStarted).to.be.ok()
        expect(type(GameStateController.NightStarted.Connect)).to.equal("function")
      end)

      it("should have DayStarted signal", function()
        expect(GameStateController.DayStarted).to.be.ok()
        expect(type(GameStateController.DayStarted.Connect)).to.equal("function")
      end)
    end)

    describe("Cached State Methods", function()
      it("should have GetCachedTimeInfo method", function()
        expect(type(GameStateController.GetCachedTimeInfo)).to.equal("function")
      end)

      it("should have GetCachedPeriod method", function()
        expect(type(GameStateController.GetCachedPeriod)).to.equal("function")
      end)

      it("should have IsCachedNight method", function()
        expect(type(GameStateController.IsCachedNight)).to.equal("function")
      end)

      it("should have GetCachedGameTime method", function()
        expect(type(GameStateController.GetCachedGameTime)).to.equal("function")
      end)

      it("should have GetCachedPredatorMultiplier method", function()
        expect(type(GameStateController.GetCachedPredatorMultiplier)).to.equal("function")
      end)

      it("should return day period initially", function()
        expect(GameStateController:GetCachedPeriod()).to.equal("day")
      end)

      it("should return not night initially", function()
        expect(GameStateController:IsCachedNight()).to.equal(false)
      end)

      it("should return default game time when not cached", function()
        expect(GameStateController:GetCachedGameTime()).to.equal(12)
      end)

      it("should return default multiplier when not cached", function()
        expect(GameStateController:GetCachedPredatorMultiplier()).to.equal(1)
      end)
    end)

    describe("Server Query Methods", function()
      it("should have GetTimeInfo method", function()
        expect(type(GameStateController.GetTimeInfo)).to.equal("function")
      end)

      it("should have GetGameTime method", function()
        expect(type(GameStateController.GetGameTime)).to.equal("function")
      end)

      it("should have GetTimeOfDay method", function()
        expect(type(GameStateController.GetTimeOfDay)).to.equal("function")
      end)

      it("should have IsNight method", function()
        expect(type(GameStateController.IsNight)).to.equal("function")
      end)

      it("should have GetPredatorMultiplier method", function()
        expect(type(GameStateController.GetPredatorMultiplier)).to.equal("function")
      end)
    end)

    describe("Utility Methods", function()
      it("should have IsDangerousTime method", function()
        expect(type(GameStateController.IsDangerousTime)).to.equal("function")
      end)

      it("should have IsSafeTime method", function()
        expect(type(GameStateController.IsSafeTime)).to.equal("function")
      end)

      it("should have GetTimeDisplayString method", function()
        expect(type(GameStateController.GetTimeDisplayString)).to.equal("function")
      end)

      it("should have GetPeriodIcon method", function()
        expect(type(GameStateController.GetPeriodIcon)).to.equal("function")
      end)

      it("should return safe time for day period", function()
        -- Default cached period is day
        expect(GameStateController:IsSafeTime()).to.equal(true)
      end)

      it("should return not dangerous for day period", function()
        expect(GameStateController:IsDangerousTime()).to.equal(false)
      end)

      it("should return Day display string for day period", function()
        expect(GameStateController:GetTimeDisplayString()).to.equal("Day")
      end)

      it("should return sun icon for day period", function()
        expect(GameStateController:GetPeriodIcon()).to.equal("☀️")
      end)
    end)

    describe("Error Handling", function()
      it("should return safe defaults when service unavailable", function()
        -- Before KnitStart, service is nil
        local timeInfo = GameStateController:GetTimeInfo()
        expect(timeInfo.gameTime).to.equal(12)
        expect(timeInfo.timeOfDay).to.equal("day")
        expect(timeInfo.isNight).to.equal(false)
        expect(timeInfo.predatorMultiplier).to.equal(1)
      end)
    end)
  end)
end
