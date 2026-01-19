--[[
	StoreController Tests
	Tests for the client-side store controller.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

  describe("StoreController", function()
    -- Note: Full integration tests require Knit to be running.
    -- These tests verify the module structure and signal setup.

    local StoreController

    beforeAll(function()
      -- In test environment, we just verify the module loads
      StoreController = require(script.Parent.StoreController)
    end)

    describe("Module Structure", function()
      it("should have Name property", function()
        expect(StoreController.Name).to.equal("StoreController")
      end)

      it("should have KnitInit method", function()
        expect(type(StoreController.KnitInit)).to.equal("function")
      end)

      it("should have KnitStart method", function()
        expect(type(StoreController.KnitStart)).to.equal("function")
      end)
    end)

    describe("GoodSignal Events", function()
      it("should have StoreReplenished signal", function()
        expect(StoreController.StoreReplenished).to.be.ok()
        expect(type(StoreController.StoreReplenished.Connect)).to.equal("function")
      end)

      it("should have ItemPurchased signal", function()
        expect(StoreController.ItemPurchased).to.be.ok()
        expect(type(StoreController.ItemPurchased.Connect)).to.equal("function")
      end)

      it("should have ItemSold signal", function()
        expect(StoreController.ItemSold).to.be.ok()
        expect(type(StoreController.ItemSold.Connect)).to.equal("function")
      end)

      it("should have StockUpdated signal", function()
        expect(StoreController.StockUpdated).to.be.ok()
        expect(type(StoreController.StockUpdated.Connect)).to.equal("function")
      end)
    end)

    describe("Query Methods", function()
      it("should have GetStoreInventory method", function()
        expect(type(StoreController.GetStoreInventory)).to.equal("function")
      end)

      it("should have GetAvailableItems method", function()
        expect(type(StoreController.GetAvailableItems)).to.equal("function")
      end)

      it("should have GetCachedInventory method", function()
        expect(type(StoreController.GetCachedInventory)).to.equal("function")
      end)

      it("should have GetCachedAvailableItems method", function()
        expect(type(StoreController.GetCachedAvailableItems)).to.equal("function")
      end)

      it("should have GetTimeUntilReplenish method", function()
        expect(type(StoreController.GetTimeUntilReplenish)).to.equal("function")
      end)

      it("should have InvalidateCache method", function()
        expect(type(StoreController.InvalidateCache)).to.equal("function")
      end)
    end)

    describe("Buy Methods", function()
      it("should have BuyEgg method", function()
        expect(type(StoreController.BuyEgg)).to.equal("function")
      end)

      it("should have BuyChicken method", function()
        expect(type(StoreController.BuyChicken)).to.equal("function")
      end)

      it("should have BuyTrap method", function()
        expect(type(StoreController.BuyTrap)).to.equal("function")
      end)

      it("should have BuyWeapon method", function()
        expect(type(StoreController.BuyWeapon)).to.equal("function")
      end)
    end)

    describe("Sell Methods", function()
      it("should have SellEgg method", function()
        expect(type(StoreController.SellEgg)).to.equal("function")
      end)

      it("should have SellChicken method", function()
        expect(type(StoreController.SellChicken)).to.equal("function")
      end)

      it("should have SellPredator method", function()
        expect(type(StoreController.SellPredator)).to.equal("function")
      end)

      it("should have SellTrap method", function()
        expect(type(StoreController.SellTrap)).to.equal("function")
      end)

      it("should have SellWeapon method", function()
        expect(type(StoreController.SellWeapon)).to.equal("function")
      end)
    end)

    describe("Error Handling", function()
      it("should return safe defaults when service unavailable", function()
        -- Before KnitStart, service is nil
        local inventory = StoreController:GetCachedInventory()
        expect(inventory).to.equal(nil)

        local available = StoreController:GetCachedAvailableItems()
        expect(available).to.equal(nil)
      end)
    end)
  end)
end
