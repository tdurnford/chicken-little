--[[
	XPConfig.spec.lua
	TestEZ tests for XPConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local XPConfig = require(Shared:WaitForChild("XPConfig"))

  describe("XPConfig", function()
    describe("getBaseReward", function()
      it("should return positive value for predator_killed", function()
        local reward = XPConfig.getBaseReward("predator_killed")
        expect(reward > 0).to.equal(true)
      end)

      it("should return positive value for chicken_hatched", function()
        local reward = XPConfig.getBaseReward("chicken_hatched")
        expect(reward > 0).to.equal(true)
      end)

      it("should return positive value for random_chicken_caught", function()
        local reward = XPConfig.getBaseReward("random_chicken_caught")
        expect(reward > 0).to.equal(true)
      end)

      it("should return positive value for day_night_cycle_survived", function()
        local reward = XPConfig.getBaseReward("day_night_cycle_survived")
        expect(reward > 0).to.equal(true)
      end)

      it("should return positive value for egg_collected", function()
        local reward = XPConfig.getBaseReward("egg_collected")
        expect(reward > 0).to.equal(true)
      end)

      it("should return positive value for trap_caught_predator", function()
        local reward = XPConfig.getBaseReward("trap_caught_predator")
        expect(reward > 0).to.equal(true)
      end)

      it("should return 0 for invalid reward type", function()
        local reward = XPConfig.getBaseReward("invalid_type" :: any)
        expect(reward).to.equal(0)
      end)
    end)

    describe("getDescription", function()
      it("should return description for valid reward types", function()
        local desc = XPConfig.getDescription("predator_killed")
        expect(typeof(desc)).to.equal("string")
        expect(#desc > 0).to.equal(true)
      end)

      it("should return unknown for invalid reward type", function()
        local desc = XPConfig.getDescription("invalid_type" :: any)
        expect(desc).to.equal("Unknown action")
      end)
    end)

    describe("calculatePredatorKillXP", function()
      it("should return base XP for unknown predator", function()
        local xp = XPConfig.calculatePredatorKillXP("UnknownPredator")
        local base = XPConfig.getBaseReward("predator_killed")
        expect(xp).to.equal(base)
      end)

      it("should scale XP with threat level", function()
        -- Fox is Minor threat, Wolf is higher threat
        local foxXP = XPConfig.calculatePredatorKillXP("Fox")
        local wolfXP = XPConfig.calculatePredatorKillXP("Wolf")
        -- Both should be positive
        expect(foxXP > 0).to.equal(true)
        expect(wolfXP > 0).to.equal(true)
      end)

      it("should return positive XP", function()
        local xp = XPConfig.calculatePredatorKillXP("Fox")
        expect(xp > 0).to.equal(true)
      end)
    end)

    describe("calculateChickenHatchXP", function()
      it("should return base XP for Common rarity", function()
        local xp = XPConfig.calculateChickenHatchXP("Common")
        local base = XPConfig.getBaseReward("chicken_hatched")
        expect(xp).to.equal(base)
      end)

      it("should scale XP with rarity", function()
        local commonXP = XPConfig.calculateChickenHatchXP("Common")
        local rareXP = XPConfig.calculateChickenHatchXP("Rare")
        local mythicXP = XPConfig.calculateChickenHatchXP("Mythic")
        expect(rareXP > commonXP).to.equal(true)
        expect(mythicXP > rareXP).to.equal(true)
      end)

      it("should return base for invalid rarity", function()
        local xp = XPConfig.calculateChickenHatchXP("SuperRare")
        local base = XPConfig.getBaseReward("chicken_hatched")
        expect(xp).to.equal(base)
      end)
    end)

    describe("calculateRandomChickenXP", function()
      it("should return base XP for Common rarity", function()
        local xp = XPConfig.calculateRandomChickenXP("Common")
        local base = XPConfig.getBaseReward("random_chicken_caught")
        expect(xp).to.equal(base)
      end)

      it("should scale XP with rarity", function()
        local commonXP = XPConfig.calculateRandomChickenXP("Common")
        local epicXP = XPConfig.calculateRandomChickenXP("Epic")
        expect(epicXP > commonXP).to.equal(true)
      end)
    end)

    describe("calculateEggCollectedXP", function()
      it("should return base XP for Common rarity", function()
        local xp = XPConfig.calculateEggCollectedXP("Common")
        local base = XPConfig.getBaseReward("egg_collected")
        expect(xp).to.equal(base)
      end)

      it("should scale XP with rarity", function()
        local commonXP = XPConfig.calculateEggCollectedXP("Common")
        local legendaryXP = XPConfig.calculateEggCollectedXP("Legendary")
        expect(legendaryXP > commonXP).to.equal(true)
      end)
    end)

    describe("calculateTrapCatchXP", function()
      it("should return base XP for unknown predator", function()
        local xp = XPConfig.calculateTrapCatchXP("UnknownPredator")
        local base = XPConfig.getBaseReward("trap_caught_predator")
        expect(xp).to.equal(base)
      end)

      it("should return positive XP for valid predators", function()
        local xp = XPConfig.calculateTrapCatchXP("Fox")
        expect(xp > 0).to.equal(true)
      end)
    end)

    describe("calculateDayNightCycleXP", function()
      it("should return fixed XP amount", function()
        local xp = XPConfig.calculateDayNightCycleXP()
        local base = XPConfig.getBaseReward("day_night_cycle_survived")
        expect(xp).to.equal(base)
      end)

      it("should return positive XP", function()
        local xp = XPConfig.calculateDayNightCycleXP()
        expect(xp > 0).to.equal(true)
      end)
    end)

    describe("getAllRewardTypes", function()
      it("should return an array of reward types", function()
        local types = XPConfig.getAllRewardTypes()
        expect(typeof(types)).to.equal("table")
        expect(#types > 0).to.equal(true)
      end)

      it("should include all 6 reward types", function()
        local types = XPConfig.getAllRewardTypes()
        expect(#types).to.equal(6)
      end)

      it("should include predator_killed", function()
        local types = XPConfig.getAllRewardTypes()
        local found = false
        for _, t in ipairs(types) do
          if t == "predator_killed" then
            found = true
            break
          end
        end
        expect(found).to.equal(true)
      end)
    end)

    describe("getRarityMultiplier", function()
      it("should return 1 for Common", function()
        expect(XPConfig.getRarityMultiplier("Common")).to.equal(1)
      end)

      it("should return increasing multipliers for higher rarities", function()
        local common = XPConfig.getRarityMultiplier("Common")
        local uncommon = XPConfig.getRarityMultiplier("Uncommon")
        local rare = XPConfig.getRarityMultiplier("Rare")
        local epic = XPConfig.getRarityMultiplier("Epic")
        local legendary = XPConfig.getRarityMultiplier("Legendary")
        local mythic = XPConfig.getRarityMultiplier("Mythic")

        expect(uncommon > common).to.equal(true)
        expect(rare > uncommon).to.equal(true)
        expect(epic > rare).to.equal(true)
        expect(legendary > epic).to.equal(true)
        expect(mythic > legendary).to.equal(true)
      end)

      it("should return 1 for invalid rarity", function()
        expect(XPConfig.getRarityMultiplier("InvalidRarity")).to.equal(1)
      end)
    end)

    describe("getThreatMultiplier", function()
      it("should return 1 for Minor", function()
        expect(XPConfig.getThreatMultiplier("Minor")).to.equal(1)
      end)

      it("should return increasing multipliers for higher threats", function()
        local minor = XPConfig.getThreatMultiplier("Minor")
        local moderate = XPConfig.getThreatMultiplier("Moderate")
        local dangerous = XPConfig.getThreatMultiplier("Dangerous")
        local severe = XPConfig.getThreatMultiplier("Severe")
        local deadly = XPConfig.getThreatMultiplier("Deadly")
        local catastrophic = XPConfig.getThreatMultiplier("Catastrophic")

        expect(moderate > minor).to.equal(true)
        expect(dangerous > moderate).to.equal(true)
        expect(severe > dangerous).to.equal(true)
        expect(deadly > severe).to.equal(true)
        expect(catastrophic > deadly).to.equal(true)
      end)

      it("should return 1 for invalid threat level", function()
        expect(XPConfig.getThreatMultiplier("InvalidThreat")).to.equal(1)
      end)
    end)

    describe("getSummary", function()
      it("should return a string", function()
        local summary = XPConfig.getSummary()
        expect(typeof(summary)).to.equal("string")
      end)

      it("should include reward information", function()
        local summary = XPConfig.getSummary()
        expect(string.find(summary, "XP")).to.be.ok()
      end)
    end)

    describe("config data validity", function()
      it("should have all base rewards be positive", function()
        local types = XPConfig.getAllRewardTypes()
        for _, rewardType in ipairs(types) do
          local reward = XPConfig.getBaseReward(rewardType)
          expect(reward > 0).to.equal(true)
        end
      end)

      it("should have rarity multipliers follow doubling pattern", function()
        expect(XPConfig.getRarityMultiplier("Uncommon")).to.equal(2)
        expect(XPConfig.getRarityMultiplier("Rare")).to.equal(4)
        expect(XPConfig.getRarityMultiplier("Epic")).to.equal(8)
        expect(XPConfig.getRarityMultiplier("Legendary")).to.equal(16)
        expect(XPConfig.getRarityMultiplier("Mythic")).to.equal(32)
      end)

      it("should have threat multipliers follow doubling pattern", function()
        expect(XPConfig.getThreatMultiplier("Moderate")).to.equal(2)
        expect(XPConfig.getThreatMultiplier("Dangerous")).to.equal(4)
        expect(XPConfig.getThreatMultiplier("Severe")).to.equal(8)
        expect(XPConfig.getThreatMultiplier("Deadly")).to.equal(16)
        expect(XPConfig.getThreatMultiplier("Catastrophic")).to.equal(32)
      end)
    end)
  end)
end
