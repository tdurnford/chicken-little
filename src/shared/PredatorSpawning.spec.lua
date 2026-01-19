--[[
	PredatorSpawning.spec.lua
	TestEZ tests for PredatorSpawning module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
  local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
  local LevelConfig = require(Shared:WaitForChild("LevelConfig"))

  describe("PredatorSpawning", function()
    describe("createSpawnState", function()
      it("should create initial spawn state with default values", function()
        local state = PredatorSpawning.createSpawnState()
        expect(state).to.be.ok()
        expect(state.lastSpawnTime).to.equal(0)
        expect(state.waveNumber).to.equal(0)
        expect(state.predatorsSpawned).to.equal(0)
        expect(typeof(state.activePredators)).to.equal("table")
        expect(#state.activePredators).to.equal(0)
        expect(state.difficultyMultiplier).to.equal(1.0)
        expect(state.playerLevel).to.equal(1)
      end)

      it("should create spawn state with specified player level", function()
        local state = PredatorSpawning.createSpawnState(10)
        expect(state.playerLevel).to.equal(10)
      end)

      it("should default player level to 1 when not specified", function()
        local state = PredatorSpawning.createSpawnState(nil)
        expect(state.playerLevel).to.equal(1)
      end)
    end)

    describe("getMaxActivePredators", function()
      it("should return max predators based on player level", function()
        local state = PredatorSpawning.createSpawnState(10)
        local maxPred = PredatorSpawning.getMaxActivePredators(state)
        local expectedMax = LevelConfig.getMaxPredatorsForLevel(10)
        expect(maxPred).to.equal(expectedMax)
      end)

      it("should default to level 1 if playerLevel not set", function()
        local state = PredatorSpawning.createSpawnState()
        state.playerLevel = nil
        local maxPred = PredatorSpawning.getMaxActivePredators(state)
        local expectedMax = LevelConfig.getMaxPredatorsForLevel(1)
        expect(maxPred).to.equal(expectedMax)
      end)
    end)

    describe("setPlayerLevel", function()
      it("should update player level in spawn state", function()
        local state = PredatorSpawning.createSpawnState(1)
        expect(state.playerLevel).to.equal(1)
        PredatorSpawning.setPlayerLevel(state, 20)
        expect(state.playerLevel).to.equal(20)
      end)

      it("should enforce minimum level of 1", function()
        local state = PredatorSpawning.createSpawnState(5)
        PredatorSpawning.setPlayerLevel(state, 0)
        expect(state.playerLevel).to.equal(1)
        PredatorSpawning.setPlayerLevel(state, -5)
        expect(state.playerLevel).to.equal(1)
      end)
    end)

    describe("calculateSpawnInterval", function()
      it("should return positive base interval", function()
        local interval = PredatorSpawning.calculateSpawnInterval(1, 1.0, nil)
        expect(interval > 0).to.equal(true)
      end)

      it("should apply night multiplier to reduce interval", function()
        local baseInterval = PredatorSpawning.calculateSpawnInterval(1, 1.0, nil)
        local nightInterval = PredatorSpawning.calculateSpawnInterval(1, 1.0, 2.0)
        expect(nightInterval < baseInterval).to.equal(true)
        expect(math.abs(nightInterval - baseInterval / 2) < 0.01).to.equal(true)
      end)

      it("should apply day multiplier to increase interval", function()
        local baseInterval = PredatorSpawning.calculateSpawnInterval(1, 1.0, nil)
        local dayInterval = PredatorSpawning.calculateSpawnInterval(1, 1.0, 0.5)
        expect(dayInterval > baseInterval).to.equal(true)
        expect(math.abs(dayInterval - baseInterval * 2) < 0.01).to.equal(true)
      end)

      it("should decrease interval as wave number increases", function()
        local wave1Interval = PredatorSpawning.calculateSpawnInterval(1, 1.0, nil)
        local wave10Interval = PredatorSpawning.calculateSpawnInterval(10, 1.0, nil)
        expect(wave10Interval < wave1Interval).to.equal(true)
      end)

      it("should decrease interval as difficulty multiplier increases", function()
        local lowDiff = PredatorSpawning.calculateSpawnInterval(1, 1.0, nil)
        local highDiff = PredatorSpawning.calculateSpawnInterval(1, 2.0, nil)
        expect(highDiff < lowDiff).to.equal(true)
      end)

      it("should not go below minimum spawn interval", function()
        local constants = PredatorSpawning.getConstants()
        local interval = PredatorSpawning.calculateSpawnInterval(100, 10.0, 10.0)
        expect(interval >= constants.minSpawnInterval).to.equal(true)
      end)
    end)

    describe("getWaveInfo", function()
      it("should return wave info with all required fields", function()
        local state = PredatorSpawning.createSpawnState()
        state.waveNumber = 1
        local info = PredatorSpawning.getWaveInfo(state, nil)

        expect(info).to.be.ok()
        expect(info.waveNumber).to.equal(1)
        expect(info.predatorCount).to.be.ok()
        expect(info.threatLevel).to.be.ok()
        expect(info.spawnInterval).to.be.ok()
        expect(info.difficultyMultiplier).to.be.ok()
      end)

      it("should include time multiplier in spawn interval", function()
        local state = PredatorSpawning.createSpawnState()
        state.waveNumber = 1
        local baseInfo = PredatorSpawning.getWaveInfo(state, nil)
        local nightInfo = PredatorSpawning.getWaveInfo(state, 2.0)
        expect(nightInfo.spawnInterval < baseInfo.spawnInterval).to.equal(true)
      end)

      it("should limit predator count to max predators", function()
        local state = PredatorSpawning.createSpawnState(1)
        state.waveNumber = 100
        local info = PredatorSpawning.getWaveInfo(state, nil)
        local maxPredators = PredatorSpawning.getMaxActivePredators(state)
        expect(info.predatorCount <= maxPredators).to.equal(true)
      end)
    end)

    describe("selectPredatorForWave", function()
      it("should return valid predator type", function()
        local predatorType = PredatorSpawning.selectPredatorForWave(1, 1)
        expect(PredatorConfig.isValidType(predatorType)).to.equal(true)
      end)

      it("should return Rat as fallback when no valid selection", function()
        -- At wave 1 with player level 1, should get minor threats
        local predatorType = PredatorSpawning.selectPredatorForWave(1, 1)
        expect(predatorType).to.be.ok()
      end)

      it("should respect player level for threat selection", function()
        -- Low level player should get lower threats
        local lowLevelResults = {}
        for _ = 1, 20 do
          local predatorType = PredatorSpawning.selectPredatorForWave(10, 1)
          lowLevelResults[predatorType] = true
        end
        -- Should mostly get minor threats at level 1
        expect(lowLevelResults["Rat"] or lowLevelResults["Snake"]).to.equal(true)
      end)
    end)

    describe("createPredator", function()
      it("should create predator with valid type", function()
        local predator = PredatorSpawning.createPredator("Rat", 1000, "player1", "chicken1")
        expect(predator).to.be.ok()
        expect(predator.predatorType).to.equal("Rat")
        expect(predator.spawnTime).to.equal(1000)
        expect(predator.targetPlayerId).to.equal("player1")
        expect(predator.targetChickenId).to.equal("chicken1")
        expect(predator.state).to.equal("spawning")
      end)

      it("should generate unique ID", function()
        local pred1 = PredatorSpawning.createPredator("Rat", 1000, nil, nil)
        local pred2 = PredatorSpawning.createPredator("Rat", 1000, nil, nil)
        expect(pred1.id ~= pred2.id).to.equal(true)
      end)

      it("should return nil for invalid predator type", function()
        local predator = PredatorSpawning.createPredator("InvalidType", 1000, nil, nil)
        expect(predator).to.equal(nil)
      end)

      it("should set correct health from config", function()
        local predator = PredatorSpawning.createPredator("Rat", 1000, nil, nil)
        local expectedHealth = PredatorConfig.getBatHitsRequired("Rat")
        expect(predator.health).to.equal(expectedHealth)
      end)

      it("should set correct attacks remaining from config", function()
        local predator = PredatorSpawning.createPredator("Rat", 1000, nil, nil)
        local config = PredatorConfig.get("Rat")
        expect(predator.attacksRemaining).to.equal(config.chickensPerAttack)
      end)
    end)

    describe("shouldSpawn", function()
      it("should return false when max predators reached", function()
        local state = PredatorSpawning.createSpawnState(1)
        local maxPredators = PredatorSpawning.getMaxActivePredators(state)
        -- Fill up active predators
        for i = 1, maxPredators do
          table.insert(state.activePredators, {
            id = "pred_" .. i,
            predatorType = "Rat",
            state = "approaching",
            health = 1,
            attacksRemaining = 1,
            spawnTime = 0,
          })
        end
        state.lastSpawnTime = 0
        local shouldSpawn = PredatorSpawning.shouldSpawn(state, 1000, nil)
        expect(shouldSpawn).to.equal(false)
      end)

      it("should return false when spawn interval not elapsed", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 1000
        state.waveNumber = 1
        local shouldSpawn = PredatorSpawning.shouldSpawn(state, 1001, nil)
        expect(shouldSpawn).to.equal(false)
      end)

      it("should return true when conditions are met", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 0
        state.waveNumber = 1
        local shouldSpawn = PredatorSpawning.shouldSpawn(state, 1000, nil)
        expect(shouldSpawn).to.equal(true)
      end)
    end)

    describe("getNextSpawnTime", function()
      it("should return correct next spawn time", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 1000
        state.waveNumber = 1
        local waveInfo = PredatorSpawning.getWaveInfo(state, nil)
        local nextSpawn = PredatorSpawning.getNextSpawnTime(state, nil)
        expect(nextSpawn).to.equal(1000 + waveInfo.spawnInterval)
      end)

      it("should respect time of day multiplier", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 1000
        state.waveNumber = 1
        local dayNextSpawn = PredatorSpawning.getNextSpawnTime(state, 0.5)
        local nightNextSpawn = PredatorSpawning.getNextSpawnTime(state, 2.0)
        expect(nightNextSpawn < dayNextSpawn).to.equal(true)
      end)
    end)

    describe("spawn", function()
      it("should fail when conditions not met", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 1000
        state.waveNumber = 1
        local result = PredatorSpawning.spawn(state, 1001, nil, nil)
        expect(result.success).to.equal(false)
        expect(result.predator).to.equal(nil)
      end)

      it("should succeed when conditions are met", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 0
        local result = PredatorSpawning.spawn(state, 1000, "player1", nil)
        expect(result.success).to.equal(true)
        expect(result.predator).to.be.ok()
      end)

      it("should increment wave number on first spawn", function()
        local state = PredatorSpawning.createSpawnState()
        expect(state.waveNumber).to.equal(0)
        PredatorSpawning.spawn(state, 1000, nil, nil)
        expect(state.waveNumber).to.equal(1)
      end)

      it("should add predator to active list", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.spawn(state, 1000, nil, nil)
        expect(#state.activePredators).to.equal(1)
        expect(state.activePredators[1].id).to.equal(result.predator.id)
      end)

      it("should increment predators spawned count", function()
        local state = PredatorSpawning.createSpawnState()
        expect(state.predatorsSpawned).to.equal(0)
        PredatorSpawning.spawn(state, 1000, nil, nil)
        expect(state.predatorsSpawned).to.equal(1)
      end)

      it("should update last spawn time", function()
        local state = PredatorSpawning.createSpawnState()
        PredatorSpawning.spawn(state, 1000, nil, nil)
        expect(state.lastSpawnTime).to.equal(1000)
      end)
    end)

    describe("forceSpawn", function()
      it("should spawn specific predator type", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Bear", 1000, "player1")
        expect(result.success).to.equal(true)
        expect(result.predator.predatorType).to.equal("Bear")
      end)

      it("should fail for invalid predator type", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "InvalidType", 1000, nil)
        expect(result.success).to.equal(false)
        expect(result.message).to.be.ok()
      end)

      it("should fail when max predators reached", function()
        local state = PredatorSpawning.createSpawnState(1)
        local maxPredators = PredatorSpawning.getMaxActivePredators(state)
        for i = 1, maxPredators do
          table.insert(state.activePredators, {
            id = "pred_" .. i,
            predatorType = "Rat",
            state = "approaching",
            health = 1,
            attacksRemaining = 1,
            spawnTime = 0,
          })
        end
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        expect(result.success).to.equal(false)
      end)
    end)

    describe("getActivePredatorCount", function()
      it("should return 0 for empty state", function()
        local state = PredatorSpawning.createSpawnState()
        expect(PredatorSpawning.getActivePredatorCount(state)).to.equal(0)
      end)

      it("should count only active predators", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          state = "approaching",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "2",
          state = "attacking",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "3",
          state = "defeated",
          predatorType = "Rat",
          health = 0,
          attacksRemaining = 0,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "4",
          state = "escaped",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 0,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "5",
          state = "caught",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        expect(PredatorSpawning.getActivePredatorCount(state)).to.equal(2)
      end)
    end)

    describe("getActivePredators", function()
      it("should return empty array for empty state", function()
        local state = PredatorSpawning.createSpawnState()
        local active = PredatorSpawning.getActivePredators(state)
        expect(#active).to.equal(0)
      end)

      it("should exclude inactive predators", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          state = "approaching",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "2",
          state = "defeated",
          predatorType = "Rat",
          health = 0,
          attacksRemaining = 0,
          spawnTime = 0,
        })
        local active = PredatorSpawning.getActivePredators(state)
        expect(#active).to.equal(1)
        expect(active[1].id).to.equal("1")
      end)
    end)

    describe("findPredator", function()
      it("should find predator by ID", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local found = PredatorSpawning.findPredator(state, result.predator.id)
        expect(found).to.be.ok()
        expect(found.id).to.equal(result.predator.id)
      end)

      it("should return nil for non-existent ID", function()
        local state = PredatorSpawning.createSpawnState()
        local found = PredatorSpawning.findPredator(state, "fake_id")
        expect(found).to.equal(nil)
      end)
    end)

    describe("updatePredatorState", function()
      it("should update predator state", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        expect(result.predator.state).to.equal("spawning")
        local updated = PredatorSpawning.updatePredatorState(state, result.predator.id, "attacking")
        expect(updated).to.equal(true)
        local predator = PredatorSpawning.findPredator(state, result.predator.id)
        expect(predator.state).to.equal("attacking")
      end)

      it("should return false for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState()
        local updated = PredatorSpawning.updatePredatorState(state, "fake_id", "attacking")
        expect(updated).to.equal(false)
      end)
    end)

    describe("applyBatHit", function()
      it("should reduce predator health", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local initialHealth = result.predator.health
        local hitResult = PredatorSpawning.applyBatHit(state, result.predator.id)
        expect(hitResult.success).to.equal(true)
        expect(hitResult.remainingHealth).to.equal(initialHealth - 1)
      end)

      it("should defeat predator when health reaches 0", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local predator = result.predator
        -- Hit until defeated
        local hitResult
        for _ = 1, predator.health do
          hitResult = PredatorSpawning.applyBatHit(state, predator.id)
        end
        expect(hitResult.defeated).to.equal(true)
        expect(hitResult.remainingHealth).to.equal(0)
        local updatedPredator = PredatorSpawning.findPredator(state, predator.id)
        expect(updatedPredator.state).to.equal("defeated")
      end)

      it("should fail for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState()
        local hitResult = PredatorSpawning.applyBatHit(state, "fake_id")
        expect(hitResult.success).to.equal(false)
      end)

      it("should fail for inactive predator", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        PredatorSpawning.markEscaped(state, result.predator.id)
        local hitResult = PredatorSpawning.applyBatHit(state, result.predator.id)
        expect(hitResult.success).to.equal(false)
      end)
    end)

    describe("markCaught", function()
      it("should mark predator as caught", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local marked = PredatorSpawning.markCaught(state, result.predator.id)
        expect(marked).to.equal(true)
        local predator = PredatorSpawning.findPredator(state, result.predator.id)
        expect(predator.state).to.equal("caught")
      end)
    end)

    describe("markEscaped", function()
      it("should mark predator as escaped", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local marked = PredatorSpawning.markEscaped(state, result.predator.id)
        expect(marked).to.equal(true)
        local predator = PredatorSpawning.findPredator(state, result.predator.id)
        expect(predator.state).to.equal("escaped")
      end)
    end)

    describe("updateTargetChicken", function()
      it("should update target chicken ID", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local updated =
          PredatorSpawning.updateTargetChicken(state, result.predator.id, "chicken123")
        expect(updated).to.equal(true)
        local predator = PredatorSpawning.findPredator(state, result.predator.id)
        expect(predator.targetChickenId).to.equal("chicken123")
      end)

      it("should return false for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState()
        local updated = PredatorSpawning.updateTargetChicken(state, "fake_id", "chicken123")
        expect(updated).to.equal(false)
      end)
    end)

    describe("getTargetChickenId", function()
      it("should return target chicken ID", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        PredatorSpawning.updateTargetChicken(state, result.predator.id, "chicken456")
        local targetId = PredatorSpawning.getTargetChickenId(state, result.predator.id)
        expect(targetId).to.equal("chicken456")
      end)

      it("should return nil for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState()
        local targetId = PredatorSpawning.getTargetChickenId(state, "fake_id")
        expect(targetId).to.equal(nil)
      end)
    end)

    describe("cleanup", function()
      it("should remove inactive predators", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          state = "approaching",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "2",
          state = "defeated",
          predatorType = "Rat",
          health = 0,
          attacksRemaining = 0,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "3",
          state = "escaped",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 0,
          spawnTime = 0,
        })
        table.insert(state.activePredators, {
          id = "4",
          state = "caught",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        local removed = PredatorSpawning.cleanup(state)
        expect(removed).to.equal(3)
        expect(#state.activePredators).to.equal(1)
        expect(state.activePredators[1].id).to.equal("1")
      end)

      it("should return 0 when nothing to clean", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          state = "approaching",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        local removed = PredatorSpawning.cleanup(state)
        expect(removed).to.equal(0)
      end)
    end)

    describe("getTimeUntilNextSpawn", function()
      it("should return positive time when spawn not ready", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 1000
        state.waveNumber = 1
        local timeUntil = PredatorSpawning.getTimeUntilNextSpawn(state, 1000, nil)
        expect(timeUntil > 0).to.equal(true)
      end)

      it("should return 0 when spawn is ready", function()
        local state = PredatorSpawning.createSpawnState()
        state.lastSpawnTime = 0
        state.waveNumber = 1
        local timeUntil = PredatorSpawning.getTimeUntilNextSpawn(state, 10000, nil)
        expect(timeUntil).to.equal(0)
      end)
    end)

    describe("getSummary", function()
      it("should return summary with all required fields", function()
        local state = PredatorSpawning.createSpawnState(15)
        local currentTime = 1000
        local summary = PredatorSpawning.getSummary(state, currentTime, 1.5)

        expect(summary).to.be.ok()
        expect(summary.waveNumber).to.be.ok()
        expect(summary.activePredators).to.be.ok()
        expect(summary.maxPredators).to.be.ok()
        expect(summary.predatorsSpawned).to.be.ok()
        expect(summary.timeUntilNextSpawn).to.be.ok()
        expect(summary.difficultyMultiplier).to.be.ok()
        expect(summary.dominantThreat).to.be.ok()
        expect(summary.timeOfDayMultiplier).to.be.ok()
        expect(summary.playerLevel).to.be.ok()
      end)

      it("should include timeOfDayMultiplier in summary", function()
        local state = PredatorSpawning.createSpawnState()
        local summary = PredatorSpawning.getSummary(state, 1000, 1.5)
        expect(summary.timeOfDayMultiplier).to.equal(1.5)
      end)

      it("should default timeOfDayMultiplier to 1.0", function()
        local state = PredatorSpawning.createSpawnState()
        local summary = PredatorSpawning.getSummary(state, 1000, nil)
        expect(summary.timeOfDayMultiplier).to.equal(1.0)
      end)

      it("should include playerLevel in summary", function()
        local state = PredatorSpawning.createSpawnState(15)
        local summary = PredatorSpawning.getSummary(state, 1000, 1.0)
        expect(summary.playerLevel).to.equal(15)
      end)
    end)

    describe("getPredatorInfo", function()
      it("should return predator info with all required fields", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local info = PredatorSpawning.getPredatorInfo(result.predator)

        expect(info).to.be.ok()
        expect(info.id).to.equal(result.predator.id)
        expect(info.displayName).to.be.ok()
        expect(info.threatLevel).to.be.ok()
        expect(info.state).to.equal("spawning")
        expect(info.health).to.be.ok()
        expect(info.maxHealth).to.be.ok()
        expect(info.attacksRemaining).to.be.ok()
      end)

      it("should use predator type as fallback display name", function()
        -- Create a minimal predator-like object
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "spawning",
          health = 1,
          attacksRemaining = 1,
        }
        local info = PredatorSpawning.getPredatorInfo(predator)
        expect(info.displayName).to.be.ok()
      end)
    end)

    describe("decreaseAttacks", function()
      it("should decrease attacks remaining", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local initialAttacks = result.predator.attacksRemaining
        local decreaseResult = PredatorSpawning.decreaseAttacks(state, result.predator.id)
        expect(decreaseResult.success).to.equal(true)
        expect(decreaseResult.attacksRemaining).to.equal(initialAttacks - 1)
      end)

      it("should mark predator as escaped when attacks depleted", function()
        local state = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(state, "Rat", 1000, nil)
        local predator = result.predator
        -- Decrease until no attacks left
        local decreaseResult
        for _ = 1, predator.attacksRemaining do
          decreaseResult = PredatorSpawning.decreaseAttacks(state, predator.id)
        end
        expect(decreaseResult.shouldEscape).to.equal(true)
        local updatedPredator = PredatorSpawning.findPredator(state, predator.id)
        expect(updatedPredator.state).to.equal("escaped")
      end)

      it("should fail for non-existent predator", function()
        local state = PredatorSpawning.createSpawnState()
        local decreaseResult = PredatorSpawning.decreaseAttacks(state, "fake_id")
        expect(decreaseResult.success).to.equal(false)
      end)
    end)

    describe("reset", function()
      it("should reset spawn state to initial values", function()
        local state = PredatorSpawning.createSpawnState(5)
        state.lastSpawnTime = 1000
        state.waveNumber = 10
        state.predatorsSpawned = 50
        state.difficultyMultiplier = 2.5
        table.insert(state.activePredators, {
          id = "1",
          state = "approaching",
          predatorType = "Rat",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })

        PredatorSpawning.reset(state)

        expect(state.lastSpawnTime).to.equal(0)
        expect(state.waveNumber).to.equal(0)
        expect(state.predatorsSpawned).to.equal(0)
        expect(state.difficultyMultiplier).to.equal(1.0)
        expect(#state.activePredators).to.equal(0)
        expect(state.playerLevel).to.equal(5) -- Should preserve player level
      end)

      it("should allow setting new player level on reset", function()
        local state = PredatorSpawning.createSpawnState(5)
        PredatorSpawning.reset(state, 10)
        expect(state.playerLevel).to.equal(10)
      end)
    end)

    describe("getConstants", function()
      it("should return all constants", function()
        local constants = PredatorSpawning.getConstants()
        expect(constants).to.be.ok()
        expect(constants.baseSpawnInterval).to.be.ok()
        expect(constants.minSpawnInterval).to.be.ok()
        expect(constants.waveSizeBase).to.be.ok()
        expect(constants.waveSizeIncrement).to.be.ok()
        expect(constants.difficultyScaleRate).to.be.ok()
      end)

      it("should return positive values for spawn intervals", function()
        local constants = PredatorSpawning.getConstants()
        expect(constants.baseSpawnInterval > 0).to.equal(true)
        expect(constants.minSpawnInterval > 0).to.equal(true)
        expect(constants.baseSpawnInterval > constants.minSpawnInterval).to.equal(true)
      end)
    end)

    describe("validateState", function()
      it("should return success for valid state", function()
        local state = PredatorSpawning.createSpawnState()
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(true)
        expect(#validation.errors).to.equal(0)
      end)

      it("should detect negative wave number", function()
        local state = PredatorSpawning.createSpawnState()
        state.waveNumber = -1
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
        expect(#validation.errors > 0).to.equal(true)
      end)

      it("should detect difficulty multiplier less than 1", function()
        local state = PredatorSpawning.createSpawnState()
        state.difficultyMultiplier = 0.5
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
      end)

      it("should detect negative predators spawned", function()
        local state = PredatorSpawning.createSpawnState()
        state.predatorsSpawned = -5
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
      end)

      it("should detect invalid predator type in active predators", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          predatorType = "InvalidType",
          state = "approaching",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
      end)

      it("should detect negative health in predators", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          predatorType = "Rat",
          state = "approaching",
          health = -1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
      end)

      it("should detect invalid predator state", function()
        local state = PredatorSpawning.createSpawnState()
        table.insert(state.activePredators, {
          id = "1",
          predatorType = "Rat",
          state = "invalid_state",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        })
        local validation = PredatorSpawning.validateState(state)
        expect(validation.success).to.equal(false)
      end)
    end)
  end)
end
