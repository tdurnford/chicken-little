--[[
	PredatorAttack.spec.lua
	TestEZ tests for PredatorAttack module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PredatorAttack = require(Shared:WaitForChild("PredatorAttack"))
  local PredatorSpawning = require(Shared:WaitForChild("PredatorSpawning"))
  local PredatorConfig = require(Shared:WaitForChild("PredatorConfig"))
  local PlayerData = require(Shared:WaitForChild("PlayerData"))
  local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))

  -- Helper function to create a test player with chickens
  local function createTestPlayerWithChickens(chickenCount, placedTimeOffset)
    local playerData = PlayerData.create("test_player")
    playerData.money = 10000
    local currentTime = os.time()
    local placeTime = currentTime - (placedTimeOffset or 100)

    for i = 1, chickenCount do
      ChickenPlacement.place(playerData, "BasicChick", i, placeTime)
    end

    return playerData, currentTime
  end

  -- Helper function to create a predator in attacking state
  local function createAttackingPredator(spawnState, predatorType, targetPlayerId, targetChickenId)
    local result =
      PredatorSpawning.forceSpawn(spawnState, predatorType or "Rat", os.time(), targetPlayerId)
    if result.success and result.predator then
      PredatorSpawning.updatePredatorState(spawnState, result.predator.id, "attacking")
      if targetChickenId then
        PredatorSpawning.updateTargetChicken(spawnState, result.predator.id, targetChickenId)
      end
    end
    return result
  end

  describe("PredatorAttack", function()
    describe("hasReachedCoop", function()
      it("should return false for predators not in approaching/spawning state", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          spawnTime = 0,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = 1000
        expect(PredatorAttack.hasReachedCoop(predator, currentTime)).to.equal(false)
      end)

      it("should return false when approach time has not elapsed", function()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "approaching",
          spawnTime = spawnTime,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = spawnTime + constants.approachTimeSeconds - 1
        expect(PredatorAttack.hasReachedCoop(predator, currentTime)).to.equal(false)
      end)

      it("should return true when approach time has elapsed", function()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "approaching",
          spawnTime = spawnTime,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = spawnTime + constants.approachTimeSeconds
        expect(PredatorAttack.hasReachedCoop(predator, currentTime)).to.equal(true)
      end)

      it("should return true for spawning predators when time elapsed", function()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "spawning",
          spawnTime = spawnTime,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = spawnTime + constants.approachTimeSeconds + 1
        expect(PredatorAttack.hasReachedCoop(predator, currentTime)).to.equal(true)
      end)
    end)

    describe("startAttacking", function()
      it("should transition predator from spawning to attacking", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        expect(result.predator.state).to.equal("spawning")

        local success = PredatorAttack.startAttacking(spawnState, result.predator.id)
        expect(success).to.equal(true)

        local predator = PredatorSpawning.findPredator(spawnState, result.predator.id)
        expect(predator.state).to.equal("attacking")
      end)

      it("should transition predator from approaching to attacking", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        PredatorSpawning.updatePredatorState(spawnState, result.predator.id, "approaching")

        local success = PredatorAttack.startAttacking(spawnState, result.predator.id)
        expect(success).to.equal(true)

        local predator = PredatorSpawning.findPredator(spawnState, result.predator.id)
        expect(predator.state).to.equal("attacking")
      end)

      it("should return false for predator already attacking", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        PredatorSpawning.updatePredatorState(spawnState, result.predator.id, "attacking")

        local success = PredatorAttack.startAttacking(spawnState, result.predator.id)
        expect(success).to.equal(false)
      end)

      it("should return false for non-existent predator", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local success = PredatorAttack.startAttacking(spawnState, "fake_id")
        expect(success).to.equal(false)
      end)

      it("should return false for defeated predator", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local result = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        PredatorSpawning.updatePredatorState(spawnState, result.predator.id, "defeated")

        local success = PredatorAttack.startAttacking(spawnState, result.predator.id)
        expect(success).to.equal(false)
      end)
    end)

    describe("executeAttack", function()
      it("should return failure for non-existent predator", function()
        local playerData, currentTime = createTestPlayerWithChickens(3)
        local spawnState = PredatorSpawning.createSpawnState()

        local result = PredatorAttack.executeAttack(playerData, spawnState, "fake_id", currentTime)
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Predator not found")
        expect(result.chickensLost).to.equal(0)
      end)

      it("should return failure for predator not in attacking state", function()
        local playerData, currentTime = createTestPlayerWithChickens(3)
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, nil)

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("Predator is not attacking")
      end)

      it("should return failure when coop has no chickens", function()
        local playerData = PlayerData.create("test_player")
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        expect(result.success).to.equal(false)
        expect(result.message).to.equal("No chickens in coop to attack")
      end)

      it("should successfully attack and remove chickens", function()
        local playerData, currentTime = createTestPlayerWithChickens(3)
        local initialChickenCount = #playerData.placedChickens
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        expect(result.success).to.equal(true)
        expect(result.chickensLost > 0).to.equal(true)
        expect(#playerData.placedChickens).to.equal(initialChickenCount - result.chickensLost)
      end)

      it("should prioritize targeted chicken (migrated from IntegrationTests)", function()
        -- Create player data with multiple chickens
        local playerData = PlayerData.create("test_player")
        playerData.money = 10000

        -- Place 3 chickens with different IDs
        local chicken1 = ChickenPlacement.place(playerData, "BasicChick", 1, os.time() - 100)
        local chicken2 = ChickenPlacement.place(playerData, "BasicChick", 2, os.time() - 100)
        local chicken3 = ChickenPlacement.place(playerData, "BasicChick", 3, os.time() - 100)

        expect(chicken1).to.be.ok()
        expect(chicken2).to.be.ok()
        expect(chicken3).to.be.ok()

        -- Create spawn state with predator targeting chicken2
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", os.time(), "test_player")
        expect(spawnResult.success).to.equal(true)

        -- Set predator to attacking state and target chicken2
        PredatorSpawning.updatePredatorState(spawnState, spawnResult.predator.id, "attacking")
        PredatorSpawning.updateTargetChicken(spawnState, spawnResult.predator.id, chicken2.id)

        -- Execute attack
        local attackResult =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, os.time())

        -- Verify attack succeeded
        expect(attackResult.success).to.equal(true)
        expect(attackResult.chickensLost > 0).to.equal(true)

        -- Check that chicken2 (the targeted one) was included in captured chickens
        local targetedChickenCaptured = false
        for _, chickenId in ipairs(attackResult.chickenIds) do
          if chickenId == chicken2.id then
            targetedChickenCaptured = true
            break
          end
        end

        expect(targetedChickenCaptured).to.equal(true)
      end)

      it("should return chicken IDs of attacked chickens", function()
        local playerData, currentTime = createTestPlayerWithChickens(3)
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        expect(result.success).to.equal(true)
        expect(#result.chickenIds).to.equal(result.chickensLost)
      end)

      it("should calculate total value lost", function()
        local playerData, currentTime = createTestPlayerWithChickens(3)
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        expect(result.success).to.equal(true)
        expect(result.totalValueLost >= 0).to.equal(true)
      end)

      it("should not attack protected chickens (within grace period)", function()
        -- Place chickens very recently (within protection period)
        local playerData = PlayerData.create("test_player")
        playerData.money = 10000
        local currentTime = os.time()
        -- Place with current time (within protection period)
        ChickenPlacement.place(playerData, "BasicChick", 1, currentTime)
        ChickenPlacement.place(playerData, "BasicChick", 2, currentTime)

        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        local result =
          PredatorAttack.executeAttack(playerData, spawnState, spawnResult.predator.id, currentTime)
        -- Should succeed but not lose any chickens (all protected)
        expect(result.chickensLost).to.equal(0)
      end)

      it("should indicate predator escaped when attacks depleted", function()
        local playerData, currentTime = createTestPlayerWithChickens(5)
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = createAttackingPredator(spawnState, "Rat")

        -- Execute attacks until predator escapes
        local lastResult
        for _ = 1, 10 do
          local predator = PredatorSpawning.findPredator(spawnState, spawnResult.predator.id)
          if not predator or predator.state ~= "attacking" then
            break
          end
          lastResult = PredatorAttack.executeAttack(
            playerData,
            spawnState,
            spawnResult.predator.id,
            currentTime
          )
          if lastResult.predatorEscaped then
            break
          end
        end

        -- Eventually predator should escape
        if lastResult and lastResult.success then
          expect(lastResult.predatorEscaped ~= nil).to.equal(true)
        end
      end)
    end)

    describe("updatePredatorStates", function()
      it("should return empty list when no predators need state change", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local nowAttacking = PredatorAttack.updatePredatorStates(spawnState, 1000)
        expect(#nowAttacking).to.equal(0)
      end)

      it("should transition spawning predators to approaching", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        expect(spawnResult.predator.state).to.equal("spawning")

        PredatorAttack.updatePredatorStates(spawnState, 1000)

        local predator = PredatorSpawning.findPredator(spawnState, spawnResult.predator.id)
        expect(predator.state).to.equal("approaching")
      end)

      it("should transition approaching predators to attacking when time elapsed", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", spawnTime, nil)

        -- Transition to approaching
        PredatorSpawning.updatePredatorState(spawnState, spawnResult.predator.id, "approaching")

        -- Update with time past approach threshold
        local attackTime = spawnTime + constants.approachTimeSeconds + 1
        local nowAttacking = PredatorAttack.updatePredatorStates(spawnState, attackTime)

        expect(#nowAttacking).to.equal(1)
        expect(nowAttacking[1]).to.equal(spawnResult.predator.id)

        local predator = PredatorSpawning.findPredator(spawnState, spawnResult.predator.id)
        expect(predator.state).to.equal("attacking")
      end)

      it("should return IDs of predators that started attacking", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000

        -- Spawn multiple predators
        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", spawnTime, nil)
        local spawn2 = PredatorSpawning.forceSpawn(spawnState, "Rat", spawnTime, nil)

        -- Transition both to approaching
        PredatorSpawning.updatePredatorState(spawnState, spawn1.predator.id, "approaching")
        PredatorSpawning.updatePredatorState(spawnState, spawn2.predator.id, "approaching")

        local attackTime = spawnTime + constants.approachTimeSeconds + 1
        local nowAttacking = PredatorAttack.updatePredatorStates(spawnState, attackTime)

        expect(#nowAttacking).to.equal(2)
      end)
    end)

    describe("getAttackInfo", function()
      it("should return attack info with all required fields", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)
        local info = PredatorAttack.getAttackInfo(spawnResult.predator)

        expect(info).to.be.ok()
        expect(info.predatorType).to.equal("Rat")
        expect(info.displayName).to.be.ok()
        expect(info.threatLevel).to.be.ok()
        expect(info.chickensPerAttack).to.be.ok()
        expect(info.attacksRemaining).to.be.ok()
        expect(typeof(info.isAttacking)).to.equal("boolean")
        expect(typeof(info.canBeTrapped)).to.equal("boolean")
        expect(typeof(info.canBeBatted)).to.equal("boolean")
      end)

      it("should indicate attacking state correctly", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)

        local infoNotAttacking = PredatorAttack.getAttackInfo(spawnResult.predator)
        expect(infoNotAttacking.isAttacking).to.equal(false)

        PredatorSpawning.updatePredatorState(spawnState, spawnResult.predator.id, "attacking")
        local predator = PredatorSpawning.findPredator(spawnState, spawnResult.predator.id)
        local infoAttacking = PredatorAttack.getAttackInfo(predator)
        expect(infoAttacking.isAttacking).to.equal(true)
      end)

      it("should indicate trappable/battable correctly for caught predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "caught",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        }
        local info = PredatorAttack.getAttackInfo(predator)
        expect(info.canBeTrapped).to.equal(false)
        expect(info.canBeBatted).to.equal(false)
      end)

      it("should indicate trappable/battable correctly for active predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        }
        local info = PredatorAttack.getAttackInfo(predator)
        expect(info.canBeTrapped).to.equal(true)
        expect(info.canBeBatted).to.equal(true)
      end)
    end)

    describe("generateAlert", function()
      it("should generate alert for approaching predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "approaching",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "approaching")

        expect(alert).to.be.ok()
        expect(alert.alertType).to.equal("approaching")
        expect(alert.predatorType).to.equal("Rat")
        expect(alert.predatorDisplayName).to.be.ok()
        expect(alert.threatLevel).to.be.ok()
        expect(alert.message:find("approaching")).to.be.ok()
        expect(alert.urgent).to.equal(true)
      end)

      it("should generate alert for attacking predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "attacking")

        expect(alert.alertType).to.equal("attacking")
        expect(alert.message:find("attacking")).to.be.ok()
        expect(alert.urgent).to.equal(true)
      end)

      it("should generate alert for escaped predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "escaped",
          health = 1,
          attacksRemaining = 0,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "escaped")

        expect(alert.alertType).to.equal("escaped")
        expect(alert.urgent).to.equal(false)
      end)

      it("should generate alert for defeated predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "defeated",
          health = 0,
          attacksRemaining = 0,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "defeated")

        expect(alert.alertType).to.equal("defeated")
        expect(alert.message:find("defeated")).to.be.ok()
        expect(alert.urgent).to.equal(false)
      end)

      it("should generate alert for caught predator", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "caught",
          health = 1,
          attacksRemaining = 1,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "caught")

        expect(alert.alertType).to.equal("caught")
        expect(alert.message:find("caught")).to.be.ok()
      end)

      it("should mark high threat level predators as urgent", function()
        local predator = {
          id = "test",
          predatorType = "Bear",
          state = "escaped",
          health = 1,
          attacksRemaining = 0,
          spawnTime = 0,
        }
        local alert = PredatorAttack.generateAlert(predator, "escaped")
        local config = PredatorConfig.get("Bear")

        -- High threat predators should be urgent regardless of alert type
        if
          config
          and (
            config.threatLevel == "Severe"
            or config.threatLevel == "Deadly"
            or config.threatLevel == "Catastrophic"
          )
        then
          expect(alert.urgent).to.equal(true)
        end
      end)
    end)

    describe("checkDefenses", function()
      it("should return defense status with all required fields", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        local result = PredatorAttack.checkDefenses(playerData, currentTime)

        expect(result).to.be.ok()
        expect(typeof(result.canDefend)).to.equal("boolean")
        expect(typeof(result.trapReady)).to.equal("boolean")
        expect(typeof(result.batAvailable)).to.equal("boolean")
        expect(typeof(result.predatorResistance)).to.equal("number")
        expect(result.message).to.be.ok()
      end)

      it("should indicate bat is always available", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.batAvailable).to.equal(true)
      end)

      it("should indicate canDefend when bat is available", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.canDefend).to.equal(true)
      end)

      it("should detect ready traps", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        -- Add a ready trap
        table.insert(playerData.traps, {
          id = "trap1",
          trapType = "BasicTrap",
          cooldownEndTime = nil,
          caughtPredator = nil,
        })

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.trapReady).to.equal(true)
      end)

      it("should not consider traps on cooldown as ready", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        -- Add a trap on cooldown
        table.insert(playerData.traps, {
          id = "trap1",
          trapType = "BasicTrap",
          cooldownEndTime = currentTime + 100,
          caughtPredator = nil,
        })

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.trapReady).to.equal(false)
      end)

      it("should not consider traps with caught predators as ready", function()
        local playerData = PlayerData.create("test_player")
        local currentTime = os.time()

        -- Add a trap with caught predator
        table.insert(playerData.traps, {
          id = "trap1",
          trapType = "BasicTrap",
          cooldownEndTime = nil,
          caughtPredator = "predator1",
        })

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.trapReady).to.equal(false)
      end)

      it("should return predator resistance from upgrades", function()
        local playerData = PlayerData.create("test_player")
        playerData.upgrades.predatorResistance = 0.25
        local currentTime = os.time()

        local result = PredatorAttack.checkDefenses(playerData, currentTime)
        expect(result.predatorResistance).to.equal(0.25)
      end)
    end)

    describe("getTimeUntilAttack", function()
      it("should return 0 for attacking predators", function()
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          spawnTime = 0,
          health = 1,
          attacksRemaining = 1,
        }
        expect(PredatorAttack.getTimeUntilAttack(predator, 1000)).to.equal(0)
      end)

      it("should return -1 for inactive predators", function()
        local inactiveStates = { "defeated", "escaped", "caught" }
        for _, state in ipairs(inactiveStates) do
          local predator = {
            id = "test",
            predatorType = "Rat",
            state = state,
            spawnTime = 0,
            health = 1,
            attacksRemaining = 1,
          }
          expect(PredatorAttack.getTimeUntilAttack(predator, 1000)).to.equal(-1)
        end
      end)

      it("should return positive time for approaching predators", function()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "approaching",
          spawnTime = spawnTime,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = spawnTime + 1
        local timeUntil = PredatorAttack.getTimeUntilAttack(predator, currentTime)
        expect(timeUntil > 0).to.equal(true)
        expect(timeUntil).to.equal(constants.approachTimeSeconds - 1)
      end)

      it("should return 0 when approach time is exceeded", function()
        local constants = PredatorAttack.getConstants()
        local spawnTime = 1000
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "approaching",
          spawnTime = spawnTime,
          health = 1,
          attacksRemaining = 1,
        }
        local currentTime = spawnTime + constants.approachTimeSeconds + 10
        local timeUntil = PredatorAttack.getTimeUntilAttack(predator, currentTime)
        expect(timeUntil).to.equal(0)
      end)
    end)

    describe("getThreateningPredators", function()
      it("should return empty list when no predators target player", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local threats = PredatorAttack.getThreateningPredators(spawnState, "player1")
        expect(#threats).to.equal(0)
      end)

      it("should return predators targeting specific player", function()
        local spawnState = PredatorSpawning.createSpawnState()
        PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player2")
        PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")

        local threats = PredatorAttack.getThreateningPredators(spawnState, "player1")
        expect(#threats).to.equal(2)
      end)

      it("should include spawning, approaching, and attacking predators", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        local spawn2 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        local spawn3 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")

        PredatorSpawning.updatePredatorState(spawnState, spawn2.predator.id, "approaching")
        PredatorSpawning.updatePredatorState(spawnState, spawn3.predator.id, "attacking")

        local threats = PredatorAttack.getThreateningPredators(spawnState, "player1")
        expect(#threats).to.equal(3)
      end)

      it("should exclude defeated, escaped, and caught predators", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        local spawn2 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        local spawn3 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")
        local spawn4 = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, "player1")

        PredatorSpawning.updatePredatorState(spawnState, spawn2.predator.id, "defeated")
        PredatorSpawning.updatePredatorState(spawnState, spawn3.predator.id, "escaped")
        PredatorSpawning.updatePredatorState(spawnState, spawn4.predator.id, "caught")

        local threats = PredatorAttack.getThreateningPredators(spawnState, "player1")
        expect(#threats).to.equal(1)
      end)
    end)

    describe("getThreatSummary", function()
      it("should return summary with all required fields", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        local summary = PredatorAttack.getThreatSummary(spawnState, "player1", currentTime)

        expect(summary).to.be.ok()
        expect(summary.totalThreats).to.equal(0)
        expect(summary.approachingCount).to.equal(0)
        expect(summary.attackingCount).to.equal(0)
      end)

      it("should count approaching and attacking predators separately", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        local spawn2 = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        local spawn3 = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")

        PredatorSpawning.updatePredatorState(spawnState, spawn1.predator.id, "approaching")
        PredatorSpawning.updatePredatorState(spawnState, spawn2.predator.id, "approaching")
        PredatorSpawning.updatePredatorState(spawnState, spawn3.predator.id, "attacking")

        local summary = PredatorAttack.getThreatSummary(spawnState, "player1", currentTime)

        expect(summary.totalThreats).to.equal(3)
        expect(summary.approachingCount).to.equal(2)
        expect(summary.attackingCount).to.equal(1)
      end)

      it("should identify most dangerous threat", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        PredatorSpawning.forceSpawn(spawnState, "Bear", currentTime, "player1")

        local summary = PredatorAttack.getThreatSummary(spawnState, "player1", currentTime)

        expect(summary.mostDangerousThreat).to.be.ok()
      end)

      it("should calculate time until next attack", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        PredatorSpawning.updatePredatorState(spawnState, spawn1.predator.id, "approaching")

        local summary = PredatorAttack.getThreatSummary(spawnState, "player1", currentTime)

        expect(summary.timeUntilNextAttack).to.be.ok()
        expect(summary.timeUntilNextAttack >= 0).to.equal(true)
      end)

      it("should return 0 time until attack when predator is attacking", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        local spawn1 = PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        PredatorSpawning.updatePredatorState(spawnState, spawn1.predator.id, "attacking")

        local summary = PredatorAttack.getThreatSummary(spawnState, "player1", currentTime)

        expect(summary.timeUntilNextAttack).to.equal(0)
      end)
    end)

    describe("calculatePotentialDamage", function()
      it("should return 0 when no threats", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local damage = PredatorAttack.calculatePotentialDamage(spawnState, "player1")
        expect(damage).to.equal(0)
      end)

      it("should calculate damage based on predator configs", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")

        local damage = PredatorAttack.calculatePotentialDamage(spawnState, "player1")
        expect(damage > 0).to.equal(true)
      end)

      it("should sum damage from multiple predators", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local currentTime = os.time()

        PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        local singleDamage = PredatorAttack.calculatePotentialDamage(spawnState, "player1")

        PredatorSpawning.forceSpawn(spawnState, "Rat", currentTime, "player1")
        local doubleDamage = PredatorAttack.calculatePotentialDamage(spawnState, "player1")

        expect(doubleDamage > singleDamage).to.equal(true)
      end)
    end)

    describe("shouldForceEscape", function()
      it("should return true when no chickens left", function()
        local playerData = PlayerData.create("test_player")
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          health = 1,
          attacksRemaining = 5,
          spawnTime = 0,
        }

        expect(PredatorAttack.shouldForceEscape(playerData, predator)).to.equal(true)
      end)

      it("should return true when no attacks remaining", function()
        local playerData, _ = createTestPlayerWithChickens(3)
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          health = 1,
          attacksRemaining = 0,
          spawnTime = 0,
        }

        expect(PredatorAttack.shouldForceEscape(playerData, predator)).to.equal(true)
      end)

      it("should return false when chickens exist and attacks remain", function()
        local playerData, _ = createTestPlayerWithChickens(3)
        local predator = {
          id = "test",
          predatorType = "Rat",
          state = "attacking",
          health = 1,
          attacksRemaining = 2,
          spawnTime = 0,
        }

        expect(PredatorAttack.shouldForceEscape(playerData, predator)).to.equal(false)
      end)
    end)

    describe("forceEscape", function()
      it("should mark predator as escaped", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local spawnResult = PredatorSpawning.forceSpawn(spawnState, "Rat", 1000, nil)

        local success = PredatorAttack.forceEscape(spawnState, spawnResult.predator.id)
        expect(success).to.equal(true)

        local predator = PredatorSpawning.findPredator(spawnState, spawnResult.predator.id)
        expect(predator.state).to.equal("escaped")
      end)

      it("should return false for non-existent predator", function()
        local spawnState = PredatorSpawning.createSpawnState()
        local success = PredatorAttack.forceEscape(spawnState, "fake_id")
        expect(success).to.equal(false)
      end)
    end)

    describe("getConstants", function()
      it("should return all constants", function()
        local constants = PredatorAttack.getConstants()

        expect(constants).to.be.ok()
        expect(constants.approachTimeSeconds).to.be.ok()
        expect(constants.escapeDelaySeconds).to.be.ok()
      end)

      it("should return positive values for time constants", function()
        local constants = PredatorAttack.getConstants()

        expect(constants.approachTimeSeconds > 0).to.equal(true)
        expect(constants.escapeDelaySeconds > 0).to.equal(true)
      end)
    end)
  end)
end
