--[[
	CombatController.spec.lua
	Tests for the CombatController client-side Knit controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local Knit = require(Packages:WaitForChild("Knit"))

  -- Get the controller (after Knit starts)
  local CombatController

  describe("CombatController", function()
    beforeAll(function()
      -- Wait for Knit to be ready and get controller
      CombatController = Knit.GetController("CombatController")
    end)

    describe("Initialization", function()
      it("should exist", function()
        expect(CombatController).to.be.ok()
      end)

      it("should have correct name", function()
        expect(CombatController.Name).to.equal("CombatController")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have WeaponEquipped signal", function()
        expect(CombatController.WeaponEquipped).to.be.ok()
        expect(CombatController.WeaponEquipped.Fire).to.be.ok()
        expect(CombatController.WeaponEquipped.Connect).to.be.ok()
      end)

      it("should have WeaponUnequipped signal", function()
        expect(CombatController.WeaponUnequipped).to.be.ok()
        expect(CombatController.WeaponUnequipped.Fire).to.be.ok()
      end)

      it("should have WeaponSwung signal", function()
        expect(CombatController.WeaponSwung).to.be.ok()
        expect(CombatController.WeaponSwung.Fire).to.be.ok()
      end)

      it("should have DamageDealt signal", function()
        expect(CombatController.DamageDealt).to.be.ok()
        expect(CombatController.DamageDealt.Fire).to.be.ok()
      end)

      it("should have DamageTaken signal", function()
        expect(CombatController.DamageTaken).to.be.ok()
        expect(CombatController.DamageTaken.Fire).to.be.ok()
      end)

      it("should have KnockbackApplied signal", function()
        expect(CombatController.KnockbackApplied).to.be.ok()
        expect(CombatController.KnockbackApplied.Fire).to.be.ok()
      end)

      it("should have ShieldActivated signal", function()
        expect(CombatController.ShieldActivated).to.be.ok()
        expect(CombatController.ShieldActivated.Fire).to.be.ok()
      end)

      it("should have ShieldDeactivated signal", function()
        expect(CombatController.ShieldDeactivated).to.be.ok()
        expect(CombatController.ShieldDeactivated.Fire).to.be.ok()
      end)

      it("should have ShieldExpired signal", function()
        expect(CombatController.ShieldExpired).to.be.ok()
        expect(CombatController.ShieldExpired.Fire).to.be.ok()
      end)

      it("should have HealthChanged signal", function()
        expect(CombatController.HealthChanged).to.be.ok()
        expect(CombatController.HealthChanged.Fire).to.be.ok()
      end)

      it("should have Incapacitated signal", function()
        expect(CombatController.Incapacitated).to.be.ok()
        expect(CombatController.Incapacitated.Fire).to.be.ok()
      end)

      it("should have CombatStateChanged signal", function()
        expect(CombatController.CombatStateChanged).to.be.ok()
        expect(CombatController.CombatStateChanged.Fire).to.be.ok()
      end)
    end)

    describe("Weapon Methods", function()
      it("should have EquipWeapon method", function()
        expect(CombatController.EquipWeapon).to.be.ok()
        expect(typeof(CombatController.EquipWeapon)).to.equal("function")
      end)

      it("should have GetEquippedWeapon method", function()
        expect(CombatController.GetEquippedWeapon).to.be.ok()
        expect(typeof(CombatController.GetEquippedWeapon)).to.equal("function")
      end)

      it("should have GetCachedEquippedWeapon method", function()
        expect(CombatController.GetCachedEquippedWeapon).to.be.ok()
        expect(typeof(CombatController.GetCachedEquippedWeapon)).to.equal("function")
      end)

      it("should have GetWeaponConfig method", function()
        expect(CombatController.GetWeaponConfig).to.be.ok()
        expect(typeof(CombatController.GetWeaponConfig)).to.equal("function")
      end)

      it("should have GetAllWeaponConfigs method", function()
        expect(CombatController.GetAllWeaponConfigs).to.be.ok()
        expect(typeof(CombatController.GetAllWeaponConfigs)).to.equal("function")
      end)

      it("should have GetPurchasableWeapons method", function()
        expect(CombatController.GetPurchasableWeapons).to.be.ok()
        expect(typeof(CombatController.GetPurchasableWeapons)).to.equal("function")
      end)

      it("should have GetOwnedWeapons method", function()
        expect(CombatController.GetOwnedWeapons).to.be.ok()
        expect(typeof(CombatController.GetOwnedWeapons)).to.equal("function")
      end)

      it("should have PlayerOwnsWeapon method", function()
        expect(CombatController.PlayerOwnsWeapon).to.be.ok()
        expect(typeof(CombatController.PlayerOwnsWeapon)).to.equal("function")
      end)
    end)

    describe("Attack Methods", function()
      it("should have Attack method", function()
        expect(CombatController.Attack).to.be.ok()
        expect(typeof(CombatController.Attack)).to.equal("function")
      end)
    end)

    describe("Shield Methods", function()
      it("should have ActivateShield method", function()
        expect(CombatController.ActivateShield).to.be.ok()
        expect(typeof(CombatController.ActivateShield)).to.equal("function")
      end)

      it("should have GetShieldStatus method", function()
        expect(CombatController.GetShieldStatus).to.be.ok()
        expect(typeof(CombatController.GetShieldStatus)).to.equal("function")
      end)
    end)

    describe("Combat State Methods", function()
      it("should have CanMove method", function()
        expect(CombatController.CanMove).to.be.ok()
        expect(typeof(CombatController.CanMove)).to.equal("function")
      end)

      it("should return boolean from CanMove", function()
        local canMove = CombatController:CanMove()
        expect(typeof(canMove)).to.equal("boolean")
      end)

      it("should have GetCombatState method", function()
        expect(CombatController.GetCombatState).to.be.ok()
        expect(typeof(CombatController.GetCombatState)).to.equal("function")
      end)

      it("should have GetHealthDisplayInfo method", function()
        expect(CombatController.GetHealthDisplayInfo).to.be.ok()
        expect(typeof(CombatController.GetHealthDisplayInfo)).to.equal("function")
      end)

      it("should have GetCombatConstants method", function()
        expect(CombatController.GetCombatConstants).to.be.ok()
        expect(typeof(CombatController.GetCombatConstants)).to.equal("function")
      end)

      it("should have GetCachedCombatState method", function()
        expect(CombatController.GetCachedCombatState).to.be.ok()
        expect(typeof(CombatController.GetCachedCombatState)).to.equal("function")
      end)
    end)

    describe("Default Return Values", function()
      it("should return safe defaults from GetCombatConstants when service unavailable", function()
        local constants = CombatController:GetCombatConstants()
        expect(typeof(constants)).to.equal("table")
      end)

      it("should return true from CanMove by default", function()
        -- When service is unavailable, player should be able to move
        local canMove = CombatController:CanMove()
        expect(canMove).to.equal(true)
      end)
    end)
  end)
end
