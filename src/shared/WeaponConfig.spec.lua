--[[
	WeaponConfig.spec.lua
	TestEZ tests for WeaponConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

  describe("WeaponConfig", function()
    describe("get", function()
      it("should return config for valid weapon type", function()
        local config = WeaponConfig.get("BaseballBat")
        expect(config).to.be.ok()
        expect(config.name).to.equal("BaseballBat")
        expect(config.displayName).to.equal("Baseball Bat")
        expect(config.tier).to.equal("Basic")
      end)

      it("should return nil for invalid weapon type", function()
        local config = WeaponConfig.get("InvalidWeapon")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = WeaponConfig.get("Axe")
        expect(config).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.tier).to.be.ok()
        expect(config.tierLevel).to.be.ok()
        expect(config.price).to.be.ok()
        expect(config.robuxPrice).to.be.ok()
        expect(config.sellPrice).to.be.ok()
        expect(config.damage).to.be.ok()
        expect(config.swingCooldownSeconds).to.be.ok()
        expect(config.swingRangeStuds).to.be.ok()
        expect(config.knockbackForce).to.be.ok()
        expect(config.knockbackDuration).to.be.ok()
        expect(config.description).to.be.ok()
        expect(config.icon).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of weapon types", function()
        local all = WeaponConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should have 3 weapon types", function()
        local all = WeaponConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(3)
      end)
    end)

    describe("getPurchasable", function()
      it("should return array of purchasable weapons", function()
        local purchasable = WeaponConfig.getPurchasable()
        expect(typeof(purchasable)).to.equal("table")
      end)

      it("should exclude free starter weapon", function()
        local purchasable = WeaponConfig.getPurchasable()
        for _, config in ipairs(purchasable) do
          expect(config.price > 0 or config.robuxPrice > 0).to.equal(true)
        end
      end)

      it("should be sorted by tier level", function()
        local purchasable = WeaponConfig.getPurchasable()
        for i = 2, #purchasable do
          expect(purchasable[i].tierLevel >= purchasable[i - 1].tierLevel).to.equal(true)
        end
      end)
    end)

    describe("getAllForStore", function()
      it("should return array of all weapons", function()
        local weapons = WeaponConfig.getAllForStore()
        expect(typeof(weapons)).to.equal("table")
        expect(#weapons).to.equal(3)
      end)

      it("should include starter weapon", function()
        local weapons = WeaponConfig.getAllForStore()
        local hasStarter = false
        for _, config in ipairs(weapons) do
          if config.name == "BaseballBat" then
            hasStarter = true
            break
          end
        end
        expect(hasStarter).to.equal(true)
      end)

      it("should be sorted by tier level", function()
        local weapons = WeaponConfig.getAllForStore()
        for i = 2, #weapons do
          expect(weapons[i].tierLevel >= weapons[i - 1].tierLevel).to.equal(true)
        end
      end)
    end)

    describe("getTierLevel", function()
      it("should return correct levels for each tier", function()
        expect(WeaponConfig.getTierLevel("Basic")).to.equal(1)
        expect(WeaponConfig.getTierLevel("Standard")).to.equal(2)
        expect(WeaponConfig.getTierLevel("Premium")).to.equal(3)
      end)

      it("should return 1 for invalid tier", function()
        expect(WeaponConfig.getTierLevel("Invalid" :: any)).to.equal(1)
      end)
    end)

    describe("getTierColor", function()
      it("should return color for valid tier", function()
        local color = WeaponConfig.getTierColor("Basic")
        expect(color).to.be.ok()
        expect(color.r).to.be.ok()
        expect(color.g).to.be.ok()
        expect(color.b).to.be.ok()
      end)

      it("should return default for invalid tier", function()
        local color = WeaponConfig.getTierColor("Invalid" :: any)
        expect(color).to.be.ok()
      end)
    end)

    describe("isValid", function()
      it("should return true for valid weapon types", function()
        expect(WeaponConfig.isValid("BaseballBat")).to.equal(true)
        expect(WeaponConfig.isValid("Sword")).to.equal(true)
        expect(WeaponConfig.isValid("Axe")).to.equal(true)
      end)

      it("should return false for invalid weapon types", function()
        expect(WeaponConfig.isValid("NotAWeapon")).to.equal(false)
        expect(WeaponConfig.isValid("")).to.equal(false)
      end)
    end)

    describe("getDefaultWeapon", function()
      it("should return BaseballBat", function()
        expect(WeaponConfig.getDefaultWeapon()).to.equal("BaseballBat")
      end)

      it("should return a valid weapon type", function()
        local default = WeaponConfig.getDefaultWeapon()
        expect(WeaponConfig.isValid(default)).to.equal(true)
      end)
    end)

    describe("getDamage", function()
      it("should return damage for valid weapon", function()
        local damage = WeaponConfig.getDamage("BaseballBat")
        expect(damage).to.equal(1)
      end)

      it("should return 1 for invalid weapon", function()
        expect(WeaponConfig.getDamage("Invalid")).to.equal(1)
      end)

      it("should have increasing damage for higher tiers", function()
        local batDamage = WeaponConfig.getDamage("BaseballBat")
        local axeDamage = WeaponConfig.getDamage("Axe")
        expect(axeDamage > batDamage).to.equal(true)
      end)
    end)

    describe("getSwingCooldown", function()
      it("should return cooldown for valid weapon", function()
        local cooldown = WeaponConfig.getSwingCooldown("BaseballBat")
        expect(cooldown > 0).to.equal(true)
      end)

      it("should return default for invalid weapon", function()
        expect(WeaponConfig.getSwingCooldown("Invalid")).to.equal(0.5)
      end)
    end)

    describe("getRange", function()
      it("should return range for valid weapon", function()
        local range = WeaponConfig.getRange("BaseballBat")
        expect(range > 0).to.equal(true)
      end)

      it("should return default for invalid weapon", function()
        expect(WeaponConfig.getRange("Invalid")).to.equal(8)
      end)
    end)

    describe("getKnockbackParams", function()
      it("should return knockback params for valid weapon", function()
        local params = WeaponConfig.getKnockbackParams("BaseballBat")
        expect(params).to.be.ok()
        expect(params.force > 0).to.equal(true)
        expect(params.duration > 0).to.equal(true)
      end)

      it("should return defaults for invalid weapon", function()
        local params = WeaponConfig.getKnockbackParams("Invalid")
        expect(params.force).to.equal(50)
        expect(params.duration).to.equal(0.5)
      end)
    end)

    describe("compare", function()
      it("should return positive when first weapon is better", function()
        local result = WeaponConfig.compare("Axe", "BaseballBat")
        expect(result > 0).to.equal(true)
      end)

      it("should return negative when first weapon is worse", function()
        local result = WeaponConfig.compare("BaseballBat", "Axe")
        expect(result < 0).to.equal(true)
      end)

      it("should return 0 when comparing same weapon", function()
        local result = WeaponConfig.compare("BaseballBat", "BaseballBat")
        expect(result).to.equal(0)
      end)

      it("should return -1 for invalid first weapon", function()
        local result = WeaponConfig.compare("Invalid", "BaseballBat")
        expect(result).to.equal(-1)
      end)

      it("should return 1 for invalid second weapon", function()
        local result = WeaponConfig.compare("BaseballBat", "Invalid")
        expect(result).to.equal(1)
      end)
    end)

    describe("config data validity", function()
      it("should have tier level between 1-3 for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.tierLevel >= 1).to.equal(true)
          expect(config.tierLevel <= 3).to.equal(true)
        end
      end)

      it("should have non-negative price for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.price >= 0).to.equal(true)
        end
      end)

      it("should have non-negative robuxPrice for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.robuxPrice >= 0).to.equal(true)
        end
      end)

      it("should have positive damage for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.damage > 0).to.equal(true)
        end
      end)

      it("should have positive swing cooldown for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.swingCooldownSeconds > 0).to.equal(true)
        end
      end)

      it("should have positive range for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.swingRangeStuds > 0).to.equal(true)
        end
      end)

      it("should have positive knockback force for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.knockbackForce > 0).to.equal(true)
        end
      end)

      it("should have positive knockback duration for all weapons", function()
        local all = WeaponConfig.getAll()
        for _, config in pairs(all) do
          expect(config.knockbackDuration > 0).to.equal(true)
        end
      end)

      it("should have matching name field and key", function()
        local all = WeaponConfig.getAll()
        for key, config in pairs(all) do
          expect(config.name).to.equal(key)
        end
      end)

      it("should have starter weapon be free", function()
        local starter = WeaponConfig.get(WeaponConfig.getDefaultWeapon())
        expect(starter.price).to.equal(0)
      end)
    end)
  end)
end
