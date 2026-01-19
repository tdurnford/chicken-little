--[[
	ShieldUI.spec.lua
	Tests for the Fusion ShieldUI component.
]]

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	-- Module under test
	local ShieldUI

	beforeEach(function()
		ShieldUI = require(script.Parent.ShieldUI)
	end)

	afterEach(function()
		pcall(function()
			ShieldUI.destroy()
		end)
	end)

	describe("ShieldUI", function()
		describe("create", function()
			it("should return true on successful creation", function()
				local result = ShieldUI.create()
				expect(result).to.equal(true)
			end)

			it("should set isCreated to true after creation", function()
				expect(ShieldUI.isCreated()).to.equal(false)
				ShieldUI.create()
				expect(ShieldUI.isCreated()).to.equal(true)
			end)

			it("should accept optional props", function()
				local activateCount = 0
				local result = ShieldUI.create({
					onActivate = function()
						activateCount = activateCount + 1
					end,
				})
				expect(result).to.equal(true)
			end)

			it("should accept custom position", function()
				local result = ShieldUI.create({
					position = UDim2.new(0.5, 0, 0.5, 0),
				})
				expect(result).to.equal(true)
			end)
		end)

		describe("destroy", function()
			it("should set isCreated to false", function()
				ShieldUI.create()
				expect(ShieldUI.isCreated()).to.equal(true)
				ShieldUI.destroy()
				expect(ShieldUI.isCreated()).to.equal(false)
			end)

			it("should handle being called without create", function()
				expect(function()
					ShieldUI.destroy()
				end).never.to.throw()
			end)

			it("should allow recreation after destroy", function()
				ShieldUI.create()
				ShieldUI.destroy()
				local result = ShieldUI.create()
				expect(result).to.equal(true)
			end)
		end)

		describe("visibility", function()
			it("should allow setting visibility", function()
				ShieldUI.create()
				-- Should not error
				expect(function()
					ShieldUI.setVisible(false)
					ShieldUI.setVisible(true)
				end).never.to.throw()
			end)

			it("should not error when setting visibility without create", function()
				expect(function()
					ShieldUI.setVisible(false)
				end).never.to.throw()
			end)
		end)

		describe("getScreenGui", function()
			it("should return nil when not created", function()
				expect(ShieldUI.getScreenGui()).to.equal(nil)
			end)

			it("should return ScreenGui when created", function()
				ShieldUI.create()
				local gui = ShieldUI.getScreenGui()
				expect(gui).to.be.ok()
				expect(gui:IsA("ScreenGui")).to.equal(true)
			end)

			it("should return ScreenGui named ShieldUI", function()
				ShieldUI.create()
				local gui = ShieldUI.getScreenGui()
				expect(gui.Name).to.equal("ShieldUI")
			end)
		end)

		describe("getButtonFrame", function()
			it("should return nil when not created", function()
				expect(ShieldUI.getButtonFrame()).to.equal(nil)
			end)

			it("should return Frame when created", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				expect(frame).to.be.ok()
				expect(frame:IsA("Frame")).to.equal(true)
			end)
		end)

		describe("updateStatus", function()
			it("should not error when updating status", function()
				ShieldUI.create()
				expect(function()
					ShieldUI.updateStatus({
						isActive = true,
						isOnCooldown = false,
						canActivate = false,
						remainingDuration = 30,
						remainingCooldown = 0,
						durationTotal = 60,
						cooldownTotal = 300,
					})
				end).never.to.throw()
			end)

			it("should not error when updating status without create", function()
				expect(function()
					ShieldUI.updateStatus({
						isActive = false,
						isOnCooldown = true,
						canActivate = false,
						remainingDuration = 0,
						remainingCooldown = 150,
						durationTotal = 60,
						cooldownTotal = 300,
					})
				end).never.to.throw()
			end)
		end)

		describe("onActivate", function()
			it("should set callback without error", function()
				expect(function()
					ShieldUI.onActivate(function() end)
				end).never.to.throw()
			end)
		end)

		describe("showActivationFeedback", function()
			it("should not error when showing feedback", function()
				ShieldUI.create()
				expect(function()
					ShieldUI.showActivationFeedback(true, "Shield activated!")
					ShieldUI.showActivationFeedback(false, "Cannot activate!")
				end).never.to.throw()
			end)

			it("should not error without create", function()
				expect(function()
					ShieldUI.showActivationFeedback(true, "Test")
				end).never.to.throw()
			end)
		end)

		describe("UI structure", function()
			it("should contain ShieldButtonFrame", function()
				ShieldUI.create()
				local gui = ShieldUI.getScreenGui()
				local buttonFrame = gui:FindFirstChild("ShieldButtonFrame")
				expect(buttonFrame).to.be.ok()
			end)

			it("should contain ShieldButton inside frame", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				local button = frame:FindFirstChild("ShieldButton")
				expect(button).to.be.ok()
				expect(button:IsA("TextButton")).to.equal(true)
			end)

			it("should contain ProgressBar inside frame", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				local progressBar = frame:FindFirstChild("ProgressBar")
				expect(progressBar).to.be.ok()
			end)

			it("should contain StatusLabel inside frame", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				local statusLabel = frame:FindFirstChild("StatusLabel")
				expect(statusLabel).to.be.ok()
			end)

			it("should contain TimerLabel inside frame", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				local timerLabel = frame:FindFirstChild("TimerLabel")
				expect(timerLabel).to.be.ok()
			end)

			it("should contain Tooltip inside frame", function()
				ShieldUI.create()
				local frame = ShieldUI.getButtonFrame()
				local tooltip = frame:FindFirstChild("Tooltip")
				expect(tooltip).to.be.ok()
			end)
		end)
	end)
end
