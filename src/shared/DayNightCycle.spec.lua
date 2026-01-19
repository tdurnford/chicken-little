--[[
	DayNightCycle.spec.lua
	TestEZ tests for DayNightCycle module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local DayNightCycle = require(Shared:WaitForChild("DayNightCycle"))

  -- Helper to create mock state with specific game time
  local function createMockState(startTime: number?): DayNightCycle.DayNightState
    return {
      startTime = startTime or os.time(),
      colorCorrection = nil,
      bloom = nil,
    }
  end

  -- Helper to create state that results in a specific game hour
  local function createStateForGameHour(targetHour: number): DayNightCycle.DayNightState
    -- SECONDS_PER_GAME_HOUR = (10 * 60) / 24 = 25 seconds per game hour
    local SECONDS_PER_GAME_HOUR = (10 * 60) / 24
    local offset = targetHour * SECONDS_PER_GAME_HOUR
    return {
      startTime = os.time() - offset,
      colorCorrection = nil,
      bloom = nil,
    }
  end

  describe("DayNightCycle", function()
    describe("getTimeOfDay", function()
      it("should return valid period", function()
        local state = createMockState()
        local timeOfDay = DayNightCycle.getTimeOfDay(state)
        local validPeriods = { day = true, night = true, dawn = true, dusk = true }
        expect(validPeriods[timeOfDay]).to.be.ok()
      end)

      it("should return 'night' for hours 20-24", function()
        local state = createStateForGameHour(21)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("night")
      end)

      it("should return 'night' for hours 0-5", function()
        local state = createStateForGameHour(2)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("night")
      end)

      it("should return 'dawn' for hours 5-7", function()
        local state = createStateForGameHour(6)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("dawn")
      end)

      it("should return 'day' for hours 7-18", function()
        local state = createStateForGameHour(12)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("day")
      end)

      it("should return 'dusk' for hours 18-20", function()
        local state = createStateForGameHour(19)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("dusk")
      end)
    end)

    describe("getGameTime", function()
      it("should return number in range 0-24", function()
        local state = createMockState()
        local gameTime = DayNightCycle.getGameTime(state)
        expect(gameTime >= 0).to.equal(true)
        expect(gameTime < 24).to.equal(true)
      end)

      it("should return a number type", function()
        local state = createMockState()
        local gameTime = DayNightCycle.getGameTime(state)
        expect(typeof(gameTime)).to.equal("number")
      end)

      it("should increase over time", function()
        local state = createMockState()
        local time1 = DayNightCycle.getGameTime(state)
        -- Simulate 1 second passing by adjusting startTime
        state.startTime = state.startTime - 1
        local time2 = DayNightCycle.getGameTime(state)
        expect(time2 > time1).to.equal(true)
      end)

      it("should wrap around at 24", function()
        -- Create state where enough time has passed to cycle
        local SECONDS_PER_GAME_HOUR = (10 * 60) / 24
        local state = createMockState(os.time() - (25 * SECONDS_PER_GAME_HOUR))
        local gameTime = DayNightCycle.getGameTime(state)
        expect(gameTime >= 0).to.equal(true)
        expect(gameTime < 24).to.equal(true)
      end)
    end)

    describe("getPredatorSpawnMultiplier", function()
      it("should return valid multiplier in range 0.5-2.0", function()
        local state = createMockState()
        local multiplier = DayNightCycle.getPredatorSpawnMultiplier(state)
        expect(multiplier >= 0.5).to.equal(true)
        expect(multiplier <= 2.0).to.equal(true)
      end)

      it("should return 0.5 during day", function()
        local state = createStateForGameHour(12)
        local multiplier = DayNightCycle.getPredatorSpawnMultiplier(state)
        expect(multiplier).to.equal(0.5)
      end)

      it("should return 0.75 during dawn", function()
        local state = createStateForGameHour(6)
        local multiplier = DayNightCycle.getPredatorSpawnMultiplier(state)
        expect(multiplier).to.equal(0.75)
      end)

      it("should return 1.25 during dusk", function()
        local state = createStateForGameHour(19)
        local multiplier = DayNightCycle.getPredatorSpawnMultiplier(state)
        expect(multiplier).to.equal(1.25)
      end)

      it("should return 2.0 during night", function()
        local state = createStateForGameHour(22)
        local multiplier = DayNightCycle.getPredatorSpawnMultiplier(state)
        expect(multiplier).to.equal(2.0)
      end)
    end)

    describe("isNight", function()
      it("should return boolean", function()
        local state = createMockState()
        local result = DayNightCycle.isNight(state)
        expect(typeof(result)).to.equal("boolean")
      end)

      it("should return true during night hours", function()
        local state = createStateForGameHour(22)
        expect(DayNightCycle.isNight(state)).to.equal(true)
      end)

      it("should return false during day hours", function()
        local state = createStateForGameHour(12)
        expect(DayNightCycle.isNight(state)).to.equal(false)
      end)
    end)

    describe("isDawn", function()
      it("should return boolean", function()
        local state = createMockState()
        local result = DayNightCycle.isDawn(state)
        expect(typeof(result)).to.equal("boolean")
      end)

      it("should return true during dawn hours", function()
        local state = createStateForGameHour(6)
        expect(DayNightCycle.isDawn(state)).to.equal(true)
      end)

      it("should return false during night hours", function()
        local state = createStateForGameHour(22)
        expect(DayNightCycle.isDawn(state)).to.equal(false)
      end)
    end)

    describe("isDusk", function()
      it("should return boolean", function()
        local state = createMockState()
        local result = DayNightCycle.isDusk(state)
        expect(typeof(result)).to.equal("boolean")
      end)

      it("should return true during dusk hours", function()
        local state = createStateForGameHour(19)
        expect(DayNightCycle.isDusk(state)).to.equal(true)
      end)

      it("should return false during day hours", function()
        local state = createStateForGameHour(12)
        expect(DayNightCycle.isDusk(state)).to.equal(false)
      end)
    end)

    describe("isDay", function()
      it("should return boolean", function()
        local state = createMockState()
        local result = DayNightCycle.isDay(state)
        expect(typeof(result)).to.equal("boolean")
      end)

      it("should return true during day hours", function()
        local state = createStateForGameHour(12)
        expect(DayNightCycle.isDay(state)).to.equal(true)
      end)

      it("should return false during night hours", function()
        local state = createStateForGameHour(22)
        expect(DayNightCycle.isDay(state)).to.equal(false)
      end)
    end)

    describe("time period exclusivity", function()
      it("should have exactly one time period active", function()
        local state = createMockState()
        local isNight = DayNightCycle.isNight(state)
        local isDawn = DayNightCycle.isDawn(state)
        local isDusk = DayNightCycle.isDusk(state)
        local isDay = DayNightCycle.isDay(state)

        local trueCount = 0
        if isNight then
          trueCount = trueCount + 1
        end
        if isDawn then
          trueCount = trueCount + 1
        end
        if isDusk then
          trueCount = trueCount + 1
        end
        if isDay then
          trueCount = trueCount + 1
        end

        expect(trueCount).to.equal(1)
      end)

      it("should be consistent with getTimeOfDay", function()
        local state = createMockState()
        local timeOfDay = DayNightCycle.getTimeOfDay(state)

        if timeOfDay == "night" then
          expect(DayNightCycle.isNight(state)).to.equal(true)
        elseif timeOfDay == "dawn" then
          expect(DayNightCycle.isDawn(state)).to.equal(true)
        elseif timeOfDay == "dusk" then
          expect(DayNightCycle.isDusk(state)).to.equal(true)
        elseif timeOfDay == "day" then
          expect(DayNightCycle.isDay(state)).to.equal(true)
        end
      end)
    end)

    describe("getTimeInfo", function()
      it("should return valid info table", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        expect(info).to.be.ok()
        expect(typeof(info)).to.equal("table")
      end)

      it("should have gameTime field", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        expect(info.gameTime).to.be.ok()
        expect(typeof(info.gameTime)).to.equal("number")
      end)

      it("should have timeOfDay field", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        expect(info.timeOfDay).to.be.ok()
        expect(typeof(info.timeOfDay)).to.equal("string")
      end)

      it("should have isNight field", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        expect(info.isNight ~= nil).to.equal(true)
        expect(typeof(info.isNight)).to.equal("boolean")
      end)

      it("should have consistent gameTime with getGameTime", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        local directGameTime = DayNightCycle.getGameTime(state)
        expect(info.gameTime).to.equal(directGameTime)
      end)

      it("should have consistent timeOfDay with getTimeOfDay", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        local directTimeOfDay = DayNightCycle.getTimeOfDay(state)
        expect(info.timeOfDay).to.equal(directTimeOfDay)
      end)

      it("should have consistent isNight with isNight function", function()
        local state = createMockState()
        local info = DayNightCycle.getTimeInfo(state)
        local directIsNight = DayNightCycle.isNight(state)
        expect(info.isNight).to.equal(directIsNight)
      end)
    end)

    describe("init", function()
      it("should return a valid state object", function()
        local state = DayNightCycle.init()
        expect(state).to.be.ok()
        expect(typeof(state)).to.equal("table")
      end)

      it("should have startTime field", function()
        local state = DayNightCycle.init()
        expect(state.startTime).to.be.ok()
        expect(typeof(state.startTime)).to.equal("number")
      end)

      it("should start at approximately 9:00 AM game time", function()
        local state = DayNightCycle.init()
        local gameTime = DayNightCycle.getGameTime(state)
        -- Allow small tolerance for timing
        expect(gameTime >= 8.9).to.equal(true)
        expect(gameTime <= 9.1).to.equal(true)
      end)

      it("should start during day period", function()
        local state = DayNightCycle.init()
        expect(DayNightCycle.isDay(state)).to.equal(true)
      end)
    end)

    describe("time boundary conditions", function()
      it("should handle dawn start boundary (hour 5)", function()
        local state = createStateForGameHour(5)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("dawn")
      end)

      it("should handle day start boundary (hour 7)", function()
        local state = createStateForGameHour(7)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("day")
      end)

      it("should handle dusk start boundary (hour 18)", function()
        local state = createStateForGameHour(18)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("dusk")
      end)

      it("should handle night start boundary (hour 20)", function()
        local state = createStateForGameHour(20)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("night")
      end)

      it("should handle midnight (hour 0)", function()
        local state = createStateForGameHour(0)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("night")
      end)

      it("should handle just before dawn (hour 4.99)", function()
        local state = createStateForGameHour(4.99)
        expect(DayNightCycle.getTimeOfDay(state)).to.equal("night")
      end)
    end)

    describe("predator multiplier consistency", function()
      it("should have lowest multiplier during day", function()
        local dayState = createStateForGameHour(12)
        local nightState = createStateForGameHour(22)
        local dayMultiplier = DayNightCycle.getPredatorSpawnMultiplier(dayState)
        local nightMultiplier = DayNightCycle.getPredatorSpawnMultiplier(nightState)
        expect(dayMultiplier < nightMultiplier).to.equal(true)
      end)

      it("should have increasing danger from day to night", function()
        local dayMultiplier = DayNightCycle.getPredatorSpawnMultiplier(createStateForGameHour(12))
        local dawnMultiplier = DayNightCycle.getPredatorSpawnMultiplier(createStateForGameHour(6))
        local duskMultiplier = DayNightCycle.getPredatorSpawnMultiplier(createStateForGameHour(19))
        local nightMultiplier = DayNightCycle.getPredatorSpawnMultiplier(createStateForGameHour(22))

        expect(dayMultiplier < dawnMultiplier).to.equal(true)
        expect(dawnMultiplier < duskMultiplier).to.equal(true)
        expect(duskMultiplier < nightMultiplier).to.equal(true)
      end)
    end)
  end)
end
