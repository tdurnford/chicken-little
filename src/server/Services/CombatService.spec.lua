--[[
	CombatService Tests
	Tests for the CombatService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
  local CombatHealth = require(Shared:WaitForChild("CombatHealth"))
  local AreaShield = require(Shared:WaitForChild("AreaShield"))

  -- Note: Full service testing requires Knit to be running
  -- These tests focus on the underlying modules used by CombatService

  describe("WeaponConfig", function()
    describe("get", function()
      it("should return config for valid weapon types", function()
        local config = WeaponConfig.get("BaseballBat")
        expect(config).to.be.ok()
        expect(config.name).to.equal("BaseballBat")
        expect(config.damage).to.be.a("number")
        expect(config.damage).to.be.ok()
      end)

      it("should return nil for invalid weapon types", function()
        local config = WeaponConfig.get("InvalidWeapon")
        expect(config).to.equal(nil)
      end)
    end)

    describe("getAll", function()
      it("should return all weapon configurations", function()
        local all = WeaponConfig.getAll()
        expect(all).to.be.ok()
        expect(all.BaseballBat).to.be.ok()
        expect(all.Sword).to.be.ok()
        expect(all.Axe).to.be.ok()
      end)
    end)

    describe("isValid", function()
      it("should return true for valid weapons", function()
        expect(WeaponConfig.isValid("BaseballBat")).to.equal(true)
        expect(WeaponConfig.isValid("Sword")).to.equal(true)
        expect(WeaponConfig.isValid("Axe")).to.equal(true)
      end)

      it("should return false for invalid weapons", function()
        expect(WeaponConfig.isValid("FakeWeapon")).to.equal(false)
        expect(WeaponConfig.isValid("")).to.equal(false)
      end)
    end)

    describe("getDefaultWeapon", function()
      it("should return BaseballBat as default", function()
        expect(WeaponConfig.getDefaultWeapon()).to.equal("BaseballBat")
      end)
    end)

    describe("getDamage", function()
      it("should return correct damage values", function()
        expect(WeaponConfig.getDamage("BaseballBat")).to.equal(1)
        expect(WeaponConfig.getDamage("Sword")).to.equal(2)
        expect(WeaponConfig.getDamage("Axe")).to.equal(4)
      end)

      it("should return default damage for invalid weapons", function()
        expect(WeaponConfig.getDamage("InvalidWeapon")).to.equal(1)
      end)
    end)

    describe("getSwingCooldown", function()
      it("should return correct cooldown values", function()
        expect(WeaponConfig.getSwingCooldown("BaseballBat")).to.equal(0.5)
        expect(WeaponConfig.getSwingCooldown("Sword")).to.equal(0.4)
        expect(WeaponConfig.getSwingCooldown("Axe")).to.equal(0.8)
      end)
    end)

    describe("getKnockbackParams", function()
      it("should return knockback parameters", function()
        local params = WeaponConfig.getKnockbackParams("BaseballBat")
        expect(params).to.be.ok()
        expect(params.force).to.be.a("number")
        expect(params.duration).to.be.a("number")
      end)

      it("should return defaults for invalid weapons", function()
        local params = WeaponConfig.getKnockbackParams("InvalidWeapon")
        expect(params.force).to.equal(50)
        expect(params.duration).to.equal(0.5)
      end)
    end)

    describe("getPurchasable", function()
      it("should return weapons with price > 0", function()
        local purchasable = WeaponConfig.getPurchasable()
        expect(#purchasable).to.be.ok()

        for _, weapon in ipairs(purchasable) do
          expect(weapon.price > 0 or weapon.robuxPrice > 0).to.equal(true)
        end
      end)

      it("should not include free starter weapon in purchasable", function()
        local purchasable = WeaponConfig.getPurchasable()
        local hasBaseballBat = false
        for _, weapon in ipairs(purchasable) do
          if weapon.name == "BaseballBat" then
            hasBaseballBat = true
            break
          end
        end
        expect(hasBaseballBat).to.equal(false)
      end)
    end)

    describe("compare", function()
      it("should compare weapons correctly", function()
        -- Axe is better than Sword
        expect(WeaponConfig.compare("Axe", "Sword")).to.be.ok()
        expect(WeaponConfig.compare("Axe", "Sword") > 0).to.equal(true)

        -- Sword is better than BaseballBat
        expect(WeaponConfig.compare("Sword", "BaseballBat") > 0).to.equal(true)

        -- Same weapon should equal 0
        expect(WeaponConfig.compare("Sword", "Sword")).to.equal(0)
      end)
    end)
  end)

  describe("CombatHealth", function()
    describe("createState", function()
      it("should create valid initial state", function()
        local state = CombatHealth.createState()
        expect(state).to.be.ok()
        expect(state.health).to.equal(100)
        expect(state.maxHealth).to.equal(100)
        expect(state.isKnockedBack).to.equal(false)
        expect(state.isIncapacitated).to.equal(false)
      end)
    end)

    describe("getHealthPercent", function()
      it("should return correct percentage", function()
        local state = CombatHealth.createState()
        expect(CombatHealth.getHealthPercent(state)).to.equal(1)

        state.health = 50
        expect(CombatHealth.getHealthPercent(state)).to.equal(0.5)

        state.health = 0
        expect(CombatHealth.getHealthPercent(state)).to.equal(0)
      end)
    end)

    describe("isFullHealth", function()
      it("should return true at full health", function()
        local state = CombatHealth.createState()
        expect(CombatHealth.isFullHealth(state)).to.equal(true)
      end)

      it("should return false when damaged", function()
        local state = CombatHealth.createState()
        state.health = 99
        expect(CombatHealth.isFullHealth(state)).to.equal(false)
      end)
    end)

    describe("applyFixedDamage", function()
      it("should apply damage correctly", function()
        local state = CombatHealth.createState()
        local result = CombatHealth.applyFixedDamage(state, 25, 0, "Test")

        expect(result.success).to.equal(true)
        expect(result.damageDealt).to.equal(25)
        expect(result.newHealth).to.equal(75)
        expect(result.wasKnockedBack).to.equal(false)
      end)

      it("should trigger knockback when health reaches 0", function()
        local state = CombatHealth.createState()
        local result = CombatHealth.applyFixedDamage(state, 100, 0, "Test")

        expect(result.success).to.equal(true)
        expect(result.newHealth).to.equal(0)
        expect(result.wasKnockedBack).to.equal(true)
        expect(state.isKnockedBack).to.equal(true)
      end)

      it("should not deal damage while knocked back", function()
        local state = CombatHealth.createState()
        CombatHealth.applyFixedDamage(state, 100, 0, "Test") -- Trigger knockback
        local result = CombatHealth.applyFixedDamage(state, 50, 0, "Test")

        expect(result.success).to.equal(false)
        expect(result.damageDealt).to.equal(0)
      end)
    end)

    describe("incapacitate", function()
      it("should incapacitate player", function()
        local state = CombatHealth.createState()
        local result = CombatHealth.incapacitate(state, "attacker123", 0)

        expect(result.success).to.equal(true)
        expect(result.duration).to.be.ok()
        expect(state.isIncapacitated).to.equal(true)
        expect(state.incapacitatedBy).to.equal("attacker123")
      end)

      it("should not incapacitate already incapacitated player", function()
        local state = CombatHealth.createState()
        CombatHealth.incapacitate(state, "attacker123", 0)
        local result = CombatHealth.incapacitate(state, "attacker456", 0)

        expect(result.success).to.equal(false)
      end)
    end)

    describe("canMove", function()
      it("should return true normally", function()
        local state = CombatHealth.createState()
        expect(CombatHealth.canMove(state, 0)).to.equal(true)
      end)

      it("should return false when incapacitated", function()
        local state = CombatHealth.createState()
        CombatHealth.incapacitate(state, "attacker", 0)
        expect(CombatHealth.canMove(state, 0)).to.equal(false)
      end)

      it("should return false when knocked back", function()
        local state = CombatHealth.createState()
        CombatHealth.applyFixedDamage(state, 100, 0, "Test")
        expect(CombatHealth.canMove(state, 0)).to.equal(false)
      end)
    end)

    describe("reset", function()
      it("should restore state to defaults", function()
        local state = CombatHealth.createState()
        CombatHealth.applyFixedDamage(state, 100, 0, "Test")
        CombatHealth.incapacitate(state, "attacker", 5)
        CombatHealth.reset(state)

        expect(state.health).to.equal(100)
        expect(state.isKnockedBack).to.equal(false)
        expect(state.isIncapacitated).to.equal(false)
        expect(state.incapacitatedBy).to.equal(nil)
      end)
    end)

    describe("getConstants", function()
      it("should return combat constants", function()
        local constants = CombatHealth.getConstants()
        expect(constants.maxHealth).to.equal(100)
        expect(constants.regenPerSecond).to.be.ok()
        expect(constants.knockbackDuration).to.be.ok()
      end)
    end)
  end)

  describe("AreaShield", function()
    describe("createDefaultState", function()
      it("should create valid default state", function()
        local state = AreaShield.createDefaultState()
        expect(state).to.be.ok()
        expect(state.isActive).to.equal(false)
        expect(state.activatedTime).to.equal(nil)
        expect(state.expiresAt).to.equal(nil)
        expect(state.cooldownEndTime).to.equal(nil)
      end)
    end)

    describe("activate", function()
      it("should activate shield successfully", function()
        local state = AreaShield.createDefaultState()
        local result = AreaShield.activate(state, 1000)

        expect(result.success).to.equal(true)
        expect(state.isActive).to.equal(true)
        expect(state.activatedTime).to.equal(1000)
        expect(state.expiresAt).to.be.ok()
      end)

      it("should not activate while already active", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        local result = AreaShield.activate(state, 1001)

        expect(result.success).to.equal(false)
      end)

      it("should not activate during cooldown", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        AreaShield.deactivate(state)
        local result = AreaShield.activate(state, 1001)

        expect(result.success).to.equal(false)
      end)
    end)

    describe("isActive", function()
      it("should return false for default state", function()
        local state = AreaShield.createDefaultState()
        expect(AreaShield.isActive(state, 0)).to.equal(false)
      end)

      it("should return true when activated", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        expect(AreaShield.isActive(state, 1000)).to.equal(true)
      end)

      it("should return false after expiration", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        -- Shield expires after 60 seconds
        expect(AreaShield.isActive(state, 1100)).to.equal(false)
      end)
    end)

    describe("getRemainingDuration", function()
      it("should return 0 for inactive shield", function()
        local state = AreaShield.createDefaultState()
        expect(AreaShield.getRemainingDuration(state, 0)).to.equal(0)
      end)

      it("should return correct remaining time", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        local remaining = AreaShield.getRemainingDuration(state, 1030)
        expect(remaining).to.equal(30) -- 60 - 30 = 30
      end)
    end)

    describe("canPlayerEnter", function()
      it("should allow owner entry always", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        expect(AreaShield.canPlayerEnter(state, true, 1000)).to.equal(true)
      end)

      it("should block non-owners when active", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        expect(AreaShield.canPlayerEnter(state, false, 1000)).to.equal(false)
      end)

      it("should allow non-owners when inactive", function()
        local state = AreaShield.createDefaultState()
        expect(AreaShield.canPlayerEnter(state, false, 1000)).to.equal(true)
      end)
    end)

    describe("canPredatorSpawn", function()
      it("should allow spawns when inactive", function()
        local state = AreaShield.createDefaultState()
        expect(AreaShield.canPredatorSpawn(state, 0)).to.equal(true)
      end)

      it("should block spawns when active", function()
        local state = AreaShield.createDefaultState()
        AreaShield.activate(state, 1000)
        expect(AreaShield.canPredatorSpawn(state, 1000)).to.equal(false)
      end)
    end)

    describe("getConstants", function()
      it("should return shield constants", function()
        local constants = AreaShield.getConstants()
        expect(constants.shieldDuration).to.equal(60)
        expect(constants.shieldCooldown).to.equal(300)
      end)
    end)

    describe("validate", function()
      it("should validate correct state", function()
        local state = AreaShield.createDefaultState()
        expect(AreaShield.validate(state)).to.equal(true)
      end)

      it("should reject invalid state", function()
        expect(AreaShield.validate(nil)).to.equal(false)
        expect(AreaShield.validate({})).to.equal(false)
        expect(AreaShield.validate({ isActive = "not a boolean" })).to.equal(false)
      end)
    end)
  end)
end
