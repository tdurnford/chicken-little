--[[
	ChickenPlacement.spec.lua
	TestEZ tests for ChickenPlacement module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))

  -- Helper function to create mock player data
  local function createMockPlayerData()
    return {
      inventory = {
        chickens = {},
        eggs = {},
      },
      placedChickens = {},
      currency = 0,
    }
  end

  -- Helper function to create a mock chicken
  local function createMockChicken(id, chickenType, rarity, spotIndex)
    return {
      id = id or "chicken-" .. tostring(math.random(1000, 9999)),
      chickenType = chickenType or "BasicChick",
      rarity = rarity or "Common",
      accumulatedMoney = 0,
      lastEggTime = 0,
      spotIndex = spotIndex,
    }
  end

  describe("ChickenPlacement", function()
    describe("getMaxSpots", function()
      it("should return the maximum number of coop spots", function()
        local maxSpots = ChickenPlacement.getMaxSpots()
        expect(maxSpots).to.equal(12)
      end)

      it("should return a positive number", function()
        expect(ChickenPlacement.getMaxSpots() > 0).to.equal(true)
      end)
    end)

    describe("isValidSpot", function()
      it("should return true for valid spot indices (1-12)", function()
        for i = 1, 12 do
          expect(ChickenPlacement.isValidSpot(i)).to.equal(true)
        end
      end)

      it("should return false for spot index 0", function()
        expect(ChickenPlacement.isValidSpot(0)).to.equal(false)
      end)

      it("should return false for negative spot indices", function()
        expect(ChickenPlacement.isValidSpot(-1)).to.equal(false)
        expect(ChickenPlacement.isValidSpot(-5)).to.equal(false)
      end)

      it("should return false for spot indices above 12", function()
        expect(ChickenPlacement.isValidSpot(13)).to.equal(false)
        expect(ChickenPlacement.isValidSpot(100)).to.equal(false)
      end)

      it("should return false for non-integer values", function()
        expect(ChickenPlacement.isValidSpot(1.5)).to.equal(false)
        expect(ChickenPlacement.isValidSpot(5.7)).to.equal(false)
      end)

      it("should return false for non-number values", function()
        expect(ChickenPlacement.isValidSpot("1" :: any)).to.equal(false)
        expect(ChickenPlacement.isValidSpot(nil :: any)).to.equal(false)
        expect(ChickenPlacement.isValidSpot({} :: any)).to.equal(false)
      end)
    end)

    describe("getOccupiedSpots", function()
      it("should return empty table when no chickens placed", function()
        local playerData = createMockPlayerData()
        local occupied = ChickenPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(0)
      end)

      it("should return occupied spot indices", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 5),
          createMockChicken("c3", "BasicChick", "Common", 10),
        }
        local occupied = ChickenPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(3)
      end)

      it("should not include free-roaming chickens (nil spotIndex)", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", nil),
        }
        local occupied = ChickenPlacement.getOccupiedSpots(playerData)
        expect(#occupied).to.equal(1)
      end)
    end)

    describe("getAvailableSpots", function()
      it("should return all spots when no chickens placed", function()
        local playerData = createMockPlayerData()
        local available = ChickenPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(12)
      end)

      it("should exclude occupied spots", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
        }
        local available = ChickenPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(10)
      end)

      it("should return spots in order", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 2),
        }
        local available = ChickenPlacement.getAvailableSpots(playerData)
        expect(available[1]).to.equal(1)
        expect(available[2]).to.equal(3)
      end)

      it("should return empty table when all spots occupied", function()
        local playerData = createMockPlayerData()
        for i = 1, 12 do
          table.insert(
            playerData.placedChickens,
            createMockChicken("c" .. i, "BasicChick", "Common", i)
          )
        end
        local available = ChickenPlacement.getAvailableSpots(playerData)
        expect(#available).to.equal(0)
      end)
    end)

    describe("isSpotOccupied", function()
      it("should return false for empty spot", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isSpotOccupied(playerData, 1)).to.equal(false)
      end)

      it("should return true for occupied spot", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 5),
        }
        expect(ChickenPlacement.isSpotOccupied(playerData, 5)).to.equal(true)
      end)

      it("should return false for invalid spot index", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isSpotOccupied(playerData, 0)).to.equal(false)
        expect(ChickenPlacement.isSpotOccupied(playerData, 13)).to.equal(false)
        expect(ChickenPlacement.isSpotOccupied(playerData, -1)).to.equal(false)
      end)
    end)

    describe("isSpotAvailable", function()
      it("should return true for empty valid spot", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isSpotAvailable(playerData, 1)).to.equal(true)
      end)

      it("should return false for occupied spot", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 3),
        }
        expect(ChickenPlacement.isSpotAvailable(playerData, 3)).to.equal(false)
      end)

      it("should return false for invalid spot index", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isSpotAvailable(playerData, 0)).to.equal(false)
        expect(ChickenPlacement.isSpotAvailable(playerData, 13)).to.equal(false)
      end)
    end)

    describe("getChickenAtSpot", function()
      it("should return nil for empty spot", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getChickenAtSpot(playerData, 1)).to.equal(nil)
      end)

      it("should return chicken at occupied spot", function()
        local playerData = createMockPlayerData()
        local chicken = createMockChicken("c1", "BasicChick", "Common", 5)
        playerData.placedChickens = { chicken }
        local result = ChickenPlacement.getChickenAtSpot(playerData, 5)
        expect(result).to.be.ok()
        expect(result.id).to.equal("c1")
      end)

      it("should return nil for invalid spot index", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getChickenAtSpot(playerData, 0)).to.equal(nil)
        expect(ChickenPlacement.getChickenAtSpot(playerData, 13)).to.equal(nil)
      end)
    end)

    describe("findChickenInInventory", function()
      it("should return nil when inventory is empty", function()
        local playerData = createMockPlayerData()
        local chicken, index = ChickenPlacement.findChickenInInventory(playerData, "c1")
        expect(chicken).to.equal(nil)
        expect(index).to.equal(nil)
      end)

      it("should find chicken by id", function()
        local playerData = createMockPlayerData()
        local chicken = createMockChicken("c1", "BasicChick", "Common", nil)
        playerData.inventory.chickens = { chicken }
        local found, index = ChickenPlacement.findChickenInInventory(playerData, "c1")
        expect(found).to.be.ok()
        expect(found.id).to.equal("c1")
        expect(index).to.equal(1)
      end)

      it("should return nil for non-existent chicken id", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }
        local chicken, index = ChickenPlacement.findChickenInInventory(playerData, "c2")
        expect(chicken).to.equal(nil)
        expect(index).to.equal(nil)
      end)

      it("should return correct index for multiple chickens", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = {
          createMockChicken("c1", "BasicChick", "Common", nil),
          createMockChicken("c2", "BasicChick", "Common", nil),
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        local _, index = ChickenPlacement.findChickenInInventory(playerData, "c2")
        expect(index).to.equal(2)
      end)
    end)

    describe("findPlacedChicken", function()
      it("should return nil when no chickens placed", function()
        local playerData = createMockPlayerData()
        local chicken, index = ChickenPlacement.findPlacedChicken(playerData, "c1")
        expect(chicken).to.equal(nil)
        expect(index).to.equal(nil)
      end)

      it("should find placed chicken by id", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }
        local found, index = ChickenPlacement.findPlacedChicken(playerData, "c1")
        expect(found).to.be.ok()
        expect(found.id).to.equal("c1")
        expect(index).to.equal(1)
      end)

      it("should return nil for non-existent chicken id", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }
        local chicken, index = ChickenPlacement.findPlacedChicken(playerData, "c2")
        expect(chicken).to.equal(nil)
        expect(index).to.equal(nil)
      end)
    end)

    describe("placeChicken", function()
      it("should place chicken from inventory to spot", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.placeChicken(playerData, "c1", 1)
        expect(result.success).to.equal(true)
        expect(result.chicken).to.be.ok()
        expect(result.chicken.spotIndex).to.equal(1)
        expect(#playerData.inventory.chickens).to.equal(0)
        expect(#playerData.placedChickens).to.equal(1)
      end)

      it("should fail with invalid spot index", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.placeChicken(playerData, "c1", 0)
        expect(result.success).to.equal(false)
        expect(result.message).to.be.ok()
      end)

      it("should fail when spot is occupied", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }
        playerData.placedChickens = { createMockChicken("c2", "BasicChick", "Common", 1) }

        local result = ChickenPlacement.placeChicken(playerData, "c1", 1)
        expect(result.success).to.equal(false)
        expect(result.message).to.be.ok()
      end)

      it("should fail when chicken not in inventory", function()
        local playerData = createMockPlayerData()

        local result = ChickenPlacement.placeChicken(playerData, "c1", 1)
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Chicken not found in inventory")
      end)

      it("should set placedTime on placement", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.placeChicken(playerData, "c1", 1)
        expect(result.success).to.equal(true)
        expect(result.chicken.placedTime).to.be.ok()
      end)
    end)

    describe("placeChickenFreeRoaming", function()
      it("should place chicken as free-roaming (no spotIndex)", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.placeChickenFreeRoaming(playerData, "c1")
        expect(result.success).to.equal(true)
        expect(result.chicken).to.be.ok()
        expect(result.chicken.spotIndex).to.equal(nil)
        expect(#playerData.inventory.chickens).to.equal(0)
        expect(#playerData.placedChickens).to.equal(1)
      end)

      it("should fail when chicken not in inventory", function()
        local playerData = createMockPlayerData()

        local result = ChickenPlacement.placeChickenFreeRoaming(playerData, "c1")
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Chicken not found in inventory")
      end)

      it("should set placedTime on placement", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.placeChickenFreeRoaming(playerData, "c1")
        expect(result.success).to.equal(true)
        expect(result.chicken.placedTime).to.be.ok()
      end)
    end)

    describe("pickupChicken", function()
      it("should pickup placed chicken to inventory", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }

        local result = ChickenPlacement.pickupChicken(playerData, "c1")
        expect(result.success).to.equal(true)
        expect(result.chicken).to.be.ok()
        expect(result.chicken.spotIndex).to.equal(nil)
        expect(#playerData.placedChickens).to.equal(0)
        expect(#playerData.inventory.chickens).to.equal(1)
      end)

      it("should fail when chicken not placed", function()
        local playerData = createMockPlayerData()

        local result = ChickenPlacement.pickupChicken(playerData, "c1")
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Chicken not found in area")
      end)

      it("should pickup free-roaming chicken", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", nil) }

        local result = ChickenPlacement.pickupChicken(playerData, "c1")
        expect(result.success).to.equal(true)
        expect(#playerData.placedChickens).to.equal(0)
        expect(#playerData.inventory.chickens).to.equal(1)
      end)
    end)

    describe("moveChicken", function()
      it("should move chicken to new spot", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }

        local result = ChickenPlacement.moveChicken(playerData, "c1", 5)
        expect(result.success).to.equal(true)
        expect(result.chicken.spotIndex).to.equal(5)
      end)

      it("should fail with invalid spot index", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }

        local result = ChickenPlacement.moveChicken(playerData, "c1", 13)
        expect(result.success).to.equal(false)
      end)

      it("should succeed if already at same spot", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = { createMockChicken("c1", "BasicChick", "Common", 1) }

        local result = ChickenPlacement.moveChicken(playerData, "c1", 1)
        expect(result.success).to.equal(true)
        expect(result.message).to.be.ok()
      end)

      it("should fail when target spot is occupied", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
        }

        local result = ChickenPlacement.moveChicken(playerData, "c1", 2)
        expect(result.success).to.equal(false)
      end)

      it("should fail when chicken not found", function()
        local playerData = createMockPlayerData()

        local result = ChickenPlacement.moveChicken(playerData, "c1", 1)
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Chicken not found in coop")
      end)
    end)

    describe("getInventoryChickenCount", function()
      it("should return 0 for empty inventory", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getInventoryChickenCount(playerData)).to.equal(0)
      end)

      it("should return correct count", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = {
          createMockChicken("c1", "BasicChick", "Common", nil),
          createMockChicken("c2", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.getInventoryChickenCount(playerData)).to.equal(2)
      end)
    end)

    describe("getPlacedChickenCount", function()
      it("should return 0 when no chickens placed", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getPlacedChickenCount(playerData)).to.equal(0)
      end)

      it("should return correct count", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.getPlacedChickenCount(playerData)).to.equal(3)
      end)
    end)

    describe("getTotalChickenCount", function()
      it("should return 0 when no chickens", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getTotalChickenCount(playerData)).to.equal(0)
      end)

      it("should return sum of inventory and placed", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = {
          createMockChicken("c1", "BasicChick", "Common", nil),
        }
        playerData.placedChickens = {
          createMockChicken("c2", "BasicChick", "Common", 1),
          createMockChicken("c3", "BasicChick", "Common", 2),
        }
        expect(ChickenPlacement.getTotalChickenCount(playerData)).to.equal(3)
      end)
    end)

    describe("isCoopFull", function()
      it("should return false when coop is empty", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isCoopFull(playerData)).to.equal(false)
      end)

      it("should return false when spots are available", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
        }
        expect(ChickenPlacement.isCoopFull(playerData)).to.equal(false)
      end)

      it("should return true when all spots occupied", function()
        local playerData = createMockPlayerData()
        for i = 1, 12 do
          table.insert(
            playerData.placedChickens,
            createMockChicken("c" .. i, "BasicChick", "Common", i)
          )
        end
        expect(ChickenPlacement.isCoopFull(playerData)).to.equal(true)
      end)
    end)

    describe("isCoopEmpty", function()
      it("should return true when no chickens placed", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isCoopEmpty(playerData)).to.equal(true)
      end)

      it("should return false when chickens are placed", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
        }
        expect(ChickenPlacement.isCoopEmpty(playerData)).to.equal(false)
      end)

      it("should return false for free-roaming chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.isCoopEmpty(playerData)).to.equal(false)
      end)
    end)

    describe("getFirstAvailableSpot", function()
      it("should return 1 when coop is empty", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getFirstAvailableSpot(playerData)).to.equal(1)
      end)

      it("should return first available spot", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
        }
        expect(ChickenPlacement.getFirstAvailableSpot(playerData)).to.equal(3)
      end)

      it("should return nil when coop is full", function()
        local playerData = createMockPlayerData()
        for i = 1, 12 do
          table.insert(
            playerData.placedChickens,
            createMockChicken("c" .. i, "BasicChick", "Common", i)
          )
        end
        expect(ChickenPlacement.getFirstAvailableSpot(playerData)).to.equal(nil)
      end)
    end)

    describe("validatePlacementState", function()
      it("should return true for valid empty state", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(true)
      end)

      it("should return true for valid state with chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
        }
        playerData.inventory.chickens = {
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(true)
      end)

      it("should return false for duplicate spots", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 1),
        }
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(false)
      end)

      it("should return false for invalid spot index in placed chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 13),
        }
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(false)
      end)

      it("should return false for inventory chicken with spotIndex", function()
        local playerData = createMockPlayerData()
        playerData.inventory.chickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
        }
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(false)
      end)

      it("should return true for free-roaming placed chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", nil),
          createMockChicken("c2", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.validatePlacementState(playerData)).to.equal(true)
      end)
    end)

    describe("getFreeRoamingCount", function()
      it("should return 0 when no placed chickens", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.getFreeRoamingCount(playerData)).to.equal(0)
      end)

      it("should return 0 when all chickens have spots", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
        }
        expect(ChickenPlacement.getFreeRoamingCount(playerData)).to.equal(0)
      end)

      it("should return correct count of free-roaming chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", nil),
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        expect(ChickenPlacement.getFreeRoamingCount(playerData)).to.equal(2)
      end)
    end)

    describe("getFreeRoamingChickens", function()
      it("should return empty table when no placed chickens", function()
        local playerData = createMockPlayerData()
        local freeRoaming = ChickenPlacement.getFreeRoamingChickens(playerData)
        expect(#freeRoaming).to.equal(0)
      end)

      it("should return empty table when all chickens have spots", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
        }
        local freeRoaming = ChickenPlacement.getFreeRoamingChickens(playerData)
        expect(#freeRoaming).to.equal(0)
      end)

      it("should return only free-roaming chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", nil),
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        local freeRoaming = ChickenPlacement.getFreeRoamingChickens(playerData)
        expect(#freeRoaming).to.equal(2)
        expect(freeRoaming[1].id).to.equal("c2")
        expect(freeRoaming[2].id).to.equal("c3")
      end)
    end)

    describe("isAtChickenLimit", function()
      it("should return false when no chickens placed", function()
        local playerData = createMockPlayerData()
        expect(ChickenPlacement.isAtChickenLimit(playerData)).to.equal(false)
      end)

      it("should return false when below limit", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
        }
        expect(ChickenPlacement.isAtChickenLimit(playerData)).to.equal(false)
      end)

      it("should return true when at limit", function()
        local playerData = createMockPlayerData()
        for i = 1, 15 do
          table.insert(
            playerData.placedChickens,
            createMockChicken("c" .. i, "BasicChick", "Common", nil)
          )
        end
        expect(ChickenPlacement.isAtChickenLimit(playerData)).to.equal(true)
      end)
    end)

    describe("getChickenLimitInfo", function()
      it("should return correct info for empty coop", function()
        local playerData = createMockPlayerData()
        local info = ChickenPlacement.getChickenLimitInfo(playerData)
        expect(info.current).to.equal(0)
        expect(info.max).to.equal(15)
        expect(info.remaining).to.equal(15)
        expect(info.isAtLimit).to.equal(false)
      end)

      it("should return correct info with placed chickens", function()
        local playerData = createMockPlayerData()
        playerData.placedChickens = {
          createMockChicken("c1", "BasicChick", "Common", 1),
          createMockChicken("c2", "BasicChick", "Common", 2),
          createMockChicken("c3", "BasicChick", "Common", nil),
        }
        local info = ChickenPlacement.getChickenLimitInfo(playerData)
        expect(info.current).to.equal(3)
        expect(info.max).to.equal(15)
        expect(info.remaining).to.equal(12)
        expect(info.isAtLimit).to.equal(false)
      end)

      it("should return correct info when at limit", function()
        local playerData = createMockPlayerData()
        for i = 1, 15 do
          table.insert(
            playerData.placedChickens,
            createMockChicken("c" .. i, "BasicChick", "Common", nil)
          )
        end
        local info = ChickenPlacement.getChickenLimitInfo(playerData)
        expect(info.current).to.equal(15)
        expect(info.max).to.equal(15)
        expect(info.remaining).to.equal(0)
        expect(info.isAtLimit).to.equal(true)
      end)
    end)
  end)
end
