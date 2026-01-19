--[[
	ChickenConfig.spec.lua
	TestEZ tests for ChickenConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))

  describe("ChickenConfig", function()
    describe("get", function()
      it("should return config for valid chicken type", function()
        local config = ChickenConfig.get("BasicChick")
        expect(config).to.be.ok()
        expect(config.name).to.equal("BasicChick")
        expect(config.displayName).to.equal("Basic Chick")
        expect(config.rarity).to.equal("Common")
      end)

      it("should return nil for invalid chicken type", function()
        local config = ChickenConfig.get("InvalidChicken")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = ChickenConfig.get("DragonChicken")
        expect(config).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.rarity).to.be.ok()
        expect(config.moneyPerSecond).to.be.ok()
        expect(config.eggLayIntervalSeconds).to.be.ok()
        expect(config.eggsLaid).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of chicken types", function()
        local all = ChickenConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should contain multiple chicken types", function()
        local all = ChickenConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count > 0).to.equal(true)
      end)

      it("should have 18 chicken types (3 per rarity × 6 rarities)", function()
        local all = ChickenConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(18)
      end)
    end)

    describe("getByRarity", function()
      it("should return chickens of specified rarity", function()
        local common = ChickenConfig.getByRarity("Common")
        expect(#common).to.equal(3)
        for _, config in ipairs(common) do
          expect(config.rarity).to.equal("Common")
        end
      end)

      it("should return empty table for invalid rarity", function()
        local invalid = ChickenConfig.getByRarity("SuperRare" :: any)
        expect(#invalid).to.equal(0)
      end)

      it("should return 3 chickens per rarity tier", function()
        local rarities = ChickenConfig.getRarities()
        for _, rarity in ipairs(rarities) do
          local chickens = ChickenConfig.getByRarity(rarity)
          expect(#chickens).to.equal(3)
        end
      end)
    end)

    describe("getRarityMultiplier", function()
      it("should return correct multipliers for each rarity", function()
        expect(ChickenConfig.getRarityMultiplier("Common")).to.equal(1)
        expect(ChickenConfig.getRarityMultiplier("Uncommon")).to.equal(10)
        expect(ChickenConfig.getRarityMultiplier("Rare")).to.equal(100)
        expect(ChickenConfig.getRarityMultiplier("Epic")).to.equal(1000)
        expect(ChickenConfig.getRarityMultiplier("Legendary")).to.equal(10000)
        expect(ChickenConfig.getRarityMultiplier("Mythic")).to.equal(100000)
      end)

      it("should return 1 for invalid rarity", function()
        expect(ChickenConfig.getRarityMultiplier("Invalid" :: any)).to.equal(1)
      end)
    end)

    describe("getRarityEggInterval", function()
      it("should return positive intervals for all rarities", function()
        local rarities = ChickenConfig.getRarities()
        for _, rarity in ipairs(rarities) do
          local interval = ChickenConfig.getRarityEggInterval(rarity)
          expect(interval > 0).to.equal(true)
        end
      end)

      it("should return default for invalid rarity", function()
        local interval = ChickenConfig.getRarityEggInterval("Invalid" :: any)
        expect(interval).to.equal(60)
      end)

      it("should have increasing intervals for rarer chickens", function()
        expect(ChickenConfig.getRarityEggInterval("Common")).to.be.ok()
        expect(
          ChickenConfig.getRarityEggInterval("Mythic")
            > ChickenConfig.getRarityEggInterval("Common")
        ).to.equal(true)
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid chicken types", function()
        expect(ChickenConfig.isValidType("BasicChick")).to.equal(true)
        expect(ChickenConfig.isValidType("DragonChicken")).to.equal(true)
        expect(ChickenConfig.isValidType("OmegaRooster")).to.equal(true)
      end)

      it("should return false for invalid chicken types", function()
        expect(ChickenConfig.isValidType("NotAChicken")).to.equal(false)
        expect(ChickenConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getAllTypes", function()
      it("should return array of chicken type names", function()
        local types = ChickenConfig.getAllTypes()
        expect(typeof(types)).to.equal("table")
        expect(#types).to.equal(18)
      end)

      it("should return valid chicken types", function()
        local types = ChickenConfig.getAllTypes()
        for _, typeName in ipairs(types) do
          expect(ChickenConfig.isValidType(typeName)).to.equal(true)
        end
      end)
    end)

    describe("getRarities", function()
      it("should return all 6 rarities in order", function()
        local rarities = ChickenConfig.getRarities()
        expect(#rarities).to.equal(6)
        expect(rarities[1]).to.equal("Common")
        expect(rarities[2]).to.equal("Uncommon")
        expect(rarities[3]).to.equal("Rare")
        expect(rarities[4]).to.equal("Epic")
        expect(rarities[5]).to.equal("Legendary")
        expect(rarities[6]).to.equal("Mythic")
      end)
    end)

    describe("calculateEarnings", function()
      it("should calculate earnings correctly", function()
        local earnings = ChickenConfig.calculateEarnings("BasicChick", 10)
        expect(earnings).to.equal(10) -- 1 money/sec × 10 sec
      end)

      it("should return 0 for invalid chicken type", function()
        local earnings = ChickenConfig.calculateEarnings("InvalidChicken", 100)
        expect(earnings).to.equal(0)
      end)

      it("should scale with time", function()
        local earnings1 = ChickenConfig.calculateEarnings("BasicChick", 10)
        local earnings2 = ChickenConfig.calculateEarnings("BasicChick", 20)
        expect(earnings2).to.equal(earnings1 * 2)
      end)
    end)

    describe("getMaxHealth", function()
      it("should return positive health for all rarities", function()
        local rarities = ChickenConfig.getRarities()
        for _, rarity in ipairs(rarities) do
          local health = ChickenConfig.getMaxHealth(rarity)
          expect(health > 0).to.equal(true)
        end
      end)

      it("should return default for invalid rarity", function()
        expect(ChickenConfig.getMaxHealth("Invalid" :: any)).to.equal(50)
      end)

      it("should have higher health for rarer chickens", function()
        expect(ChickenConfig.getMaxHealth("Mythic") > ChickenConfig.getMaxHealth("Common")).to.equal(
          true
        )
      end)
    end)

    describe("getHealthRegen", function()
      it("should return positive regen for all rarities", function()
        local rarities = ChickenConfig.getRarities()
        for _, rarity in ipairs(rarities) do
          local regen = ChickenConfig.getHealthRegen(rarity)
          expect(regen > 0).to.equal(true)
        end
      end)

      it("should return default for invalid rarity", function()
        expect(ChickenConfig.getHealthRegen("Invalid" :: any)).to.equal(5)
      end)
    end)

    describe("getHealthRegenDelay", function()
      it("should return a positive number", function()
        local delay = ChickenConfig.getHealthRegenDelay()
        expect(delay > 0).to.equal(true)
      end)
    end)

    describe("getMaxHealthForType", function()
      it("should return correct health for chicken type", function()
        local health = ChickenConfig.getMaxHealthForType("BasicChick")
        expect(health).to.equal(50) -- Common rarity health
      end)

      it("should return default for invalid type", function()
        expect(ChickenConfig.getMaxHealthForType("Invalid")).to.equal(50)
      end)
    end)

    describe("getHealthRegenForType", function()
      it("should return correct regen for chicken type", function()
        local regen = ChickenConfig.getHealthRegenForType("BasicChick")
        expect(regen).to.equal(5) -- Common rarity regen
      end)

      it("should return default for invalid type", function()
        expect(ChickenConfig.getHealthRegenForType("Invalid")).to.equal(5)
      end)
    end)

    describe("getMaxChickensPerArea", function()
      it("should return a positive number", function()
        local max = ChickenConfig.getMaxChickensPerArea()
        expect(max > 0).to.equal(true)
      end)

      it("should return 15", function()
        expect(ChickenConfig.getMaxChickensPerArea()).to.equal(15)
      end)
    end)

    describe("config data validity", function()
      it("should have positive moneyPerSecond for all chickens", function()
        local all = ChickenConfig.getAll()
        for name, config in pairs(all) do
          expect(config.moneyPerSecond > 0).to.equal(true)
        end
      end)

      it("should have positive eggLayIntervalSeconds for all chickens", function()
        local all = ChickenConfig.getAll()
        for _, config in pairs(all) do
          expect(config.eggLayIntervalSeconds > 0).to.equal(true)
        end
      end)

      it("should have at least one egg type for all chickens", function()
        local all = ChickenConfig.getAll()
        for _, config in pairs(all) do
          expect(#config.eggsLaid >= 1).to.equal(true)
        end
      end)

      it("should have matching name field and key", function()
        local all = ChickenConfig.getAll()
        for key, config in pairs(all) do
          expect(config.name).to.equal(key)
        end
      end)
    end)
  end)
end
