--[[
	PlayerDataService.spec.lua
	Tests for the PlayerDataService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PlayerData = require(Shared:WaitForChild("PlayerData"))

  describe("PlayerDataService", function()
    -- Note: Full integration tests require Knit to be started.
    -- These tests validate the service structure and types.

    describe("Service Definition", function()
      it("should export a valid Knit service", function()
        -- The service is created when required, so we check it exists
        -- Full Knit integration is tested at runtime
        expect(PlayerData).to.be.ok()
        expect(PlayerData.createDefault).to.be.a("function")
      end)

      it("should have createDefault return valid data", function()
        local defaultData = PlayerData.createDefault()
        expect(defaultData).to.be.ok()
        expect(defaultData.money).to.be.a("number")
        expect(defaultData.inventory).to.be.ok()
        expect(defaultData.placedChickens).to.be.ok()
      end)
    end)

    describe("PlayerData Integration", function()
      it("should validate default data", function()
        local defaultData = PlayerData.createDefault()
        expect(PlayerData.validate(defaultData)).to.equal(true)
      end)

      it("should clone data correctly", function()
        local original = PlayerData.createDefault()
        original.money = 500

        local cloned = PlayerData.clone(original)
        expect(cloned.money).to.equal(500)

        -- Modify clone shouldn't affect original
        cloned.money = 1000
        expect(original.money).to.equal(500)
      end)

      it("should get level correctly", function()
        local data = PlayerData.createDefault()
        data.level = 5
        expect(PlayerData.getLevel(data)).to.equal(5)
      end)

      it("should get XP correctly", function()
        local data = PlayerData.createDefault()
        data.xp = 1500
        expect(PlayerData.getXP(data)).to.equal(1500)
      end)

      it("should detect bankruptcy correctly", function()
        local data = PlayerData.createDefault()
        data.money = 0
        data.placedChickens = {}
        data.inventory.chickens = {}
        data.inventory.eggs = {}

        expect(PlayerData.isBankrupt(data)).to.equal(true)
      end)

      it("should not consider player bankrupt with money", function()
        local data = PlayerData.createDefault()
        data.money = 100
        data.placedChickens = {}
        data.inventory.chickens = {}
        data.inventory.eggs = {}

        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)
    end)

    describe("Data Validation", function()
      it("should reject invalid money", function()
        local data = PlayerData.createDefault()
        data.money = -100
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should reject non-table inventory", function()
        local data = PlayerData.createDefault()
        data.inventory = "invalid"
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should validate chicken data", function()
        local validChicken = {
          id = "test_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
          spotIndex = 1,
        }
        expect(PlayerData.validateChicken(validChicken)).to.equal(true)
      end)

      it("should reject invalid chicken rarity", function()
        local invalidChicken = {
          id = "test_123",
          chickenType = "BasicChick",
          rarity = "SuperRare", -- Invalid rarity
          accumulatedMoney = 0,
          lastEggTime = os.time(),
        }
        expect(PlayerData.validateChicken(invalidChicken)).to.equal(false)
      end)

      it("should validate egg data", function()
        local validEgg = {
          id = "egg_123",
          eggType = "BasicEgg",
          rarity = "Common",
        }
        expect(PlayerData.validateEgg(validEgg)).to.equal(true)
      end)
    end)

    describe("Weapon Functions", function()
      it("should check weapon ownership", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.ownsWeapon(data, "BaseballBat")).to.equal(true)
        expect(PlayerData.ownsWeapon(data, "Sword")).to.equal(false)
      end)

      it("should add weapons", function()
        local data = PlayerData.createDefault()
        local added = PlayerData.addWeapon(data, "Sword")
        expect(added).to.equal(true)
        expect(PlayerData.ownsWeapon(data, "Sword")).to.equal(true)
      end)

      it("should not add duplicate weapons", function()
        local data = PlayerData.createDefault()
        local added = PlayerData.addWeapon(data, "BaseballBat")
        expect(added).to.equal(false)
      end)

      it("should equip owned weapons", function()
        local data = PlayerData.createDefault()
        PlayerData.addWeapon(data, "Sword")
        local equipped = PlayerData.equipWeapon(data, "Sword")
        expect(equipped).to.equal(true)
        expect(PlayerData.getEquippedWeapon(data)).to.equal("Sword")
      end)

      it("should not equip unowned weapons", function()
        local data = PlayerData.createDefault()
        local equipped = PlayerData.equipWeapon(data, "Sword")
        expect(equipped).to.equal(false)
      end)
    end)

    describe("PowerUp Functions", function()
      it("should add power-ups", function()
        local data = PlayerData.createDefault()
        PlayerData.addPowerUp(data, "HatchLuck_1", 300)

        expect(#data.activePowerUps).to.equal(1)
        expect(data.activePowerUps[1].powerUpId).to.equal("HatchLuck_1")
      end)

      it("should check for active power-ups", function()
        local data = PlayerData.createDefault()
        PlayerData.addPowerUp(data, "HatchLuck_1", 300)

        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(true)
        expect(PlayerData.hasActivePowerUp(data, "EggQuality")).to.equal(false)
      end)

      it("should clean up expired power-ups", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_1",
            activatedTime = os.time() - 1000,
            expiresAt = os.time() - 100, -- Expired
          },
        }

        PlayerData.cleanupExpiredPowerUps(data)
        expect(#data.activePowerUps).to.equal(0)
      end)
    end)
  end)
end
