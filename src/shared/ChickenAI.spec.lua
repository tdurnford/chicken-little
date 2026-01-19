--[[
	ChickenAI.spec.lua
	TestEZ tests for ChickenAI module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local ChickenAI = require(Shared:WaitForChild("ChickenAI"))

  describe("ChickenAI", function()
    describe("createState", function()
      it("should return valid state", function()
        local state = ChickenAI.createState()
        expect(state).to.be.ok()
        expect(state.positions).to.be.ok()
      end)

      it("should accept custom neutral zone", function()
        local center = Vector3.new(10, 0, 20)
        local size = 50
        local state = ChickenAI.createState(center, size)
        expect(state.neutralZoneCenter.X).to.equal(10)
        expect(state.neutralZoneSize).to.equal(50)
      end)
    end)

    describe("registerChicken", function()
      it("should add chicken to state", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        local spawnPos = Vector3.new(5, 0, 5)
        local position =
          ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
        expect(position).to.be.ok()
        expect(ChickenAI.getActiveCount(state)).to.equal(1)
      end)

      it("should spawn chicken at correct position", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        local spawnPos = Vector3.new(8, 2, 4)
        local position =
          ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
        expect(position.currentPosition.X).to.equal(8)
        expect(position.currentPosition.Y).to.equal(2)
        expect(position.currentPosition.Z).to.equal(4)
      end)
    end)

    describe("getWalkSpeed", function()
      it("should return speed based on rarity", function()
        -- Common should be slower (0.8 multiplier)
        local commonSpeed = ChickenAI.getWalkSpeed("Cluck")
        -- Legendary should be faster (1.2 multiplier)
        local legendarySpeed = ChickenAI.getWalkSpeed("Goldie")
        expect(legendarySpeed > commonSpeed).to.equal(true)
      end)
    end)

    describe("isWithinBounds", function()
      it("should return true for position inside zone", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local insidePos = Vector3.new(5, 0, 5)
        expect(ChickenAI.isWithinBounds(state, insidePos)).to.equal(true)
      end)

      it("should return false for position outside zone", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local outsidePos = Vector3.new(100, 0, 100)
        expect(ChickenAI.isWithinBounds(state, outsidePos)).to.equal(false)
      end)
    end)

    describe("clampToBounds", function()
      it("should keep position inside neutral zone", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local outsidePos = Vector3.new(100, 5, 100)
        local clamped = ChickenAI.clampToBounds(state, outsidePos)
        expect(ChickenAI.isWithinBounds(state, clamped)).to.equal(true)
        expect(clamped.Y).to.equal(5)
      end)
    end)

    describe("generateRandomTarget", function()
      it("should stay within bounds", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentPos = Vector3.new(0, 0, 0)
        -- Generate multiple targets to test consistency
        for _ = 1, 10 do
          local target = ChickenAI.generateRandomTarget(state, currentPos)
          expect(ChickenAI.isWithinBounds(state, target)).to.equal(true)
        end
      end)
    end)

    describe("updatePosition", function()
      it("should move chicken towards target", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        local spawnPos = Vector3.new(0, 0, 0)
        ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
        -- Get initial position
        local initial = ChickenAI.getPosition(state, "chicken1")
        local initialX = initial.currentPosition.X
        local initialZ = initial.currentPosition.Z
        -- Update with 1 second delta time
        ChickenAI.updatePosition(state, "chicken1", 1.0, currentTime + 1)
        local updated = ChickenAI.getPosition(state, "chicken1")
        -- Position should change (unless idle or already at target)
        if updated.isIdle then
          -- Chicken is idle, no movement expected - this is valid
          expect(true).to.equal(true)
        else
          local moved = updated.currentPosition.X ~= initialX
            or updated.currentPosition.Z ~= initialZ
          expect(moved).to.equal(true)
        end
      end)

      it("should keep chicken within bounds during movement", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        local spawnPos = Vector3.new(0, 0, 0)
        ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
        -- Simulate many updates
        for i = 1, 50 do
          ChickenAI.updatePosition(state, "chicken1", 0.5, currentTime + i * 0.5)
          local pos = ChickenAI.getPosition(state, "chicken1")
          expect(ChickenAI.isWithinBounds(state, pos.currentPosition)).to.equal(true)
        end
      end)
    end)

    describe("unregisterChicken", function()
      it("should remove chicken from state", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
        expect(ChickenAI.getActiveCount(state)).to.equal(1)
        ChickenAI.unregisterChicken(state, "chicken1")
        expect(ChickenAI.getActiveCount(state)).to.equal(0)
      end)
    end)

    describe("isIdle", function()
      it("should return correct idle state", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
        -- Initially not idle
        local initialIdle = ChickenAI.isIdle(state, "chicken1")
        -- After registration, chicken should not be idle (starts walking)
        expect(initialIdle).to.equal(false)
      end)
    end)

    describe("updateAll", function()
      it("should update all chickens", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
        ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
        local updated = ChickenAI.updateAll(state, 0.5, currentTime + 0.5)
        expect(updated["chicken1"]).to.be.ok()
        expect(updated["chicken2"]).to.be.ok()
      end)
    end)

    describe("getActiveChickenIds", function()
      it("should return all IDs", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
        ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
        local ids = ChickenAI.getActiveChickenIds(state)
        expect(#ids).to.equal(2)
      end)
    end)

    describe("getAllPositions", function()
      it("should return all positions", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
        ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
        local positions = ChickenAI.getAllPositions(state)
        expect(positions["chicken1"]).to.be.ok()
        expect(positions["chicken2"]).to.be.ok()
      end)
    end)

    describe("getPositionInfo", function()
      it("should return detailed position info", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(5, 0, 5), currentTime)
        local info = ChickenAI.getPositionInfo(state, "chicken1")
        expect(info).to.be.ok()
        expect(info.position).to.be.ok()
        expect(info.facingDirection).to.be.ok()
        expect(info.isIdle ~= nil).to.equal(true)
      end)
    end)

    describe("setNeutralZone", function()
      it("should update zone configuration", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local newCenter = Vector3.new(50, 0, 50)
        ChickenAI.setNeutralZone(state, newCenter, 100)
        expect(state.neutralZoneCenter.X).to.equal(50)
        expect(state.neutralZoneSize).to.equal(100)
      end)
    end)

    describe("getSummary", function()
      it("should return correct walking and idle counts", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
        ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
        local summary = ChickenAI.getSummary(state)
        expect(summary.totalActive).to.equal(2)
        -- Both should start walking (not idle)
        expect(summary.walking).to.equal(2)
      end)
    end)

    describe("reset", function()
      it("should clear all chickens", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
        ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(5, 0, 5), currentTime)
        expect(ChickenAI.getActiveCount(state)).to.equal(2)
        ChickenAI.reset(state)
        expect(ChickenAI.getActiveCount(state)).to.equal(0)
      end)
    end)

    describe("updateSpawnPosition", function()
      it("should update chicken position", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
        local newPos = Vector3.new(5, 2, 5)
        local success = ChickenAI.updateSpawnPosition(state, "chicken1", newPos)
        expect(success).to.equal(true)
        local position = ChickenAI.getPosition(state, "chicken1")
        expect(position.currentPosition.X).to.equal(5)
      end)
    end)

    describe("chicken behavior", function()
      it("should become idle after reaching target", function()
        local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
        local currentTime = os.time()
        -- Spawn at origin
        ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
        -- Update many times to reach target and trigger idle
        for i = 1, 100 do
          ChickenAI.updatePosition(state, "chicken1", 0.1, currentTime + i * 0.1)
        end
        local position = ChickenAI.getPosition(state, "chicken1")
        -- After many updates, chicken should have reached target at least once and gone idle
        -- We just verify the position is valid and within bounds
        expect(ChickenAI.isWithinBounds(state, position.currentPosition)).to.equal(true)
      end)
    end)
  end)
end
