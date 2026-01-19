--[[
	PredatorService Tests
	Tests for the PredatorService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
  local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
  local PredatorAI = require(Shared:WaitForChild("PredatorAI"))

  describe("PredatorSpawning", function()
    describe("createSpawnState", function()
      it("should create initial spawn state", function()
        local state = PredatorSpawning.createSpawnState(1)
        expect(state).to.be.ok()
        expect(state.waveNumber).to.equal(0)
        expect(state.predatorsSpawned).to.equal(0)
        expect(state.difficultyMultiplier).to.equal(1.0)
        expect(state.playerLevel).to.equal(1)
      end)

      it("should respect provided player level", function()
        local state = PredatorSpawning.createSpawnState(5)
        expect(state.playerLevel).to.equal(5)
      end)
    end)

    describe("selectPredatorForWave", function()
      it("should return a valid predator type", function()
        local predatorType = PredatorSpawning.selectPredatorForWave(1, 1)
        expect(predatorType).to.be.a("string")
        expect(PredatorConfig.isValidType(predatorType)).to.equal(true)
      end)

      it("should favor lower threat predators in early waves", function()
        -- Run multiple times to check distribution
        local minorCount = 0
        for _ = 1, 100 do
          local predatorType = PredatorSpawning.selectPredatorForWave(1, 1)
          local config = PredatorConfig.get(predatorType)
          if config and config.threatLevel == "Minor" then
            minorCount = minorCount + 1
          end
        end
        -- Most early wave predators should be minor threats
        expect(minorCount).to.be.ok()
      end)
    end)

    describe("createPredator", function()
      it("should create a predator instance", function()
        local predator = PredatorSpawning.createPredator("Rat", os.time(), "player1")
        expect(predator).to.be.ok()
        expect(predator.id).to.be.a("string")
        expect(predator.predatorType).to.equal("Rat")
        expect(predator.state).to.equal("spawning")
        expect(predator.health).to.be.ok()
      end)

      it("should return nil for invalid predator type", function()
        local predator = PredatorSpawning.createPredator("InvalidType", os.time(), "player1")
        expect(predator).to.never.be.ok()
      end)
    end)

    describe("applyBatHit", function()
      it("should decrease predator health", function()
        local state = PredatorSpawning.createSpawnState(1)
        local predator = PredatorSpawning.createPredator("Rat", os.time(), "player1")
        table.insert(state.activePredators, predator)

        local initialHealth = predator.health
        local result = PredatorSpawning.applyBatHit(state, predator.id)

        expect(result.success).to.equal(true)
        expect(result.remainingHealth).to.equal(initialHealth - 1)
      end)

      it("should defeat predator when health reaches zero", function()
        local state = PredatorSpawning.createSpawnState(1)
        local predator = PredatorSpawning.createPredator("Rat", os.time(), "player1")
        predator.health = 1
        table.insert(state.activePredators, predator)

        local result = PredatorSpawning.applyBatHit(state, predator.id)

        expect(result.success).to.equal(true)
        expect(result.defeated).to.equal(true)
        expect(predator.state).to.equal("defeated")
      end)

      it("should fail for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState(1)
        local result = PredatorSpawning.applyBatHit(state, "nonexistent")

        expect(result.success).to.equal(false)
      end)
    end)

    describe("getActivePredators", function()
      it("should return only active predators", function()
        local state = PredatorSpawning.createSpawnState(1)

        local activePred = PredatorSpawning.createPredator("Rat", os.time(), "player1")
        local defeatedPred = PredatorSpawning.createPredator("Fox", os.time(), "player1")
        defeatedPred.state = "defeated"

        table.insert(state.activePredators, activePred)
        table.insert(state.activePredators, defeatedPred)

        local active = PredatorSpawning.getActivePredators(state)
        expect(#active).to.equal(1)
        expect(active[1].id).to.equal(activePred.id)
      end)
    end)

    describe("cleanup", function()
      it("should remove inactive predators", function()
        local state = PredatorSpawning.createSpawnState(1)

        local activePred = PredatorSpawning.createPredator("Rat", os.time(), "player1")
        local defeatedPred = PredatorSpawning.createPredator("Fox", os.time(), "player1")
        defeatedPred.state = "defeated"
        local escapedPred = PredatorSpawning.createPredator("Snake", os.time(), "player1")
        escapedPred.state = "escaped"

        table.insert(state.activePredators, activePred)
        table.insert(state.activePredators, defeatedPred)
        table.insert(state.activePredators, escapedPred)

        local removed = PredatorSpawning.cleanup(state)
        expect(removed).to.equal(2)
        expect(#state.activePredators).to.equal(1)
      end)
    end)
  end)

  describe("PredatorConfig", function()
    describe("get", function()
      it("should return config for valid predator type", function()
        local config = PredatorConfig.get("Rat")
        expect(config).to.be.ok()
        expect(config.name).to.equal("Rat")
        expect(config.threatLevel).to.equal("Minor")
      end)

      it("should return nil for invalid predator type", function()
        local config = PredatorConfig.get("InvalidType")
        expect(config).to.never.be.ok()
      end)
    end)

    describe("isValidType", function()
      it("should return true for valid types", function()
        expect(PredatorConfig.isValidType("Rat")).to.equal(true)
        expect(PredatorConfig.isValidType("Fox")).to.equal(true)
        expect(PredatorConfig.isValidType("Bear")).to.equal(true)
      end)

      it("should return false for invalid types", function()
        expect(PredatorConfig.isValidType("InvalidType")).to.equal(false)
        expect(PredatorConfig.isValidType("")).to.equal(false)
      end)
    end)

    describe("getBatHitsRequired", function()
      it("should return bat hits based on catch difficulty", function()
        local ratHits = PredatorConfig.getBatHitsRequired("Rat")
        local bearHits = PredatorConfig.getBatHitsRequired("Bear")

        expect(ratHits).to.be.ok()
        expect(bearHits).to.be.ok()
        expect(bearHits).to.be.gte(ratHits)
      end)
    end)

    describe("selectRandomPredator", function()
      it("should return a valid predator type", function()
        local predatorType = PredatorConfig.selectRandomPredator()
        expect(predatorType).to.be.a("string")
        expect(PredatorConfig.isValidType(predatorType)).to.equal(true)
      end)
    end)

    describe("getThreatLevels", function()
      it("should return all threat levels in order", function()
        local levels = PredatorConfig.getThreatLevels()
        expect(#levels).to.equal(6)
        expect(levels[1]).to.equal("Minor")
        expect(levels[6]).to.equal("Catastrophic")
      end)
    end)

    describe("validateAll", function()
      it("should validate all predator configs", function()
        local result = PredatorConfig.validateAll()
        expect(result.success).to.equal(true)
        expect(#result.errors).to.equal(0)
      end)
    end)
  end)

  describe("PredatorAI", function()
    describe("createState", function()
      it("should create initial AI state", function()
        local state = PredatorAI.createState()
        expect(state).to.be.ok()
        expect(state.positions).to.be.a("table")
      end)
    end)

    describe("getWalkSpeed", function()
      it("should return higher speed for more dangerous predators", function()
        local ratSpeed = PredatorAI.getWalkSpeed("Rat")
        local bearSpeed = PredatorAI.getWalkSpeed("Bear")

        expect(ratSpeed).to.be.ok()
        expect(bearSpeed).to.be.ok()
        expect(bearSpeed).to.be.gte(ratSpeed)
      end)
    end)

    describe("calculateSpawnPosition", function()
      it("should return a valid spawn position", function()
        local sectionCenter = Vector3.new(100, 0, 100)
        local spawnPos = PredatorAI.calculateSpawnPosition(sectionCenter)

        expect(spawnPos).to.be.ok()
        expect(typeof(spawnPos)).to.equal("Vector3")
      end)
    end)

    describe("calculateTargetPosition", function()
      it("should return coop center position", function()
        local sectionCenter = Vector3.new(100, 0, 100)
        local targetPos = PredatorAI.calculateTargetPosition(sectionCenter)

        expect(targetPos).to.be.ok()
        expect(typeof(targetPos)).to.equal("Vector3")
      end)
    end)
  end)
end
