--[[
	StoreUI.spec.lua
	Tests for the Fusion-based StoreUI component.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Players = game:GetService("Players")

  local StoreUI

  beforeEach(function()
    -- Fresh require for each test
    StoreUI = require(script.Parent.StoreUI)

    -- Ensure clean state
    if StoreUI.isCreated() then
      StoreUI.destroy()
    end
  end)

  afterEach(function()
    -- Cleanup after each test
    if StoreUI and StoreUI.isCreated() then
      StoreUI.destroy()
    end
  end)

  describe("StoreUI", function()
    describe("create", function()
      it("should create the UI successfully", function()
        local success = StoreUI.create()
        expect(success).to.equal(true)
        expect(StoreUI.isCreated()).to.equal(true)
      end)

      it("should return false if already created", function()
        StoreUI.create()
        local success = StoreUI.create()
        expect(success).to.equal(false)
      end)

      it("should accept props", function()
        local callCount = 0
        local success = StoreUI.create({
          onEggPurchase = function()
            callCount = callCount + 1
          end,
        })
        expect(success).to.equal(true)
      end)
    end)

    describe("destroy", function()
      it("should destroy the UI successfully", function()
        StoreUI.create()
        expect(StoreUI.isCreated()).to.equal(true)

        StoreUI.destroy()
        expect(StoreUI.isCreated()).to.equal(false)
      end)

      it("should handle destroy when not created", function()
        expect(function()
          StoreUI.destroy()
        end).never.to.throw()
      end)
    end)

    describe("visibility", function()
      beforeEach(function()
        StoreUI.create()
      end)

      it("should start closed", function()
        expect(StoreUI.isOpen()).to.equal(false)
        expect(StoreUI.isVisible()).to.equal(false)
      end)

      it("should open when open() is called", function()
        StoreUI.open()
        expect(StoreUI.isOpen()).to.equal(true)
      end)

      it("should close when close() is called", function()
        StoreUI.open()
        StoreUI.close()
        expect(StoreUI.isOpen()).to.equal(false)
      end)

      it("should toggle visibility", function()
        expect(StoreUI.isOpen()).to.equal(false)

        StoreUI.toggle()
        expect(StoreUI.isOpen()).to.equal(true)

        StoreUI.toggle()
        expect(StoreUI.isOpen()).to.equal(false)
      end)

      it("should set visibility directly", function()
        StoreUI.setVisible(true)
        expect(StoreUI.isOpen()).to.equal(true)

        StoreUI.setVisible(false)
        expect(StoreUI.isOpen()).to.equal(false)
      end)

      it("should call onVisibilityChanged callback", function()
        local visibilityChanges = {}

        StoreUI.destroy()
        StoreUI.create({
          onVisibilityChanged = function(visible)
            table.insert(visibilityChanges, visible)
          end,
        })

        StoreUI.open()
        StoreUI.close()

        expect(#visibilityChanges).to.equal(2)
        expect(visibilityChanges[1]).to.equal(true)
        expect(visibilityChanges[2]).to.equal(false)
      end)
    end)

    describe("tabs", function()
      beforeEach(function()
        StoreUI.create()
      end)

      it("should default to eggs tab", function()
        expect(StoreUI.getCurrentTab()).to.equal("eggs")
      end)

      it("should change tab", function()
        StoreUI.setTab("supplies")
        expect(StoreUI.getCurrentTab()).to.equal("supplies")

        StoreUI.setTab("powerups")
        expect(StoreUI.getCurrentTab()).to.equal("powerups")

        StoreUI.setTab("weapons")
        expect(StoreUI.getCurrentTab()).to.equal("weapons")
      end)
    end)

    describe("data updates", function()
      beforeEach(function()
        StoreUI.create()
      end)

      it("should handle updateMoney (no-op in Fusion)", function()
        expect(function()
          StoreUI.updateMoney(1000)
        end).never.to.throw()
      end)

      it("should update owned weapons", function()
        expect(function()
          StoreUI.updateOwnedWeapons({ "BaseballBat", "Shotgun" })
        end).never.to.throw()
      end)

      it("should handle nil owned weapons", function()
        expect(function()
          StoreUI.updateOwnedWeapons(nil)
        end).never.to.throw()
      end)

      it("should update active power-ups", function()
        expect(function()
          StoreUI.updateActivePowerUps({
            EarningsBoost = os.time() + 300,
          })
        end).never.to.throw()
      end)

      it("should handle nil active power-ups", function()
        expect(function()
          StoreUI.updateActivePowerUps(nil)
        end).never.to.throw()
      end)

      it("should refresh inventory", function()
        expect(function()
          StoreUI.refreshInventory()
        end).never.to.throw()
      end)

      it("should update item stock", function()
        expect(function()
          StoreUI.updateItemStock("egg", "BasicEgg", 5)
        end).never.to.throw()
      end)
    end)

    describe("legacy callbacks", function()
      it("should set purchase callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onPurchase(function(eggType, quantity)
            -- Callback handler
          end)
        end).never.to.throw()
      end)

      it("should set replenish callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onReplenish(function()
            -- Callback handler
          end)
        end).never.to.throw()
      end)

      it("should set robux purchase callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onRobuxPurchase(function(itemType, itemId)
            -- Callback handler
          end)
        end).never.to.throw()
      end)

      it("should set power-up purchase callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onPowerUpPurchase(function(powerUpId)
            -- Callback handler
          end)
        end).never.to.throw()
      end)

      it("should set trap purchase callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onTrapPurchase(function(trapType)
            -- Callback handler
          end)
        end).never.to.throw()
      end)

      it("should set weapon purchase callback", function()
        StoreUI.create()
        expect(function()
          StoreUI.onWeaponPurchase(function(weaponType)
            -- Callback handler
          end)
        end).never.to.throw()
      end)
    end)

    describe("UI structure", function()
      it("should create ScreenGui in PlayerGui", function()
        StoreUI.create()

        local player = Players.LocalPlayer
        if player then
          local playerGui = player:FindFirstChild("PlayerGui")
          if playerGui then
            local storeGui = playerGui:FindFirstChild("StoreUI")
            expect(storeGui).to.be.ok()
            expect(storeGui:IsA("ScreenGui")).to.equal(true)
          end
        end
      end)

      it("should have MainFrame", function()
        StoreUI.create()

        local player = Players.LocalPlayer
        if player then
          local playerGui = player:FindFirstChild("PlayerGui")
          if playerGui then
            local storeGui = playerGui:FindFirstChild("StoreUI")
            if storeGui then
              local mainFrame = storeGui:FindFirstChild("MainFrame")
              expect(mainFrame).to.be.ok()
            end
          end
        end
      end)
    end)
  end)
end
