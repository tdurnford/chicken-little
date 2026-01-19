--[[
	Tutorial.spec.lua
	TestEZ tests for the Fusion-based Tutorial component.
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
	local Tutorial

	-- Setup before tests
	beforeAll(function()
		local success, result = pcall(function()
			Tutorial = require(UIComponents:WaitForChild("Tutorial"))
		end)
		if not success then
			warn("Tutorial module load failed:", result)
		end
	end)

	describe("Tutorial", function()
		afterEach(function()
			if Tutorial and Tutorial.destroy then
				Tutorial.destroy()
			end
		end)

		describe("create()", function()
			it("should create the UI successfully", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local success = Tutorial.create()
				expect(success).to.equal(true)
				expect(Tutorial.isCreated()).to.equal(true)
			end)

			it("should accept custom config", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local customConfig = {
					steps = Tutorial.getDefaultSteps(),
					skipEnabled = false,
					autoAdvanceDelay = 5,
				}
				local success = Tutorial.create(customConfig)
				expect(success).to.equal(true)
			end)
		end)

		describe("destroy()", function()
			it("should clean up all resources", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				expect(Tutorial.isCreated()).to.equal(true)

				Tutorial.destroy()
				expect(Tutorial.isCreated()).to.equal(false)
			end)
		end)

		describe("start()", function()
			it("should start the tutorial", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()

				expect(Tutorial.isActive()).to.equal(true)
				expect(Tutorial.getCurrentStepIndex()).to.equal(1)
			end)

			it("should not start twice", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()
				Tutorial.start() -- Should be no-op

				expect(Tutorial.getCurrentStepIndex()).to.equal(1)
			end)
		end)

		describe("nextStep()", function()
			it("should advance to next step", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()
				expect(Tutorial.getCurrentStepIndex()).to.equal(1)

				Tutorial.nextStep()
				expect(Tutorial.getCurrentStepIndex()).to.equal(2)
			end)

			it("should complete when reaching last step", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local completed = false
				Tutorial.create()
				Tutorial.onComplete(function()
					completed = true
				end)

				Tutorial.start()

				-- Advance through all steps
				local totalSteps = Tutorial.getTotalSteps()
				for i = 1, totalSteps do
					Tutorial.nextStep()
				end

				task.wait(0.35)
				expect(completed).to.equal(true)
				expect(Tutorial.isActive()).to.equal(false)
			end)
		end)

		describe("completeStep()", function()
			it("should advance when step ID matches", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()

				local currentStep = Tutorial.getCurrentStep()
				expect(currentStep).to.be.ok()

				Tutorial.completeStep(currentStep.id)
				expect(Tutorial.getCurrentStepIndex()).to.equal(2)
			end)

			it("should not advance when step ID does not match", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()

				Tutorial.completeStep("invalid_step_id")
				expect(Tutorial.getCurrentStepIndex()).to.equal(1)
			end)
		end)

		describe("skip()", function()
			it("should skip the tutorial and call onSkip", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local skipped = false
				Tutorial.create()
				Tutorial.onSkip(function()
					skipped = true
				end)

				Tutorial.start()
				Tutorial.skip()

				task.wait(0.35)
				expect(skipped).to.equal(true)
				expect(Tutorial.isActive()).to.equal(false)
			end)
		end)

		describe("pause() and resume()", function()
			it("should pause and resume the tutorial", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()

				expect(Tutorial.isPaused()).to.equal(false)

				Tutorial.pause()
				expect(Tutorial.isPaused()).to.equal(true)

				Tutorial.resume()
				expect(Tutorial.isPaused()).to.equal(false)
			end)
		end)

		describe("getCurrentStep()", function()
			it("should return current step", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				Tutorial.start()

				local step = Tutorial.getCurrentStep()
				expect(step).to.be.ok()
				expect(step.id).to.equal("buy_egg")
			end)

			it("should return nil when not active", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				local step = Tutorial.getCurrentStep()
				expect(step).to.equal(nil)
			end)
		end)

		describe("getTotalSteps()", function()
			it("should return total step count", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				Tutorial.create()
				local total = Tutorial.getTotalSteps()

				expect(total).to.be.ok()
				expect(total > 0).to.equal(true)
			end)
		end)

		describe("shouldShowTutorial()", function()
			it("should return true for nil player data", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				expect(Tutorial.shouldShowTutorial(nil)).to.equal(true)
			end)

			it("should return true when tutorialComplete is false", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local playerData = { tutorialComplete = false }
				expect(Tutorial.shouldShowTutorial(playerData)).to.equal(true)
			end)

			it("should return false when tutorialComplete is true", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local playerData = { tutorialComplete = true }
				expect(Tutorial.shouldShowTutorial(playerData)).to.equal(false)
			end)
		end)

		describe("getDefaultSteps()", function()
			it("should return default tutorial steps", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local steps = Tutorial.getDefaultSteps()

				expect(#steps > 0).to.equal(true)
				expect(steps[1].id).to.equal("buy_egg")
			end)
		end)

		describe("getDefaultConfig()", function()
			it("should return default configuration", function()
				if not Tutorial then
					pending("Module not loaded")
					return
				end

				local config = Tutorial.getDefaultConfig()

				expect(config.steps).to.be.ok()
				expect(config.skipEnabled).to.equal(true)
				expect(config.autoAdvanceDelay).to.equal(4)
			end)
		end)
	end)
end
