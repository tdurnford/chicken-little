--[[
	TrapConfig.spec.lua
	TestEZ tests for TrapConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
  local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

  describe("TrapConfig", function()
    describe("get", function()
      it("should return config for valid trap type", function()
        local config = TrapConfig.get("WoodenSnare")
        expect(config).to.be.ok()
        expect(config.name).to.equal("WoodenSnare")
        expect(config.displayName).to.equal("Wooden Snare")
        expect(config.tier).to.equal("Basic")
      end)

      it("should return nil for invalid trap type", function()
        local config = TrapConfig.get("InvalidTrap")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = TrapConfig.get("QuantumContainment")
        expect(config).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.tier).to.be.ok()
        expect(config.tierLevel).to.be.ok()
        expect(config.price).to.be.ok()
        expect(config.sellPrice).to.be.ok()
        expect(config.maxPlacement).to.be.ok()
        expect(config.cooldownSeconds).to.be.ok()
        expect(config.durability).to.be.ok()
        expect(config.effectivenessBonus).to.be.ok()
        expect(config.description).to.be.ok()
        expect(config.icon).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of trap types", function()
        local all = TrapConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should have 12 trap types (2 per tier × 6 tiers)", function()
        local all = TrapConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(12)
      end)
    end)

    describe("getByTier", function()
      it("should return traps of specified tier", function()
        local basic = TrapConfig.getByTier("Basic")
        expect(#basic).to.equal(2)
        for _, config in ipairs(basic) do
          expect(config.tier).to.equal("Basic")
        end
      end)

      it("should return empty table for invalid tier", function()
        local invalid = TrapConfig.getByTier("SuperTier" :: any)
        expect(#invalid).to.equal(0)
      end)

      it("should return 2 traps per tier", function()
        local tiers = TrapConfig.getTiers()
        for _, tier in ipairs(tiers) do
          local traps = TrapConfig.getByTier(tier)
          expect(#traps).to.equal(2)
        end
      end)
    end)

    describe("getTierLevel", function()
      it("should return correct levels for each tier", function()
        expect(TrapConfig.getTierLevel("Basic")).to.equal(1)
        expect(TrapConfig.getTierLevel("Improved")).to.equal(2)
        expect(TrapConfig.getTierLevel("Advanced")).to.equal(3)
        expect(TrapConfig.getTierLevel("Expert")).to.equal(4)
        expect(TrapConfig.getTierLevel("Master")).to.equal(5)
        expect(TrapConfig.getTierLevel("Ultimate")).to.equal(6)
      end)

      it("should return 1 for invalid tier", function()
        expect(TrapConfig.getTierLevel("Invalid" :: any)).to.equal(1)
      end)
    end)

    describe("getTierPrice", function()
      it("should return positive prices for all tiers", function()
        local tiers = TrapConfig.getTiers()
        for _, tier in ipairs(tiers) do
          local price = TrapConfig.getTierPrice(tier)
          expect(price > 0).to.equal(true)
        end
      end)

      it("should return default for invalid tier", function()
        expect(TrapConfig.getTierPrice("Invalid" :: any)).to.equal(500)
      end)

      it("should have increasing prices for higher tiers", function()
        expect(TrapConfig.getTierPrice("Ultimate") > TrapConfig.getTierPrice("Basic")).to.equal(
          true
        )
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid trap types", function()
        expect(TrapConfig.isValidType("WoodenSnare")).to.equal(true)
        expect(TrapConfig.isValidType("QuantumContainment")).to.equal(true)
        expect(TrapConfig.isValidType("VoidPrison")).to.equal(true)
      end)

      it("should return false for invalid trap types", function()
        expect(TrapConfig.isValidType("NotATrap")).to.equal(false)
        expect(TrapConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getAllTypes", function()
      it("should return array of trap type names", function()
        local types = TrapConfig.getAllTypes()
        expect(typeof(types)).to.equal("table")
        expect(#types).to.equal(12)
      end)

      it("should return valid trap types", function()
        local types = TrapConfig.getAllTypes()
        for _, typeName in ipairs(types) do
          expect(TrapConfig.isValidType(typeName)).to.equal(true)
        end
      end)
    end)

    describe("getTiers", function()
      it("should return all 6 tiers in order", function()
        local tiers = TrapConfig.getTiers()
        expect(#tiers).to.equal(6)
        expect(tiers[1]).to.equal("Basic")
        expect(tiers[2]).to.equal("Improved")
        expect(tiers[3]).to.equal("Advanced")
        expect(tiers[4]).to.equal("Expert")
        expect(tiers[5]).to.equal("Master")
        expect(tiers[6]).to.equal("Ultimate")
      end)
    end)

    describe("calculateCatchProbability", function()
      it("should return percentage for valid trap and predator", function()
        local prob = TrapConfig.calculateCatchProbability("WoodenSnare", "Rat")
        expect(prob >= 5).to.equal(true)
        expect(prob <= 100).to.equal(true)
      end)

      it("should return 0 for invalid trap", function()
        expect(TrapConfig.calculateCatchProbability("InvalidTrap", "Rat")).to.equal(0)
      end)

      it("should return 0 for invalid predator", function()
        expect(TrapConfig.calculateCatchProbability("WoodenSnare", "InvalidPredator")).to.equal(0)
      end)

      it("should have higher probability for higher tier traps", function()
        local basicProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Bear")
        local ultimateProb = TrapConfig.calculateCatchProbability("QuantumContainment", "Bear")
        expect(ultimateProb >= basicProb).to.equal(true)
      end)

      it("should have lower probability for harder predators", function()
        local ratProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Rat")
        local bearProb = TrapConfig.calculateCatchProbability("WoodenSnare", "Bear")
        expect(ratProb >= bearProb).to.equal(true)
      end)
    end)

    describe("getEffectivenessRating", function()
      it("should return rating between 0-5", function()
        local rating = TrapConfig.getEffectivenessRating("WoodenSnare", "Rat")
        expect(rating >= 0).to.equal(true)
        expect(rating <= 5).to.equal(true)
      end)

      it("should return higher rating for better matchups", function()
        local basicVsRat = TrapConfig.getEffectivenessRating("WoodenSnare", "Rat")
        local basicVsBear = TrapConfig.getEffectivenessRating("WoodenSnare", "Bear")
        expect(basicVsRat >= basicVsBear).to.equal(true)
      end)
    end)

    describe("canEffectivelyCatch", function()
      it("should return boolean", function()
        local result = TrapConfig.canEffectivelyCatch("WoodenSnare", "Rat")
        expect(typeof(result)).to.equal("boolean")
      end)

      it("should return true for easy matchups", function()
        local result = TrapConfig.canEffectivelyCatch("QuantumContainment", "Rat")
        expect(result).to.equal(true)
      end)
    end)

    describe("getMinimumTierForPredator", function()
      it("should return a valid tier for valid predator", function()
        local tier = TrapConfig.getMinimumTierForPredator("Rat")
        expect(tier).to.be.ok()
        local tiers = TrapConfig.getTiers()
        local validTier = false
        for _, t in ipairs(tiers) do
          if t == tier then
            validTier = true
            break
          end
        end
        expect(validTier).to.equal(true)
      end)

      it("should return nil for invalid predator", function()
        local tier = TrapConfig.getMinimumTierForPredator("InvalidPredator")
        expect(tier).to.equal(nil)
      end)
    end)

    describe("getAllSorted", function()
      it("should return array of trap configs", function()
        local sorted = TrapConfig.getAllSorted()
        expect(typeof(sorted)).to.equal("table")
        expect(#sorted).to.equal(12)
      end)

      it("should be sorted by tier level", function()
        local sorted = TrapConfig.getAllSorted()
        for i = 2, #sorted do
          expect(sorted[i].tierLevel >= sorted[i - 1].tierLevel).to.equal(true)
        end
      end)
    end)

    describe("getMaxTotalTraps", function()
      it("should return a positive number", function()
        local max = TrapConfig.getMaxTotalTraps()
        expect(max > 0).to.equal(true)
      end)
    end)

    describe("getAffordableTraps", function()
      it("should return empty array for 0 money", function()
        local traps = TrapConfig.getAffordableTraps(0)
        expect(#traps).to.equal(0)
      end)

      it("should return some traps for sufficient money", function()
        local traps = TrapConfig.getAffordableTraps(1000000000)
        expect(#traps > 0).to.equal(true)
      end)

      it("should be sorted by price", function()
        local traps = TrapConfig.getAffordableTraps(1000000000)
        for i = 2, #traps do
          expect(traps[i].price >= traps[i - 1].price).to.equal(true)
        end
      end)

      it("should only include traps within budget", function()
        local budget = 5000
        local traps = TrapConfig.getAffordableTraps(budget)
        for _, trap in ipairs(traps) do
          expect(trap.price <= budget).to.equal(true)
        end
      end)
    end)

    describe("validateAll", function()
      it("should return success for all configs", function()
        local result = TrapConfig.validateAll()
        expect(result.success).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)

      it("should return errors array even on success", function()
        local result = TrapConfig.validateAll()
        expect(typeof(result.errors)).to.equal("table")
      end)
    end)

    describe("getStoreInfo", function()
      it("should return info for valid trap type", function()
        local info = TrapConfig.getStoreInfo("WoodenSnare")
        expect(info).to.be.ok()
        expect(info.name).to.equal("WoodenSnare")
        expect(info.displayName).to.be.ok()
        expect(info.tier).to.be.ok()
        expect(info.price).to.be.ok()
        expect(info.description).to.be.ok()
        expect(info.effectiveness).to.be.ok()
      end)

      it("should return nil for invalid trap type", function()
        local info = TrapConfig.getStoreInfo("InvalidTrap")
        expect(info).to.equal(nil)
      end)
    end)

    describe("config data validity", function()
      it("should have tier level between 1-6 for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.tierLevel >= 1).to.equal(true)
          expect(config.tierLevel <= 6).to.equal(true)
        end
      end)

      it("should have positive price for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.price > 0).to.equal(true)
        end
      end)

      it("should have sellPrice less than price for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.sellPrice < config.price).to.equal(true)
        end
      end)

      it("should have positive cooldown for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.cooldownSeconds > 0).to.equal(true)
        end
      end)

      it("should have non-negative durability for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.durability >= 0).to.equal(true)
        end
      end)

      it("should have positive maxPlacement for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.maxPlacement > 0).to.equal(true)
        end
      end)

      it("should have non-negative effectivenessBonus for all traps", function()
        local all = TrapConfig.getAll()
        for _, config in pairs(all) do
          expect(config.effectivenessBonus >= 0).to.equal(true)
        end
      end)

      it("should have matching name field and key", function()
        local all = TrapConfig.getAll()
        for key, config in pairs(all) do
          expect(config.name).to.equal(key)
        end
      end)
    end)
  end)
end
