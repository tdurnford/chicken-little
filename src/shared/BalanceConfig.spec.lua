--[[
	BalanceConfig.spec.lua
	TestEZ tests for BalanceConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local BalanceConfig = require(Shared:WaitForChild("BalanceConfig"))

  describe("BalanceConfig", function()
    describe("getEconomy", function()
      it("should return economy config table", function()
        local economy = BalanceConfig.getEconomy()
        expect(typeof(economy)).to.equal("table")
      end)

      it("should have BASE_MONEY_PER_SECOND", function()
        local economy = BalanceConfig.getEconomy()
        expect(economy.BASE_MONEY_PER_SECOND).to.be.ok()
        expect(economy.BASE_MONEY_PER_SECOND > 0).to.equal(true)
      end)

      it("should have RARITY_SCALE_FACTOR", function()
        local economy = BalanceConfig.getEconomy()
        expect(economy.RARITY_SCALE_FACTOR).to.be.ok()
        expect(economy.RARITY_SCALE_FACTOR > 1).to.equal(true)
      end)

      it("should have BASE_EGG_PRICE", function()
        local economy = BalanceConfig.getEconomy()
        expect(economy.BASE_EGG_PRICE).to.be.ok()
        expect(economy.BASE_EGG_PRICE > 0).to.equal(true)
      end)

      it("should have SELL_PRICE_RATIO between 0 and 1", function()
        local economy = BalanceConfig.getEconomy()
        expect(economy.SELL_PRICE_RATIO >= 0).to.equal(true)
        expect(economy.SELL_PRICE_RATIO <= 1).to.equal(true)
      end)
    end)

    describe("getProgressionTargets", function()
      it("should return progression targets table", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(typeof(targets)).to.equal("table")
      end)

      it("should have early game targets", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(targets.EARLY_START).to.be.ok()
        expect(targets.EARLY_END).to.be.ok()
        expect(targets.EARLY_END > targets.EARLY_START).to.equal(true)
      end)

      it("should have mid game targets", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(targets.MID_START).to.be.ok()
        expect(targets.MID_END).to.be.ok()
        expect(targets.MID_END > targets.MID_START).to.equal(true)
      end)

      it("should have late game targets", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(targets.LATE_START).to.be.ok()
        expect(targets.LATE_END).to.be.ok()
        expect(targets.LATE_END > targets.LATE_START).to.equal(true)
      end)

      it("should have stages that progress in order", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(targets.EARLY_END).to.equal(targets.MID_START)
        expect(targets.MID_END).to.equal(targets.LATE_START)
      end)
    end)

    describe("getUpgradeMultiplier", function()
      it("should return 1.0 for tier 1", function()
        expect(BalanceConfig.getUpgradeMultiplier(1)).to.equal(1.0)
      end)

      it("should return increasing multipliers for higher tiers", function()
        local tier1 = BalanceConfig.getUpgradeMultiplier(1)
        local tier5 = BalanceConfig.getUpgradeMultiplier(5)
        local tier10 = BalanceConfig.getUpgradeMultiplier(10)
        expect(tier5 > tier1).to.equal(true)
        expect(tier10 > tier5).to.equal(true)
      end)

      it("should return 1.0 for tier below 1", function()
        expect(BalanceConfig.getUpgradeMultiplier(0)).to.equal(1.0)
        expect(BalanceConfig.getUpgradeMultiplier(-1)).to.equal(1.0)
      end)

      it("should cap at tier 10", function()
        local tier10 = BalanceConfig.getUpgradeMultiplier(10)
        local tier15 = BalanceConfig.getUpgradeMultiplier(15)
        expect(tier15).to.equal(tier10)
      end)
    end)

    describe("getUpgradeCost", function()
      it("should return nil for tier 1 (no upgrade needed)", function()
        expect(BalanceConfig.getUpgradeCost(1)).to.equal(nil)
      end)

      it("should return positive cost for tiers 2-10", function()
        for tier = 2, 10 do
          local cost = BalanceConfig.getUpgradeCost(tier)
          expect(cost).to.be.ok()
          expect(cost > 0).to.equal(true)
        end
      end)

      it("should have increasing costs for higher tiers", function()
        local cost2 = BalanceConfig.getUpgradeCost(2)
        local cost5 = BalanceConfig.getUpgradeCost(5)
        local cost10 = BalanceConfig.getUpgradeCost(10)
        expect(cost5 > cost2).to.equal(true)
        expect(cost10 > cost5).to.equal(true)
      end)

      it("should return nil for tier 11+", function()
        expect(BalanceConfig.getUpgradeCost(11)).to.equal(nil)
      end)
    end)

    describe("getPrestigeConfig", function()
      it("should return prestige config table", function()
        local prestige = BalanceConfig.getPrestigeConfig()
        expect(typeof(prestige)).to.equal("table")
      end)

      it("should have BASE_BONUS", function()
        local prestige = BalanceConfig.getPrestigeConfig()
        expect(prestige.BASE_BONUS).to.be.ok()
        expect(prestige.BASE_BONUS > 0).to.equal(true)
      end)

      it("should have MINIMUM_MONEY", function()
        local prestige = BalanceConfig.getPrestigeConfig()
        expect(prestige.MINIMUM_MONEY).to.be.ok()
        expect(prestige.MINIMUM_MONEY > 0).to.equal(true)
      end)

      it("should have RETENTION_RATE", function()
        local prestige = BalanceConfig.getPrestigeConfig()
        expect(prestige.RETENTION_RATE).to.be.ok()
      end)
    end)

    describe("getOfflineConfig", function()
      it("should return offline config table", function()
        local offline = BalanceConfig.getOfflineConfig()
        expect(typeof(offline)).to.equal("table")
      end)

      it("should have MAX_HOURS", function()
        local offline = BalanceConfig.getOfflineConfig()
        expect(offline.MAX_HOURS).to.be.ok()
        expect(offline.MAX_HOURS > 0).to.equal(true)
      end)

      it("should have EFFICIENCY between 0 and 1", function()
        local offline = BalanceConfig.getOfflineConfig()
        expect(offline.EFFICIENCY >= 0).to.equal(true)
        expect(offline.EFFICIENCY <= 1).to.equal(true)
      end)

      it("should have MAX_MONEY", function()
        local offline = BalanceConfig.getOfflineConfig()
        expect(offline.MAX_MONEY).to.be.ok()
        expect(offline.MAX_MONEY > 0).to.equal(true)
      end)
    end)

    describe("getProgressionStage", function()
      it("should return Early for 0 money", function()
        expect(BalanceConfig.getProgressionStage(0)).to.equal("Early")
      end)

      it("should return Mid for mid-range money", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(BalanceConfig.getProgressionStage(targets.MID_START + 1000)).to.equal("Mid")
      end)

      it("should return Late for late-range money", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(BalanceConfig.getProgressionStage(targets.LATE_START + 1000)).to.equal("Late")
      end)

      it("should return Endgame for money beyond late end", function()
        local targets = BalanceConfig.getProgressionTargets()
        expect(BalanceConfig.getProgressionStage(targets.LATE_END + 1)).to.equal("Endgame")
      end)
    end)

    describe("calculateMoneyPerSecond", function()
      it("should return 0 for empty chicken list", function()
        local mps = BalanceConfig.calculateMoneyPerSecond({}, 1)
        expect(mps).to.equal(0)
      end)

      it("should return positive value for valid chickens", function()
        local mps = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 1)
        expect(mps > 0).to.equal(true)
      end)

      it("should scale with upgrade tier", function()
        local mps1 = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 1)
        local mps5 = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 5)
        expect(mps5 > mps1).to.equal(true)
      end)

      it("should accumulate from multiple chickens", function()
        local mps1 = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 1)
        local mps3 =
          BalanceConfig.calculateMoneyPerSecond({ "BasicChick", "BasicChick", "BasicChick" }, 1)
        expect(mps3).to.equal(mps1 * 3)
      end)

      it("should default to tier 1 if not provided", function()
        local mps = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" })
        local mps1 = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 1)
        expect(mps).to.equal(mps1)
      end)
    end)

    describe("estimateTimeToTarget", function()
      it("should return 0 if already at target", function()
        local time = BalanceConfig.estimateTimeToTarget(1000, 500, 10)
        expect(time).to.equal(0)
      end)

      it("should return nil if no income", function()
        local time = BalanceConfig.estimateTimeToTarget(100, 1000, 0)
        expect(time).to.equal(nil)
      end)

      it("should calculate correct time", function()
        local time = BalanceConfig.estimateTimeToTarget(0, 100, 10)
        expect(time).to.equal(10) -- 100 / 10 = 10 seconds
      end)

      it("should return positive value for valid inputs", function()
        local time = BalanceConfig.estimateTimeToTarget(0, 1000, 5)
        expect(time).to.be.ok()
        expect(time > 0).to.equal(true)
      end)
    end)

    describe("analyzeProgression", function()
      it("should return analysis table", function()
        local analysis = BalanceConfig.analyzeProgression(0, { "BasicChick" }, 1)
        expect(typeof(analysis)).to.equal("table")
      end)

      it("should include stage", function()
        local analysis = BalanceConfig.analyzeProgression(0, { "BasicChick" }, 1)
        expect(analysis.stage).to.be.ok()
      end)

      it("should include moneyPerSecond", function()
        local analysis = BalanceConfig.analyzeProgression(0, { "BasicChick" }, 1)
        expect(analysis.moneyPerSecond).to.be.ok()
      end)

      it("should include percentComplete", function()
        local analysis = BalanceConfig.analyzeProgression(0, { "BasicChick" }, 1)
        expect(analysis.percentComplete >= 0).to.equal(true)
        expect(analysis.percentComplete <= 100).to.equal(true)
      end)

      it("should include bottlenecks array", function()
        local analysis = BalanceConfig.analyzeProgression(0, { "BasicChick" }, 1)
        expect(typeof(analysis.bottlenecks)).to.equal("table")
      end)

      it("should detect no income bottleneck", function()
        local analysis = BalanceConfig.analyzeProgression(0, {}, 1)
        local found = false
        for _, bottleneck in ipairs(analysis.bottlenecks) do
          if string.find(bottleneck, "No income") then
            found = true
            break
          end
        end
        expect(found).to.equal(true)
      end)
    end)

    describe("validateBalance", function()
      it("should return balance report", function()
        local report = BalanceConfig.validateBalance()
        expect(typeof(report)).to.equal("table")
      end)

      it("should include early/mid/late game validity flags", function()
        local report = BalanceConfig.validateBalance()
        expect(report.earlyGameValid).to.be.ok()
        expect(report.midGameValid).to.be.ok()
        expect(report.lateGameValid).to.be.ok()
      end)

      it("should include issues array", function()
        local report = BalanceConfig.validateBalance()
        expect(typeof(report.issues)).to.equal("table")
      end)

      it("should include recommendations array", function()
        local report = BalanceConfig.validateBalance()
        expect(typeof(report.recommendations)).to.equal("table")
      end)
    end)

    describe("simulateProgression", function()
      it("should return simulation result", function()
        local result = BalanceConfig.simulateProgression(0, { "BasicChick" }, 1, 100)
        expect(typeof(result)).to.equal("table")
      end)

      it("should include final money", function()
        local result = BalanceConfig.simulateProgression(100, { "BasicChick" }, 1, 100)
        expect(result.money).to.be.ok()
        expect(result.money >= 100).to.equal(true)
      end)

      it("should include progression stage", function()
        local result = BalanceConfig.simulateProgression(0, { "BasicChick" }, 1, 100)
        expect(result.stage).to.be.ok()
      end)

      it("should calculate money increase correctly", function()
        local mps = BalanceConfig.calculateMoneyPerSecond({ "BasicChick" }, 1)
        local result = BalanceConfig.simulateProgression(0, { "BasicChick" }, 1, 100)
        expect(result.money).to.equal(mps * 100)
      end)
    end)

    describe("calculateSessionEarnings", function()
      it("should return positive earnings for valid session", function()
        local earnings = BalanceConfig.calculateSessionEarnings({ "BasicChick" }, 1, 30)
        expect(earnings > 0).to.equal(true)
      end)

      it("should scale with session length", function()
        local earnings30 = BalanceConfig.calculateSessionEarnings({ "BasicChick" }, 1, 30)
        local earnings60 = BalanceConfig.calculateSessionEarnings({ "BasicChick" }, 1, 60)
        expect(earnings60).to.equal(earnings30 * 2)
      end)

      it("should return 0 for no chickens", function()
        local earnings = BalanceConfig.calculateSessionEarnings({}, 1, 30)
        expect(earnings).to.equal(0)
      end)
    end)

    describe("getProgressionRecommendations", function()
      it("should return array of recommendations", function()
        local recs = BalanceConfig.getProgressionRecommendations(0, { "BasicChick" }, 1)
        expect(typeof(recs)).to.equal("table")
      end)

      it("should recommend upgrade when affordable", function()
        local upgradeCost = BalanceConfig.getUpgradeCost(2)
        local recs = BalanceConfig.getProgressionRecommendations(upgradeCost, { "BasicChick" }, 1)
        local foundUpgrade = false
        for _, rec in ipairs(recs) do
          if string.find(rec, "Upgrade") then
            foundUpgrade = true
            break
          end
        end
        expect(foundUpgrade).to.equal(true)
      end)
    end)

    describe("getSummary", function()
      it("should return a string", function()
        local summary = BalanceConfig.getSummary()
        expect(typeof(summary)).to.equal("string")
      end)

      it("should include economy information", function()
        local summary = BalanceConfig.getSummary()
        expect(string.find(summary, "Economy")).to.be.ok()
      end)

      it("should include progression targets", function()
        local summary = BalanceConfig.getSummary()
        expect(string.find(summary, "Progression")).to.be.ok()
      end)
    end)

    describe("config data validity", function()
      it("should have upgrade costs that increase", function()
        local prevCost = 0
        for tier = 2, 10 do
          local cost = BalanceConfig.getUpgradeCost(tier)
          expect(cost > prevCost).to.equal(true)
          prevCost = cost
        end
      end)

      it("should have upgrade multipliers that increase", function()
        local prevMult = 0
        for tier = 1, 10 do
          local mult = BalanceConfig.getUpgradeMultiplier(tier)
          expect(mult > prevMult).to.equal(true)
          prevMult = mult
        end
      end)

      it("should have offline efficiency less than or equal to 100%", function()
        local offline = BalanceConfig.getOfflineConfig()
        expect(offline.EFFICIENCY <= 1).to.equal(true)
      end)
    end)
  end)
end
