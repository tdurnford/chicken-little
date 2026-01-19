--[[
	TrapService Tests
	Tests for the TrapService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local TrapPlacement = require(Shared:WaitForChild("TrapPlacement"))
  local TrapCatching = require(Shared:WaitForChild("TrapCatching"))
  local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))

  -- Helper function to create mock player data
  local function createMockPlayerData(): PlayerData.PlayerDataSchema
    return {
      money = 10000,
      level = 5,
      xp = 0,
      chickens = {},
      eggs = {},
      traps = {},
      weapons = {},
      equippedWeapon = nil,
      achievements = {},
      tutorialCompleted = false,
      joinTime = os.time(),
      lastSaveTime = os.time(),
      playTime = 0,
    }
  end

  describe("TrapConfig", function()
    describe("get", function()
      it("should return config for valid trap type", function()
        local config = TrapConfig.get("WoodenSnare")
        expect(config).to.be.ok()
        expect(config.name).to.equal("WoodenSnare")
        expect(config.tier).to.equal("Basic")
      end)

      it("should return nil for invalid trap type", function()
        local config = TrapConfig.get("InvalidType")
        expect(config).to.never.be.ok()
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid types", function()
        expect(TrapConfig.isValidType("WoodenSnare")).to.equal(true)
        expect(TrapConfig.isValidType("MetalCage")).to.equal(true)
        expect(TrapConfig.isValidType("QuantumContainment")).to.equal(true)
      end)

      it("should return false for invalid types", function()
        expect(TrapConfig.isValidType("InvalidType")).to.equal(false)
        expect(TrapConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getByTier", function()
      it("should return all traps of a specific tier", function()
        local basicTraps = TrapConfig.getByTier("Basic")
        expect(#basicTraps).to.be.gte(1)
        for _, trap in ipairs(basicTraps) do
          expect(trap.tier).to.equal("Basic")
        end
      end)
    end)

    describe("getAllSorted", function()
      it("should return traps sorted by tier and price", function()
        local sorted = TrapConfig.getAllSorted()
        expect(#sorted).to.be.gte(1)

        -- Verify sorting
        for i = 2, #sorted do
          local prev = sorted[i - 1]
          local curr = sorted[i]
          local validOrder = prev.tierLevel < curr.tierLevel
            or (prev.tierLevel == curr.tierLevel and prev.price <= curr.price)
          expect(validOrder).to.equal(true)
        end
      end)
    end)

    describe("calculateCatchProbability", function()
      it("should return higher probability for better traps", function()
        local basicProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Rat")
        local advancedProb = TrapConfig.calculateCatchProbability("ElectricFence", "Rat")

        expect(advancedProb).to.be.gte(basicProb)
      end)

      it("should return lower probability for tougher predators", function()
        local easyProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Rat")
        local hardProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Bear")

        expect(easyProb).to.be.gte(hardProb)
      end)

      it("should return value between 5 and 100", function()
        local prob = TrapConfig.calculateCatchProbability("WoodenSnare", "Bear")
        expect(prob).to.be.gte(5)
        expect(prob).to.be.lte(100)
      end)
    end)

    describe("getAffordableTraps", function()
      it("should return traps within budget", function()
        local affordable = TrapConfig.getAffordableTraps(1000)
        for _, trap in ipairs(affordable) do
          expect(trap.price).to.be.lte(1000)
        end
      end)

      it("should return empty for low budget", function()
        local affordable = TrapConfig.getAffordableTraps(100)
        expect(#affordable).to.equal(0)
      end)
    end)

    describe("getTiers", function()
      it("should return all tiers in order", function()
        local tiers = TrapConfig.getTiers()
        expect(#tiers).to.equal(6)
        expect(tiers[1]).to.equal("Basic")
        expect(tiers[6]).to.equal("Ultimate")
      end)
    end)

    describe("validateAll", function()
      it("should validate all trap configs", function()
        local result = TrapConfig.validateAll()
        expect(result.success).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)
    end)
  end)

  describe("TrapPlacement", function()
    describe("getMaxSpots", function()
      it("should return maximum trap spots", function()
        local maxSpots = TrapPlacement.getMaxSpots()
        expect(maxSpots).to.equal(8)
      end)
    end)

    describe("isValidSpot", function()
      it("should return true for valid spots", function()
        expect(TrapPlacement.isValidSpot(1)).to.equal(true)
        expect(TrapPlacement.isValidSpot(8)).to.equal(true)
      end)

      it("should return false for invalid spots", function()
        expect(TrapPlacement.isValidSpot(0)).to.equal(false)
        expect(TrapPlacement.isValidSpot(9)).to.equal(false)
        expect(TrapPlacement.isValidSpot(-1)).to.equal(false)
      end)
    end)

    describe("getAvailableSpots", function()
      it("should return all spots for empty player data", function()
        local playerData = createMockPlayerData()
        local available = TrapPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(8)
      end)

      it("should exclude occupied spots", function()
        local playerData = createMockPlayerData()
        table.insert(playerData.traps, {
          id = "trap1",
          trapType = "WoodenSnare",
          tier = 1,
          spotIndex = 3,
          cooldownEndTime = nil,
          caughtPredator = nil,
        })

        local available = TrapPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(7)

        for _, spot in ipairs(available) do
          expect(spot).to.never.equal(3)
        end
      end)
    end)

    describe("placeTrap", function()
      it("should place a trap successfully", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        expect(result.success).to.equal(true)
        expect(result.trap).to.be.ok()
        expect(result.trap.trapType).to.equal("WoodenSnare")
        expect(result.trap.spotIndex).to.equal(1)
      end)

      it("should fail for invalid trap type", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.placeTrap(playerData, "InvalidTrap", 1)

        expect(result.success).to.equal(false)
      end)

      it("should fail for occupied spot", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        local result = TrapPlacement.placeTrap(playerData, "RopeTrap", 1)

        expect(result.success).to.equal(false)
      end)

      it("should fail if not enough money", function()
        local playerData = createMockPlayerData()
        playerData.money = 100
        local result = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        expect(result.success).to.equal(false)
      end)

      it("should deduct money on success", function()
        local playerData = createMockPlayerData()
        local initialMoney = playerData.money
        local config = TrapConfig.get("WoodenSnare")

        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        expect(playerData.money).to.equal(initialMoney - config.price)
      end)
    end)

    describe("pickupTrap", function()
      it("should pick up a trap and refund money", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        local moneyAfterPlace = playerData.money

        local result = TrapPlacement.pickupTrap(playerData, placeResult.trap.id)

        expect(result.success).to.equal(true)
        expect(#playerData.traps).to.equal(0)
        expect(playerData.money).to.be.gt(moneyAfterPlace)
      end)

      it("should fail for non-existent trap", function()
        local playerData = createMockPlayerData()
        local result = TrapPlacement.pickupTrap(playerData, "nonexistent")

        expect(result.success).to.equal(false)
      end)
    end)

    describe("moveTrap", function()
      it("should move a trap to a new spot", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local result = TrapPlacement.moveTrap(playerData, placeResult.trap.id, 5)

        expect(result.success).to.equal(true)
        expect(result.trap.spotIndex).to.equal(5)
      end)

      it("should fail for occupied destination", function()
        local playerData = createMockPlayerData()
        local trap1 = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        TrapPlacement.placeTrap(playerData, "RopeTrap", 2)

        local result = TrapPlacement.moveTrap(playerData, trap1.trap.id, 2)

        expect(result.success).to.equal(false)
      end)
    end)

    describe("getTrapState", function()
      it("should return correct trap state", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local state = TrapPlacement.getTrapState(placeResult.trap, os.time())

        expect(state.isOnCooldown).to.equal(false)
        expect(state.hasCaughtPredator).to.equal(false)
      end)

      it("should detect cooldown state", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        playerData.traps[1].cooldownEndTime = os.time() + 60

        local state = TrapPlacement.getTrapState(playerData.traps[1], os.time())

        expect(state.isOnCooldown).to.equal(true)
        expect(state.cooldownRemaining).to.be.gt(0)
      end)
    end)

    describe("isReadyToCatch", function()
      it("should return true for ready trap", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local isReady = TrapPlacement.isReadyToCatch(placeResult.trap, os.time())

        expect(isReady).to.equal(true)
      end)

      it("should return false for trap with caught predator", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        playerData.traps[1].caughtPredator = "Rat"

        local isReady = TrapPlacement.isReadyToCatch(playerData.traps[1], os.time())

        expect(isReady).to.equal(false)
      end)

      it("should return false for trap on cooldown", function()
        local playerData = createMockPlayerData()
        local placeResult = TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        playerData.traps[1].cooldownEndTime = os.time() + 60

        local isReady = TrapPlacement.isReadyToCatch(playerData.traps[1], os.time())

        expect(isReady).to.equal(false)
      end)
    end)

    describe("getSummary", function()
      it("should return accurate summary", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        TrapPlacement.placeTrap(playerData, "RopeTrap", 2)
        playerData.traps[2].caughtPredator = "Rat"

        local summary = TrapPlacement.getSummary(playerData, os.time())

        expect(summary.totalTraps).to.equal(2)
        expect(summary.availableSpots).to.equal(6)
        expect(summary.readyTraps).to.equal(1)
        expect(summary.trapsWithPredators).to.equal(1)
      end)
    end)
  end)

  describe("TrapCatching", function()
    describe("attemptCatch", function()
      it("should succeed or fail based on probability", function()
        local playerData = createMockPlayerData()
        playerData.money = 1000000
        TrapPlacement.placeTrap(playerData, "QuantumContainment", 1)

        -- Ultimate trap has very high catch chance, should eventually succeed
        local caught = false
        for _ = 1, 100 do
          -- Reset for each attempt
          playerData.traps[1].cooldownEndTime = nil
          playerData.traps[1].caughtPredator = nil

          local result =
            TrapCatching.attemptCatch(playerData, playerData.traps[1].id, "Rat", os.time())
          if result.caught then
            caught = true
            break
          end
        end

        expect(caught).to.equal(true)
      end)

      it("should fail for invalid predator type", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local result = TrapCatching.attemptCatch(
          playerData,
          playerData.traps[1].id,
          "InvalidPredator",
          os.time()
        )

        expect(result.success).to.equal(false)
      end)

      it("should fail for trap not ready", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        playerData.traps[1].caughtPredator = "Rat"

        local result =
          TrapCatching.attemptCatch(playerData, playerData.traps[1].id, "Fox", os.time())

        expect(result.success).to.equal(false)
      end)
    end)

    describe("collectCaughtPredator", function()
      it("should collect reward from caught predator", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        playerData.traps[1].caughtPredator = "Rat"
        local moneyBefore = playerData.money

        local result =
          TrapCatching.collectCaughtPredator(playerData, playerData.traps[1].id, os.time())

        expect(result.success).to.equal(true)
        expect(result.rewardMoney).to.be.ok()
        expect(playerData.money).to.be.gt(moneyBefore)
        expect(playerData.traps[1].caughtPredator).to.equal(nil)
      end)

      it("should fail if no predator caught", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local result =
          TrapCatching.collectCaughtPredator(playerData, playerData.traps[1].id, os.time())

        expect(result.success).to.equal(false)
      end)
    end)

    describe("collectAllCaughtPredators", function()
      it("should collect all caught predators", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        TrapPlacement.placeTrap(playerData, "RopeTrap", 2)
        TrapPlacement.placeTrap(playerData, "MetalCage", 3)
        playerData.traps[1].caughtPredator = "Rat"
        playerData.traps[2].caughtPredator = "Fox"

        local moneyBefore = playerData.money
        local result = TrapCatching.collectAllCaughtPredators(playerData, os.time())

        expect(result.count).to.equal(2)
        expect(result.totalReward).to.be.gt(0)
        expect(playerData.money).to.equal(moneyBefore + result.totalReward)
      end)

      it("should return zero for no caught predators", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)

        local result = TrapCatching.collectAllCaughtPredators(playerData, os.time())

        expect(result.count).to.equal(0)
        expect(result.totalReward).to.equal(0)
      end)
    end)

    describe("getCombinedCatchProbability", function()
      it("should increase with more traps", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        local prob1 = TrapCatching.getCombinedCatchProbability(playerData, "Rat", os.time())

        TrapPlacement.placeTrap(playerData, "RopeTrap", 2)
        local prob2 = TrapCatching.getCombinedCatchProbability(playerData, "Rat", os.time())

        expect(prob2).to.be.gte(prob1)
      end)
    end)

    describe("getBestTrapForPredator", function()
      it("should return best ready trap", function()
        local playerData = createMockPlayerData()
        playerData.money = 100000
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        TrapPlacement.placeTrap(playerData, "ElectricFence", 2)

        local best = TrapCatching.getBestTrapForPredator(playerData, "Rat", os.time())

        expect(best).to.be.ok()
        expect(best.trapType).to.equal("ElectricFence")
      end)
    end)

    describe("getSummary", function()
      it("should return accurate catching summary", function()
        local playerData = createMockPlayerData()
        TrapPlacement.placeTrap(playerData, "WoodenSnare", 1)
        TrapPlacement.placeTrap(playerData, "RopeTrap", 2)
        playerData.traps[1].caughtPredator = "Rat"
        playerData.traps[2].cooldownEndTime = os.time() + 60

        local summary = TrapCatching.getSummary(playerData, os.time())

        expect(summary.totalTraps).to.equal(2)
        expect(summary.readyTraps).to.equal(0)
        expect(summary.caughtPredators).to.equal(1)
        expect(summary.trapsOnCooldown).to.equal(1)
        expect(summary.pendingReward).to.be.gt(0)
      end)
    end)
  end)
end
