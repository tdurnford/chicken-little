--[[
	MoneyCollection.spec.lua
	TestEZ tests for MoneyCollection module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
  local ChickenHealth = require(Shared:WaitForChild("ChickenHealth"))

  -- Helper to create mock player data
  local function createMockPlayerData(options)
    options = options or {}
    return {
      money = options.money or 100,
      placedChickens = options.placedChickens or {},
    }
  end

  -- Helper to create mock chicken data
  local function createMockChicken(options)
    options = options or {}
    return {
      id = options.id or "chicken-1",
      chickenType = options.chickenType or "BasicChick",
      accumulatedMoney = options.accumulatedMoney or 0,
      lastEggTime = options.lastEggTime or os.time(),
    }
  end

  describe("MoneyCollection", function()
    describe("collect", function()
      it("should collect whole dollars from a chicken", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 5.75 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken },
        })

        local result = MoneyCollection.collect(playerData, "chicken-1")

        expect(result.success).to.equal(true)
        expect(result.amountCollected).to.equal(5)
        expect(result.newBalance).to.equal(105)
        expect(result.remainder).to.be.near(0.75, 0.001)
        expect(chicken.accumulatedMoney).to.be.near(0.75, 0.001)
      end)

      it("should return failure for non-existent chicken", function()
        local playerData = createMockPlayerData({ money = 100 })

        local result = MoneyCollection.collect(playerData, "non-existent")

        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Chicken not found in placed chickens")
        expect(result.amountCollected).to.equal(0)
        expect(result.newBalance).to.equal(100)
      end)

      it("should not collect when less than $1 accumulated", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 0.5 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken },
        })

        local result = MoneyCollection.collect(playerData, "chicken-1")

        expect(result.success).to.equal(true)
        expect(result.amountCollected).to.equal(0)
        expect(result.newBalance).to.equal(100)
        expect(chicken.accumulatedMoney).to.equal(0.5)
      end)

      it("should collect exactly $1 when accumulated", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 1.0 })
        local playerData = createMockPlayerData({
          money = 50,
          placedChickens = { chicken },
        })

        local result = MoneyCollection.collect(playerData, "chicken-1")

        expect(result.success).to.equal(true)
        expect(result.amountCollected).to.equal(1)
        expect(result.newBalance).to.equal(51)
      end)

      it("should return chickenId in result", function()
        local chicken = createMockChicken({ id = "my-chicken-id", accumulatedMoney = 10 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local result = MoneyCollection.collect(playerData, "my-chicken-id")

        expect(result.chickenId).to.equal("my-chicken-id")
      end)
    end)

    describe("collectAll", function()
      it("should collect from all chickens with money", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5.5 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 3.2 })
        local chicken3 = createMockChicken({ id = "chicken-3", accumulatedMoney = 7.9 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken1, chicken2, chicken3 },
        })

        local result = MoneyCollection.collectAll(playerData)

        expect(result.success).to.equal(true)
        expect(result.totalCollected).to.equal(15) -- 5 + 3 + 7
        expect(result.chickensCollected).to.equal(3)
        expect(result.newBalance).to.equal(115)
        expect(#result.results).to.equal(3)
      end)

      it("should handle empty placed chickens", function()
        local playerData = createMockPlayerData({ money = 100, placedChickens = {} })

        local result = MoneyCollection.collectAll(playerData)

        expect(result.success).to.equal(true)
        expect(result.totalCollected).to.equal(0)
        expect(result.chickensCollected).to.equal(0)
        expect(result.message).to.equal("No placed chickens to collect from")
      end)

      it("should not count chickens with less than $1", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 0.3 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken1, chicken2 },
        })

        local result = MoneyCollection.collectAll(playerData)

        expect(result.totalCollected).to.equal(5)
        expect(result.chickensCollected).to.equal(1)
      end)

      it("should return message for no money to collect", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 0.1 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 0.2 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken1, chicken2 },
        })

        local result = MoneyCollection.collectAll(playerData)

        expect(result.message).to.equal("No money to collect from any chickens")
      end)

      it("should use singular 'chicken' for one chicken collected", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local playerData = createMockPlayerData({
          money = 100,
          placedChickens = { chicken1 },
        })

        local result = MoneyCollection.collectAll(playerData)

        expect(result.message).to.equal("Collected $5 from 1 chicken")
      end)
    end)

    describe("updateChickenMoney", function()
      it("should return accumulated money for valid chicken", function()
        local chicken = createMockChicken({
          chickenType = "BasicChick",
          accumulatedMoney = 10,
        })

        local result = MoneyCollection.updateChickenMoney(chicken)

        expect(result).to.equal(10)
      end)

      it("should return 0 for invalid chicken type", function()
        local chicken = createMockChicken({
          chickenType = "InvalidType",
          accumulatedMoney = 10,
        })

        local result = MoneyCollection.updateChickenMoney(chicken)

        expect(result).to.equal(0)
      end)
    end)

    describe("updateAllChickenMoney", function()
      it("should generate money for all chickens based on elapsed time", function()
        local chicken1 = createMockChicken({
          id = "chicken-1",
          chickenType = "BasicChick",
          accumulatedMoney = 0,
        })
        local playerData = createMockPlayerData({ placedChickens = { chicken1 } })

        local generated = MoneyCollection.updateAllChickenMoney(playerData, 10)

        -- BasicChick generates 1 money per second
        expect(generated).to.equal(10)
        expect(chicken1.accumulatedMoney).to.equal(10)
      end)

      it("should accumulate money for multiple chickens", function()
        local chicken1 = createMockChicken({
          id = "chicken-1",
          chickenType = "BasicChick",
          accumulatedMoney = 5,
        })
        local chicken2 = createMockChicken({
          id = "chicken-2",
          chickenType = "BasicChick",
          accumulatedMoney = 3,
        })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local generated = MoneyCollection.updateAllChickenMoney(playerData, 5)

        expect(generated).to.equal(10) -- 5 seconds × 2 chickens × 1/sec
        expect(chicken1.accumulatedMoney).to.equal(10) -- 5 + 5
        expect(chicken2.accumulatedMoney).to.equal(8) -- 3 + 5
      end)

      it("should return 0 for empty chickens", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local generated = MoneyCollection.updateAllChickenMoney(playerData, 10)

        expect(generated).to.equal(0)
      end)

      it("should apply health multiplier from registry", function()
        local chicken = createMockChicken({
          id = "chicken-1",
          chickenType = "BasicChick",
          accumulatedMoney = 0,
        })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        -- Create health registry with damaged chicken (50% health)
        local healthRegistry = ChickenHealth.createRegistry()
        ChickenHealth.register(healthRegistry, "chicken-1", 100)
        ChickenHealth.takeDamage(healthRegistry, "chicken-1", 50) -- Now at 50%

        local generated = MoneyCollection.updateAllChickenMoney(playerData, 10, healthRegistry)

        -- Should generate 50% of normal (10 × 0.5 = 5)
        expect(generated).to.be.near(5, 0.001)
      end)

      it("should generate no money for dead chickens", function()
        local chicken = createMockChicken({
          id = "chicken-1",
          chickenType = "BasicChick",
          accumulatedMoney = 0,
        })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local healthRegistry = ChickenHealth.createRegistry()
        ChickenHealth.register(healthRegistry, "chicken-1", 100)
        ChickenHealth.takeDamage(healthRegistry, "chicken-1", 100) -- Dead

        local generated = MoneyCollection.updateAllChickenMoney(playerData, 10, healthRegistry)

        expect(generated).to.equal(0)
      end)
    end)

    describe("getIncomeMultiplier", function()
      it("should return 1.0 when no health registry provided", function()
        local multiplier = MoneyCollection.getIncomeMultiplier(nil, "chicken-1")

        expect(multiplier).to.equal(1.0)
      end)

      it("should return 1.0 for chicken not in registry", function()
        local healthRegistry = ChickenHealth.createRegistry()

        local multiplier = MoneyCollection.getIncomeMultiplier(healthRegistry, "non-existent")

        expect(multiplier).to.equal(1.0)
      end)

      it("should return health percent for damaged chicken", function()
        local healthRegistry = ChickenHealth.createRegistry()
        ChickenHealth.register(healthRegistry, "chicken-1", 100)
        ChickenHealth.takeDamage(healthRegistry, "chicken-1", 25) -- 75% health

        local multiplier = MoneyCollection.getIncomeMultiplier(healthRegistry, "chicken-1")

        expect(multiplier).to.be.near(0.75, 0.001)
      end)

      it("should return 0 for dead chicken", function()
        local healthRegistry = ChickenHealth.createRegistry()
        ChickenHealth.register(healthRegistry, "chicken-1", 100)
        ChickenHealth.takeDamage(healthRegistry, "chicken-1", 100)

        local multiplier = MoneyCollection.getIncomeMultiplier(healthRegistry, "chicken-1")

        expect(multiplier).to.equal(0)
      end)
    end)

    describe("getTotalAccumulated", function()
      it("should sum accumulated money from all chickens", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5.5 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 3.3 })
        local chicken3 = createMockChicken({ id = "chicken-3", accumulatedMoney = 1.2 })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2, chicken3 },
        })

        local total = MoneyCollection.getTotalAccumulated(playerData)

        expect(total).to.equal(10)
      end)

      it("should return 0 for no placed chickens", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local total = MoneyCollection.getTotalAccumulated(playerData)

        expect(total).to.equal(0)
      end)

      it("should handle chickens with nil accumulatedMoney", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local chicken2 = { id = "chicken-2", chickenType = "BasicChick" } -- no accumulatedMoney
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local total = MoneyCollection.getTotalAccumulated(playerData)

        expect(total).to.equal(5)
      end)
    end)

    describe("getAccumulated", function()
      it("should return accumulated money for specific chicken", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 7.5 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local accumulated = MoneyCollection.getAccumulated(playerData, "chicken-1")

        expect(accumulated).to.equal(7.5)
      end)

      it("should return nil for non-existent chicken", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local accumulated = MoneyCollection.getAccumulated(playerData, "non-existent")

        expect(accumulated).to.equal(nil)
      end)

      it("should find correct chicken among multiple", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 10 })
        local chicken3 = createMockChicken({ id = "chicken-3", accumulatedMoney = 15 })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2, chicken3 },
        })

        expect(MoneyCollection.getAccumulated(playerData, "chicken-1")).to.equal(5)
        expect(MoneyCollection.getAccumulated(playerData, "chicken-2")).to.equal(10)
        expect(MoneyCollection.getAccumulated(playerData, "chicken-3")).to.equal(15)
      end)
    end)

    describe("getChickensWithMoney", function()
      it("should count chickens with money above threshold", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 0.5 })
        local chicken3 = createMockChicken({ id = "chicken-3", accumulatedMoney = 10 })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2, chicken3 },
        })

        local count = MoneyCollection.getChickensWithMoney(playerData, 1)

        expect(count).to.equal(2) -- chicken1 and chicken3 have > $1
      end)

      it("should use 0 as default threshold", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 0.1 })
        local chicken2 = createMockChicken({ id = "chicken-2", accumulatedMoney = 0 })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local count = MoneyCollection.getChickensWithMoney(playerData)

        expect(count).to.equal(1) -- Only chicken1 has > 0
      end)

      it("should return 0 for empty chickens", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local count = MoneyCollection.getChickensWithMoney(playerData)

        expect(count).to.equal(0)
      end)

      it("should handle nil accumulatedMoney", function()
        local chicken1 = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local chicken2 = { id = "chicken-2", chickenType = "BasicChick" }
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local count = MoneyCollection.getChickensWithMoney(playerData, 1)

        expect(count).to.equal(1)
      end)
    end)

    describe("hasMoney", function()
      it("should return true when chicken has money above threshold", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local result = MoneyCollection.hasMoney(playerData, "chicken-1", 1)

        expect(result).to.equal(true)
      end)

      it("should return false when chicken has money below threshold", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 0.5 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local result = MoneyCollection.hasMoney(playerData, "chicken-1", 1)

        expect(result).to.equal(false)
      end)

      it("should return false for non-existent chicken", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local result = MoneyCollection.hasMoney(playerData, "non-existent", 0)

        expect(result).to.equal(false)
      end)

      it("should use 0 as default threshold", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 0.01 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local result = MoneyCollection.hasMoney(playerData, "chicken-1")

        expect(result).to.equal(true)
      end)

      it("should return false when exactly at threshold", function()
        local chicken = createMockChicken({ id = "chicken-1", accumulatedMoney = 5 })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        -- Threshold is exclusive (> not >=)
        local result = MoneyCollection.hasMoney(playerData, "chicken-1", 5)

        expect(result).to.equal(false)
      end)
    end)

    describe("getTotalMoneyPerSecond", function()
      it("should sum money per second from all chickens", function()
        local chicken1 = createMockChicken({ id = "chicken-1", chickenType = "BasicChick" })
        local chicken2 = createMockChicken({ id = "chicken-2", chickenType = "BasicChick" })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local total = MoneyCollection.getTotalMoneyPerSecond(playerData)

        -- BasicChick generates 1 money per second
        expect(total).to.equal(2)
      end)

      it("should return 0 for no placed chickens", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local total = MoneyCollection.getTotalMoneyPerSecond(playerData)

        expect(total).to.equal(0)
      end)

      it("should ignore chickens with invalid types", function()
        local chicken1 = createMockChicken({ id = "chicken-1", chickenType = "BasicChick" })
        local chicken2 = createMockChicken({ id = "chicken-2", chickenType = "InvalidType" })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local total = MoneyCollection.getTotalMoneyPerSecond(playerData)

        expect(total).to.equal(1) -- Only BasicChick counted
      end)
    end)

    describe("estimateEarnings", function()
      it("should calculate earnings for time period", function()
        local chicken1 = createMockChicken({ id = "chicken-1", chickenType = "BasicChick" })
        local chicken2 = createMockChicken({ id = "chicken-2", chickenType = "BasicChick" })
        local playerData = createMockPlayerData({
          placedChickens = { chicken1, chicken2 },
        })

        local earnings = MoneyCollection.estimateEarnings(playerData, 60)

        -- 2 chickens × 1/sec × 60 seconds = 120
        expect(earnings).to.equal(120)
      end)

      it("should return 0 for no chickens", function()
        local playerData = createMockPlayerData({ placedChickens = {} })

        local earnings = MoneyCollection.estimateEarnings(playerData, 100)

        expect(earnings).to.equal(0)
      end)

      it("should return 0 for 0 seconds", function()
        local chicken = createMockChicken({ id = "chicken-1", chickenType = "BasicChick" })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local earnings = MoneyCollection.estimateEarnings(playerData, 0)

        expect(earnings).to.equal(0)
      end)

      it("should scale linearly with time", function()
        local chicken = createMockChicken({ id = "chicken-1", chickenType = "BasicChick" })
        local playerData = createMockPlayerData({ placedChickens = { chicken } })

        local earnings10 = MoneyCollection.estimateEarnings(playerData, 10)
        local earnings20 = MoneyCollection.estimateEarnings(playerData, 20)

        expect(earnings20).to.equal(earnings10 * 2)
      end)
    end)
  end)
end
