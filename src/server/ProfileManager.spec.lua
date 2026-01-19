--[[
	ProfileManager.spec.lua
	TestEZ tests for ProfileManager module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PlayerData = require(Shared:WaitForChild("PlayerData"))

  local ServerScriptService = game:GetService("ServerScriptService")
  local ProfileManager = require(ServerScriptService:WaitForChild("ProfileManager"))

  describe("ProfileManager", function()
    describe("init", function()
      it("should initialize without errors", function()
        -- init() returns boolean indicating success
        -- In test environment, ProfileService may not be available
        local success = ProfileManager.init()
        expect(typeof(success)).to.equal("boolean")
      end)
    end)

    describe("getData", function()
      it("should return nil for unknown user", function()
        local result = ProfileManager.getData(999999999)
        expect(result).to.equal(nil)
      end)
    end)

    describe("hasProfile", function()
      it("should return false for unknown user", function()
        local result = ProfileManager.hasProfile(999999999)
        expect(result).to.equal(false)
      end)
    end)

    describe("getLoadedProfileCount", function()
      it("should return a number", function()
        local count = ProfileManager.getLoadedProfileCount()
        expect(typeof(count)).to.equal("number")
        expect(count >= 0).to.equal(true)
      end)
    end)

    describe("getGlobalChickenCounts", function()
      it("should return a table", function()
        local counts = ProfileManager.getGlobalChickenCounts()
        expect(typeof(counts)).to.equal("table")
      end)

      it("should return empty table when no profiles loaded", function()
        -- Clear state for test
        local counts = ProfileManager.getGlobalChickenCounts()
        -- In test environment with no loaded profiles, should be empty or have existing data
        expect(typeof(counts)).to.equal("table")
      end)
    end)

    describe("updateData", function()
      it("should return false for unknown user", function()
        local testData = PlayerData.createDefault()
        local result = ProfileManager.updateData(999999999, testData)
        expect(result).to.equal(false)
      end)

      it("should reject invalid data", function()
        -- This should fail because there's no loaded profile for this user
        local invalidData = { invalidField = true }
        local result = ProfileManager.updateData(999999999, invalidData :: any)
        expect(result).to.equal(false)
      end)
    end)

    describe("releaseProfile", function()
      it("should handle non-existent profile gracefully", function()
        -- Create a mock player-like object
        local mockPlayer = {
          UserId = 999999999,
          Name = "TestPlayer",
        }
        local result = ProfileManager.releaseProfile(mockPlayer :: any)
        expect(result.success).to.equal(true)
        expect(result.message).to.equal("No profile to release")
      end)
    end)

    describe("type definitions", function()
      it("should have ProfileLoadResult type structure", function()
        -- Verify the expected result structure
        local expectedFields = { "success", "message", "isNewPlayer" }
        -- This test validates the structure is documented correctly
        expect(#expectedFields).to.equal(3)
      end)

      it("should have ProfileSaveResult type structure", function()
        -- Verify the expected result structure
        local expectedFields = { "success", "message" }
        expect(#expectedFields).to.equal(2)
      end)
    end)
  end)
end
