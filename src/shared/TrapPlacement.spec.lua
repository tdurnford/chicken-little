--[[
	TrapPlacement.spec.lua
	TestEZ tests for TrapPlacement module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))

  -- Helper function to create mock player data
  local function createMockPlayerData()
    return {
      money = 10000,
      traps = {},
      inventory = {
        eggs = {},
        chickens = {},
      },
      placedChickens = {},
      upgrades = {
        cageTier = 1,
      },
    }
  end

  -- Helper function to create a mock trap
  local function createMockTrap(id, trapType, spotIndex, cooldownEndTime, caughtPredator)
    return {
      id = id or "trap-" .. tostring(math.random(1000, 9999)),
      trapType = trapType or "BasicTrap",
      tier = 1,
      spotIndex = spotIndex,
      cooldownEndTime = cooldownEndTime,
      caughtPredator = caughtPredator,
    }
  end

  describe("TrapPlacement", function()
    describe("getMaxSpots", function()
      it("should return the maximum number of trap spots", function()
        local maxSpots = TrapPlacement.getMaxSpots()
        expect(maxSpots).to.equal(8)
      end)

      it("should return a positive number", function()
        expect(TrapPlacement.getMaxSpots() > 0).to.equal(true)
      end)
    end)

    describe("isValidSpot", function()
      it("should return true for valid spot indices (1-8)", function()
        for i = 1, 8 do
          expect(TrapPlacement.isValidSpot(i)).to.equal(true)
        end
      end)

      it("should return false for spot index 0", function()
        expect(TrapPlacement.isValidSpot(0)).to.equal(false)
      end)

      it("should return false for negative spot indices", function()
        expect(TrapPlacement.isValidSpot(-1)).to.equal(false)
        expect(TrapPlacement.isValidSpot(-5)).to.equal(false)
      end)

      it("should return false for spot indices above 8", function()
        expect(TrapPlacement.isValidSpot(9)).to.equal(false)
        expect(TrapPlacement.isValidSpot(100)).to.equal(false)
      end)

      it("should return false for non-integer values", function()
        expect(TrapPlacement.isValidSpot(1.5)).to.equal(false)
        expect(TrapPlacement.isValidSpot(5.7)).to.equal(false)
      end)

      it("should return false for non-number values", function()
        expect(TrapPlacement.isValidSpot("1" :: any)).to.equal(false)
        expect(TrapPlacement.isValidSpot(nil :: any)).to.equal(false)
        expect(TrapPlacement.isValidSpot({} :: any)).to.equal(false)
      end)
    end)

    describe("getOccupiedSpots", function()
      it("should return empty table when no traps placed", function()
        local playerData = createMockPlayerData()
        local occupied = TrapPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(0)
      end)

      it("should return occupied spot indices", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 5),
          createMockTrap("t3", "BasicTrap", 8),
        }
        local occupied = TrapPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(3)
      end)

      it("should not include traps with spotIndex outside valid range", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", -1), -- Invalid/inventory
          createMockTrap("t3", "BasicTrap", 10), -- Out of range
        }
        local occupied = TrapPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(1)
      end)
    end)

    describe("getAvailableSpots", function()
      it("should return all spots when no traps placed", function()
        local playerData = createMockPlayerData()
        local available = TrapPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(8)
      end)

      it("should exclude occupied spots", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 3),
        }
        local available = TrapPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(6)
      end)

      it("should return empty table when all spots are filled", function()
        local playerData = createMockPlayerData()
        for i = 1, 8 do
          table.insert(playerData.traps, createMockTrap("t" .. i, "BasicTrap", i))
        end
        local available = TrapPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(0)
      end)
    end)

    describe("isSpotOccupied", function()
      it("should return false for empty spots", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.isSpotOccupied(playerData, 1)).to.equal(false)
      end)

      it("should return true for occupied spots", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 3) }
        expect(TrapPlacement.isSpotOccupied(playerData, 3)).to.equal(true)
      end)

      it("should return false for invalid spot indices", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.isSpotOccupied(playerData, 0)).to.equal(false)
        expect(TrapPlacement.isSpotOccupied(playerData, 9)).to.equal(false)
      end)
    end)

    describe("isSpotAvailable", function()
      it("should return true for empty valid spots", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.isSpotAvailable(playerData, 1)).to.equal(true)
      end)

      it("should return false for occupied spots", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 3) }
        expect(TrapPlacement.isSpotAvailable(playerData, 3)).to.equal(false)
      end)

      it("should return false for invalid spot indices", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.isSpotAvailable(playerData, 0)).to.equal(false)
        expect(TrapPlacement.isSpotAvailable(playerData, 9)).to.equal(false)
      end)
    end)

    describe("getTrapAtSpot", function()
      it("should return nil for empty spots", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.getTrapAtSpot(playerData, 1)).to.equal(nil)
      end)

      it("should return the trap at a given spot", function()
        local playerData = createMockPlayerData()
        local trap = createMockTrap("t1", "BasicTrap", 3)
        playerData.traps = { trap }
        local result = TrapPlacement.getTrapAtSpot(playerData, 3)
        expect(result).to.be.ok()
        expect(result.id).to.equal("t1")
      end)

      it("should return nil for invalid spot indices", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.getTrapAtSpot(playerData, 0)).to.equal(nil)
        expect(TrapPlacement.getTrapAtSpot(playerData, 9)).to.equal(nil)
      end)
    end)

    describe("findTrap", function()
      it("should return nil for non-existent trap", function()
        local playerData = createMockPlayerData()
        local trap, index = TrapPlacement.findTrap(playerData, "nonexistent")
        expect(trap).to.equal(nil)
        expect(index).to.equal(nil)
      end)

      it("should return trap and index for existing trap", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2),
        }
        local trap, index = TrapPlacement.findTrap(playerData, "t2")
        expect(trap).to.be.ok()
        expect(trap.id).to.equal("t2")
        expect(index).to.equal(2)
      end)
    end)

    describe("countTrapsOfType", function()
      it("should return 0 when no traps of type exist", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.countTrapsOfType(playerData, "BasicTrap")).to.equal(0)
      end)

      it("should count traps of a specific type", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "SpikedTrap", 2),
          createMockTrap("t3", "BasicTrap", 3),
        }
        expect(TrapPlacement.countTrapsOfType(playerData, "BasicTrap")).to.equal(2)
        expect(TrapPlacement.countTrapsOfType(playerData, "SpikedTrap")).to.equal(1)
      end)
    end)

    describe("placeTrap", function()
      it("should fail for invalid trap type", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrap(playerData, "InvalidTrap", 1)
        expect(result.success).to.equal(false)
        expect(result.trap).to.equal(nil)
      end)

      it("should fail for invalid spot index", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrap(playerData, "BasicTrap", 0)
        expect(result.success).to.equal(false)
      end)

      it("should fail if spot is occupied", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local result = TrapPlacement.placeTrap(playerData, "BasicTrap", 1)
        expect(result.success).to.equal(false)
      end)

      it("should fail if player cannot afford the trap", function()
        local playerData = createMockPlayerData()
        playerData.money = 0
        local result = TrapPlacement.placeTrap(playerData, "BasicTrap", 1)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("placeTrapFromInventory", function()
      it("should fail for invalid spot index", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrapFromInventory(playerData, "t1", 0)
        expect(result.success).to.equal(false)
      end)

      it("should fail if spot is occupied", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", -1), -- In inventory
        }
        local result = TrapPlacement.placeTrapFromInventory(playerData, "t2", 1)
        expect(result.success).to.equal(false)
      end)

      it("should fail if trap not found", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrapFromInventory(playerData, "nonexistent", 1)
        expect(result.success).to.equal(false)
      end)

      it("should fail if trap is already placed", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 3) }
        local result = TrapPlacement.placeTrapFromInventory(playerData, "t1", 1)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("pickupTrap", function()
      it("should fail if trap not found", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.pickupTrap(playerData, "nonexistent")
        expect(result.success).to.equal(false)
      end)

      it("should remove trap and return sell price", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local initialMoney = playerData.money
        local result = TrapPlacement.pickupTrap(playerData, "t1")
        expect(result.success).to.equal(true)
        expect(#playerData.traps).to.equal(0)
      end)
    end)

    describe("moveTrap", function()
      it("should fail for invalid new spot", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local result = TrapPlacement.moveTrap(playerData, "t1", 0)
        expect(result.success).to.equal(false)
      end)

      it("should fail if trap not found", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.moveTrap(playerData, "nonexistent", 2)
        expect(result.success).to.equal(false)
      end)

      it("should succeed if moving to same spot", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local result = TrapPlacement.moveTrap(playerData, "t1", 1)
        expect(result.success).to.equal(true)
      end)

      it("should fail if new spot is occupied", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2),
        }
        local result = TrapPlacement.moveTrap(playerData, "t1", 2)
        expect(result.success).to.equal(false)
      end)

      it("should move trap to new spot", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local result = TrapPlacement.moveTrap(playerData, "t1", 5)
        expect(result.success).to.equal(true)
        expect(playerData.traps[1].spotIndex).to.equal(5)
      end)
    end)

    describe("getTrapState", function()
      it("should return not on cooldown when no cooldown set", function()
        local trap = createMockTrap("t1", "BasicTrap", 1)
        local state = TrapPlacement.getTrapState(trap, os.time())
        expect(state.isOnCooldown).to.equal(false)
        expect(state.cooldownRemaining).to.equal(0)
      end)

      it("should return on cooldown when cooldown active", function()
        local currentTime = os.time()
        local trap = createMockTrap("t1", "BasicTrap", 1, currentTime + 100)
        local state = TrapPlacement.getTrapState(trap, currentTime)
        expect(state.isOnCooldown).to.equal(true)
        expect(state.cooldownRemaining).to.equal(100)
      end)

      it("should return hasCaughtPredator correctly", function()
        local trap = createMockTrap("t1", "BasicTrap", 1, nil, "Fox")
        local state = TrapPlacement.getTrapState(trap, os.time())
        expect(state.hasCaughtPredator).to.equal(true)
      end)
    end)

    describe("isReadyToCatch", function()
      it("should return true when no cooldown and no predator", function()
        local trap = createMockTrap("t1", "BasicTrap", 1)
        expect(TrapPlacement.isReadyToCatch(trap, os.time())).to.equal(true)
      end)

      it("should return false when has caught predator", function()
        local trap = createMockTrap("t1", "BasicTrap", 1, nil, "Fox")
        expect(TrapPlacement.isReadyToCatch(trap, os.time())).to.equal(false)
      end)

      it("should return false when on cooldown", function()
        local currentTime = os.time()
        local trap = createMockTrap("t1", "BasicTrap", 1, currentTime + 100)
        expect(TrapPlacement.isReadyToCatch(trap, currentTime)).to.equal(false)
      end)
    end)

    describe("startCooldown", function()
      it("should return false if trap not found", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.startCooldown(playerData, "nonexistent", os.time())).to.equal(false)
      end)

      it("should set cooldown end time", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local currentTime = os.time()
        local result = TrapPlacement.startCooldown(playerData, "t1", currentTime)
        expect(result).to.equal(true)
        expect(playerData.traps[1].cooldownEndTime).to.be.ok()
      end)
    end)

    describe("clearCooldown", function()
      it("should return false if trap not found", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.clearCooldown(playerData, "nonexistent")).to.equal(false)
      end)

      it("should clear cooldown end time", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1, os.time() + 100) }
        local result = TrapPlacement.clearCooldown(playerData, "t1")
        expect(result).to.equal(true)
        expect(playerData.traps[1].cooldownEndTime).to.equal(nil)
      end)
    end)

    describe("setCaughtPredator", function()
      it("should return false if trap not found", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.setCaughtPredator(playerData, "nonexistent", "Fox")).to.equal(false)
      end)

      it("should set caught predator", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local result = TrapPlacement.setCaughtPredator(playerData, "t1", "Fox")
        expect(result).to.equal(true)
        expect(playerData.traps[1].caughtPredator).to.equal("Fox")
      end)
    end)

    describe("clearCaughtPredator", function()
      it("should return nil if trap not found", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.clearCaughtPredator(playerData, "nonexistent")).to.equal(nil)
      end)

      it("should clear and return caught predator", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1, nil, "Fox") }
        local predator = TrapPlacement.clearCaughtPredator(playerData, "t1")
        expect(predator).to.equal("Fox")
        expect(playerData.traps[1].caughtPredator).to.equal(nil)
      end)
    end)

    describe("getPlacedTrapCount", function()
      it("should return 0 when no traps", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.getPlacedTrapCount(playerData)).to.equal(0)
      end)

      it("should return correct count", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2),
        }
        expect(TrapPlacement.getPlacedTrapCount(playerData)).to.equal(2)
      end)
    end)

    describe("areAllSpotsFull", function()
      it("should return false when spots available", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.areAllSpotsFull(playerData)).to.equal(false)
      end)

      it("should return true when all spots filled", function()
        local playerData = createMockPlayerData()
        for i = 1, 8 do
          table.insert(playerData.traps, createMockTrap("t" .. i, "BasicTrap", i))
        end
        expect(TrapPlacement.areAllSpotsFull(playerData)).to.equal(true)
      end)
    end)

    describe("hasNoTraps", function()
      it("should return true when no traps", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.hasNoTraps(playerData)).to.equal(true)
      end)

      it("should return false when traps exist", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        expect(TrapPlacement.hasNoTraps(playerData)).to.equal(false)
      end)
    end)

    describe("getFirstAvailableSpot", function()
      it("should return 1 when all spots empty", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.getFirstAvailableSpot(playerData)).to.equal(1)
      end)

      it("should return first available spot", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2),
        }
        expect(TrapPlacement.getFirstAvailableSpot(playerData)).to.equal(3)
      end)

      it("should return nil when all spots full", function()
        local playerData = createMockPlayerData()
        for i = 1, 8 do
          table.insert(playerData.traps, createMockTrap("t" .. i, "BasicTrap", i))
        end
        expect(TrapPlacement.getFirstAvailableSpot(playerData)).to.equal(nil)
      end)
    end)

    describe("getReadyTraps", function()
      it("should return empty when no traps", function()
        local playerData = createMockPlayerData()
        local ready = TrapPlacement.getReadyTraps(playerData, os.time())
        expect(#ready).to.equal(0)
      end)

      it("should return only ready traps", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1), -- Ready
          createMockTrap("t2", "BasicTrap", 2, currentTime + 100), -- On cooldown
          createMockTrap("t3", "BasicTrap", 3, nil, "Fox"), -- Has predator
        }
        local ready = TrapPlacement.getReadyTraps(playerData, currentTime)
        expect(#ready).to.equal(1)
        expect(ready[1].id).to.equal("t1")
      end)
    end)

    describe("getTrapsWithPredators", function()
      it("should return empty when no traps have predators", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local withPredators = TrapPlacement.getTrapsWithPredators(playerData)
        expect(#withPredators).to.equal(0)
      end)

      it("should return traps with caught predators", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2, nil, "Fox"),
          createMockTrap("t3", "BasicTrap", 3, nil, "Wolf"),
        }
        local withPredators = TrapPlacement.getTrapsWithPredators(playerData)
        expect(#withPredators).to.equal(2)
      end)
    end)

    describe("getTrapsOnCooldown", function()
      it("should return empty when no traps on cooldown", function()
        local playerData = createMockPlayerData()
        playerData.traps = { createMockTrap("t1", "BasicTrap", 1) }
        local onCooldown = TrapPlacement.getTrapsOnCooldown(playerData, os.time())
        expect(#onCooldown).to.equal(0)
      end)

      it("should return traps on cooldown", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 2, currentTime + 100),
          createMockTrap("t3", "BasicTrap", 3, currentTime + 200),
        }
        local onCooldown = TrapPlacement.getTrapsOnCooldown(playerData, currentTime)
        expect(#onCooldown).to.equal(2)
      end)
    end)

    describe("getTrapInfo", function()
      it("should return nil for invalid trap type", function()
        local trap = createMockTrap("t1", "InvalidType", 1)
        expect(TrapPlacement.getTrapInfo(trap)).to.equal(nil)
      end)

      it("should return trap info for valid trap", function()
        local trap = createMockTrap("t1", "BasicTrap", 3, nil, "Fox")
        local info = TrapPlacement.getTrapInfo(trap)
        expect(info).to.be.ok()
        expect(info.spotIndex).to.equal(3)
        expect(info.hasPredator).to.equal(true)
      end)
    end)

    describe("validatePlacementState", function()
      it("should return true for empty traps", function()
        local playerData = createMockPlayerData()
        expect(TrapPlacement.validatePlacementState(playerData)).to.equal(true)
      end)

      it("should return true for valid placement state", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 3),
        }
        expect(TrapPlacement.validatePlacementState(playerData)).to.equal(true)
      end)

      it("should return false for duplicate spots", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1),
          createMockTrap("t2", "BasicTrap", 1), -- Duplicate
        }
        expect(TrapPlacement.validatePlacementState(playerData)).to.equal(false)
      end)

      it("should return false for invalid spot index", function()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 100), -- Invalid
        }
        expect(TrapPlacement.validatePlacementState(playerData)).to.equal(false)
      end)
    end)

    describe("getSummary", function()
      it("should return correct summary for empty state", function()
        local playerData = createMockPlayerData()
        local summary = TrapPlacement.getSummary(playerData, os.time())
        expect(summary.totalTraps).to.equal(0)
        expect(summary.availableSpots).to.equal(8)
        expect(summary.readyTraps).to.equal(0)
        expect(summary.trapsWithPredators).to.equal(0)
        expect(summary.trapsOnCooldown).to.equal(0)
      end)

      it("should return correct summary for mixed state", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.traps = {
          createMockTrap("t1", "BasicTrap", 1), -- Ready
          createMockTrap("t2", "BasicTrap", 2, currentTime + 100), -- On cooldown
          createMockTrap("t3", "BasicTrap", 3, nil, "Fox"), -- Has predator
        }
        local summary = TrapPlacement.getSummary(playerData, currentTime)
        expect(summary.totalTraps).to.equal(3)
        expect(summary.availableSpots).to.equal(5)
        expect(summary.readyTraps).to.equal(1)
        expect(summary.trapsWithPredators).to.equal(1)
        expect(summary.trapsOnCooldown).to.equal(1)
      end)
    end)
  end)
end
