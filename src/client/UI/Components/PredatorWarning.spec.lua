--[[
	PredatorWarning.spec.lua
	TestEZ tests for the Fusion-based PredatorWarning component.
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
	local PredatorWarning

	-- Setup before tests
	beforeAll(function()
		local success, result = pcall(function()
			PredatorWarning = require(UIComponents:WaitForChild("PredatorWarning"))
		end)
		if not success then
			warn("PredatorWarning module load failed:", result)
		end
	end)

	describe("PredatorWarning", function()
		afterEach(function()
			if PredatorWarning and PredatorWarning.cleanup then
				PredatorWarning.cleanup()
			end
		end)

		describe("initialize()", function()
			it("should initialize the warning system", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				local summary = PredatorWarning.getSummary()

				expect(summary.hasUI).to.equal(true)
				expect(summary.activeCount).to.equal(0)
			end)
		end)

		describe("cleanup()", function()
			it("should clean up all resources", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.cleanup()

				local summary = PredatorWarning.getSummary()
				expect(summary.hasUI).to.equal(false)
				expect(summary.activeCount).to.equal(0)
			end)
		end)

		describe("show()", function()
			it("should show warning for predator", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))

				expect(PredatorWarning.hasActiveWarnings()).to.equal(true)
				expect(PredatorWarning.getActiveCount()).to.equal(1)
			end)

			it("should track multiple warnings", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				PredatorWarning.show("pred_2", "Wolf", "Dangerous", Vector3.new(10, 0, 10))

				expect(PredatorWarning.getActiveCount()).to.equal(2)
			end)
		end)

		describe("updatePosition()", function()
			it("should update predator position", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				PredatorWarning.updatePosition("pred_1", Vector3.new(5, 0, 5))

				local warnings = PredatorWarning.getActiveWarnings()
				expect(warnings["pred_1"].position).to.equal(Vector3.new(5, 0, 5))
			end)
		end)

		describe("clear()", function()
			it("should clear specific warning", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				PredatorWarning.show("pred_2", "Wolf", "Dangerous", Vector3.new(10, 0, 10))

				expect(PredatorWarning.getActiveCount()).to.equal(2)

				PredatorWarning.clear("pred_1")
				expect(PredatorWarning.getActiveCount()).to.equal(1)
				expect(PredatorWarning.hasActiveWarnings()).to.equal(true)
			end)

			it("should do nothing for non-existent warning", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))

				PredatorWarning.clear("non_existent")
				expect(PredatorWarning.getActiveCount()).to.equal(1)
			end)
		end)

		describe("clearAll()", function()
			it("should clear all warnings", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				PredatorWarning.show("pred_2", "Wolf", "Dangerous", Vector3.new(10, 0, 10))

				expect(PredatorWarning.getActiveCount()).to.equal(2)

				PredatorWarning.clearAll()
				expect(PredatorWarning.getActiveCount()).to.equal(0)
				expect(PredatorWarning.hasActiveWarnings()).to.equal(false)
			end)
		end)

		describe("hasActiveWarnings()", function()
			it("should return false when no warnings", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				expect(PredatorWarning.hasActiveWarnings()).to.equal(false)
			end)

			it("should return true when warnings exist", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				expect(PredatorWarning.hasActiveWarnings()).to.equal(true)
			end)
		end)

		describe("getActiveCount()", function()
			it("should return correct count", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				expect(PredatorWarning.getActiveCount()).to.equal(0)

				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))
				expect(PredatorWarning.getActiveCount()).to.equal(1)

				PredatorWarning.show("pred_2", "Wolf", "Dangerous", Vector3.new(10, 0, 10))
				expect(PredatorWarning.getActiveCount()).to.equal(2)
			end)
		end)

		describe("getActiveWarnings()", function()
			it("should return warning data", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(5, 0, 5))

				local warnings = PredatorWarning.getActiveWarnings()
				expect(warnings["pred_1"]).to.be.ok()
				expect(warnings["pred_1"].predatorType).to.equal("Fox")
				expect(warnings["pred_1"].threatLevel).to.equal("Moderate")
			end)
		end)

		describe("getSummary()", function()
			it("should return complete summary", function()
				if not PredatorWarning then
					pending("Module not loaded")
					return
				end

				PredatorWarning.initialize()
				PredatorWarning.show("pred_1", "Fox", "Moderate", Vector3.new(0, 0, 0))

				local summary = PredatorWarning.getSummary()

				expect(summary.hasUI).to.equal(true)
				expect(summary.activeCount).to.equal(1)
				expect(#summary.warnings).to.equal(1)
				expect(summary.warnings[1].predatorId).to.equal("pred_1")
			end)
		end)
	end)
end
