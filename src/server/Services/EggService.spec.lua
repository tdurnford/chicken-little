--[[
	EggService Tests
	Tests for the EggService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local EggHatching = require(Shared:WaitForChild("EggHatching"))
  local EggConfig = require(Shared:WaitForChild("EggConfig"))
  local WorldEgg = require(Shared:WaitForChild("WorldEgg"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local Store = require(Shared:WaitForChild("Store"))

  describe("EggHatching", function()
    it("should validate hatch for valid egg", function()
      local playerData = PlayerData.createDefault()
      -- Add an egg to inventory
      table.insert(playerData.inventory.eggs, {
        id = "test-egg-1",
        eggType = "CommonEgg",
        rarity = "Common",
      })

      local canHatch, message = EggHatching.canHatch(playerData, "test-egg-1")
      expect(canHatch).to.equal(true)
    end)

    it("should fail validation for non-existent egg", function()
      local playerData = PlayerData.createDefault()

      local canHatch, message = EggHatching.canHatch(playerData, "non-existent-egg")
      expect(canHatch).to.equal(false)
      expect(message).to.equal("Egg not found in inventory")
    end)

    it("should hatch egg and produce chicken", function()
      local playerData = PlayerData.createDefault()
      -- Add an egg to inventory
      table.insert(playerData.inventory.eggs, {
        id = "test-egg-2",
        eggType = "CommonEgg",
        rarity = "Common",
      })

      local initialEggCount = #playerData.inventory.eggs
      local initialChickenCount = #playerData.inventory.chickens

      local result = EggHatching.hatch(playerData, "test-egg-2")

      expect(result.success).to.equal(true)
      expect(result.chickenType).to.be.ok()
      expect(result.chickenId).to.be.ok()
      expect(#playerData.inventory.eggs).to.equal(initialEggCount - 1)
      expect(#playerData.inventory.chickens).to.equal(initialChickenCount + 1)
    end)

    it("should return correct celebration tier for rarity", function()
      expect(EggHatching.getCelebrationTier("Common")).to.equal(0)
      expect(EggHatching.getCelebrationTier("Uncommon")).to.equal(1)
      expect(EggHatching.getCelebrationTier("Rare")).to.equal(2)
      expect(EggHatching.getCelebrationTier("Epic")).to.equal(3)
      expect(EggHatching.getCelebrationTier("Legendary")).to.equal(4)
      expect(EggHatching.getCelebrationTier("Mythic")).to.equal(5)
    end)

    it("should identify rare hatches correctly", function()
      expect(EggHatching.isRareHatch("Common")).to.equal(false)
      expect(EggHatching.isRareHatch("Uncommon")).to.equal(false)
      expect(EggHatching.isRareHatch("Rare")).to.equal(true)
      expect(EggHatching.isRareHatch("Epic")).to.equal(true)
      expect(EggHatching.isRareHatch("Legendary")).to.equal(true)
      expect(EggHatching.isRareHatch("Mythic")).to.equal(true)
    end)
  end)

  describe("EggConfig", function()
    it("should return valid egg config", function()
      local config = EggConfig.get("CommonEgg")
      expect(config).to.be.ok()
      expect(config.name).to.equal("CommonEgg")
      expect(config.rarity).to.equal("Common")
    end)

    it("should return nil for invalid egg type", function()
      local config = EggConfig.get("InvalidEggType")
      expect(config).to.equal(nil)
    end)

    it("should validate egg type existence", function()
      expect(EggConfig.isValidType("CommonEgg")).to.equal(true)
      expect(EggConfig.isValidType("RareEgg")).to.equal(true)
      expect(EggConfig.isValidType("FakeEgg")).to.equal(false)
    end)

    it("should return all egg types", function()
      local types = EggConfig.getAllTypes()
      expect(#types).to.be.at.least(6) -- At least 6 egg types
    end)

    it("should select valid hatch outcome", function()
      local outcome = EggConfig.selectHatchOutcome("CommonEgg")
      expect(outcome).to.be.ok()
      -- Verify it's one of the valid outcomes
      local config = EggConfig.get("CommonEgg")
      local validOutcomes = {}
      for _, o in ipairs(config.hatchOutcomes) do
        validOutcomes[o.chickenType] = true
      end
      expect(validOutcomes[outcome]).to.equal(true)
    end)

    it("should validate all egg probabilities sum to 100", function()
      local result = EggConfig.validateAll()
      expect(result.success).to.equal(true)
    end)
  end)

  describe("WorldEgg", function()
    it("should create registry", function()
      local registry = WorldEgg.createRegistry()
      expect(registry).to.be.ok()
      expect(registry.eggs).to.be.ok()
    end)

    it("should create world egg", function()
      local worldEgg = WorldEgg.create("CommonEgg", 12345, "chicken-1", 1, { x = 0, y = 5, z = 0 })
      expect(worldEgg).to.be.ok()
      expect(worldEgg.eggType).to.equal("CommonEgg")
      expect(worldEgg.ownerId).to.equal(12345)
      expect(worldEgg.chickenId).to.equal("chicken-1")
    end)

    it("should add and remove eggs from registry", function()
      local registry = WorldEgg.createRegistry()
      local worldEgg = WorldEgg.create("CommonEgg", 12345, "chicken-1", 1, { x = 0, y = 5, z = 0 })

      local added = WorldEgg.add(registry, worldEgg)
      expect(added).to.equal(true)
      expect(WorldEgg.getCount(registry)).to.equal(1)

      local removed = WorldEgg.remove(registry, worldEgg.id)
      expect(removed).to.be.ok()
      expect(WorldEgg.getCount(registry)).to.equal(0)
    end)

    it("should validate egg collection by owner only", function()
      local registry = WorldEgg.createRegistry()
      local worldEgg = WorldEgg.create("CommonEgg", 12345, "chicken-1", 1, { x = 0, y = 5, z = 0 })
      WorldEgg.add(registry, worldEgg)

      -- Owner can collect
      local canCollect, _ = WorldEgg.canCollect(registry, worldEgg.id, 12345)
      expect(canCollect).to.equal(true)

      -- Non-owner cannot collect
      local canCollect2, message = WorldEgg.canCollect(registry, worldEgg.id, 99999)
      expect(canCollect2).to.equal(false)
    end)

    it("should collect egg and return inventory data", function()
      local registry = WorldEgg.createRegistry()
      local worldEgg = WorldEgg.create("CommonEgg", 12345, "chicken-1", 1, { x = 0, y = 5, z = 0 })
      WorldEgg.add(registry, worldEgg)

      local success, message, inventoryEgg = WorldEgg.collect(registry, worldEgg.id, 12345)
      expect(success).to.equal(true)
      expect(inventoryEgg).to.be.ok()
      expect(inventoryEgg.eggType).to.equal("CommonEgg")
      expect(WorldEgg.getCount(registry)).to.equal(0)
    end)

    it("should detect expired eggs", function()
      local worldEgg = WorldEgg.create("CommonEgg", 12345, "chicken-1", 1, { x = 0, y = 5, z = 0 })
      -- Not expired at spawn time
      expect(WorldEgg.isExpired(worldEgg, worldEgg.spawnTime)).to.equal(false)
      -- Expired after despawn time
      expect(WorldEgg.isExpired(worldEgg, worldEgg.spawnTime + 301)).to.equal(true)
    end)
  end)

  describe("Store Egg Operations", function()
    it("should purchase egg with sufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 1000

      local initialEggCount = #playerData.inventory.eggs
      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 1)

      expect(result.success).to.equal(true)
      expect(#playerData.inventory.eggs).to.equal(initialEggCount + 1)
    end)

    it("should fail purchase with insufficient money", function()
      local playerData = PlayerData.createDefault()
      playerData.money = 0

      local result = Store.purchaseEggFromInventory(playerData, "CommonEgg", 1)
      expect(result.success).to.equal(false)
    end)

    it("should sell egg from inventory", function()
      local playerData = PlayerData.createDefault()
      table.insert(playerData.inventory.eggs, {
        id = "sell-egg-1",
        eggType = "CommonEgg",
        rarity = "Common",
      })

      local initialMoney = playerData.money
      local result = Store.sellEgg(playerData, "sell-egg-1")

      expect(result.success).to.equal(true)
      expect(playerData.money).to.be.at.least(initialMoney)
      expect(#playerData.inventory.eggs).to.equal(0)
    end)
  end)
end
