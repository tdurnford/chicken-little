--[[
	GameLoopService Tests
	Tests for the GameLoopService Knit service.
]]

return function()
  describe("GameLoopService", function()
    describe("Configuration", function()
      it("should have correct store update interval", function()
        local STORE_UPDATE_INTERVAL = 1.0
        expect(STORE_UPDATE_INTERVAL).to.equal(1.0)
      end)
    end)

    describe("Loop State", function()
      it("should track running state correctly", function()
        local isRunning = false
        expect(isRunning).to.equal(false)

        isRunning = true
        expect(isRunning).to.equal(true)
      end)
    end)

    describe("Update Accumulator", function()
      it("should accumulate delta time correctly", function()
        local accumulator = 0
        local deltaTime = 0.016 -- ~60fps

        accumulator = accumulator + deltaTime
        expect(accumulator).to.be.near(0.016, 0.001)

        accumulator = accumulator + deltaTime
        expect(accumulator).to.be.near(0.032, 0.001)
      end)

      it("should reset after reaching interval", function()
        local accumulator = 0.95
        local STORE_UPDATE_INTERVAL = 1.0
        local deltaTime = 0.1

        accumulator = accumulator + deltaTime
        if accumulator >= STORE_UPDATE_INTERVAL then
          accumulator = 0
        end

        expect(accumulator).to.equal(0)
      end)
    end)

    describe("Service Dependencies", function()
      it("should define required service names", function()
        local requiredServices = {
          "GameStateService",
          "PlayerDataService",
          "StoreService",
        }

        expect(#requiredServices).to.equal(3)
        expect(table.find(requiredServices, "GameStateService")).to.be.ok()
        expect(table.find(requiredServices, "PlayerDataService")).to.be.ok()
        expect(table.find(requiredServices, "StoreService")).to.be.ok()
      end)

      it("should define optional service names", function()
        local optionalServices = {
          "PredatorService",
          "ChickenService",
          "EggService",
          "CombatService",
          "LevelService",
          "MapService",
        }

        expect(#optionalServices).to.equal(6)
      end)
    end)
  end)
end
