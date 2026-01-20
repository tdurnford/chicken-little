--[[
	PredatorHealthBar.spec.lua
	Tests for the Fusion PredatorHealthBar component.
]]

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Packages = ReplicatedStorage:WaitForChild("Packages")
	local Fusion = require(Packages:WaitForChild("Fusion"))

	-- Module under test
	local PredatorHealthBar

	-- Mock model for testing
	local mockModel

	local function createMockModel()
		local model = Instance.new("Model")
		model.Name = "TestPredator"
		
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2, 2, 2)
		body.Parent = model
		
		model.PrimaryPart = body
		
		return model
	end

	beforeEach(function()
		PredatorHealthBar = require(script.Parent.PredatorHealthBar)
		mockModel = createMockModel()
	end)

	afterEach(function()
		pcall(function()
			PredatorHealthBar.cleanup()
		end)
		
		if mockModel then
			mockModel:Destroy()
			mockModel = nil
		end
	end)

	describe("PredatorHealthBar", function()
		describe("create", function()
			it("should return state on successful creation", function()
				local state = PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				expect(state).to.be.ok()
				expect(state.predatorId).to.equal("predator1")
			end)

			it("should return nil if model has no primary part", function()
				local emptyModel = Instance.new("Model")
				local state = PredatorHealthBar.create("predator2", "Wolf", "Moderate", emptyModel)
				expect(state).to.equal(nil)
				emptyModel:Destroy()
			end)

			it("should set threat level correctly", function()
				local state = PredatorHealthBar.create("predator1", "Wolf", "Dangerous", mockModel)
				expect(state.threatLevel).to.equal("Dangerous")
			end)

			it("should replace existing health bar for same predator", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local state2 = PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				expect(state2).to.be.ok()
				expect(PredatorHealthBar.getActiveCount()).to.equal(1)
			end)
		end)

		describe("updateHealth", function()
			it("should return true when predator exists", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local result = PredatorHealthBar.updateHealth("predator1", 3)
				expect(result).to.equal(true)
			end)

			it("should return false when predator does not exist", function()
				local result = PredatorHealthBar.updateHealth("nonexistent", 3)
				expect(result).to.equal(false)
			end)
		end)

		describe("applyDamage", function()
			it("should return true when predator exists", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local result = PredatorHealthBar.applyDamage("predator1", 1)
				expect(result).to.equal(true)
			end)

			it("should return false when predator does not exist", function()
				local result = PredatorHealthBar.applyDamage("nonexistent", 1)
				expect(result).to.equal(false)
			end)

			it("should reduce health correctly", function()
				local state = PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local initialHealth = Fusion.peek(state.currentHealth)
				PredatorHealthBar.applyDamage("predator1", 1)
				local newHealth = Fusion.peek(state.currentHealth)
				expect(newHealth).to.equal(initialHealth - 1)
			end)

			it("should not go below 0 health", function()
				local state = PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				PredatorHealthBar.applyDamage("predator1", 1000)
				expect(Fusion.peek(state.currentHealth)).to.equal(0)
			end)
		end)

		describe("destroy", function()
			it("should return true when predator exists", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local result = PredatorHealthBar.destroy("predator1")
				expect(result).to.equal(true)
			end)

			it("should return false when predator does not exist", function()
				local result = PredatorHealthBar.destroy("nonexistent")
				expect(result).to.equal(false)
			end)

			it("should remove health bar from active list", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				PredatorHealthBar.destroy("predator1")
				expect(PredatorHealthBar.get("predator1")).to.equal(nil)
			end)
		end)

		describe("get", function()
			it("should return state when predator exists", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local state = PredatorHealthBar.get("predator1")
				expect(state).to.be.ok()
				expect(state.predatorId).to.equal("predator1")
			end)

			it("should return nil when predator does not exist", function()
				local state = PredatorHealthBar.get("nonexistent")
				expect(state).to.equal(nil)
			end)
		end)

		describe("getAll", function()
			it("should return empty table when no health bars", function()
				local all = PredatorHealthBar.getAll()
				expect(next(all)).to.equal(nil)
			end)

			it("should return all active health bars", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				
				local model2 = createMockModel()
				PredatorHealthBar.create("predator2", "Fox", "Minor", model2)
				
				local all = PredatorHealthBar.getAll()
				expect(all["predator1"]).to.be.ok()
				expect(all["predator2"]).to.be.ok()
				
				model2:Destroy()
			end)
		end)

		describe("getActiveCount", function()
			it("should return 0 when no health bars", function()
				expect(PredatorHealthBar.getActiveCount()).to.equal(0)
			end)

			it("should return correct count", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				expect(PredatorHealthBar.getActiveCount()).to.equal(1)
				
				local model2 = createMockModel()
				PredatorHealthBar.create("predator2", "Fox", "Minor", model2)
				expect(PredatorHealthBar.getActiveCount()).to.equal(2)
				
				model2:Destroy()
			end)
		end)

		describe("cleanup", function()
			it("should remove all health bars", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				
				local model2 = createMockModel()
				PredatorHealthBar.create("predator2", "Fox", "Minor", model2)
				
				PredatorHealthBar.cleanup()
				expect(PredatorHealthBar.getActiveCount()).to.equal(0)
				
				model2:Destroy()
			end)

			it("should not error when called with no health bars", function()
				expect(function()
					PredatorHealthBar.cleanup()
				end).never.to.throw()
			end)
		end)

		describe("getSummary", function()
			it("should return correct summary", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				
				local summary = PredatorHealthBar.getSummary()
				expect(summary.activeCount).to.equal(1)
				expect(#summary.healthBars).to.equal(1)
			end)

			it("should return empty summary when no health bars", function()
				local summary = PredatorHealthBar.getSummary()
				expect(summary.activeCount).to.equal(0)
				expect(#summary.healthBars).to.equal(0)
			end)
		end)

		describe("showDamageNumber", function()
			it("should return true when predator exists", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				local result = PredatorHealthBar.showDamageNumber("predator1", 1)
				expect(result).to.equal(true)
			end)

			it("should return false when predator does not exist", function()
				local result = PredatorHealthBar.showDamageNumber("nonexistent", 1)
				expect(result).to.equal(false)
			end)

			it("should not error when showing damage", function()
				PredatorHealthBar.create("predator1", "Wolf", "Moderate", mockModel)
				expect(function()
					PredatorHealthBar.showDamageNumber("predator1", 5)
				end).never.to.throw()
			end)
		end)
	end)
end
