--[[
	ChickenService.spec.lua
	TestEZ tests for ChickenService
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local ServerScriptService = game:GetService("ServerScriptService")

  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local Knit = require(Packages:WaitForChild("Knit"))

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))
  local Chicken = require(Shared:WaitForChild("Chicken"))

  -- Get services after Knit has started
  local ChickenService
  local PlayerDataService

  beforeAll(function()
    -- These will only work if Knit has been started
    local success = pcall(function()
      ChickenService = Knit.GetService("ChickenService")
      PlayerDataService = Knit.GetService("PlayerDataService")
    end)
    if not success then
      -- Skip tests if Knit isn't running
      warn("[ChickenService.spec] Knit not started, tests will be limited")
    end
  end)

  describe("ChickenService", function()
    describe("initialization", function()
      it("should have required methods", function()
        -- Test that the module exists and can be required
        local ChickenServiceModule =
          require(ServerScriptService:WaitForChild("Services"):WaitForChild("ChickenService"))
        expect(ChickenServiceModule).to.be.ok()
        expect(ChickenServiceModule.Name).to.equal("ChickenService")
      end)

      it("should have Client table with signals", function()
        local ChickenServiceModule =
          require(ServerScriptService:WaitForChild("Services"):WaitForChild("ChickenService"))
        expect(ChickenServiceModule.Client).to.be.ok()
        expect(ChickenServiceModule.Client.ChickenPlaced).to.be.ok()
        expect(ChickenServiceModule.Client.ChickenPickedUp).to.be.ok()
        expect(ChickenServiceModule.Client.ChickenMoved).to.be.ok()
        expect(ChickenServiceModule.Client.ChickenSold).to.be.ok()
        expect(ChickenServiceModule.Client.MoneyCollected).to.be.ok()
      end)

      it("should have server-side signals", function()
        local ChickenServiceModule =
          require(ServerScriptService:WaitForChild("Services"):WaitForChild("ChickenService"))
        expect(ChickenServiceModule.ChickenAdded).to.be.ok()
        expect(ChickenServiceModule.ChickenRemoved).to.be.ok()
        expect(ChickenServiceModule.MoneyGenerated).to.be.ok()
      end)
    end)

    describe("PlaceChicken logic", function()
      it("should validate chicken limit", function()
        -- Test using ChickenPlacement directly (doesn't require Knit)
        local playerData = PlayerData.createDefault()

        -- Fill up to limit
        local limit = ChickenPlacement.getChickenLimitInfo(playerData).max
        for i = 1, limit do
          local chicken = Chicken.create("Rir", "Common")
          chicken.id = "test-chicken-" .. i
          table.insert(playerData.placedChickens, chicken)
        end

        expect(ChickenPlacement.isAtChickenLimit(playerData)).to.equal(true)
      end)

      it("should allow placement when under limit", function()
        local playerData = PlayerData.createDefault()
        expect(ChickenPlacement.isAtChickenLimit(playerData)).to.equal(false)
      end)
    end)

    describe("ChickenPlacement integration", function()
      it("should place chicken from inventory", function()
        local playerData = PlayerData.createDefault()

        -- Add a chicken to inventory
        local chicken = Chicken.create("Rir", "Common")
        table.insert(playerData.inventory.chickens, chicken)
        local chickenId = chicken.id

        -- Place it
        local result = ChickenPlacement.placeChickenFreeRoaming(playerData, chickenId)
        expect(result.success).to.equal(true)
        expect(#playerData.inventory.chickens).to.equal(0)
        expect(#playerData.placedChickens).to.equal(1)
      end)

      it("should pickup chicken to inventory", function()
        local playerData = PlayerData.createDefault()

        -- Add a chicken to inventory and place it
        local chicken = Chicken.create("Rir", "Common")
        table.insert(playerData.inventory.chickens, chicken)
        local chickenId = chicken.id
        ChickenPlacement.placeChickenFreeRoaming(playerData, chickenId)

        -- Pick it up
        local result = ChickenPlacement.pickupChicken(playerData, chickenId)
        expect(result.success).to.equal(true)
        expect(#playerData.inventory.chickens).to.equal(1)
        expect(#playerData.placedChickens).to.equal(0)
      end)

      it("should fail to place non-existent chicken", function()
        local playerData = PlayerData.createDefault()
        local result = ChickenPlacement.placeChickenFreeRoaming(playerData, "fake-id")
        expect(result.success).to.equal(false)
      end)
    end)

    describe("MoneyCollection integration", function()
      it("should collect money from chicken with accumulated money", function()
        local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
        local playerData = PlayerData.createDefault()

        -- Add a placed chicken with accumulated money
        local chicken = Chicken.create("Rir", "Common")
        chicken.accumulatedMoney = 100
        table.insert(playerData.placedChickens, chicken)

        local result = MoneyCollection.collect(playerData, chicken.id)
        expect(result.success).to.equal(true)
        expect(result.amountCollected).to.equal(100)
      end)

      it("should collect all money from multiple chickens", function()
        local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
        local playerData = PlayerData.createDefault()

        -- Add multiple placed chickens with accumulated money
        for i = 1, 3 do
          local chicken = Chicken.create("Rir", "Common")
          chicken.id = "collect-test-" .. i
          chicken.accumulatedMoney = 50
          table.insert(playerData.placedChickens, chicken)
        end

        local result = MoneyCollection.collectAll(playerData)
        expect(result.success).to.equal(true)
        expect(result.totalCollected).to.equal(150)
      end)
    end)

    describe("Store.sellChicken integration", function()
      it("should sell chicken from inventory", function()
        local Store = require(Shared:WaitForChild("Store"))
        local playerData = PlayerData.createDefault()

        -- Add a chicken to inventory
        local chicken = Chicken.create("Rir", "Common")
        table.insert(playerData.inventory.chickens, chicken)
        local initialMoney = playerData.money

        local result = Store.sellChicken(playerData, chicken.id)
        expect(result.success).to.equal(true)
        expect(#playerData.inventory.chickens).to.equal(0)
        expect(playerData.money).to.be.gt(initialMoney)
      end)

      it("should sell chicken from placed chickens", function()
        local Store = require(Shared:WaitForChild("Store"))
        local playerData = PlayerData.createDefault()

        -- Add a placed chicken
        local chicken = Chicken.create("Rir", "Common")
        table.insert(playerData.placedChickens, chicken)
        local initialMoney = playerData.money

        local result = Store.sellChicken(playerData, chicken.id)
        expect(result.success).to.equal(true)
        expect(#playerData.placedChickens).to.equal(0)
        expect(playerData.money).to.be.gt(initialMoney)
      end)

      it("should fail to sell non-existent chicken", function()
        local Store = require(Shared:WaitForChild("Store"))
        local playerData = PlayerData.createDefault()

        local result = Store.sellChicken(playerData, "fake-id")
        expect(result.success).to.equal(false)
      end)
    end)
  end)
end
