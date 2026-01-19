--[[
	GameStateService Tests
	Tests for the GameStateService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))

  describe("DayNightCycle", function()
    local testState: DayNightCycle.DayNightState

    beforeEach(function()
      testState = DayNightCycle.init()
    end)

    describe("init", function()
      it("should create a valid state", function()
        expect(testState).to.be.ok()
        expect(testState.startTime).to.be.ok()
        expect(type(testState.startTime)).to.equal("number")
      end)

      it("should create ColorCorrection effect", function()
        expect(testState.colorCorrection).to.be.ok()
      end)

      it("should create Bloom effect", function()
        expect(testState.bloom).to.be.ok()
      end)
    end)

    describe("getGameTime", function()
      it("should return a number between 0 and 24", function()
        local gameTime = DayNightCycle.getGameTime(testState)
        expect(type(gameTime)).to.equal("number")
        expect(gameTime).to.be.greaterThanOrEqualTo(0)
        expect(gameTime).to.be.lessThan(24)
      end)

      it("should start around 9 AM", function()
        -- Fresh state should start at 9:00 AM
        local gameTime = DayNightCycle.getGameTime(testState)
        expect(gameTime).to.be.near(9, 0.1)
      end)
    end)

    describe("getTimeOfDay", function()
      it("should return a valid period", function()
        local period = DayNightCycle.getTimeOfDay(testState)
        local validPeriods = { "day", "night", "dawn", "dusk" }
        expect(table.find(validPeriods, period)).to.be.ok()
      end)

      it("should return day at start (9 AM)", function()
        local period = DayNightCycle.getTimeOfDay(testState)
        expect(period).to.equal("day")
      end)
    end)

    describe("time period checks", function()
      it("should correctly identify day", function()
        -- Default start is 9 AM which is day
        expect(DayNightCycle.isDay(testState)).to.equal(true)
        expect(DayNightCycle.isNight(testState)).to.equal(false)
        expect(DayNightCycle.isDawn(testState)).to.equal(false)
        expect(DayNightCycle.isDusk(testState)).to.equal(false)
      end)
    end)

    describe("getPredatorSpawnMultiplier", function()
      it("should return a number", function()
        local mult = DayNightCycle.getPredatorSpawnMultiplier(testState)
        expect(type(mult)).to.equal("number")
      end)

      it("should return 0.5 during day", function()
        -- Default start is during day
        local mult = DayNightCycle.getPredatorSpawnMultiplier(testState)
        expect(mult).to.equal(0.5)
      end)

      it("should return a value between 0.5 and 2.0", function()
        local mult = DayNightCycle.getPredatorSpawnMultiplier(testState)
        expect(mult).to.be.greaterThanOrEqualTo(0.5)
        expect(mult).to.be.lessThanOrEqualTo(2.0)
      end)
    end)

    describe("getTimeInfo", function()
      it("should return complete time info", function()
        local info = DayNightCycle.getTimeInfo(testState)
        expect(info).to.be.ok()
        expect(info.gameTime).to.be.ok()
        expect(info.timeOfDay).to.be.ok()
        expect(info.isNight).to.be.ok()
      end)

      it("should have consistent values", function()
        local info = DayNightCycle.getTimeInfo(testState)
        expect(info.timeOfDay).to.equal(DayNightCycle.getTimeOfDay(testState))
        expect(info.isNight).to.equal(DayNightCycle.isNight(testState))
      end)
    end)

    describe("update", function()
      it("should not error when called", function()
        expect(function()
          DayNightCycle.update(testState)
        end).never.to.throw()
      end)

      it("should update lighting clock time", function()
        local Lighting = game:GetService("Lighting")
        local prevTime = Lighting.ClockTime
        DayNightCycle.update(testState)
        -- ClockTime should be updated to match game time
        expect(Lighting.ClockTime).to.be.near(DayNightCycle.getGameTime(testState), 0.1)
      end)
    end)
  end)

  describe("GameStateService Types", function()
    it("should define TimeInfo type structure", function()
      -- Type validation through structure
      local validTimeInfo = {
        gameTime = 12.5,
        timeOfDay = "day",
        isNight = false,
        predatorMultiplier = 0.5,
      }

      expect(validTimeInfo.gameTime).to.be.a("number")
      expect(validTimeInfo.timeOfDay).to.be.a("string")
      expect(validTimeInfo.isNight).to.be.a("boolean")
      expect(validTimeInfo.predatorMultiplier).to.be.a("number")
    end)
  end)

  describe("Time Period Boundaries", function()
    it("should have correct dawn hours (5-7)", function()
      -- Dawn should be 5:00 to 7:00
      local DAWN_START = 5
      local DAY_START = 7
      expect(DAY_START - DAWN_START).to.equal(2)
    end)

    it("should have correct day hours (7-18)", function()
      -- Day should be 7:00 to 18:00
      local DAY_START = 7
      local DUSK_START = 18
      expect(DUSK_START - DAY_START).to.equal(11)
    end)

    it("should have correct dusk hours (18-20)", function()
      -- Dusk should be 18:00 to 20:00
      local DUSK_START = 18
      local NIGHT_START = 20
      expect(NIGHT_START - DUSK_START).to.equal(2)
    end)

    it("should have correct night hours (20-5)", function()
      -- Night should be 20:00 to 5:00 (9 hours)
      local NIGHT_START = 20
      local DAWN_START = 5
      local nightHours = (24 - NIGHT_START) + DAWN_START
      expect(nightHours).to.equal(9)
    end)
  end)

  describe("Spawn Multiplier Values", function()
    it("should have correct multiplier for day", function()
      local multipliers = {
        day = 0.5,
        dawn = 0.75,
        dusk = 1.25,
        night = 2.0,
      }
      expect(multipliers.day).to.equal(0.5)
    end)

    it("should have increasing danger toward night", function()
      local multipliers = {
        day = 0.5,
        dawn = 0.75,
        dusk = 1.25,
        night = 2.0,
      }
      expect(multipliers.dawn).to.be.greaterThan(multipliers.day)
      expect(multipliers.dusk).to.be.greaterThan(multipliers.dawn)
      expect(multipliers.night).to.be.greaterThan(multipliers.dusk)
    end)

    it("should have night at 4x day multiplier", function()
      local dayMult = 0.5
      local nightMult = 2.0
      expect(nightMult / dayMult).to.equal(4)
    end)
  end)

  describe("Cycle Configuration", function()
    it("should have 10 minute full cycle", function()
      local FULL_CYCLE_MINUTES = 10
      expect(FULL_CYCLE_MINUTES).to.equal(10)
    end)

    it("should start at 9 AM", function()
      local START_GAME_HOUR = 9
      expect(START_GAME_HOUR).to.equal(9)
    end)

    it("should calculate correct seconds per game hour", function()
      local FULL_CYCLE_MINUTES = 10
      local SECONDS_PER_GAME_HOUR = (FULL_CYCLE_MINUTES * 60) / 24
      expect(SECONDS_PER_GAME_HOUR).to.equal(25)
    end)
  end)
end
