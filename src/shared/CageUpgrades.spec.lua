--[[
	CageUpgrades.spec.lua
	TestEZ tests for CageUpgrades module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local CageUpgrades = require(Shared:WaitForChild("CageUpgrades"))

  -- Helper function to create mock player data
  local function createMockPlayerData(money, cageTier)
    return {
      money = money or 10000,
      upgrades = {
        cageTier = cageTier or 1,
        lockDurationMultiplier = 1.0,
        predatorResistance = 0.0,
      },
    }
  end

  describe("CageUpgrades", function()
    describe("getTierConfig", function()
      it("should return config for valid tiers (1-6)", function()
        for tier = 1, 6 do
          local config = CageUpgrades.getTierConfig(tier)
          expect(config).to.be.ok()
          expect(config.tier).to.equal(tier)
        end
      end)

      it("should return nil for invalid tiers", function()
        expect(CageUpgrades.getTierConfig(0)).to.equal(nil)
        expect(CageUpgrades.getTierConfig(7)).to.equal(nil)
        expect(CageUpgrades.getTierConfig(-1)).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = CageUpgrades.getTierConfig(1)
        expect(config.tier).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.price).to.be.ok()
        expect(config.lockDurationMultiplier).to.be.ok()
        expect(config.predatorResistance).to.be.ok()
        expect(config.description).to.be.ok()
      end)
    end)

    describe("getAllTiers", function()
      it("should return all 6 tiers", function()
        local tiers = CageUpgrades.getAllTiers()
        expect(#tiers).to.equal(6)
      end)

      it("should return tiers in order", function()
        local tiers = CageUpgrades.getAllTiers()
        for i, tier in ipairs(tiers) do
          expect(tier.tier).to.equal(i)
        end
      end)
    end)

    describe("getMaxTier", function()
      it("should return 6", function()
        expect(CageUpgrades.getMaxTier()).to.equal(6)
      end)
    end)

    describe("isValidTier", function()
      it("should return true for valid tiers (1-6)", function()
        for tier = 1, 6 do
          expect(CageUpgrades.isValidTier(tier)).to.equal(true)
        end
      end)

      it("should return false for invalid tiers", function()
        expect(CageUpgrades.isValidTier(0)).to.equal(false)
        expect(CageUpgrades.isValidTier(7)).to.equal(false)
        expect(CageUpgrades.isValidTier(-1)).to.equal(false)
      end)
    end)

    describe("getLockDurationMultiplier", function()
      it("should return 1.0 for tier 1", function()
        expect(CageUpgrades.getLockDurationMultiplier(1)).to.equal(1.0)
      end)

      it("should increase with higher tiers", function()
        local prev = CageUpgrades.getLockDurationMultiplier(1)
        for tier = 2, 6 do
          local current = CageUpgrades.getLockDurationMultiplier(tier)
          expect(current > prev).to.equal(true)
          prev = current
        end
      end)

      it("should return 1.0 for invalid tiers", function()
        expect(CageUpgrades.getLockDurationMultiplier(0)).to.equal(1.0)
        expect(CageUpgrades.getLockDurationMultiplier(7)).to.equal(1.0)
      end)
    end)

    describe("getPredatorResistance", function()
      it("should return 0.0 for tier 1", function()
        expect(CageUpgrades.getPredatorResistance(1)).to.equal(0.0)
      end)

      it("should increase with higher tiers", function()
        local prev = CageUpgrades.getPredatorResistance(1)
        for tier = 2, 6 do
          local current = CageUpgrades.getPredatorResistance(tier)
          expect(current >= prev).to.equal(true)
          prev = current
        end
      end)

      it("should return 0.0 for invalid tiers", function()
        expect(CageUpgrades.getPredatorResistance(0)).to.equal(0.0)
        expect(CageUpgrades.getPredatorResistance(7)).to.equal(0.0)
      end)

      it("should be between 0 and 1 for all tiers", function()
        for tier = 1, 6 do
          local resistance = CageUpgrades.getPredatorResistance(tier)
          expect(resistance >= 0).to.equal(true)
          expect(resistance <= 1).to.equal(true)
        end
      end)
    end)

    describe("getLockDuration", function()
      it("should return base duration for tier 1", function()
        local duration = CageUpgrades.getLockDuration(1)
        expect(duration).to.equal(60)
      end)

      it("should increase with higher tiers", function()
        local prev = CageUpgrades.getLockDuration(1)
        for tier = 2, 6 do
          local current = CageUpgrades.getLockDuration(tier)
          expect(current > prev).to.equal(true)
          prev = current
        end
      end)
    end)

    describe("getTierPrice", function()
      it("should return 0 for tier 1", function()
        expect(CageUpgrades.getTierPrice(1)).to.equal(0)
      end)

      it("should return positive prices for tiers 2+", function()
        for tier = 2, 6 do
          expect(CageUpgrades.getTierPrice(tier) > 0).to.equal(true)
        end
      end)

      it("should increase prices with higher tiers", function()
        local prev = CageUpgrades.getTierPrice(2)
        for tier = 3, 6 do
          local current = CageUpgrades.getTierPrice(tier)
          expect(current > prev).to.equal(true)
          prev = current
        end
      end)

      it("should return 0 for invalid tiers", function()
        expect(CageUpgrades.getTierPrice(0)).to.equal(0)
        expect(CageUpgrades.getTierPrice(7)).to.equal(0)
      end)
    end)

    describe("getNextTierPrice", function()
      it("should return tier 2 price for tier 1", function()
        local price = CageUpgrades.getNextTierPrice(1)
        expect(price).to.equal(CageUpgrades.getTierPrice(2))
      end)

      it("should return nil for max tier", function()
        expect(CageUpgrades.getNextTierPrice(6)).to.equal(nil)
      end)
    end)

    describe("canAffordNextTier", function()
      it("should return true when player has enough money", function()
        local price = CageUpgrades.getTierPrice(2)
        expect(CageUpgrades.canAffordNextTier(1, price)).to.equal(true)
        expect(CageUpgrades.canAffordNextTier(1, price + 1000)).to.equal(true)
      end)

      it("should return false when player has insufficient money", function()
        local price = CageUpgrades.getTierPrice(2)
        expect(CageUpgrades.canAffordNextTier(1, price - 1)).to.equal(false)
        expect(CageUpgrades.canAffordNextTier(1, 0)).to.equal(false)
      end)

      it("should return false at max tier", function()
        expect(CageUpgrades.canAffordNextTier(6, 999999999)).to.equal(false)
      end)
    end)

    describe("isMaxTier", function()
      it("should return false for tiers below max", function()
        for tier = 1, 5 do
          expect(CageUpgrades.isMaxTier(tier)).to.equal(false)
        end
      end)

      it("should return true for max tier", function()
        expect(CageUpgrades.isMaxTier(6)).to.equal(true)
      end)

      it("should return true for tiers above max", function()
        expect(CageUpgrades.isMaxTier(7)).to.equal(true)
      end)
    end)

    describe("purchaseUpgrade", function()
      it("should fail for invalid player data", function()
        local result = CageUpgrades.purchaseUpgrade(nil)
        expect(result.success).to.equal(false)
      end)

      it("should fail for player data without upgrades", function()
        local result = CageUpgrades.purchaseUpgrade({ money = 10000 })
        expect(result.success).to.equal(false)
      end)

      it("should fail at max tier", function()
        local playerData = createMockPlayerData(10000000, 6)
        local result = CageUpgrades.purchaseUpgrade(playerData)
        expect(result.success).to.equal(false)
        expect(result.message).to.be.ok()
      end)

      it("should fail with insufficient funds", function()
        local playerData = createMockPlayerData(0, 1)
        local result = CageUpgrades.purchaseUpgrade(playerData)
        expect(result.success).to.equal(false)
      end)

      it("should succeed with sufficient funds", function()
        local price = CageUpgrades.getTierPrice(2)
        local playerData = createMockPlayerData(price, 1)
        local result = CageUpgrades.purchaseUpgrade(playerData)
        expect(result.success).to.equal(true)
        expect(result.newTier).to.equal(2)
        expect(playerData.upgrades.cageTier).to.equal(2)
        expect(playerData.money).to.equal(0)
      end)

      it("should update multipliers after purchase", function()
        local price = CageUpgrades.getTierPrice(2)
        local playerData = createMockPlayerData(price, 1)
        local result = CageUpgrades.purchaseUpgrade(playerData)
        expect(result.success).to.equal(true)
        expect(playerData.upgrades.lockDurationMultiplier > 1.0).to.equal(true)
        expect(playerData.upgrades.predatorResistance > 0).to.equal(true)
      end)
    end)

    describe("purchaseSpecificTier", function()
      it("should fail for invalid player data", function()
        local result = CageUpgrades.purchaseSpecificTier(nil, 2)
        expect(result.success).to.equal(false)
      end)

      it("should fail for invalid target tier", function()
        local playerData = createMockPlayerData(10000000, 1)
        local result = CageUpgrades.purchaseSpecificTier(playerData, 7)
        expect(result.success).to.equal(false)
      end)

      it("should fail if target tier is current tier or lower", function()
        local playerData = createMockPlayerData(10000000, 3)
        expect(CageUpgrades.purchaseSpecificTier(playerData, 3).success).to.equal(false)
        expect(CageUpgrades.purchaseSpecificTier(playerData, 2).success).to.equal(false)
        expect(CageUpgrades.purchaseSpecificTier(playerData, 1).success).to.equal(false)
      end)

      it("should fail if skipping tiers", function()
        local playerData = createMockPlayerData(10000000, 1)
        local result = CageUpgrades.purchaseSpecificTier(playerData, 3)
        expect(result.success).to.equal(false)
      end)

      it("should succeed for next tier", function()
        local price = CageUpgrades.getTierPrice(2)
        local playerData = createMockPlayerData(price, 1)
        local result = CageUpgrades.purchaseSpecificTier(playerData, 2)
        expect(result.success).to.equal(true)
      end)
    end)

    describe("getUpgradeInfo", function()
      it("should return correct info for tier 1", function()
        local playerData = createMockPlayerData(10000, 1)
        local info = CageUpgrades.getUpgradeInfo(playerData)
        expect(info.currentTier).to.equal(1)
        expect(info.nextTier).to.equal(2)
        expect(info.isMaxTier).to.equal(false)
        expect(info.currentTierName).to.be.ok()
        expect(info.nextTierName).to.be.ok()
        expect(info.nextTierPrice).to.be.ok()
      end)

      it("should return correct info for max tier", function()
        local playerData = createMockPlayerData(10000, 6)
        local info = CageUpgrades.getUpgradeInfo(playerData)
        expect(info.currentTier).to.equal(6)
        expect(info.nextTier).to.equal(nil)
        expect(info.isMaxTier).to.equal(true)
        expect(info.nextTierName).to.equal(nil)
        expect(info.nextTierPrice).to.equal(nil)
      end)

      it("should correctly determine canAffordNext", function()
        local price = CageUpgrades.getTierPrice(2)
        local playerData = createMockPlayerData(price - 1, 1)
        local info = CageUpgrades.getUpgradeInfo(playerData)
        expect(info.canAffordNext).to.equal(false)

        playerData.money = price
        info = CageUpgrades.getUpgradeInfo(playerData)
        expect(info.canAffordNext).to.equal(true)
      end)

      it("should handle nil player data", function()
        local info = CageUpgrades.getUpgradeInfo(nil)
        expect(info.currentTier).to.equal(1)
      end)
    end)

    describe("getDisplayInfo", function()
      it("should return display info for regular tier", function()
        local playerData = createMockPlayerData(10000, 1)
        local info = CageUpgrades.getDisplayInfo(playerData)
        expect(info.tierText).to.be.ok()
        expect(info.descriptionText).to.be.ok()
        expect(info.statsText).to.be.ok()
        expect(info.buttonText).to.be.ok()
        expect(type(info.buttonEnabled)).to.equal("boolean")
      end)

      it("should show MAX TIER at max tier", function()
        local playerData = createMockPlayerData(10000, 6)
        local info = CageUpgrades.getDisplayInfo(playerData)
        expect(info.buttonText).to.equal("MAX TIER")
        expect(info.buttonEnabled).to.equal(false)
      end)

      it("should disable button when cannot afford", function()
        local playerData = createMockPlayerData(0, 1)
        local info = CageUpgrades.getDisplayInfo(playerData)
        expect(info.buttonEnabled).to.equal(false)
      end)

      it("should enable button when can afford", function()
        local price = CageUpgrades.getTierPrice(2)
        local playerData = createMockPlayerData(price, 1)
        local info = CageUpgrades.getDisplayInfo(playerData)
        expect(info.buttonEnabled).to.equal(true)
      end)
    end)

    describe("getUpgradeComparison", function()
      it("should return comparison for valid tier", function()
        local comparison = CageUpgrades.getUpgradeComparison(1)
        expect(comparison.currentLockDuration).to.be.ok()
        expect(comparison.nextLockDuration).to.be.ok()
        expect(comparison.currentResistance).to.be.ok()
        expect(comparison.nextResistance).to.be.ok()
        expect(comparison.lockDurationIncrease).to.be.ok()
        expect(comparison.resistanceIncrease).to.be.ok()
      end)

      it("should return nil values for max tier", function()
        local comparison = CageUpgrades.getUpgradeComparison(6)
        expect(comparison.currentLockDuration).to.be.ok()
        expect(comparison.nextLockDuration).to.equal(nil)
        expect(comparison.currentResistance).to.be.ok()
        expect(comparison.nextResistance).to.equal(nil)
        expect(comparison.lockDurationIncrease).to.equal(nil)
        expect(comparison.resistanceIncrease).to.equal(nil)
      end)

      it("should show positive increases", function()
        local comparison = CageUpgrades.getUpgradeComparison(1)
        expect(comparison.lockDurationIncrease > 0).to.equal(true)
        expect(comparison.resistanceIncrease > 0).to.equal(true)
      end)
    end)

    describe("getAffordableTiers", function()
      it("should return empty when cannot afford next tier", function()
        local affordable = CageUpgrades.getAffordableTiers(1, 0)
        expect(#affordable).to.equal(0)
      end)

      it("should return next tier when affordable", function()
        local price = CageUpgrades.getTierPrice(2)
        local affordable = CageUpgrades.getAffordableTiers(1, price)
        expect(#affordable).to.equal(1)
        expect(affordable[1].tier).to.equal(2)
      end)

      it("should return empty at max tier", function()
        local affordable = CageUpgrades.getAffordableTiers(6, 999999999)
        expect(#affordable).to.equal(0)
      end)
    end)

    describe("getTotalCostToTier", function()
      it("should return 0 for same or lower tier", function()
        expect(CageUpgrades.getTotalCostToTier(3, 3)).to.equal(0)
        expect(CageUpgrades.getTotalCostToTier(3, 2)).to.equal(0)
        expect(CageUpgrades.getTotalCostToTier(3, 1)).to.equal(0)
      end)

      it("should return correct cost for single tier upgrade", function()
        local cost = CageUpgrades.getTotalCostToTier(1, 2)
        expect(cost).to.equal(CageUpgrades.getTierPrice(2))
      end)

      it("should sum costs for multiple tier upgrades", function()
        local cost = CageUpgrades.getTotalCostToTier(1, 3)
        local expected = CageUpgrades.getTierPrice(2) + CageUpgrades.getTierPrice(3)
        expect(cost).to.equal(expected)
      end)

      it("should calculate full cost from tier 1 to max", function()
        local cost = CageUpgrades.getTotalCostToTier(1, 6)
        local expected = 0
        for tier = 2, 6 do
          expected = expected + CageUpgrades.getTierPrice(tier)
        end
        expect(cost).to.equal(expected)
      end)
    end)

    describe("validateConfig", function()
      it("should return valid for current config", function()
        local result = CageUpgrades.validateConfig()
        expect(result.valid).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)
    end)

    describe("getTierByName", function()
      it("should find tier by name", function()
        local tier = CageUpgrades.getTierByName("Basic")
        expect(tier).to.be.ok()
        expect(tier.tier).to.equal(1)
      end)

      it("should find tier by display name", function()
        local tier = CageUpgrades.getTierByName("Basic Cage")
        expect(tier).to.be.ok()
        expect(tier.tier).to.equal(1)
      end)

      it("should return nil for unknown name", function()
        expect(CageUpgrades.getTierByName("NonexistentTier")).to.equal(nil)
      end)
    end)

    describe("getTierNames", function()
      it("should return 6 tier names", function()
        local names = CageUpgrades.getTierNames()
        expect(#names).to.equal(6)
      end)

      it("should return display names in order", function()
        local names = CageUpgrades.getTierNames()
        expect(names[1]).to.equal("Basic Cage")
      end)
    end)

    describe("getConfig", function()
      it("should return config constants", function()
        local config = CageUpgrades.getConfig()
        expect(config.baseLockDuration).to.equal(60)
        expect(config.maxTier).to.equal(6)
      end)
    end)
  end)
end
