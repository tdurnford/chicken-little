--[[
	EggConfig.spec.lua
	TestEZ tests for EggConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local EggConfig = require(Shared:WaitForChild("EggConfig"))

  describe("EggConfig", function()
    describe("get", function()
      it("should return config for valid egg type", function()
        local config = EggConfig.get("CommonEgg")
        expect(config).to.be.ok()
        expect(config.name).to.equal("CommonEgg")
        expect(config.displayName).to.equal("Common Egg")
        expect(config.rarity).to.equal("Common")
      end)

      it("should return nil for invalid egg type", function()
        local config = EggConfig.get("InvalidEgg")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = EggConfig.get("MythicEgg")
        expect(config).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.rarity).to.be.ok()
        expect(config.purchasePrice).to.be.ok()
        expect(config.sellPrice).to.be.ok()
        expect(config.hatchOutcomes).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of egg types", function()
        local all = EggConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should have 6 egg types (one per rarity)", function()
        local all = EggConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(6)
      end)
    end)

    describe("getByRarity", function()
      it("should return eggs of specified rarity", function()
        local common = EggConfig.getByRarity("Common")
        expect(#common).to.equal(1)
        expect(common[1].rarity).to.equal("Common")
      end)

      it("should return empty table for invalid rarity", function()
        local invalid = EggConfig.getByRarity("SuperRare" :: any)
        expect(#invalid).to.equal(0)
      end)
    end)

    describe("getRarityPriceMultiplier", function()
      it("should return correct multipliers for each rarity", function()
        expect(EggConfig.getRarityPriceMultiplier("Common")).to.equal(1)
        expect(EggConfig.getRarityPriceMultiplier("Uncommon")).to.equal(10)
        expect(EggConfig.getRarityPriceMultiplier("Rare")).to.equal(100)
        expect(EggConfig.getRarityPriceMultiplier("Epic")).to.equal(1000)
        expect(EggConfig.getRarityPriceMultiplier("Legendary")).to.equal(10000)
        expect(EggConfig.getRarityPriceMultiplier("Mythic")).to.equal(100000)
      end)

      it("should return 1 for invalid rarity", function()
        expect(EggConfig.getRarityPriceMultiplier("Invalid" :: any)).to.equal(1)
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid egg types", function()
        expect(EggConfig.isValidType("CommonEgg")).to.equal(true)
        expect(EggConfig.isValidType("MythicEgg")).to.equal(true)
      end)

      it("should return false for invalid egg types", function()
        expect(EggConfig.isValidType("NotAnEgg")).to.equal(false)
        expect(EggConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getAllTypes", function()
      it("should return array of egg type names", function()
        local types = EggConfig.getAllTypes()
        expect(typeof(types)).to.equal("table")
        expect(#types).to.equal(6)
      end)

      it("should return valid egg types", function()
        local types = EggConfig.getAllTypes()
        for _, typeName in ipairs(types) do
          expect(EggConfig.isValidType(typeName)).to.equal(true)
        end
      end)
    end)

    describe("validateProbabilities", function()
      it("should return true for valid egg types", function()
        local types = EggConfig.getAllTypes()
        for _, typeName in ipairs(types) do
          expect(EggConfig.validateProbabilities(typeName)).to.equal(true)
        end
      end)

      it("should return false for invalid egg type", function()
        expect(EggConfig.validateProbabilities("InvalidEgg")).to.equal(false)
      end)
    end)

    describe("validateAll", function()
      it("should return success for all configs", function()
        local result = EggConfig.validateAll()
        expect(result.success).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)

      it("should return errors array even on success", function()
        local result = EggConfig.validateAll()
        expect(typeof(result.errors)).to.equal("table")
      end)
    end)

    describe("selectHatchOutcome", function()
      it("should return a valid chicken type", function()
        local chicken = EggConfig.selectHatchOutcome("CommonEgg")
        expect(chicken).to.be.ok()
        expect(typeof(chicken)).to.equal("string")
      end)

      it("should return nil for invalid egg type", function()
        local chicken = EggConfig.selectHatchOutcome("InvalidEgg")
        expect(chicken).to.equal(nil)
      end)

      it("should return chicken from egg's hatch outcomes", function()
        local config = EggConfig.get("CommonEgg")
        local validChickens = {}
        for _, outcome in ipairs(config.hatchOutcomes) do
          validChickens[outcome.chickenType] = true
        end

        -- Run multiple times to account for randomness
        for _ = 1, 10 do
          local chicken = EggConfig.selectHatchOutcome("CommonEgg")
          expect(validChickens[chicken]).to.equal(true)
        end
      end)
    end)

    describe("selectHatchOutcomeWithLuck", function()
      it("should return a valid chicken type", function()
        local chicken = EggConfig.selectHatchOutcomeWithLuck("CommonEgg", 1.0)
        expect(chicken).to.be.ok()
        expect(typeof(chicken)).to.equal("string")
      end)

      it("should return nil for invalid egg type", function()
        local chicken = EggConfig.selectHatchOutcomeWithLuck("InvalidEgg", 2.0)
        expect(chicken).to.equal(nil)
      end)

      it("should work with luck multiplier of 1", function()
        local chicken = EggConfig.selectHatchOutcomeWithLuck("CommonEgg", 1.0)
        expect(chicken).to.be.ok()
      end)

      it("should work with luck multiplier greater than 1", function()
        local chicken = EggConfig.selectHatchOutcomeWithLuck("CommonEgg", 2.0)
        expect(chicken).to.be.ok()
      end)
    end)

    describe("getRarities", function()
      it("should return all 6 rarities in order", function()
        local rarities = EggConfig.getRarities()
        expect(#rarities).to.equal(6)
        expect(rarities[1]).to.equal("Common")
        expect(rarities[6]).to.equal("Mythic")
      end)
    end)

    describe("getStarterEggType", function()
      it("should return CommonEgg", function()
        expect(EggConfig.getStarterEggType()).to.equal("CommonEgg")
      end)

      it("should return a valid egg type", function()
        local starter = EggConfig.getStarterEggType()
        expect(EggConfig.isValidType(starter)).to.equal(true)
      end)
    end)

    describe("config data validity", function()
      it("should have positive purchasePrice for all eggs", function()
        local all = EggConfig.getAll()
        for _, config in pairs(all) do
          expect(config.purchasePrice > 0).to.equal(true)
        end
      end)

      it("should have positive sellPrice for all eggs", function()
        local all = EggConfig.getAll()
        for _, config in pairs(all) do
          expect(config.sellPrice > 0).to.equal(true)
        end
      end)

      it("should have sellPrice less than purchasePrice", function()
        local all = EggConfig.getAll()
        for _, config in pairs(all) do
          expect(config.sellPrice < config.purchasePrice).to.equal(true)
        end
      end)

      it("should have exactly 3 hatch outcomes per egg", function()
        local all = EggConfig.getAll()
        for _, config in pairs(all) do
          expect(#config.hatchOutcomes).to.equal(3)
        end
      end)

      it("should have probabilities summing to 100 for all eggs", function()
        local all = EggConfig.getAll()
        for _, config in pairs(all) do
          local sum = 0
          for _, outcome in ipairs(config.hatchOutcomes) do
            sum = sum + outcome.probability
          end
          expect(sum).to.equal(100)
        end
      end)

      it("should have matching name field and key", function()
        local all = EggConfig.getAll()
        for key, config in pairs(all) do
          expect(config.name).to.equal(key)
        end
      end)
    end)
  end)
end
