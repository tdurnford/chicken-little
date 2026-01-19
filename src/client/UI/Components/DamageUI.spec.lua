--[[
	DamageUI.spec.lua
	Tests for the Fusion DamageUI component.
]]

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	-- Module under test
	local DamageUI

	beforeEach(function()
		DamageUI = require(script.Parent.DamageUI)
	end)

	afterEach(function()
		pcall(function()
			DamageUI.cleanup()
		end)
	end)

	describe("DamageUI", function()
		describe("initialize", function()
			it("should initialize without error", function()
				expect(function()
					DamageUI.initialize()
				end).never.to.throw()
			end)

			it("should set isCreated to true after initialization", function()
				expect(DamageUI.isCreated()).to.equal(false)
				DamageUI.initialize()
				expect(DamageUI.isCreated()).to.equal(true)
			end)

			it("should accept optional props", function()
				expect(function()
					DamageUI.initialize({
						healthBarPosition = UDim2.new(0.5, 0, 0.1, 0),
					})
				end).never.to.throw()
			end)
		end)

		describe("cleanup", function()
			it("should set isCreated to false", function()
				DamageUI.initialize()
				expect(DamageUI.isCreated()).to.equal(true)
				DamageUI.cleanup()
				expect(DamageUI.isCreated()).to.equal(false)
			end)

			it("should handle being called without initialize", function()
				expect(function()
					DamageUI.cleanup()
				end).never.to.throw()
			end)

			it("should allow re-initialization after cleanup", function()
				DamageUI.initialize()
				DamageUI.cleanup()
				expect(function()
					DamageUI.initialize()
				end).never.to.throw()
				expect(DamageUI.isCreated()).to.equal(true)
			end)
		end)

		describe("getScreenGui", function()
			it("should return nil when not initialized", function()
				expect(DamageUI.getScreenGui()).to.equal(nil)
			end)

			it("should return ScreenGui when initialized", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				expect(gui).to.be.ok()
				expect(gui:IsA("ScreenGui")).to.equal(true)
			end)

			it("should return ScreenGui named DamageUI", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				expect(gui.Name).to.equal("DamageUI")
			end)
		end)

		describe("showDamageNumber", function()
			it("should not error when showing damage number", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showDamageNumber(50, "predator")
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.showDamageNumber(25)
				end).never.to.throw()
			end)

			it("should ignore zero damage", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showDamageNumber(0)
				end).never.to.throw()
			end)

			it("should ignore negative damage", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showDamageNumber(-10)
				end).never.to.throw()
			end)
		end)

		describe("showMoneyLoss", function()
			it("should not error when showing money loss", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showMoneyLoss(100, "predator")
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.showMoneyLoss(50)
				end).never.to.throw()
			end)

			it("should ignore zero amount", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showMoneyLoss(0)
				end).never.to.throw()
			end)
		end)

		describe("showKnockback", function()
			it("should not error when showing knockback", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showKnockback(2, "predator")
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.showKnockback(1)
				end).never.to.throw()
			end)
		end)

		describe("showIncapacitation", function()
			it("should not error when showing incapacitation", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showIncapacitation(3, "TestPlayer")
				end).never.to.throw()
			end)

			it("should not error without attacker name", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.showIncapacitation(2)
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.showIncapacitation(2, "TestPlayer")
				end).never.to.throw()
			end)
		end)

		describe("updateHealthBar", function()
			it("should not error when updating health bar", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.updateHealthBar(50, 100, true)
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.updateHealthBar(75, 100)
				end).never.to.throw()
			end)
		end)

		describe("hideHealthBar", function()
			it("should not error when hiding health bar", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.hideHealthBar()
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.hideHealthBar()
				end).never.to.throw()
			end)
		end)

		describe("event handlers", function()
			it("should handle onPlayerDamaged", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.onPlayerDamaged({
						damage = 25,
						newHealth = 75,
						maxHealth = 100,
						source = "predator",
					})
				end).never.to.throw()
			end)

			it("should handle onPlayerKnockback", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.onPlayerKnockback({
						duration = 2,
						source = "predator",
					})
				end).never.to.throw()
			end)

			it("should handle onPlayerHealthChanged", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.onPlayerHealthChanged({
						health = 80,
						maxHealth = 100,
						isKnockedBack = false,
						inCombat = true,
					})
				end).never.to.throw()
			end)

			it("should handle onPlayerIncapacitated", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.onPlayerIncapacitated({
						duration = 3,
						attackerId = "123",
						attackerName = "TestPlayer",
					})
				end).never.to.throw()
			end)

			it("should handle onMoneyLost", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.onMoneyLost({
						amount = 100,
						source = "predator",
					})
				end).never.to.throw()
			end)
		end)

		describe("update", function()
			it("should not error when calling update", function()
				DamageUI.initialize()
				expect(function()
					DamageUI.update()
				end).never.to.throw()
			end)

			it("should not error without initialize", function()
				expect(function()
					DamageUI.update()
				end).never.to.throw()
			end)
		end)

		describe("UI structure", function()
			it("should contain HealthBarContainer", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				local container = gui:FindFirstChild("HealthBarContainer")
				expect(container).to.be.ok()
			end)

			it("should contain Background inside HealthBarContainer", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				local container = gui:FindFirstChild("HealthBarContainer")
				local background = container:FindFirstChild("Background")
				expect(background).to.be.ok()
			end)

			it("should contain Fill inside Background", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				local container = gui:FindFirstChild("HealthBarContainer")
				local background = container:FindFirstChild("Background")
				local fill = background:FindFirstChild("Fill")
				expect(fill).to.be.ok()
			end)

			it("should contain HealthText", function()
				DamageUI.initialize()
				local gui = DamageUI.getScreenGui()
				local container = gui:FindFirstChild("HealthBarContainer")
				local healthText = container:FindFirstChild("HealthText")
				expect(healthText).to.be.ok()
			end)
		end)
	end)
end
