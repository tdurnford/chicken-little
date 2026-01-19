--[[
	OfflineEarnings.spec.lua
	TestEZ tests for OfflineEarnings module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local OfflineEarnings = require(Shared:WaitForChild("OfflineEarnings"))

  -- Helper function to create mock player data
  local function createMockPlayerData()
    return {
      money = 1000,
      lastLogoutTime = os.time() - 3600, -- 1 hour ago
      inventory = {
        eggs = {},
        chickens = {},
      },
      placedChickens = {},
      traps = {},
      upgrades = {
        cageTier = 1,
      },
    }
  end

  -- Helper function to create a mock placed chicken
  local function createMockChicken(id, chickenType, rarity, lastEggTime)
    return {
      id = id or "chicken-" .. tostring(math.random(1000, 9999)),
      chickenType = chickenType or "BasicChick",
      rarity = rarity or "Common",
      accumulatedMoney = 0,
      lastEggTime = lastEggTime or os.time() - 3600,
      spotIndex = 1,
    }
  end

  describe("OfflineEarnings", function()
    describe("getConfig", function()
      it("should return configuration values", function()
        local config = OfflineEarnings.getConfig()
        expect(config).to.be.ok()
        expect(config.maxOfflineHours).to.be.ok()
        expect(config.offlineEarningsRate).to.be.ok()
        expect(config.maxOfflineEggsPerChicken).to.be.ok()
      end)

      it("should have reasonable default values", function()
        local config = OfflineEarnings.getConfig()
        expect(config.maxOfflineHours).to.equal(24)
        expect(config.offlineEarningsRate).to.equal(0.5)
        expect(config.maxOfflineEggsPerChicken).to.equal(10)
      end)
    end)

    describe("calculate", function()
      it("should return zero earnings for no placed chickens", function()
        local playerData = createMockPlayerData()
        local currentTime = os.time()
        local result = OfflineEarnings.calculate(playerData, currentTime)
        expect(result.cappedMoney).to.equal(0)
        expect(#result.eggsEarned).to.equal(0)
      end)

      it("should return zero earnings for no time elapsed", function()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = os.time()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        local result = OfflineEarnings.calculate(playerData, os.time())
        expect(result.cappedMoney).to.equal(0)
      end)

      it("should calculate earnings for placed chickens", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 3600 -- 1 hour ago
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        local result = OfflineEarnings.calculate(playerData, currentTime)
        expect(result.elapsedSeconds).to.equal(3600)
        expect(result.cappedSeconds).to.equal(3600)
      end)

      it("should cap offline time at maximum", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        -- 48 hours ago (exceeds max)
        playerData.lastLogoutTime = currentTime - (48 * 3600)
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        local result = OfflineEarnings.calculate(playerData, currentTime)
        expect(result.wasCapped).to.equal(true)
        expect(result.cappedSeconds).to.equal(24 * 3600) -- Max 24 hours
      end)

      it("should track money per chicken", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 3600
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick"),
          createMockChicken("c2", "BasicChick"),
        }
        local result = OfflineEarnings.calculate(playerData, currentTime)
        expect(#result.moneyPerChicken).to.equal(2)
      end)
    end)

    describe("apply", function()
      it("should return success with no changes for zero earnings", function()
        local playerData = createMockPlayerData()
        local earnings = {
          cappedMoney = 0,
          eggsEarned = {},
          totalMoney = 0,
          totalEggs = 0,
          cappedEggs = 0,
          elapsedSeconds = 0,
          cappedSeconds = 0,
          wasCapped = false,
          moneyPerChicken = {},
        }
        local result = OfflineEarnings.apply(playerData, earnings)
        expect(result.success).to.equal(true)
        expect(result.moneyAdded).to.equal(0)
        expect(result.eggsAdded).to.equal(0)
      end)

      it("should add money to player data", function()
        local playerData = createMockPlayerData()
        local initialMoney = playerData.money
        local earnings = {
          cappedMoney = 500,
          eggsEarned = {},
          totalMoney = 500,
          totalEggs = 0,
          cappedEggs = 0,
          elapsedSeconds = 3600,
          cappedSeconds = 3600,
          wasCapped = false,
          moneyPerChicken = {},
        }
        local result = OfflineEarnings.apply(playerData, earnings)
        expect(result.success).to.equal(true)
        expect(result.moneyAdded).to.equal(500)
        expect(playerData.money).to.equal(initialMoney + 500)
      end)

      it("should add eggs to inventory", function()
        local playerData = createMockPlayerData()
        local earnings = {
          cappedMoney = 0,
          eggsEarned = {
            {
              eggType = "BasicEgg",
              rarity = "Common",
              chickenId = "c1",
              chickenType = "BasicChick",
            },
            {
              eggType = "BasicEgg",
              rarity = "Common",
              chickenId = "c1",
              chickenType = "BasicChick",
            },
          },
          totalMoney = 0,
          totalEggs = 2,
          cappedEggs = 2,
          elapsedSeconds = 3600,
          cappedSeconds = 3600,
          wasCapped = false,
          moneyPerChicken = {},
        }
        local result = OfflineEarnings.apply(playerData, earnings)
        expect(result.success).to.equal(true)
        expect(result.eggsAdded).to.equal(2)
        expect(#playerData.inventory.eggs).to.equal(2)
      end)
    end)

    describe("calculateAndApply", function()
      it("should calculate and apply in one call", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 3600
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        local earnings, applyResult = OfflineEarnings.calculateAndApply(playerData, currentTime)
        expect(earnings).to.be.ok()
        expect(applyResult).to.be.ok()
        expect(applyResult.success).to.equal(true)
      end)
    end)

    describe("hasEarnings", function()
      it("should return false when no logout time", function()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = nil
        expect(OfflineEarnings.hasEarnings(playerData, os.time())).to.equal(false)
      end)

      it("should return false when no placed chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {}
        expect(OfflineEarnings.hasEarnings(playerData, os.time())).to.equal(false)
      end)

      it("should return false when offline less than 1 minute", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 30 -- 30 seconds
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        expect(OfflineEarnings.hasEarnings(playerData, currentTime)).to.equal(false)
      end)

      it("should return true when has placed chickens and offline > 1 minute", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 120 -- 2 minutes
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        expect(OfflineEarnings.hasEarnings(playerData, currentTime)).to.equal(true)
      end)
    end)

    describe("getPreview", function()
      it("should return no pending earnings when hasEarnings is false", function()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = nil
        local preview = OfflineEarnings.getPreview(playerData, os.time())
        expect(preview.hasPendingEarnings).to.equal(false)
        expect(preview.estimatedMoney).to.equal(0)
        expect(preview.estimatedEggs).to.equal(0)
      end)

      it("should return preview data when earnings pending", function()
        local currentTime = os.time()
        local playerData = createMockPlayerData()
        playerData.lastLogoutTime = currentTime - 3600
        playerData.placedChickens = { createMockChicken("c1", "BasicChick") }
        local preview = OfflineEarnings.getPreview(playerData, currentTime)
        expect(preview.placedChickenCount).to.equal(1)
        expect(preview.offlineHours).to.be.near(1, 0.1)
      end)
    end)

    describe("formatDuration", function()
      it("should format seconds correctly", function()
        expect(OfflineEarnings.formatDuration(30)).to.equal("30 seconds")
        expect(OfflineEarnings.formatDuration(1)).to.equal("1 seconds")
      end)

      it("should format minutes correctly", function()
        expect(OfflineEarnings.formatDuration(60)).to.equal("1 minute")
        expect(OfflineEarnings.formatDuration(120)).to.equal("2 minutes")
        expect(OfflineEarnings.formatDuration(300)).to.equal("5 minutes")
      end)

      it("should format hours correctly", function()
        expect(OfflineEarnings.formatDuration(3600)).to.equal("1 hour")
        expect(OfflineEarnings.formatDuration(7200)).to.equal("2 hours")
      end)

      it("should format hours and minutes", function()
        expect(OfflineEarnings.formatDuration(3660)).to.equal("1h 1m")
        expect(OfflineEarnings.formatDuration(7260)).to.equal("2h 1m")
      end)

      it("should format days correctly", function()
        expect(OfflineEarnings.formatDuration(86400)).to.equal("1 day")
        expect(OfflineEarnings.formatDuration(172800)).to.equal("2 days")
      end)

      it("should format days and hours", function()
        expect(OfflineEarnings.formatDuration(90000)).to.equal("1d 1h")
      end)
    end)

    describe("getEarningsByRarity", function()
      it("should initialize all rarities with zero values", function()
        local earnings = {
          cappedMoney = 0,
          eggsEarned = {},
          totalMoney = 0,
          totalEggs = 0,
          cappedEggs = 0,
          elapsedSeconds = 0,
          cappedSeconds = 0,
          wasCapped = false,
          moneyPerChicken = {},
        }
        local byRarity = OfflineEarnings.getEarningsByRarity(earnings)
        expect(byRarity.Common).to.be.ok()
        expect(byRarity.Common.money).to.equal(0)
        expect(byRarity.Common.eggs).to.equal(0)
        expect(byRarity.Rare).to.be.ok()
        expect(byRarity.Legendary).to.be.ok()
      end)

      it("should sum money by chicken rarity", function()
        local earnings = {
          cappedMoney = 300,
          eggsEarned = {},
          totalMoney = 300,
          totalEggs = 0,
          cappedEggs = 0,
          elapsedSeconds = 3600,
          cappedSeconds = 3600,
          wasCapped = false,
          moneyPerChicken = {
            {
              chickenId = "c1",
              chickenType = "BasicChick",
              displayName = "Basic",
              rarity = "Common",
              moneyEarned = 100,
              eggsLaid = {},
            },
            {
              chickenId = "c2",
              chickenType = "RareChick",
              displayName = "Rare",
              rarity = "Rare",
              moneyEarned = 200,
              eggsLaid = {},
            },
          },
        }
        local byRarity = OfflineEarnings.getEarningsByRarity(earnings)
        expect(byRarity.Common.money).to.equal(100)
        expect(byRarity.Rare.money).to.equal(200)
      end)

      it("should sum eggs by egg rarity", function()
        local earnings = {
          cappedMoney = 0,
          eggsEarned = {
            {
              eggType = "BasicEgg",
              rarity = "Common",
              chickenId = "c1",
              chickenType = "BasicChick",
            },
            {
              eggType = "BasicEgg",
              rarity = "Common",
              chickenId = "c1",
              chickenType = "BasicChick",
            },
            { eggType = "RareEgg", rarity = "Rare", chickenId = "c2", chickenType = "RareChick" },
          },
          totalMoney = 0,
          totalEggs = 3,
          cappedEggs = 3,
          elapsedSeconds = 3600,
          cappedSeconds = 3600,
          wasCapped = false,
          moneyPerChicken = {},
        }
        local byRarity = OfflineEarnings.getEarningsByRarity(earnings)
        expect(byRarity.Common.eggs).to.equal(2)
        expect(byRarity.Rare.eggs).to.equal(1)
      end)
    end)

    describe("validateResult", function()
      it("should return true for valid result", function()
        local result = {
          cappedMoney = 100,
          cappedSeconds = 3600,
          cappedEggs = 5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 7200,
          cappedSeconds = 3600,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(true)
      end)

      it("should return false for negative cappedMoney", function()
        local result = {
          cappedMoney = -100,
          cappedSeconds = 3600,
          cappedEggs = 5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 7200,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(false)
      end)

      it("should return false for negative cappedSeconds", function()
        local result = {
          cappedMoney = 100,
          cappedSeconds = -3600,
          cappedEggs = 5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 7200,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(false)
      end)

      it("should return false for negative cappedEggs", function()
        local result = {
          cappedMoney = 100,
          cappedSeconds = 3600,
          cappedEggs = -5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 7200,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(false)
      end)

      it("should return false if cappedSeconds > elapsedSeconds", function()
        local result = {
          cappedMoney = 100,
          cappedSeconds = 10000,
          cappedEggs = 5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 3600,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(false)
      end)

      it("should return false if cappedMoney > totalMoney", function()
        local result = {
          cappedMoney = 500,
          cappedSeconds = 3600,
          cappedEggs = 5,
          totalMoney = 200,
          totalEggs = 10,
          elapsedSeconds = 7200,
          wasCapped = true,
          moneyPerChicken = {},
          eggsEarned = {},
        }
        expect(OfflineEarnings.validateResult(result)).to.equal(false)
      end)
    end)

    describe("getMaxPotential", function()
      it("should return zero for no placed chickens", function()
        local playerData = createMockPlayerData()
        local potential = OfflineEarnings.getMaxPotential(playerData)
        expect(potential.maxMoneyPerHour).to.equal(0)
        expect(potential.maxEggsPerHour).to.equal(0)
      end)

      it("should calculate max potential for placed chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick"),
          createMockChicken("c2", "BasicChick"),
        }
        local potential = OfflineEarnings.getMaxPotential(playerData)
        expect(potential.maxMoneyPerHour >= 0).to.equal(true)
        expect(potential.maxEggsPerHour >= 0).to.equal(true)
      end)
    end)
  end)
end
