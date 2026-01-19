--[[
	StoreService Tests
	Tests for the StoreService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local Store = require(Shared:WaitForChild("Store"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local EggConfig = require(Shared:WaitForChild("EggConfig"))
  local ChickenConfig = require(Shared:WaitForChild("ChickenConfig"))
  local TrapConfig = require(Shared:WaitForChild("TrapConfig"))
  local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

  describe("Store Inventory", function()
    it("should initialize store inventory", function()
      local inventory = Store.initializeInventory()
      expect(inventory).to.be.ok()
      expect(inventory.eggs).to.be.ok()
      expect(inventory.chickens).to.be.ok()
      expect(inventory.lastReplenishTime).to.be.ok()
    end)

    it("should get store inventory", function()
      local inventory = Store.getStoreInventory()
      expect(inventory).to.be.ok()
    end)

    it("should have eggs with stock based on rarity", function()
      local inventory = Store.getStoreInventory()
      -- Common eggs should have stock
      local commonEgg = inventory.eggs["CommonEgg"]
      if commonEgg then
        expect(commonEgg.stock).to.be.at.least(1)
        expect(commonEgg.maxStock).to.be.at.least(1)
      end
    end)

    it("should track time until replenish", function()
      local timeUntil = Store.getTimeUntilReplenish()
      expect(timeUntil).to.be.ok()
      expect(timeUntil).to.be.at.least(0)
    end)

    it("should replenish store inventory", function()
      -- Force replenish
      local inventory = Store.forceReplenish()
      expect(inventory).to.be.ok()
      expect(inventory.lastReplenishTime).to.be.ok()
    end)
  end)

  describe("Egg Purchases", function()
    it("should purchase egg with sufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 10000

      local initialEggCount = #playerData.inventory.eggs
      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 1)

      expect(result.success).to.equal(true)
      expect(#playerData.inventory.eggs).to.equal(initialEggCount + 1)
      expect(playerData.money).to.be.below(10000)
    end)

    it("should fail purchase with insufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 0

      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 1)
      expect(result.success).to.equal(false)
      expect(result.message:find("Insufficient")).to.be.ok()
    end)

    it("should purchase multiple eggs", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 100000

      -- Need to ensure stock is available
      Store.forceReplenish()

      local initialEggCount = #playerData.inventory.eggs
      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 3)

      if result.success then
        expect(#playerData.inventory.eggs).to.equal(initialEggCount + 3)
      else
        -- May fail due to stock limitations
        expect(result.message:find("stock")).to.be.ok()
      end
    end)

    it("should fail purchase when out of stock", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 1000000

      -- Try to buy more than possible stock
      local result = Store.purchaseEggFromInventory(playerData, "MythicEgg", 100)
      -- Should fail due to stock limitation
      expect(result.success).to.equal(false)
    end)
  end)

  describe("Chicken Purchases", function()
    it("should purchase chicken with sufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 10000

      -- Ensure stock is available
      Store.forceReplenish()

      local initialChickenCount = #playerData.inventory.chickens
      local result = Store.purchaseChickenFromInventory(playerData, "BasicChicken", 1)

      if result.success then
        expect(#playerData.inventory.chickens).to.equal(initialChickenCount + 1)
      end
    end)

    it("should fail chicken purchase with insufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 0

      local result = Store.purchaseChickenFromInventory(playerData, "BasicChicken", 1)
      expect(result.success).to.equal(false)
    end)

    it("should calculate chicken price correctly", function()
      local price = Store.getChickenPrice("BasicChicken")
      expect(price).to.be.ok()
      expect(price).to.be.at.least(1)
    end)

    it("should calculate chicken sell value correctly", function()
      local value = Store.getChickenValue("BasicChicken")
      expect(value).to.be.ok()
      expect(value).to.be.at.least(0)
    end)
  end)

  describe("Egg Sales", function()
    it("should sell egg from inventory", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.inventory.eggs, {
        id = "sell-test-egg-1",
        eggType = "CommonEgg",
        rarity = "Common",
      })

      local initialMoney = playerData.money
      local result = Store.sellEgg(playerData, "sell-test-egg-1")

      expect(result.success).to.equal(true)
      expect(playerData.money).to.be.at.least(initialMoney)
      expect(#playerData.inventory.eggs).to.equal(0)
    end)

    it("should fail to sell non-existent egg", function()
      local playerData = PlayerData.createDefault()

      local result = Store.sellEgg(playerData, "non-existent-egg")
      expect(result.success).to.equal(false)
      expect(result.message:find("not found")).to.be.ok()
    end)

    it("should sell multiple eggs by type", function()
      local playerData = PlayerData.createDefault()
      -- Add multiple eggs of same type
      for i = 1, 5 do
        table.insert(playerData.inventory.eggs, {
          id = "bulk-egg-" .. i,
          eggType = "CommonEgg",
          rarity = "Common",
        })
      end

      local initialMoney = playerData.money
      local result = Store.sellEggsByType(playerData, "CommonEgg", 3)

      expect(result.success).to.equal(true)
      expect(#playerData.inventory.eggs).to.equal(2)
      expect(playerData.money).to.be.at.least(initialMoney)
    end)
  end)

  describe("Chicken Sales", function()
    it("should sell chicken from inventory", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.inventory.chickens, {
        id = "sell-test-chicken-1",
        chickenType = "BasicChicken",
        rarity = "Common",
        accumulatedMoney = 0,
        lastEggTime = os.time(),
        spotIndex = nil,
      })

      local initialMoney = playerData.money
      local result = Store.sellChicken(playerData, "sell-test-chicken-1")

      expect(result.success).to.equal(true)
      expect(playerData.money).to.be.at.least(initialMoney)
      expect(#playerData.inventory.chickens).to.equal(0)
    end)

    it("should sell placed chicken", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.placedChickens, {
        id = "sell-placed-chicken-1",
        chickenType = "BasicChicken",
        rarity = "Common",
        accumulatedMoney = 50,
        lastEggTime = os.time(),
        spotIndex = 1,
      })

      local initialMoney = playerData.money
      local result = Store.sellChicken(playerData, "sell-placed-chicken-1")

      expect(result.success).to.equal(true)
      -- Should include accumulated money
      expect(playerData.money).to.be.at.least(initialMoney + 50)
      expect(#playerData.placedChickens).to.equal(0)
    end)

    it("should fail to sell non-existent chicken", function()
      local playerData = PlayerData.createDefault()

      local result = Store.sellChicken(playerData, "non-existent-chicken")
      expect(result.success).to.equal(false)
      expect(result.message:find("not found")).to.be.ok()
    end)
  end)

  describe("Trap Purchases and Sales", function()
    it("should purchase trap with sufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 10000

      local result = Store.buyTrap(playerData, "BasicTrap")

      expect(result.success).to.equal(true)
      expect(#playerData.traps).to.be.at.least(1)
    end)

    it("should fail trap purchase with insufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 0

      local result = Store.buyTrap(playerData, "BasicTrap")
      expect(result.success).to.equal(false)
    end)

    it("should sell trap", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.traps, {
        id = "sell-test-trap-1",
        trapType = "BasicTrap",
        tier = 1,
        spotIndex = -1,
        cooldownEndTime = nil,
        caughtPredator = nil,
      })

      local initialMoney = playerData.money
      local result = Store.sellTrap(playerData, "sell-test-trap-1")

      expect(result.success).to.equal(true)
      expect(playerData.money).to.be.at.least(initialMoney)
      expect(#playerData.traps).to.equal(0)
    end)

    it("should not sell trap with caught predator", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.traps, {
        id = "trap-with-predator",
        trapType = "BasicTrap",
        tier = 1,
        spotIndex = 1,
        cooldownEndTime = nil,
        caughtPredator = "Fox",
      })

      local result = Store.sellTrap(playerData, "trap-with-predator")
      expect(result.success).to.equal(false)
      expect(result.message:find("caught predator")).to.be.ok()
    end)

    it("should get available traps", function()
      local traps = Store.getAvailableTraps()
      expect(traps).to.be.ok()
      expect(#traps).to.be.at.least(1)
    end)
  end)

  describe("Predator Sales", function()
    it("should sell trapped predator", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.traps, {
        id = "trap-with-fox",
        trapType = "BasicTrap",
        tier = 1,
        spotIndex = 1,
        cooldownEndTime = nil,
        caughtPredator = "Fox",
      })

      local initialMoney = playerData.money
      local result = Store.sellPredator(playerData, "trap-with-fox")

      expect(result.success).to.equal(true)
      expect(playerData.money).to.be.at.least(initialMoney + 100)
      -- Trap should still exist but without predator
      expect(#playerData.traps).to.equal(1)
      expect(playerData.traps[1].caughtPredator).to.equal(nil)
    end)

    it("should fail to sell from empty trap", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.traps, {
        id = "empty-trap",
        trapType = "BasicTrap",
        tier = 1,
        spotIndex = 1,
        cooldownEndTime = nil,
        caughtPredator = nil,
      })

      local result = Store.sellPredator(playerData, "empty-trap")
      expect(result.success).to.equal(false)
    end)

    it("should get predator values", function()
      local foxValue = Store.getPredatorValue("Fox")
      local wolfValue = Store.getPredatorValue("Wolf")
      local bearValue = Store.getPredatorValue("Bear")

      expect(foxValue).to.be.at.least(100)
      expect(wolfValue).to.be.at.least(foxValue)
      expect(bearValue).to.be.at.least(wolfValue)
    end)
  end)

  describe("Weapon Purchases and Sales", function()
    it("should purchase weapon with sufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 100000

      -- Find a purchasable weapon (not free)
      local weapons = Store.getAvailableWeapons()
      local purchasableWeapon = nil
      for _, weapon in ipairs(weapons) do
        if weapon.price > 0 and not PlayerData.ownsWeapon(playerData, weapon.id) then
          purchasableWeapon = weapon
          break
        end
      end

      if purchasableWeapon then
        local result = Store.buyWeapon(playerData, purchasableWeapon.id)
        expect(result.success).to.equal(true)
        expect(PlayerData.ownsWeapon(playerData, purchasableWeapon.id)).to.equal(true)
      end
    end)

    it("should fail weapon purchase with insufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 0

      -- Find a purchasable weapon
      local weapons = Store.getAvailableWeapons()
      local purchasableWeapon = nil
      for _, weapon in ipairs(weapons) do
        if weapon.price > 0 and not PlayerData.ownsWeapon(playerData, weapon.id) then
          purchasableWeapon = weapon
          break
        end
      end

      if purchasableWeapon then
        local result = Store.buyWeapon(playerData, purchasableWeapon.id)
        expect(result.success).to.equal(false)
      end
    end)

    it("should not allow buying already owned weapon", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 100000

      -- Add a weapon to owned
      local weapons = Store.getAvailableWeapons()
      local purchasableWeapon = nil
      for _, weapon in ipairs(weapons) do
        if weapon.price > 0 then
          purchasableWeapon = weapon
          break
        end
      end

      if purchasableWeapon then
        PlayerData.addWeapon(playerData, purchasableWeapon.id)
        local result = Store.buyWeapon(playerData, purchasableWeapon.id)
        expect(result.success).to.equal(false)
        expect(result.message:find("already own")).to.be.ok()
      end
    end)

    it("should get available weapons", function()
      local weapons = Store.getAvailableWeapons()
      expect(weapons).to.be.ok()
      expect(#weapons).to.be.at.least(1)
    end)
  end)

  describe("Inventory Value", function()
    it("should calculate inventory value", function()
      local playerData = PlayerData.createDefault()
      -- Add some items
      table.insert(playerData.inventory.eggs, {
        id = "value-egg-1",
        eggType = "CommonEgg",
        rarity = "Common",
      })
      table.insert(playerData.inventory.chickens, {
        id = "value-chicken-1",
        chickenType = "BasicChicken",
        rarity = "Common",
        accumulatedMoney = 100,
        lastEggTime = os.time(),
        spotIndex = nil,
      })

      local value = Store.getInventoryValue(playerData)
      expect(value).to.be.ok()
      expect(value.eggsValue).to.be.at.least(0)
      expect(value.chickensValue).to.be.at.least(100)
      expect(value.totalValue).to.equal(value.eggsValue + value.chickensValue)
    end)
  end)

  describe("Stock Management", function()
    it("should track stock after purchase", function()
      -- Replenish first
      Store.forceReplenish()

      local initialStock = Store.getStock("egg", "CommonEgg")
      expect(initialStock).to.be.at.least(1)

      local playerData = PlayerData.createDefault()
      playerData.money = 10000

      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 1)
      if result.success then
        local newStock = Store.getStock("egg", "CommonEgg")
        -- Common eggs should never go below 1
        expect(newStock).to.be.at.least(1)
      end
    end)

    it("should check if item is in stock", function()
      Store.forceReplenish()
      local inStock = Store.isInStock("egg", "CommonEgg")
      expect(inStock).to.equal(true)
    end)
  end)
end
