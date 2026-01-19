--[[
	ChickenHealthBar.spec.lua
	Tests for the Fusion ChickenHealthBar component.
]]

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- Module under test
	local ChickenHealthBar

	-- Mock model for testing
	local mockModel

	local function createMockModel()
		local model = Instance.new("Model")
		model.Name = "TestChicken"
		
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(1, 1, 1)
		body.Parent = model
		
		model.PrimaryPart = body
		
		return model
	end

	beforeEach(function()
		ChickenHealthBar = require(script.Parent.ChickenHealthBar)
		mockModel = createMockModel()
	end)

	afterEach(function()
		pcall(function()
			ChickenHealthBar.cleanup()
		end)
		
		if mockModel then
			mockModel:Destroy()
			mockModel = nil
		end
	end)

	describe("ChickenHealthBar", function()
		describe("create", function()
			it("should return state on successful creation", function()
				local state = ChickenHealthBar.create("chicken1", "Basic", mockModel)
				expect(state).to.be.ok()
				expect(state.chickenId).to.equal("chicken1")
			end)

			it("should return nil if model has no primary part", function()
				local emptyModel = Instance.new("Model")
				local state = ChickenHealthBar.create("chicken2", "Basic", emptyModel)
				expect(state).to.equal(nil)
				emptyModel:Destroy()
			end)

			it("should use Body part if PrimaryPart is nil", function()
				local modelWithBody = Instance.new("Model")
				local body = Instance.new("Part")
				body.Name = "Body"
				body.Parent = modelWithBody
				modelWithBody.PrimaryPart = nil
				
				local state = ChickenHealthBar.create("chicken3", "Basic", modelWithBody)
				expect(state).to.be.ok()
				
				modelWithBody:Destroy()
			end)

			it("should replace existing health bar for same chicken", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local state2 = ChickenHealthBar.create("chicken1", "Basic", mockModel)
				expect(state2).to.be.ok()
				expect(ChickenHealthBar.getActiveCount()).to.equal(1)
			end)
		end)

		describe("updateHealth", function()
			it("should return true when chicken exists", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local result = ChickenHealthBar.updateHealth("chicken1", 50)
				expect(result).to.equal(true)
			end)

			it("should return false when chicken does not exist", function()
				local result = ChickenHealthBar.updateHealth("nonexistent", 50)
				expect(result).to.equal(false)
			end)

			it("should update visibility state", function()
				local state = ChickenHealthBar.create("chicken1", "Basic", mockModel)
				ChickenHealthBar.updateHealth("chicken1", 50)
				expect(state.isVisible).to.equal(true)
			end)

			it("should set isVisible to false at full health", function()
				local state = ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local maxHealth = state.maxHealth:get()
				ChickenHealthBar.updateHealth("chicken1", maxHealth)
				expect(state.isVisible).to.equal(false)
			end)
		end)

		describe("setMaxHealth", function()
			it("should return true when chicken exists", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local result = ChickenHealthBar.setMaxHealth("chicken1", 200)
				expect(result).to.equal(true)
			end)

			it("should return false when chicken does not exist", function()
				local result = ChickenHealthBar.setMaxHealth("nonexistent", 200)
				expect(result).to.equal(false)
			end)
		end)

		describe("destroy", function()
			it("should return true when chicken exists", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local result = ChickenHealthBar.destroy("chicken1")
				expect(result).to.equal(true)
			end)

			it("should return false when chicken does not exist", function()
				local result = ChickenHealthBar.destroy("nonexistent")
				expect(result).to.equal(false)
			end)

			it("should remove health bar from active list", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				ChickenHealthBar.destroy("chicken1")
				expect(ChickenHealthBar.get("chicken1")).to.equal(nil)
			end)
		end)

		describe("get", function()
			it("should return state when chicken exists", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				local state = ChickenHealthBar.get("chicken1")
				expect(state).to.be.ok()
				expect(state.chickenId).to.equal("chicken1")
			end)

			it("should return nil when chicken does not exist", function()
				local state = ChickenHealthBar.get("nonexistent")
				expect(state).to.equal(nil)
			end)
		end)

		describe("getAll", function()
			it("should return empty table when no health bars", function()
				local all = ChickenHealthBar.getAll()
				expect(next(all)).to.equal(nil)
			end)

			it("should return all active health bars", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				
				local model2 = createMockModel()
				ChickenHealthBar.create("chicken2", "Basic", model2)
				
				local all = ChickenHealthBar.getAll()
				expect(all["chicken1"]).to.be.ok()
				expect(all["chicken2"]).to.be.ok()
				
				model2:Destroy()
			end)
		end)

		describe("getActiveCount", function()
			it("should return 0 when no health bars", function()
				expect(ChickenHealthBar.getActiveCount()).to.equal(0)
			end)

			it("should return correct count", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				expect(ChickenHealthBar.getActiveCount()).to.equal(1)
				
				local model2 = createMockModel()
				ChickenHealthBar.create("chicken2", "Basic", model2)
				expect(ChickenHealthBar.getActiveCount()).to.equal(2)
				
				model2:Destroy()
			end)
		end)

		describe("getVisibleCount", function()
			it("should return 0 when no visible health bars", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				-- At full health, should not be visible
				expect(ChickenHealthBar.getVisibleCount()).to.equal(0)
			end)

			it("should count visible health bars", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				ChickenHealthBar.updateHealth("chicken1", 50)
				expect(ChickenHealthBar.getVisibleCount()).to.equal(1)
			end)
		end)

		describe("cleanup", function()
			it("should remove all health bars", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				
				local model2 = createMockModel()
				ChickenHealthBar.create("chicken2", "Basic", model2)
				
				ChickenHealthBar.cleanup()
				expect(ChickenHealthBar.getActiveCount()).to.equal(0)
				
				model2:Destroy()
			end)

			it("should not error when called with no health bars", function()
				expect(function()
					ChickenHealthBar.cleanup()
				end).never.to.throw()
			end)
		end)

		describe("getSummary", function()
			it("should return correct summary", function()
				ChickenHealthBar.create("chicken1", "Basic", mockModel)
				ChickenHealthBar.updateHealth("chicken1", 50)
				
				local summary = ChickenHealthBar.getSummary()
				expect(summary.activeCount).to.equal(1)
				expect(summary.visibleCount).to.equal(1)
				expect(#summary.healthBars).to.equal(1)
			end)

			it("should return empty summary when no health bars", function()
				local summary = ChickenHealthBar.getSummary()
				expect(summary.activeCount).to.equal(0)
				expect(summary.visibleCount).to.equal(0)
				expect(#summary.healthBars).to.equal(0)
			end)
		end)
	end)
end
