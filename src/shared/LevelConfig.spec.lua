--[[
	LevelConfig.spec.lua
	TestEZ tests for LevelConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

  describe("LevelConfig", function()
    describe("getXPForLevel", function()
      it("should return 0 for level 1", function()
        expect(LevelConfig.getXPForLevel(1)).to.equal(0)
      end)

      it("should return 0 for level 0 or below", function()
        expect(LevelConfig.getXPForLevel(0)).to.equal(0)
        expect(LevelConfig.getXPForLevel(-5)).to.equal(0)
      end)

      it("should return positive XP for level 2", function()
        local xp = LevelConfig.getXPForLevel(2)
        expect(xp > 0).to.equal(true)
      end)

      it("should return increasing XP for higher levels", function()
        local xp5 = LevelConfig.getXPForLevel(5)
        local xp10 = LevelConfig.getXPForLevel(10)
        local xp20 = LevelConfig.getXPForLevel(20)
        expect(xp10 > xp5).to.equal(true)
        expect(xp20 > xp10).to.equal(true)
      end)

      it("should cap at max level", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local xpAtMax = LevelConfig.getXPForLevel(maxLevel)
        local xpBeyond = LevelConfig.getXPForLevel(maxLevel + 10)
        expect(xpBeyond).to.equal(xpAtMax)
      end)
    end)

    describe("getLevelFromXP", function()
      it("should return level 1 for 0 XP", function()
        expect(LevelConfig.getLevelFromXP(0)).to.equal(1)
      end)

      it("should return level 1 for low XP", function()
        expect(LevelConfig.getLevelFromXP(50)).to.equal(1)
      end)

      it("should return level 2 at exactly level 2 XP", function()
        local xpForLevel2 = LevelConfig.getXPForLevel(2)
        expect(LevelConfig.getLevelFromXP(xpForLevel2)).to.equal(2)
      end)

      it("should be consistent with getXPForLevel", function()
        for level = 1, 20 do
          local xpNeeded = LevelConfig.getXPForLevel(level)
          local calculatedLevel = LevelConfig.getLevelFromXP(xpNeeded)
          expect(calculatedLevel).to.equal(level)
        end
      end)

      it("should handle large XP values", function()
        local level = LevelConfig.getLevelFromXP(999999999)
        expect(level).to.equal(LevelConfig.getMaxLevel())
      end)
    end)

    describe("getLevelProgress", function()
      it("should return 0 at start of level", function()
        local xpForLevel5 = LevelConfig.getXPForLevel(5)
        local progress = LevelConfig.getLevelProgress(xpForLevel5)
        expect(progress).to.equal(0)
      end)

      it("should return 1 at max level", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local xpForMax = LevelConfig.getXPForLevel(maxLevel)
        local progress = LevelConfig.getLevelProgress(xpForMax + 1000)
        expect(progress).to.equal(1)
      end)

      it("should return value between 0 and 1", function()
        local xpForLevel5 = LevelConfig.getXPForLevel(5)
        local xpForLevel6 = LevelConfig.getXPForLevel(6)
        local midXP = xpForLevel5 + math.floor((xpForLevel6 - xpForLevel5) / 2)
        local progress = LevelConfig.getLevelProgress(midXP)
        expect(progress >= 0).to.equal(true)
        expect(progress <= 1).to.equal(true)
      end)
    end)

    describe("getXPToNextLevel", function()
      it("should return positive value for non-max levels", function()
        local xpToNext = LevelConfig.getXPToNextLevel(0)
        expect(xpToNext).to.be.ok()
        expect(xpToNext > 0).to.equal(true)
      end)

      it("should return nil at max level", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local xpForMax = LevelConfig.getXPForLevel(maxLevel)
        local xpToNext = LevelConfig.getXPToNextLevel(xpForMax)
        expect(xpToNext).to.equal(nil)
      end)

      it("should decrease as XP increases within a level", function()
        local xpForLevel5 = LevelConfig.getXPForLevel(5)
        local toNext1 = LevelConfig.getXPToNextLevel(xpForLevel5)
        local toNext2 = LevelConfig.getXPToNextLevel(xpForLevel5 + 50)
        expect(toNext1).to.be.ok()
        expect(toNext2).to.be.ok()
        expect(toNext2 < toNext1).to.equal(true)
      end)
    end)

    describe("getMaxPredatorsForLevel", function()
      it("should return at least 1 predator for level 1", function()
        local maxPredators = LevelConfig.getMaxPredatorsForLevel(1)
        expect(maxPredators >= 1).to.equal(true)
      end)

      it("should increase with level", function()
        local level1 = LevelConfig.getMaxPredatorsForLevel(1)
        local level20 = LevelConfig.getMaxPredatorsForLevel(20)
        expect(level20 >= level1).to.equal(true)
      end)

      it("should cap at maximum simultaneous predators", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local maxPredators = LevelConfig.getMaxPredatorsForLevel(maxLevel)
        expect(maxPredators <= 8).to.equal(true)
      end)
    end)

    describe("getThreatMultiplierForLevel", function()
      it("should return 1.0 for level 1", function()
        local multiplier = LevelConfig.getThreatMultiplierForLevel(1)
        expect(multiplier).to.equal(1.0)
      end)

      it("should increase with level", function()
        local level1 = LevelConfig.getThreatMultiplierForLevel(1)
        local level50 = LevelConfig.getThreatMultiplierForLevel(50)
        expect(level50 > level1).to.equal(true)
      end)

      it("should return value between 1.0 and 2.0", function()
        for level = 1, 100 do
          local mult = LevelConfig.getThreatMultiplierForLevel(level)
          expect(mult >= 1.0).to.equal(true)
          expect(mult <= 2.0).to.equal(true)
        end
      end)
    end)

    describe("getMaxThreatLevel", function()
      it("should return Minor for level 1", function()
        local threat = LevelConfig.getMaxThreatLevel(1)
        expect(threat).to.equal("Minor")
      end)

      it("should unlock higher threats at higher levels", function()
        -- Moderate unlocks at level 5
        local threat5 = LevelConfig.getMaxThreatLevel(5)
        expect(threat5).to.never.equal("Minor")
      end)

      it("should return a valid threat level string", function()
        local validThreats =
          { "Minor", "Moderate", "Dangerous", "Severe", "Deadly", "Catastrophic" }
        for level = 1, 100, 10 do
          local threat = LevelConfig.getMaxThreatLevel(level)
          local found = false
          for _, valid in ipairs(validThreats) do
            if valid == threat then
              found = true
              break
            end
          end
          expect(found).to.equal(true)
        end
      end)
    end)

    describe("isThreatLevelUnlocked", function()
      it("should return true for Minor at level 1", function()
        expect(LevelConfig.isThreatLevelUnlocked(1, "Minor")).to.equal(true)
      end)

      it("should return false for invalid threat level", function()
        expect(LevelConfig.isThreatLevelUnlocked(100, "SuperThreat")).to.equal(false)
      end)

      it("should unlock Moderate at level 5", function()
        expect(LevelConfig.isThreatLevelUnlocked(4, "Moderate")).to.equal(false)
        expect(LevelConfig.isThreatLevelUnlocked(5, "Moderate")).to.equal(true)
      end)

      it("should unlock Catastrophic at level 75", function()
        expect(LevelConfig.isThreatLevelUnlocked(74, "Catastrophic")).to.equal(false)
        expect(LevelConfig.isThreatLevelUnlocked(75, "Catastrophic")).to.equal(true)
      end)
    end)

    describe("getLevelData", function()
      it("should return complete level data", function()
        local data = LevelConfig.getLevelData(5)
        expect(data).to.be.ok()
        expect(data.level).to.equal(5)
        expect(data.xpRequired).to.be.ok()
        expect(data.maxSimultaneousPredators).to.be.ok()
        expect(data.predatorThreatMultiplier).to.be.ok()
      end)

      it("should include xpToNextLevel for non-max levels", function()
        local data = LevelConfig.getLevelData(10)
        expect(data.xpToNextLevel).to.be.ok()
        expect(data.xpToNextLevel > 0).to.equal(true)
      end)

      it("should not include xpToNextLevel at max level", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local data = LevelConfig.getLevelData(maxLevel)
        expect(data.xpToNextLevel).to.equal(nil)
      end)

      it("should clamp level below 1 to 1", function()
        local data = LevelConfig.getLevelData(0)
        expect(data.level).to.equal(1)
      end)

      it("should clamp level above max to max", function()
        local maxLevel = LevelConfig.getMaxLevel()
        local data = LevelConfig.getLevelData(maxLevel + 50)
        expect(data.level).to.equal(maxLevel)
      end)
    end)

    describe("getLevelDataFromXP", function()
      it("should return level data based on XP", function()
        local xpForLevel10 = LevelConfig.getXPForLevel(10)
        local data = LevelConfig.getLevelDataFromXP(xpForLevel10)
        expect(data.level).to.equal(10)
      end)

      it("should return level 1 for 0 XP", function()
        local data = LevelConfig.getLevelDataFromXP(0)
        expect(data.level).to.equal(1)
      end)
    end)

    describe("getThreatUnlockLevels", function()
      it("should return a table of threat levels", function()
        local unlocks = LevelConfig.getThreatUnlockLevels()
        expect(typeof(unlocks)).to.equal("table")
      end)

      it("should include all threat levels", function()
        local unlocks = LevelConfig.getThreatUnlockLevels()
        expect(unlocks.Minor).to.be.ok()
        expect(unlocks.Moderate).to.be.ok()
        expect(unlocks.Dangerous).to.be.ok()
        expect(unlocks.Severe).to.be.ok()
        expect(unlocks.Deadly).to.be.ok()
        expect(unlocks.Catastrophic).to.be.ok()
      end)

      it("should return a copy (not modifiable)", function()
        local unlocks1 = LevelConfig.getThreatUnlockLevels()
        unlocks1.Minor = 999
        local unlocks2 = LevelConfig.getThreatUnlockLevels()
        expect(unlocks2.Minor).to.equal(1)
      end)
    end)

    describe("getMaxLevel", function()
      it("should return 100", function()
        expect(LevelConfig.getMaxLevel()).to.equal(100)
      end)
    end)

    describe("getBaseXPRequirement", function()
      it("should return a positive number", function()
        local base = LevelConfig.getBaseXPRequirement()
        expect(base > 0).to.equal(true)
      end)
    end)

    describe("getXPScalingFactor", function()
      it("should return a value greater than 1", function()
        local factor = LevelConfig.getXPScalingFactor()
        expect(factor > 1).to.equal(true)
      end)
    end)

    describe("isValidLevel", function()
      it("should return true for valid levels", function()
        expect(LevelConfig.isValidLevel(1)).to.equal(true)
        expect(LevelConfig.isValidLevel(50)).to.equal(true)
        expect(LevelConfig.isValidLevel(100)).to.equal(true)
      end)

      it("should return false for invalid levels", function()
        expect(LevelConfig.isValidLevel(0)).to.equal(false)
        expect(LevelConfig.isValidLevel(-1)).to.equal(false)
        expect(LevelConfig.isValidLevel(101)).to.equal(false)
        expect(LevelConfig.isValidLevel(5.5)).to.equal(false)
      end)
    end)

    describe("isValidXP", function()
      it("should return true for valid XP values", function()
        expect(LevelConfig.isValidXP(0)).to.equal(true)
        expect(LevelConfig.isValidXP(100)).to.equal(true)
        expect(LevelConfig.isValidXP(999999)).to.equal(true)
      end)

      it("should return false for negative XP", function()
        expect(LevelConfig.isValidXP(-1)).to.equal(false)
      end)

      it("should return false for non-integer XP", function()
        expect(LevelConfig.isValidXP(50.5)).to.equal(false)
      end)
    end)

    describe("getLevelUpBonusXP", function()
      it("should return 0 for most levels", function()
        expect(LevelConfig.getLevelUpBonusXP(3)).to.equal(0)
        expect(LevelConfig.getLevelUpBonusXP(7)).to.equal(0)
      end)

      it("should return 200 for milestone levels (multiples of 5)", function()
        expect(LevelConfig.getLevelUpBonusXP(5)).to.equal(200)
        expect(LevelConfig.getLevelUpBonusXP(15)).to.equal(200)
        expect(LevelConfig.getLevelUpBonusXP(25)).to.equal(200)
      end)

      it("should return 500 for major milestones (multiples of 10)", function()
        expect(LevelConfig.getLevelUpBonusXP(10)).to.equal(500)
        expect(LevelConfig.getLevelUpBonusXP(50)).to.equal(500)
        expect(LevelConfig.getLevelUpBonusXP(100)).to.equal(500)
      end)
    end)

    describe("getSummary", function()
      it("should return a string", function()
        local summary = LevelConfig.getSummary()
        expect(typeof(summary)).to.equal("string")
      end)

      it("should include level range info", function()
        local summary = LevelConfig.getSummary()
        expect(string.find(summary, "Level Range")).to.be.ok()
      end)
    end)

    describe("config data validity", function()
      it("should have XP requirements that always increase", function()
        local prevXP = 0
        for level = 1, 50 do
          local xp = LevelConfig.getXPForLevel(level)
          expect(xp >= prevXP).to.equal(true)
          prevXP = xp
        end
      end)

      it("should have threat unlocks at increasing levels", function()
        local unlocks = LevelConfig.getThreatUnlockLevels()
        expect(unlocks.Minor < unlocks.Moderate).to.equal(true)
        expect(unlocks.Moderate < unlocks.Dangerous).to.equal(true)
        expect(unlocks.Dangerous < unlocks.Severe).to.equal(true)
        expect(unlocks.Severe < unlocks.Deadly).to.equal(true)
        expect(unlocks.Deadly < unlocks.Catastrophic).to.equal(true)
      end)
    end)
  end)
end
