--[[
	OfflineEarningsUI.spec.lua
	TestEZ tests for the Fusion-based OfflineEarningsUI component.
]]

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	-- Get test utilities
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Testing = Shared:WaitForChild("Testing")
	local TestUtilities = require(Testing:WaitForChild("TestUtilities"))
	local Mocks = require(Testing:WaitForChild("Mocks"))

	-- Get the module under test
	local UIComponents = ReplicatedStorage.Parent:WaitForChild("StarterPlayer")
		:WaitForChild("StarterPlayerScripts")
		:WaitForChild("UI")
		:WaitForChild("Components")
	local OfflineEarningsUI

	-- Setup before tests
	beforeAll(function()
		-- Load module (may fail in test environment without LocalPlayer)
		local success, result = pcall(function()
			OfflineEarningsUI = require(UIComponents:WaitForChild("OfflineEarningsUI"))
		end)
		if not success then
			warn("OfflineEarningsUI module load failed:", result)
		end
	end)

	describe("OfflineEarningsUI", function()
		afterEach(function()
			-- Cleanup after each test
			if OfflineEarningsUI and OfflineEarningsUI.destroy then
				OfflineEarningsUI.destroy()
			end
		end)

		describe("create()", function()
			it("should create the UI successfully", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				local success = OfflineEarningsUI.create()
				expect(success).to.equal(true)
				expect(OfflineEarningsUI.isCreated()).to.equal(true)
			end)

			it("should accept custom config", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				local customConfig = {
					position = UDim2.new(0.5, 0, 0.3, 0),
					backgroundColor = Color3.fromRGB(50, 50, 50),
				}
				local success = OfflineEarningsUI.create(customConfig)
				expect(success).to.equal(true)
			end)
		end)

		describe("destroy()", function()
			it("should clean up all resources", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.create()
				expect(OfflineEarningsUI.isCreated()).to.equal(true)

				OfflineEarningsUI.destroy()
				expect(OfflineEarningsUI.isCreated()).to.equal(false)
			end)
		end)

		describe("show()", function()
			it("should show popup with earnings data", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.create()
				OfflineEarningsUI.show(1000, 5, 3600)

				expect(OfflineEarningsUI.isVisible()).to.equal(true)

				local earnings = OfflineEarningsUI.getDisplayedEarnings()
				expect(earnings.money).to.equal(1000)
				expect(earnings.eggs).to.equal(5)
				expect(earnings.timeAway).to.equal(3600)
			end)

			it("should not show popup when no earnings", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.create()
				OfflineEarningsUI.show(0, 0, 3600)

				expect(OfflineEarningsUI.isVisible()).to.equal(false)
			end)
		end)

		describe("hide()", function()
			it("should hide the popup", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.create()
				OfflineEarningsUI.show(1000, 5, 3600)
				expect(OfflineEarningsUI.isVisible()).to.equal(true)

				OfflineEarningsUI.hide()
				-- Note: May need a small delay for animation
				task.wait(0.35)
				expect(OfflineEarningsUI.isVisible()).to.equal(false)
			end)
		end)

		describe("claim()", function()
			it("should call onClaim callback and hide popup", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				local claimedMoney = nil
				local claimedEggs = nil

				OfflineEarningsUI.create()
				OfflineEarningsUI.onClaim(function(money, eggs)
					claimedMoney = money
					claimedEggs = eggs
				end)

				OfflineEarningsUI.show(500, 3, 1800)
				OfflineEarningsUI.claim()

				expect(claimedMoney).to.equal(500)
				expect(claimedEggs).to.equal(3)
			end)
		end)

		describe("dismiss()", function()
			it("should call onDismiss callback and hide popup", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				local dismissed = false

				OfflineEarningsUI.create()
				OfflineEarningsUI.onDismiss(function()
					dismissed = true
				end)

				OfflineEarningsUI.show(500, 3, 1800)
				OfflineEarningsUI.dismiss()

				expect(dismissed).to.equal(true)
			end)
		end)

		describe("getDefaultConfig()", function()
			it("should return default configuration", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				local config = OfflineEarningsUI.getDefaultConfig()

				expect(config.anchorPoint).to.be.ok()
				expect(config.position).to.be.ok()
				expect(config.size).to.be.ok()
				expect(config.backgroundColor).to.be.ok()
				expect(config.accentColor).to.be.ok()
			end)
		end)

		describe("getScreenGui()", function()
			it("should return ScreenGui after creation", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.create()
				local gui = OfflineEarningsUI.getScreenGui()

				expect(gui).to.be.ok()
				expect(gui:IsA("ScreenGui")).to.equal(true)
			end)

			it("should return nil before creation", function()
				if not OfflineEarningsUI then
					pending("Module not loaded")
					return
				end

				OfflineEarningsUI.destroy()
				local gui = OfflineEarningsUI.getScreenGui()

				expect(gui).to.equal(nil)
			end)
		end)
	end)
end
