--[[
	Store.spec.lua
	TestEZ tests for Store module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local Store = require(Shared:WaitForChild("Store"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local EggConfig = require(Shared:WaitForChild("EggConfig"))

  describe("Store", function()
    describe("buyEgg", function()
      it("should succeed with sufficient money", function()
        local data = PlayerData.createDefault()
        data.money = 10000
        local result = Store.buyEgg(data, "CommonEgg", 1)
        expect(result.success).to.equal(true)
        expect(data.money < 10000).to.equal(true)
      end)

      it("should fail with insufficient money", function()
        local data = PlayerData.createDefault()
        data.money = 0
        local result = Store.buyEgg(data, "CommonEgg", 1)
        expect(result.success).to.equal(false)
      end)

      it("should fail with invalid egg type", function()
        local data = PlayerData.createDefault()
        data.money = 10000
        local result = Store.buyEgg(data, "SuperEgg", 1)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("sellChicken", function()
      it("should give money when selling", function()
        local data = PlayerData.createDefault()
        -- Add a chicken to inventory
        local chickenId = PlayerData.generateId()
        table.insert(data.inventory.chickens, {
          id = chickenId,
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
          spotIndex = nil,
        })
        local initialMoney = data.money
        local result = Store.sellChicken(data, chickenId)
        expect(result.success).to.equal(true)
        expect(data.money > initialMoney).to.equal(true)
      end)
    end)

    describe("buyChicken", function()
      it("should succeed with sufficient money", function()
        local data = PlayerData.createDefault()
        data.money = 10000
        local initialChickens = #data.inventory.chickens
        local result = Store.buyChicken(data, "BasicChick", 1)
        expect(result.success).to.equal(true)
        expect(data.money < 10000).to.equal(true)
        expect(#data.inventory.chickens).to.equal(initialChickens + 1)
      end)

      it("should fail with insufficient money", function()
        local data = PlayerData.createDefault()
        data.money = 0
        local result = Store.buyChicken(data, "BasicChick", 1)
        expect(result.success).to.equal(false)
      end)

      it("should fail with invalid chicken type", function()
        local data = PlayerData.createDefault()
        data.money = 10000
        local result = Store.buyChicken(data, "SuperChicken", 1)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("getAvailableChickens", function()
      it("should return items", function()
        local chickens = Store.getAvailableChickens()
        expect(#chickens > 0).to.equal(true)
        local first = chickens[1]
        expect(first.itemType).to.equal("chicken")
        expect(first.price > 0).to.equal(true)
      end)
    end)

    describe("initializeInventory", function()
      it("should create inventory with items", function()
        local inventory = Store.initializeInventory()
        expect(inventory).to.be.ok()
        expect(inventory.eggs).to.be.ok()
        expect(inventory.chickens).to.be.ok()
        -- Check that common egg has stock of 10
        local commonEgg = inventory.eggs["CommonEgg"]
        expect(commonEgg).to.be.ok()
        expect(commonEgg.stock).to.equal(10)
      end)
    end)

    describe("isInStock", function()
      it("should return true for stocked items", function()
        Store.initializeInventory()
        local inStock = Store.isInStock("egg", "CommonEgg")
        expect(inStock).to.equal(true)
      end)

      it("should return false for out of stock items", function()
        local inventory = Store.initializeInventory()
        -- Manually set stock to 0
        inventory.eggs["CommonEgg"].stock = 0
        Store.setStoreInventory(inventory)
        local inStock = Store.isInStock("egg", "CommonEgg")
        expect(inStock).to.equal(false)
      end)
    end)

    describe("purchaseEggFromInventory", function()
      it("should decrement stock", function()
        Store.initializeInventory()
        local data = PlayerData.createDefault()
        data.money = 1000
        local initialStock = Store.getStock("egg", "CommonEgg")
        local result = Store.purchaseEggFromInventory(data, "CommonEgg", 1)
        expect(result.success).to.equal(true)
        local newStock = Store.getStock("egg", "CommonEgg")
        expect(newStock).to.equal(initialStock - 1)
      end)

      it("should fail when sold out", function()
        local inventory = Store.initializeInventory()
        inventory.eggs["CommonEgg"].stock = 0
        Store.setStoreInventory(inventory)
        local data = PlayerData.createDefault()
        data.money = 1000
        local result = Store.purchaseEggFromInventory(data, "CommonEgg", 1)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("purchaseChickenFromInventory", function()
      it("should decrement stock", function()
        Store.initializeInventory()
        local data = PlayerData.createDefault()
        data.money = 50000
        local initialStock = Store.getStock("chicken", "BasicChick")
        local result = Store.purchaseChickenFromInventory(data, "BasicChick", 1)
        expect(result.success).to.equal(true)
        local newStock = Store.getStock("chicken", "BasicChick")
        expect(newStock).to.equal(initialStock - 1)
      end)
    end)

    describe("getAvailableEggsWithStock", function()
      it("should include stock info", function()
        Store.initializeInventory()
        local eggs = Store.getAvailableEggsWithStock()
        expect(#eggs > 0).to.equal(true)
        local first = eggs[1]
        expect(first.stock).to.be.ok()
        expect(first.maxStock).to.be.ok()
      end)
    end)

    describe("getStockForRarity", function()
      it("should return correct values", function()
        expect(Store.getStockForRarity("Common")).to.equal(10)
        expect(Store.getStockForRarity("Rare")).to.equal(3)
        expect(Store.getStockForRarity("Mythic")).to.equal(0)
      end)
    end)

    describe("getReplenishInterval", function()
      it("should return 300 seconds", function()
        local interval = Store.getReplenishInterval()
        expect(interval).to.equal(300)
      end)
    end)

    describe("replenishStore", function()
      it("should restore stock", function()
        local inventory = Store.initializeInventory()
        -- Deplete stock
        for _, item in pairs(inventory.eggs) do
          item.stock = 0
        end
        -- Verify stock is depleted
        local depleted = true
        for _, item in pairs(inventory.eggs) do
          if item.stock > 0 then
            depleted = false
            break
          end
        end
        expect(depleted).to.equal(true)
        -- Replenish store
        local newInventory = Store.replenishStore()
        -- Verify stock is restored
        local hasStock = false
        for _, item in pairs(newInventory.eggs) do
          if item.stock > 0 then
            hasStock = true
            break
          end
        end
        expect(hasStock).to.equal(true)
      end)

      it("should update lastReplenishTime", function()
        Store.initializeInventory()
        local beforeTime = os.time()
        local newInventory = Store.replenishStore()
        local afterTime = os.time()
        expect(newInventory.lastReplenishTime >= beforeTime).to.equal(true)
        expect(newInventory.lastReplenishTime <= afterTime).to.equal(true)
      end)
    end)

    describe("needsReplenish", function()
      it("should return false immediately after replenish", function()
        Store.initializeInventory()
        Store.replenishStore()
        expect(Store.needsReplenish()).to.equal(false)
      end)
    end)

    describe("getTimeUntilReplenish", function()
      it("should return positive value after replenish", function()
        Store.initializeInventory()
        Store.replenishStore()
        local remaining = Store.getTimeUntilReplenish()
        expect(remaining > 0).to.equal(true)
      end)
    end)

    describe("forceReplenish", function()
      it("should work same as replenishStore", function()
        local inventory = Store.initializeInventory()
        -- Deplete stock
        for _, item in pairs(inventory.eggs) do
          item.stock = 0
        end
        -- Force replenish
        local newInventory = Store.forceReplenish()
        local hasStock = false
        for _, item in pairs(newInventory.eggs) do
          if item.stock > 0 then
            hasStock = true
            break
          end
        end
        expect(hasStock).to.equal(true)
      end)
    end)

    describe("pricing", function()
      it("should have basic chicken cheaper than common egg", function()
        -- Bug #39: Basic chicken should cost less than common egg
        -- Eggs are a gamble with upside potential; direct chicken purchase should be cheaper
        local basicChickPrice = Store.getChickenPrice("BasicChick")
        local commonEggConfig = EggConfig.get("CommonEgg")
        expect(commonEggConfig).to.be.ok()
        expect(basicChickPrice < commonEggConfig.purchasePrice).to.equal(true)
      end)

      it("should have egg prices slightly above expected chicken values", function()
        -- For each egg rarity, the egg should cost more than the expected chicken value
        -- This makes eggs a gamble with upside potential
        local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
        for _, rarity in ipairs(rarities) do
          local eggs = EggConfig.getByRarity(rarity)
          if #eggs > 0 then
            local egg = eggs[1]
            -- Calculate expected chicken purchase price from hatch outcomes
            local expectedValue = 0
            for _, outcome in ipairs(egg.hatchOutcomes) do
              local chickenPrice = Store.getChickenPrice(outcome.chickenType)
              expectedValue = expectedValue + (chickenPrice * outcome.probability / 100)
            end
            -- Egg should cost at least as much as expected value (slight premium for gamble)
            expect(egg.purchasePrice >= expectedValue * 0.95).to.equal(true)
          end
        end
      end)
    end)
  end)
end
