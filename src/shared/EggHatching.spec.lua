--[[
	EggHatching.spec.lua
	TestEZ tests for EggHatching module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local EggHatching = require(Shared:WaitForChild("EggHatching"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local EggConfig = require(Shared:WaitForChild("EggConfig"))

  -- Helper function to create mock player data with eggs
  local function createMockPlayerData(): PlayerData.PlayerDataSchema
    local currentTime = os.time()
    return {
      money = 1000,
      inventory = {
        eggs = {
          {
            id = "test_egg_1",
            eggType = "CommonEgg",
            rarity = "Common",
          },
          {
            id = "test_egg_2",
            eggType = "CommonEgg",
            rarity = "Common",
          },
          {
            id = "test_egg_3",
            eggType = "RareEgg",
            rarity = "Rare",
          },
        },
        chickens = {},
      },
      placedChickens = {},
      traps = {},
      upgrades = {
        cageTier = 1,
        lockDurationMultiplier = 1,
        predatorResistance = 0,
      },
      activePowerUps = {},
      ownedWeapons = { "BaseballBat" },
      equippedWeapon = "BaseballBat",
      shieldState = {
        isActive = false,
        activatedTime = nil,
        expiresAt = nil,
        cooldownEndTime = nil,
      },
      sectionIndex = nil,
      lastLogoutTime = nil,
      totalPlayTime = 0,
      tutorialComplete = false,
      level = 1,
      xp = 0,
    }
  end

  -- Helper function to create empty mock player data
  local function createEmptyMockPlayerData(): PlayerData.PlayerDataSchema
    return {
      money = 0,
      inventory = {
        eggs = {},
        chickens = {},
      },
      placedChickens = {},
      traps = {},
      upgrades = {
        cageTier = 1,
        lockDurationMultiplier = 1,
        predatorResistance = 0,
      },
      activePowerUps = {},
      ownedWeapons = {},
      equippedWeapon = nil,
      shieldState = {
        isActive = false,
        activatedTime = nil,
        expiresAt = nil,
        cooldownEndTime = nil,
      },
      sectionIndex = nil,
      lastLogoutTime = nil,
      totalPlayTime = 0,
      tutorialComplete = false,
      level = 1,
      xp = 0,
    }
  end

  describe("EggHatching", function()
    describe("getCelebrationTier", function()
      it("should return 0 for Common rarity", function()
        expect(EggHatching.getCelebrationTier("Common")).to.equal(0)
      end)

      it("should return 1 for Uncommon rarity", function()
        expect(EggHatching.getCelebrationTier("Uncommon")).to.equal(1)
      end)

      it("should return 2 for Rare rarity", function()
        expect(EggHatching.getCelebrationTier("Rare")).to.equal(2)
      end)

      it("should return 3 for Epic rarity", function()
        expect(EggHatching.getCelebrationTier("Epic")).to.equal(3)
      end)

      it("should return 4 for Legendary rarity", function()
        expect(EggHatching.getCelebrationTier("Legendary")).to.equal(4)
      end)

      it("should return 5 for Mythic rarity", function()
        expect(EggHatching.getCelebrationTier("Mythic")).to.equal(5)
      end)

      it("should return 0 for invalid rarity", function()
        expect(EggHatching.getCelebrationTier("InvalidRarity")).to.equal(0)
        expect(EggHatching.getCelebrationTier("")).to.equal(0)
      end)
    end)

    describe("isRareHatch", function()
      it("should return false for Common rarity", function()
        expect(EggHatching.isRareHatch("Common")).to.equal(false)
      end)

      it("should return false for Uncommon rarity", function()
        expect(EggHatching.isRareHatch("Uncommon")).to.equal(false)
      end)

      it("should return true for Rare rarity", function()
        expect(EggHatching.isRareHatch("Rare")).to.equal(true)
      end)

      it("should return true for Epic rarity", function()
        expect(EggHatching.isRareHatch("Epic")).to.equal(true)
      end)

      it("should return true for Legendary rarity", function()
        expect(EggHatching.isRareHatch("Legendary")).to.equal(true)
      end)

      it("should return true for Mythic rarity", function()
        expect(EggHatching.isRareHatch("Mythic")).to.equal(true)
      end)

      it("should return false for invalid rarity", function()
        expect(EggHatching.isRareHatch("InvalidRarity")).to.equal(false)
      end)
    end)

    describe("getHatchPreview", function()
      it("should return hatch outcomes for valid egg type", function()
        local preview = EggHatching.getHatchPreview("CommonEgg")
        expect(preview).to.be.ok()
        expect(typeof(preview)).to.equal("table")
        expect(#preview).to.equal(3)
      end)

      it("should return outcomes with chickenType and probability", function()
        local preview = EggHatching.getHatchPreview("CommonEgg")
        expect(preview).to.be.ok()
        for _, outcome in ipairs(preview) do
          expect(outcome.chickenType).to.be.ok()
          expect(outcome.probability).to.be.ok()
          expect(typeof(outcome.chickenType)).to.equal("string")
          expect(typeof(outcome.probability)).to.equal("number")
        end
      end)

      it("should return nil for invalid egg type", function()
        local preview = EggHatching.getHatchPreview("InvalidEgg")
        expect(preview).to.equal(nil)
      end)

      it("should return correct outcomes for each egg type", function()
        local eggTypes = EggConfig.getAllTypes()
        for _, eggType in ipairs(eggTypes) do
          local preview = EggHatching.getHatchPreview(eggType)
          expect(preview).to.be.ok()
          expect(#preview).to.equal(3)
        end
      end)
    end)

    describe("canHatch", function()
      it("should return true for valid egg in inventory", function()
        local playerData = createMockPlayerData()
        local canHatch, message = EggHatching.canHatch(playerData, "test_egg_1")
        expect(canHatch).to.equal(true)
        expect(message).to.equal("Ready to hatch")
      end)

      it("should return false for egg not in inventory", function()
        local playerData = createMockPlayerData()
        local canHatch, message = EggHatching.canHatch(playerData, "nonexistent_egg")
        expect(canHatch).to.equal(false)
        expect(message).to.equal("Egg not found in inventory")
      end)

      it("should return false for invalid player data", function()
        local canHatch, message = EggHatching.canHatch(nil :: any, "test_egg_1")
        expect(canHatch).to.equal(false)
        expect(message).to.equal("Invalid player data")
      end)

      it("should return false for player data without inventory", function()
        local playerData = { money = 100 } :: any
        local canHatch, message = EggHatching.canHatch(playerData, "test_egg_1")
        expect(canHatch).to.equal(false)
        expect(message).to.equal("Invalid player data")
      end)

      it("should return false for egg with invalid egg type", function()
        local playerData = createMockPlayerData()
        -- Add an egg with invalid type
        table.insert(playerData.inventory.eggs, {
          id = "invalid_type_egg",
          eggType = "NonExistentEgg",
          rarity = "Common",
        })
        local canHatch, message = EggHatching.canHatch(playerData, "invalid_type_egg")
        expect(canHatch).to.equal(false)
        expect(message).to.equal("Invalid egg type")
      end)
    end)

    describe("hatch", function()
      it("should successfully hatch a valid egg", function()
        local playerData = createMockPlayerData()
        local initialEggCount = #playerData.inventory.eggs
        local result = EggHatching.hatch(playerData, "test_egg_1")

        expect(result.success).to.equal(true)
        expect(result.message).to.equal("Hatched successfully!")
        expect(result.chickenType).to.be.ok()
        expect(result.chickenRarity).to.be.ok()
        expect(result.chickenId).to.be.ok()
        expect(#playerData.inventory.eggs).to.equal(initialEggCount - 1)
        expect(#playerData.inventory.chickens).to.equal(1)
      end)

      it("should return valid celebration tier", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatch(playerData, "test_egg_1")

        expect(result.success).to.equal(true)
        expect(typeof(result.celebrationTier)).to.equal("number")
        expect(result.celebrationTier >= 0).to.equal(true)
        expect(result.celebrationTier <= 5).to.equal(true)
      end)

      it("should fail for nonexistent egg", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatch(playerData, "nonexistent_egg")

        expect(result.success).to.equal(false)
        expect(result.chickenType).to.equal(nil)
        expect(result.chickenRarity).to.equal(nil)
        expect(result.chickenId).to.equal(nil)
        expect(result.celebrationTier).to.equal(0)
      end)

      it("should fail for invalid player data", function()
        local result = EggHatching.hatch(nil :: any, "test_egg_1")

        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Invalid player data")
      end)

      it("should add chicken to inventory with correct properties", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatch(playerData, "test_egg_1")

        expect(result.success).to.equal(true)
        local chicken = playerData.inventory.chickens[1]
        expect(chicken).to.be.ok()
        expect(chicken.id).to.be.ok()
        expect(chicken.chickenType).to.equal(result.chickenType)
        expect(chicken.rarity).to.equal(result.chickenRarity)
        expect(chicken.accumulatedMoney).to.equal(0)
        expect(chicken.spotIndex).to.equal(nil) -- Should be in inventory
      end)

      it("should set isRareHatch correctly", function()
        local playerData = createMockPlayerData()
        -- Hatch common egg - isRareHatch should be false for common chickens
        local result = EggHatching.hatch(playerData, "test_egg_1")

        expect(result.success).to.equal(true)
        expect(typeof(result.isRareHatch)).to.equal("boolean")
        -- Common egg hatches common chickens, which should not be rare
        expect(result.isRareHatch).to.equal(false)
      end)
    end)

    describe("hatchByType", function()
      it("should hatch first egg of specified type", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatchByType(playerData, "CommonEgg")

        expect(result.success).to.equal(true)
        expect(result.chickenType).to.be.ok()
      end)

      it("should fail when no egg of type exists", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatchByType(playerData, "MythicEgg")

        expect(result.success).to.equal(false)
        expect(result.message).to.equal("No egg of type MythicEgg found in inventory")
      end)

      it("should fail for invalid egg type", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatchByType(playerData, "InvalidEggType")

        expect(result.success).to.equal(false)
      end)

      it("should remove the correct egg from inventory", function()
        local playerData = createMockPlayerData()
        local initialCount = EggHatching.getEggCount(playerData, "CommonEgg")

        local result = EggHatching.hatchByType(playerData, "CommonEgg")

        expect(result.success).to.equal(true)
        expect(EggHatching.getEggCount(playerData, "CommonEgg")).to.equal(initialCount - 1)
      end)
    end)

    describe("getEggCount", function()
      it("should return correct count for egg type in inventory", function()
        local playerData = createMockPlayerData()
        local count = EggHatching.getEggCount(playerData, "CommonEgg")
        expect(count).to.equal(2)
      end)

      it("should return correct count for different egg type", function()
        local playerData = createMockPlayerData()
        local count = EggHatching.getEggCount(playerData, "RareEgg")
        expect(count).to.equal(1)
      end)

      it("should return 0 for egg type not in inventory", function()
        local playerData = createMockPlayerData()
        local count = EggHatching.getEggCount(playerData, "MythicEgg")
        expect(count).to.equal(0)
      end)

      it("should return 0 for empty inventory", function()
        local playerData = createEmptyMockPlayerData()
        local count = EggHatching.getEggCount(playerData, "CommonEgg")
        expect(count).to.equal(0)
      end)

      it("should return 0 for invalid egg type", function()
        local playerData = createMockPlayerData()
        local count = EggHatching.getEggCount(playerData, "InvalidEgg")
        expect(count).to.equal(0)
      end)
    end)

    describe("getTotalEggCount", function()
      it("should return total egg count in inventory", function()
        local playerData = createMockPlayerData()
        local count = EggHatching.getTotalEggCount(playerData)
        expect(count).to.equal(3)
      end)

      it("should return 0 for empty inventory", function()
        local playerData = createEmptyMockPlayerData()
        local count = EggHatching.getTotalEggCount(playerData)
        expect(count).to.equal(0)
      end)

      it("should decrease after hatching", function()
        local playerData = createMockPlayerData()
        local initialCount = EggHatching.getTotalEggCount(playerData)

        EggHatching.hatch(playerData, "test_egg_1")

        expect(EggHatching.getTotalEggCount(playerData)).to.equal(initialCount - 1)
      end)
    end)

    describe("simulateHatches", function()
      it("should return results table", function()
        local results = EggHatching.simulateHatches("CommonEgg", 10)
        expect(typeof(results)).to.equal("table")
      end)

      it("should return counts for valid chicken types", function()
        local results = EggHatching.simulateHatches("CommonEgg", 100)
        local totalCount = 0
        for chickenType, count in pairs(results) do
          expect(typeof(chickenType)).to.equal("string")
          expect(typeof(count)).to.equal("number")
          expect(count > 0).to.equal(true)
          totalCount = totalCount + count
        end
        expect(totalCount).to.equal(100)
      end)

      it("should return empty table for invalid egg type", function()
        local results = EggHatching.simulateHatches("InvalidEgg", 10)
        local count = 0
        for _ in pairs(results) do
          count = count + 1
        end
        expect(count).to.equal(0)
      end)

      it("should return empty table for zero hatches", function()
        local results = EggHatching.simulateHatches("CommonEgg", 0)
        local count = 0
        for _ in pairs(results) do
          count = count + 1
        end
        expect(count).to.equal(0)
      end)

      it("should produce results matching configured chicken types", function()
        local results = EggHatching.simulateHatches("CommonEgg", 100)
        local preview = EggHatching.getHatchPreview("CommonEgg")
        local expectedTypes = {}
        for _, outcome in ipairs(preview) do
          expectedTypes[outcome.chickenType] = true
        end

        for chickenType, _ in pairs(results) do
          expect(expectedTypes[chickenType]).to.equal(true)
        end
      end)
    end)

    describe("getCelebrationEffects", function()
      it("should return effects for tier 0 (Common)", function()
        local effects = EggHatching.getCelebrationEffects(0)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(0)
        expect(effects.soundName).to.equal("hatch_common")
        expect(effects.screenFlash).to.equal(false)
        expect(effects.announceToServer).to.equal(false)
      end)

      it("should return effects for tier 1 (Uncommon)", function()
        local effects = EggHatching.getCelebrationEffects(1)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(10)
        expect(effects.soundName).to.equal("hatch_uncommon")
        expect(effects.screenFlash).to.equal(false)
        expect(effects.announceToServer).to.equal(false)
      end)

      it("should return effects for tier 2 (Rare)", function()
        local effects = EggHatching.getCelebrationEffects(2)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(25)
        expect(effects.soundName).to.equal("hatch_rare")
        expect(effects.screenFlash).to.equal(true)
        expect(effects.announceToServer).to.equal(false)
      end)

      it("should return effects for tier 3 (Epic)", function()
        local effects = EggHatching.getCelebrationEffects(3)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(50)
        expect(effects.soundName).to.equal("hatch_epic")
        expect(effects.screenFlash).to.equal(true)
        expect(effects.announceToServer).to.equal(false)
      end)

      it("should return effects for tier 4 (Legendary)", function()
        local effects = EggHatching.getCelebrationEffects(4)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(100)
        expect(effects.soundName).to.equal("hatch_legendary")
        expect(effects.screenFlash).to.equal(true)
        expect(effects.announceToServer).to.equal(true)
      end)

      it("should return effects for tier 5 (Mythic)", function()
        local effects = EggHatching.getCelebrationEffects(5)
        expect(effects).to.be.ok()
        expect(effects.particleCount).to.equal(200)
        expect(effects.soundName).to.equal("hatch_mythic")
        expect(effects.screenFlash).to.equal(true)
        expect(effects.announceToServer).to.equal(true)
      end)

      it("should return tier 0 effects for negative values", function()
        local effects = EggHatching.getCelebrationEffects(-1)
        expect(effects.particleCount).to.equal(0)
        expect(effects.soundName).to.equal("hatch_common")
      end)

      it("should return tier 5 effects for values above 5", function()
        local effects = EggHatching.getCelebrationEffects(10)
        expect(effects.particleCount).to.equal(200)
        expect(effects.soundName).to.equal("hatch_mythic")
      end)

      it("should have increasing particle counts for higher tiers", function()
        local prevParticles = -1
        for tier = 0, 5 do
          local effects = EggHatching.getCelebrationEffects(tier)
          expect(effects.particleCount >= prevParticles).to.equal(true)
          prevParticles = effects.particleCount
        end
      end)

      it("should enable server announce only for Legendary and above", function()
        for tier = 0, 3 do
          local effects = EggHatching.getCelebrationEffects(tier)
          expect(effects.announceToServer).to.equal(false)
        end
        for tier = 4, 5 do
          local effects = EggHatching.getCelebrationEffects(tier)
          expect(effects.announceToServer).to.equal(true)
        end
      end)
    end)

    describe("integration tests", function()
      it("should correctly link celebration tier with isRareHatch", function()
        -- Verify that isRareHatch is true when tier >= 2
        local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
        for _, rarity in ipairs(rarities) do
          local tier = EggHatching.getCelebrationTier(rarity)
          local isRare = EggHatching.isRareHatch(rarity)
          expect(isRare).to.equal(tier >= 2)
        end
      end)

      it("should handle multiple consecutive hatches", function()
        local playerData = createMockPlayerData()
        -- Add more eggs
        for i = 1, 5 do
          table.insert(playerData.inventory.eggs, {
            id = "batch_egg_" .. i,
            eggType = "CommonEgg",
            rarity = "Common",
          })
        end

        local initialCount = EggHatching.getTotalEggCount(playerData)
        local successCount = 0

        for i = 1, 5 do
          local result = EggHatching.hatchByType(playerData, "CommonEgg")
          if result.success then
            successCount = successCount + 1
          end
        end

        expect(successCount).to.equal(5)
        expect(EggHatching.getTotalEggCount(playerData)).to.equal(initialCount - 5)
        expect(#playerData.inventory.chickens).to.equal(5)
      end)

      it("should return effects that match the hatched chicken's rarity", function()
        local playerData = createMockPlayerData()
        local result = EggHatching.hatch(playerData, "test_egg_1")

        if result.success and result.chickenRarity then
          local expectedTier = EggHatching.getCelebrationTier(result.chickenRarity)
          expect(result.celebrationTier).to.equal(expectedTier)

          local effects = EggHatching.getCelebrationEffects(result.celebrationTier)
          expect(effects).to.be.ok()
        end
      end)
    end)
  end)
end
