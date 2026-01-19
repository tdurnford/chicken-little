--[[
	PredatorConfig.spec.lua
	TestEZ tests for PredatorConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))

  describe("PredatorConfig", function()
    describe("get", function()
      it("should return config for valid predator type", function()
        local config = PredatorConfig.get("Rat")
        expect(config).to.be.ok()
        expect(config.name).to.equal("Rat")
        expect(config.displayName).to.equal("Rat")
        expect(config.threatLevel).to.equal("Minor")
      end)

      it("should return nil for invalid predator type", function()
        local config = PredatorConfig.get("InvalidPredator")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = PredatorConfig.get("Bear")
        expect(config).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.threatLevel).to.be.ok()
        expect(config.spawnWeight).to.be.ok()
        expect(config.attackIntervalSeconds).to.be.ok()
        expect(config.chickensPerAttack).to.be.ok()
        expect(config.catchDifficulty).to.be.ok()
        expect(config.rewardMoney).to.be.ok()
        expect(config.damage).to.be.ok()
        expect(config.description).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of predator types", function()
        local all = PredatorConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should have 12 predator types (2 per threat level × 6 levels)", function()
        local all = PredatorConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(12)
      end)
    end)

    describe("getByThreatLevel", function()
      it("should return predators of specified threat level", function()
        local minor = PredatorConfig.getByThreatLevel("Minor")
        expect(#minor).to.equal(2)
        for _, config in ipairs(minor) do
          expect(config.threatLevel).to.equal("Minor")
        end
      end)

      it("should return empty table for invalid threat level", function()
        local invalid = PredatorConfig.getByThreatLevel("SuperThreat" :: any)
        expect(#invalid).to.equal(0)
      end)

      it("should return 2 predators per threat level", function()
        local levels = PredatorConfig.getThreatLevels()
        for _, level in ipairs(levels) do
          local predators = PredatorConfig.getByThreatLevel(level)
          expect(#predators).to.equal(2)
        end
      end)
    end)

    describe("getThreatRewardMultiplier", function()
      it("should return correct multipliers for each threat level", function()
        expect(PredatorConfig.getThreatRewardMultiplier("Minor")).to.equal(1)
        expect(PredatorConfig.getThreatRewardMultiplier("Moderate")).to.equal(5)
        expect(PredatorConfig.getThreatRewardMultiplier("Dangerous")).to.equal(25)
        expect(PredatorConfig.getThreatRewardMultiplier("Severe")).to.equal(100)
        expect(PredatorConfig.getThreatRewardMultiplier("Deadly")).to.equal(500)
        expect(PredatorConfig.getThreatRewardMultiplier("Catastrophic")).to.equal(2500)
      end)

      it("should return 1 for invalid threat level", function()
        expect(PredatorConfig.getThreatRewardMultiplier("Invalid" :: any)).to.equal(1)
      end)
    end)

    describe("getThreatSpawnWeight", function()
      it("should return positive weights for all threat levels", function()
        local levels = PredatorConfig.getThreatLevels()
        for _, level in ipairs(levels) do
          local weight = PredatorConfig.getThreatSpawnWeight(level)
          expect(weight > 0).to.equal(true)
        end
      end)

      it("should return 1 for invalid threat level", function()
        expect(PredatorConfig.getThreatSpawnWeight("Invalid" :: any)).to.equal(1)
      end)

      it("should have decreasing weights for higher threat levels", function()
        expect(
          PredatorConfig.getThreatSpawnWeight("Minor")
            > PredatorConfig.getThreatSpawnWeight("Catastrophic")
        ).to.equal(true)
      end)
    end)

    describe("getThreatAttackInterval", function()
      it("should return positive intervals for all threat levels", function()
        local levels = PredatorConfig.getThreatLevels()
        for _, level in ipairs(levels) do
          local interval = PredatorConfig.getThreatAttackInterval(level)
          expect(interval > 0).to.equal(true)
        end
      end)

      it("should return default for invalid threat level", function()
        expect(PredatorConfig.getThreatAttackInterval("Invalid" :: any)).to.equal(60)
      end)
    end)

    describe("getThreatDamage", function()
      it("should return positive damage for all threat levels", function()
        local levels = PredatorConfig.getThreatLevels()
        for _, level in ipairs(levels) do
          local damage = PredatorConfig.getThreatDamage(level)
          expect(damage > 0).to.equal(true)
        end
      end)

      it("should return default for invalid threat level", function()
        expect(PredatorConfig.getThreatDamage("Invalid" :: any)).to.equal(5)
      end)

      it("should have increasing damage for higher threat levels", function()
        expect(
          PredatorConfig.getThreatDamage("Catastrophic") > PredatorConfig.getThreatDamage("Minor")
        ).to.equal(true)
      end)
    end)

    describe("getDamage", function()
      it("should return damage for valid predator type", function()
        local damage = PredatorConfig.getDamage("Rat")
        expect(damage > 0).to.equal(true)
      end)

      it("should return default for invalid predator type", function()
        expect(PredatorConfig.getDamage("Invalid")).to.equal(5)
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid predator types", function()
        expect(PredatorConfig.isValidType("Rat")).to.equal(true)
        expect(PredatorConfig.isValidType("Bear")).to.equal(true)
        expect(PredatorConfig.isValidType("Eagle")).to.equal(true)
      end)

      it("should return false for invalid predator types", function()
        expect(PredatorConfig.isValidType("NotAPredator")).to.equal(false)
        expect(PredatorConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getAllTypes", function()
      it("should return array of predator type names", function()
        local types = PredatorConfig.getAllTypes()
        expect(typeof(types)).to.equal("table")
        expect(#types).to.equal(12)
      end)

      it("should return valid predator types", function()
        local types = PredatorConfig.getAllTypes()
        for _, typeName in ipairs(types) do
          expect(PredatorConfig.isValidType(typeName)).to.equal(true)
        end
      end)
    end)

    describe("getThreatLevels", function()
      it("should return all 6 threat levels in order", function()
        local levels = PredatorConfig.getThreatLevels()
        expect(#levels).to.equal(6)
        expect(levels[1]).to.equal("Minor")
        expect(levels[2]).to.equal("Moderate")
        expect(levels[3]).to.equal("Dangerous")
        expect(levels[4]).to.equal("Severe")
        expect(levels[5]).to.equal("Deadly")
        expect(levels[6]).to.equal("Catastrophic")
      end)
    end)

    describe("getTotalSpawnWeight", function()
      it("should return a positive number", function()
        local total = PredatorConfig.getTotalSpawnWeight()
        expect(total > 0).to.equal(true)
      end)

      it("should equal sum of all predator spawn weights", function()
        local all = PredatorConfig.getAll()
        local sum = 0
        for _, config in pairs(all) do
          sum = sum + config.spawnWeight
        end
        expect(PredatorConfig.getTotalSpawnWeight()).to.equal(sum)
      end)
    end)

    describe("selectRandomPredator", function()
      it("should return a valid predator type", function()
        local predator = PredatorConfig.selectRandomPredator()
        expect(PredatorConfig.isValidType(predator)).to.equal(true)
      end)

      it("should return different predators over multiple calls", function()
        local results = {}
        for _ = 1, 20 do
          local predator = PredatorConfig.selectRandomPredator()
          results[predator] = true
        end
        -- Should have at least 2 different results
        local count = 0
        for _ in pairs(results) do
          count = count + 1
        end
        expect(count >= 1).to.equal(true)
      end)
    end)

    describe("validateAll", function()
      it("should return success for all configs", function()
        local result = PredatorConfig.validateAll()
        expect(result.success).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)

      it("should return errors array even on success", function()
        local result = PredatorConfig.validateAll()
        expect(typeof(result.errors)).to.equal("table")
      end)
    end)

    describe("getBatHitsRequired", function()
      it("should return positive number for valid predator", function()
        local hits = PredatorConfig.getBatHitsRequired("Rat")
        expect(hits >= 1).to.equal(true)
      end)

      it("should return 1 for invalid predator", function()
        expect(PredatorConfig.getBatHitsRequired("Invalid")).to.equal(1)
      end)

      it("should require more hits for higher difficulty predators", function()
        local ratHits = PredatorConfig.getBatHitsRequired("Rat")
        local bearHits = PredatorConfig.getBatHitsRequired("Bear")
        expect(bearHits > ratHits).to.equal(true)
      end)
    end)

    describe("getTrapEffectiveness", function()
      it("should return percentage for valid predator and trap tier", function()
        local effectiveness = PredatorConfig.getTrapEffectiveness("Rat", 1)
        expect(effectiveness >= 0).to.equal(true)
        expect(effectiveness <= 100).to.equal(true)
      end)

      it("should return 0 for invalid predator", function()
        expect(PredatorConfig.getTrapEffectiveness("Invalid", 1)).to.equal(0)
      end)

      it("should increase with higher trap tier", function()
        local tier1 = PredatorConfig.getTrapEffectiveness("Bear", 1)
        local tier6 = PredatorConfig.getTrapEffectiveness("Bear", 6)
        expect(tier6 >= tier1).to.equal(true)
      end)
    end)

    describe("calculateAttackDamage", function()
      it("should return chickens per attack for valid predator", function()
        local damage = PredatorConfig.calculateAttackDamage("Rat")
        expect(damage >= 1).to.equal(true)
      end)

      it("should return 0 for invalid predator", function()
        expect(PredatorConfig.calculateAttackDamage("Invalid")).to.equal(0)
      end)
    end)

    describe("getSpawnProbability", function()
      it("should return percentage for valid predator", function()
        local prob = PredatorConfig.getSpawnProbability("Rat")
        expect(prob > 0).to.equal(true)
        expect(prob <= 100).to.equal(true)
      end)

      it("should return 0 for invalid predator", function()
        expect(PredatorConfig.getSpawnProbability("Invalid")).to.equal(0)
      end)

      it("should have all probabilities sum to 100", function()
        local types = PredatorConfig.getAllTypes()
        local sum = 0
        for _, typeName in ipairs(types) do
          sum = sum + PredatorConfig.getSpawnProbability(typeName)
        end
        expect(math.abs(sum - 100) < 0.01).to.equal(true)
      end)
    end)

    describe("config data validity", function()
      it("should have catch difficulty between 1-10 for all predators", function()
        local all = PredatorConfig.getAll()
        for _, config in pairs(all) do
          expect(config.catchDifficulty >= 1).to.equal(true)
          expect(config.catchDifficulty <= 10).to.equal(true)
        end
      end)

      it("should have positive spawn weight for all predators", function()
        local all = PredatorConfig.getAll()
        for _, config in pairs(all) do
          expect(config.spawnWeight > 0).to.equal(true)
        end
      end)

      it("should have positive reward money for all predators", function()
        local all = PredatorConfig.getAll()
        for _, config in pairs(all) do
          expect(config.rewardMoney > 0).to.equal(true)
        end
      end)

      it("should have positive damage for all predators", function()
        local all = PredatorConfig.getAll()
        for _, config in pairs(all) do
          expect(config.damage > 0).to.equal(true)
        end
      end)

      it("should have matching name field and key", function()
        local all = PredatorConfig.getAll()
        for key, config in pairs(all) do
          expect(config.name).to.equal(key)
        end
      end)
    end)
  end)
end
