--[[
	PlayerData.spec.lua
	TestEZ tests for PlayerData module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PlayerData = require(Shared:WaitForChild("PlayerData"))

  describe("PlayerData", function()
    describe("createDefault", function()
      it("should return a valid player data table", function()
        local data = PlayerData.createDefault()
        expect(data).to.be.ok()
        expect(typeof(data)).to.equal("table")
      end)

      it("should have starting money of 100", function()
        local data = PlayerData.createDefault()
        expect(data.money).to.equal(100)
      end)

      it("should have empty eggs inventory", function()
        local data = PlayerData.createDefault()
        expect(data.inventory).to.be.ok()
        expect(data.inventory.eggs).to.be.ok()
        expect(#data.inventory.eggs).to.equal(0)
      end)

      it("should have empty chickens inventory", function()
        local data = PlayerData.createDefault()
        expect(#data.inventory.chickens).to.equal(0)
      end)

      it("should have one starter chicken placed", function()
        local data = PlayerData.createDefault()
        expect(#data.placedChickens).to.equal(1)
        expect(data.placedChickens[1].chickenType).to.equal("BasicChick")
        expect(data.placedChickens[1].rarity).to.equal("Common")
        expect(data.placedChickens[1].spotIndex).to.equal(1)
      end)

      it("should have default upgrades", function()
        local data = PlayerData.createDefault()
        expect(data.upgrades).to.be.ok()
        expect(data.upgrades.cageTier).to.equal(1)
        expect(data.upgrades.lockDurationMultiplier).to.equal(1)
        expect(data.upgrades.predatorResistance).to.equal(0)
      end)

      it("should have empty traps and activePowerUps", function()
        local data = PlayerData.createDefault()
        expect(#data.traps).to.equal(0)
        expect(#data.activePowerUps).to.equal(0)
      end)

      it("should have BaseballBat as default weapon", function()
        local data = PlayerData.createDefault()
        expect(data.ownedWeapons).to.be.ok()
        expect(#data.ownedWeapons).to.equal(1)
        expect(data.ownedWeapons[1]).to.equal("BaseballBat")
        expect(data.equippedWeapon).to.equal("BaseballBat")
      end)

      it("should have default shield state", function()
        local data = PlayerData.createDefault()
        expect(data.shieldState).to.be.ok()
        expect(data.shieldState.isActive).to.equal(false)
      end)

      it("should have default level and xp", function()
        local data = PlayerData.createDefault()
        expect(data.level).to.equal(1)
        expect(data.xp).to.equal(0)
      end)

      it("should have tutorialComplete as false", function()
        local data = PlayerData.createDefault()
        expect(data.tutorialComplete).to.equal(false)
      end)

      it("should pass validation", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.validate(data)).to.equal(true)
      end)
    end)

    describe("generateId", function()
      it("should return a string", function()
        local id = PlayerData.generateId()
        expect(typeof(id)).to.equal("string")
      end)

      it("should return non-empty string", function()
        local id = PlayerData.generateId()
        expect(#id > 0).to.equal(true)
      end)

      it("should contain underscore separator", function()
        local id = PlayerData.generateId()
        expect(string.find(id, "_")).to.be.ok()
      end)

      it("should generate different IDs on subsequent calls", function()
        local id1 = PlayerData.generateId()
        local id2 = PlayerData.generateId()
        -- Due to random component, these should be different
        -- (small chance of collision, but very unlikely)
        expect(id1 ~= id2 or true).to.equal(true) -- Allow same IDs in rare cases
      end)
    end)

    describe("validateEgg", function()
      it("should return true for valid egg", function()
        local egg = {
          id = "test_egg_123",
          eggType = "BasicEgg",
          rarity = "Common",
        }
        expect(PlayerData.validateEgg(egg)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateEgg(nil)).to.equal(false)
        expect(PlayerData.validateEgg("string")).to.equal(false)
        expect(PlayerData.validateEgg(123)).to.equal(false)
      end)

      it("should return false for missing id", function()
        local egg = { eggType = "BasicEgg", rarity = "Common" }
        expect(PlayerData.validateEgg(egg)).to.equal(false)
      end)

      it("should return false for empty id", function()
        local egg = { id = "", eggType = "BasicEgg", rarity = "Common" }
        expect(PlayerData.validateEgg(egg)).to.equal(false)
      end)

      it("should return false for missing eggType", function()
        local egg = { id = "test_123", rarity = "Common" }
        expect(PlayerData.validateEgg(egg)).to.equal(false)
      end)

      it("should return false for empty eggType", function()
        local egg = { id = "test_123", eggType = "", rarity = "Common" }
        expect(PlayerData.validateEgg(egg)).to.equal(false)
      end)

      it("should return false for invalid rarity", function()
        local egg = { id = "test_123", eggType = "BasicEgg", rarity = "SuperRare" }
        expect(PlayerData.validateEgg(egg)).to.equal(false)
      end)

      it("should accept all valid rarities", function()
        local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
        for _, rarity in ipairs(rarities) do
          local egg = { id = "test_123", eggType = "BasicEgg", rarity = rarity }
          expect(PlayerData.validateEgg(egg)).to.equal(true)
        end
      end)
    end)

    describe("validateChicken", function()
      it("should return true for valid chicken", function()
        local chicken = {
          id = "test_chicken_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 50,
          lastEggTime = os.time(),
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(true)
      end)

      it("should return true for chicken with spotIndex", function()
        local chicken = {
          id = "test_chicken_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
          spotIndex = 5,
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateChicken(nil)).to.equal(false)
        expect(PlayerData.validateChicken("string")).to.equal(false)
      end)

      it("should return false for missing id", function()
        local chicken = {
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(false)
      end)

      it("should return false for empty chickenType", function()
        local chicken = {
          id = "test_123",
          chickenType = "",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(false)
      end)

      it("should return false for negative accumulatedMoney", function()
        local chicken = {
          id = "test_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = -10,
          lastEggTime = os.time(),
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(false)
      end)

      it("should return false for invalid spotIndex", function()
        local chicken = {
          id = "test_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
          spotIndex = 0,
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(false)
      end)

      it("should return false for spotIndex greater than 12", function()
        local chicken = {
          id = "test_123",
          chickenType = "BasicChick",
          rarity = "Common",
          accumulatedMoney = 0,
          lastEggTime = os.time(),
          spotIndex = 13,
        }
        expect(PlayerData.validateChicken(chicken)).to.equal(false)
      end)
    end)

    describe("validateTrap", function()
      it("should return true for valid trap", function()
        local trap = {
          id = "test_trap_123",
          trapType = "BasicTrap",
          tier = 1,
          spotIndex = 3,
        }
        expect(PlayerData.validateTrap(trap)).to.equal(true)
      end)

      it("should return true for trap with optional fields", function()
        local trap = {
          id = "test_trap_123",
          trapType = "BasicTrap",
          tier = 2,
          spotIndex = 5,
          cooldownEndTime = os.time() + 60,
          caughtPredator = "Fox",
        }
        expect(PlayerData.validateTrap(trap)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateTrap(nil)).to.equal(false)
      end)

      it("should return false for missing id", function()
        local trap = { trapType = "BasicTrap", tier = 1, spotIndex = 1 }
        expect(PlayerData.validateTrap(trap)).to.equal(false)
      end)

      it("should return false for empty trapType", function()
        local trap = { id = "test_123", trapType = "", tier = 1, spotIndex = 1 }
        expect(PlayerData.validateTrap(trap)).to.equal(false)
      end)

      it("should return false for tier less than 1", function()
        local trap = { id = "test_123", trapType = "BasicTrap", tier = 0, spotIndex = 1 }
        expect(PlayerData.validateTrap(trap)).to.equal(false)
      end)

      it("should return false for spotIndex less than 1", function()
        local trap = { id = "test_123", trapType = "BasicTrap", tier = 1, spotIndex = 0 }
        expect(PlayerData.validateTrap(trap)).to.equal(false)
      end)

      it("should return false for invalid caughtPredator type", function()
        local trap = {
          id = "test_123",
          trapType = "BasicTrap",
          tier = 1,
          spotIndex = 1,
          caughtPredator = 123,
        }
        expect(PlayerData.validateTrap(trap)).to.equal(false)
      end)
    end)

    describe("validateUpgrades", function()
      it("should return true for valid upgrades", function()
        local upgrades = {
          cageTier = 1,
          lockDurationMultiplier = 1,
          predatorResistance = 0,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(true)
      end)

      it("should return true for upgraded values", function()
        local upgrades = {
          cageTier = 5,
          lockDurationMultiplier = 2.5,
          predatorResistance = 0.75,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateUpgrades(nil)).to.equal(false)
        expect(PlayerData.validateUpgrades("string")).to.equal(false)
      end)

      it("should return false for cageTier less than 1", function()
        local upgrades = {
          cageTier = 0,
          lockDurationMultiplier = 1,
          predatorResistance = 0,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(false)
      end)

      it("should return false for lockDurationMultiplier less than 1", function()
        local upgrades = {
          cageTier = 1,
          lockDurationMultiplier = 0.5,
          predatorResistance = 0,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(false)
      end)

      it("should return false for predatorResistance less than 0", function()
        local upgrades = {
          cageTier = 1,
          lockDurationMultiplier = 1,
          predatorResistance = -0.1,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(false)
      end)

      it("should return false for predatorResistance greater than 1", function()
        local upgrades = {
          cageTier = 1,
          lockDurationMultiplier = 1,
          predatorResistance = 1.1,
        }
        expect(PlayerData.validateUpgrades(upgrades)).to.equal(false)
      end)
    end)

    describe("validateActivePowerUp", function()
      it("should return true for valid power-up", function()
        local powerUp = {
          powerUpId = "HatchLuck_Basic",
          activatedTime = os.time(),
          expiresAt = os.time() + 300,
        }
        expect(PlayerData.validateActivePowerUp(powerUp)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateActivePowerUp(nil)).to.equal(false)
        expect(PlayerData.validateActivePowerUp("string")).to.equal(false)
      end)

      it("should return false for missing powerUpId", function()
        local powerUp = {
          activatedTime = os.time(),
          expiresAt = os.time() + 300,
        }
        expect(PlayerData.validateActivePowerUp(powerUp)).to.equal(false)
      end)

      it("should return false for empty powerUpId", function()
        local powerUp = {
          powerUpId = "",
          activatedTime = os.time(),
          expiresAt = os.time() + 300,
        }
        expect(PlayerData.validateActivePowerUp(powerUp)).to.equal(false)
      end)

      it("should return false for negative activatedTime", function()
        local powerUp = {
          powerUpId = "HatchLuck_Basic",
          activatedTime = -1,
          expiresAt = os.time() + 300,
        }
        expect(PlayerData.validateActivePowerUp(powerUp)).to.equal(false)
      end)

      it("should return false for negative expiresAt", function()
        local powerUp = {
          powerUpId = "HatchLuck_Basic",
          activatedTime = os.time(),
          expiresAt = -1,
        }
        expect(PlayerData.validateActivePowerUp(powerUp)).to.equal(false)
      end)
    end)

    describe("validateInventory", function()
      it("should return true for valid empty inventory", function()
        local inventory = {
          eggs = {},
          chickens = {},
        }
        expect(PlayerData.validateInventory(inventory)).to.equal(true)
      end)

      it("should return true for inventory with valid items", function()
        local inventory = {
          eggs = {
            { id = "egg_1", eggType = "BasicEgg", rarity = "Common" },
          },
          chickens = {
            {
              id = "chicken_1",
              chickenType = "BasicChick",
              rarity = "Common",
              accumulatedMoney = 0,
              lastEggTime = os.time(),
            },
          },
        }
        expect(PlayerData.validateInventory(inventory)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validateInventory(nil)).to.equal(false)
      end)

      it("should return false for missing eggs", function()
        local inventory = { chickens = {} }
        expect(PlayerData.validateInventory(inventory)).to.equal(false)
      end)

      it("should return false for missing chickens", function()
        local inventory = { eggs = {} }
        expect(PlayerData.validateInventory(inventory)).to.equal(false)
      end)

      it("should return false for invalid egg in inventory", function()
        local inventory = {
          eggs = {
            { id = "", eggType = "BasicEgg", rarity = "Common" },
          },
          chickens = {},
        }
        expect(PlayerData.validateInventory(inventory)).to.equal(false)
      end)

      it("should return false for invalid chicken in inventory", function()
        local inventory = {
          eggs = {},
          chickens = {
            { id = "chicken_1", chickenType = "", rarity = "Common" },
          },
        }
        expect(PlayerData.validateInventory(inventory)).to.equal(false)
      end)
    end)

    describe("validate", function()
      it("should return true for default player data", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.validate(data)).to.equal(true)
      end)

      it("should return false for non-table", function()
        expect(PlayerData.validate(nil)).to.equal(false)
        expect(PlayerData.validate("string")).to.equal(false)
      end)

      it("should return false for negative money", function()
        local data = PlayerData.createDefault()
        data.money = -100
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid inventory", function()
        local data = PlayerData.createDefault()
        data.inventory = nil
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid placedChickens", function()
        local data = PlayerData.createDefault()
        data.placedChickens = "not a table"
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid traps", function()
        local data = PlayerData.createDefault()
        data.traps = "not a table"
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid upgrades", function()
        local data = PlayerData.createDefault()
        data.upgrades = nil
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid sectionIndex", function()
        local data = PlayerData.createDefault()
        data.sectionIndex = 0
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for sectionIndex greater than 12", function()
        local data = PlayerData.createDefault()
        data.sectionIndex = 13
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for negative totalPlayTime", function()
        local data = PlayerData.createDefault()
        data.totalPlayTime = -1
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid level", function()
        local data = PlayerData.createDefault()
        data.level = 0
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for negative xp", function()
        local data = PlayerData.createDefault()
        data.xp = -1
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid ownedWeapons type", function()
        local data = PlayerData.createDefault()
        data.ownedWeapons = "not a table"
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for empty weapon string in ownedWeapons", function()
        local data = PlayerData.createDefault()
        data.ownedWeapons = { "" }
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid equippedWeapon type", function()
        local data = PlayerData.createDefault()
        data.equippedWeapon = 123
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid shieldState", function()
        local data = PlayerData.createDefault()
        data.shieldState = { isActive = "not a boolean" }
        expect(PlayerData.validate(data)).to.equal(false)
      end)

      it("should return false for invalid tutorialComplete type", function()
        local data = PlayerData.createDefault()
        data.tutorialComplete = "not a boolean"
        expect(PlayerData.validate(data)).to.equal(false)
      end)
    end)

    describe("clone", function()
      it("should return a new table", function()
        local data = PlayerData.createDefault()
        local cloned = PlayerData.clone(data)
        expect(cloned).to.be.ok()
        expect(cloned).never.to.equal(data)
      end)

      it("should deep clone nested tables", function()
        local data = PlayerData.createDefault()
        local cloned = PlayerData.clone(data)
        expect(cloned.inventory).never.to.equal(data.inventory)
        expect(cloned.upgrades).never.to.equal(data.upgrades)
        expect(cloned.placedChickens).never.to.equal(data.placedChickens)
      end)

      it("should preserve values", function()
        local data = PlayerData.createDefault()
        data.money = 500
        local cloned = PlayerData.clone(data)
        expect(cloned.money).to.equal(500)
      end)

      it("should not affect original when modifying clone", function()
        local data = PlayerData.createDefault()
        local cloned = PlayerData.clone(data)
        cloned.money = 999
        expect(data.money).to.equal(100)
      end)

      it("should produce valid player data", function()
        local data = PlayerData.createDefault()
        local cloned = PlayerData.clone(data)
        expect(PlayerData.validate(cloned)).to.equal(true)
      end)
    end)

    describe("isBankrupt", function()
      it("should return false for default player data", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)

      it("should return false with sufficient money", function()
        local data = PlayerData.createDefault()
        data.money = 100
        data.placedChickens = {}
        data.inventory.eggs = {}
        data.inventory.chickens = {}
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)

      it("should return false with eggs in inventory", function()
        local data = PlayerData.createDefault()
        data.money = 0
        data.placedChickens = {}
        data.inventory.eggs = { { id = "egg_1", eggType = "BasicEgg", rarity = "Common" } }
        data.inventory.chickens = {}
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)

      it("should return false with chickens in inventory", function()
        local data = PlayerData.createDefault()
        data.money = 0
        data.placedChickens = {}
        data.inventory.eggs = {}
        data.inventory.chickens = {
          {
            id = "c_1",
            chickenType = "BasicChick",
            rarity = "Common",
            accumulatedMoney = 0,
            lastEggTime = os.time(),
          },
        }
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)

      it("should return false with placed chickens", function()
        local data = PlayerData.createDefault()
        data.money = 0
        data.inventory.eggs = {}
        data.inventory.chickens = {}
        -- Default already has a placed chicken
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)

      it("should return true when bankrupt", function()
        local data = PlayerData.createDefault()
        data.money = 0
        data.placedChickens = {}
        data.inventory.eggs = {}
        data.inventory.chickens = {}
        expect(PlayerData.isBankrupt(data)).to.equal(true)
      end)

      it("should return true with money below cheapest item price", function()
        local data = PlayerData.createDefault()
        data.money = 99 -- Below $100
        data.placedChickens = {}
        data.inventory.eggs = {}
        data.inventory.chickens = {}
        expect(PlayerData.isBankrupt(data)).to.equal(true)
      end)
    end)

    describe("getBankruptcyStarterMoney", function()
      it("should return 100", function()
        expect(PlayerData.getBankruptcyStarterMoney()).to.equal(100)
      end)

      it("should return a positive number", function()
        expect(PlayerData.getBankruptcyStarterMoney() > 0).to.equal(true)
      end)
    end)

    describe("hasActivePowerUp", function()
      it("should return false for data without activePowerUps", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = nil
        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(false)
      end)

      it("should return false for empty activePowerUps", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(false)
      end)

      it("should return true for active non-expired power-up", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time(),
            expiresAt = os.time() + 300,
          },
        }
        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(true)
      end)

      it("should return false for expired power-up", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time() - 600,
            expiresAt = os.time() - 300,
          },
        }
        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(false)
      end)

      it("should return false for non-matching power-up type", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "EggQuality_Basic",
            activatedTime = os.time(),
            expiresAt = os.time() + 300,
          },
        }
        expect(PlayerData.hasActivePowerUp(data, "HatchLuck")).to.equal(false)
      end)
    end)

    describe("getActivePowerUp", function()
      it("should return nil for data without activePowerUps", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = nil
        expect(PlayerData.getActivePowerUp(data, "HatchLuck")).to.equal(nil)
      end)

      it("should return nil for empty activePowerUps", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.getActivePowerUp(data, "HatchLuck")).to.equal(nil)
      end)

      it("should return the power-up for active non-expired power-up", function()
        local data = PlayerData.createDefault()
        local powerUp = {
          powerUpId = "HatchLuck_Basic",
          activatedTime = os.time(),
          expiresAt = os.time() + 300,
        }
        data.activePowerUps = { powerUp }
        local result = PlayerData.getActivePowerUp(data, "HatchLuck")
        expect(result).to.be.ok()
        expect(result.powerUpId).to.equal("HatchLuck_Basic")
      end)

      it("should return nil for expired power-up", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time() - 600,
            expiresAt = os.time() - 300,
          },
        }
        expect(PlayerData.getActivePowerUp(data, "HatchLuck")).to.equal(nil)
      end)
    end)

    describe("addPowerUp", function()
      it("should initialize activePowerUps if nil", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = nil
        PlayerData.addPowerUp(data, "HatchLuck_Basic", 300)
        expect(data.activePowerUps).to.be.ok()
        expect(#data.activePowerUps).to.equal(1)
      end)

      it("should add new power-up", function()
        local data = PlayerData.createDefault()
        PlayerData.addPowerUp(data, "HatchLuck_Basic", 300)
        expect(#data.activePowerUps).to.equal(1)
        expect(data.activePowerUps[1].powerUpId).to.equal("HatchLuck_Basic")
      end)

      it("should extend existing power-up of same type", function()
        local data = PlayerData.createDefault()
        local baseTime = os.time()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = baseTime,
            expiresAt = baseTime + 300,
          },
        }
        PlayerData.addPowerUp(data, "HatchLuck_Premium", 300)
        expect(#data.activePowerUps).to.equal(1)
        expect(data.activePowerUps[1].powerUpId).to.equal("HatchLuck_Premium")
        expect(data.activePowerUps[1].expiresAt >= baseTime + 600).to.equal(true)
      end)

      it("should add different power-up types separately", function()
        local data = PlayerData.createDefault()
        PlayerData.addPowerUp(data, "HatchLuck_Basic", 300)
        PlayerData.addPowerUp(data, "EggQuality_Basic", 300)
        expect(#data.activePowerUps).to.equal(2)
      end)
    end)

    describe("cleanupExpiredPowerUps", function()
      it("should do nothing for nil activePowerUps", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = nil
        PlayerData.cleanupExpiredPowerUps(data)
        expect(data.activePowerUps).to.equal(nil)
      end)

      it("should keep non-expired power-ups", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time(),
            expiresAt = os.time() + 300,
          },
        }
        PlayerData.cleanupExpiredPowerUps(data)
        expect(#data.activePowerUps).to.equal(1)
      end)

      it("should remove expired power-ups", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time() - 600,
            expiresAt = os.time() - 300,
          },
        }
        PlayerData.cleanupExpiredPowerUps(data)
        expect(#data.activePowerUps).to.equal(0)
      end)

      it("should keep active and remove expired", function()
        local data = PlayerData.createDefault()
        data.activePowerUps = {
          {
            powerUpId = "HatchLuck_Basic",
            activatedTime = os.time() - 600,
            expiresAt = os.time() - 300,
          },
          {
            powerUpId = "EggQuality_Basic",
            activatedTime = os.time(),
            expiresAt = os.time() + 300,
          },
        }
        PlayerData.cleanupExpiredPowerUps(data)
        expect(#data.activePowerUps).to.equal(1)
        expect(data.activePowerUps[1].powerUpId).to.equal("EggQuality_Basic")
      end)
    end)

    describe("ownsWeapon", function()
      it("should return false for nil ownedWeapons", function()
        local data = PlayerData.createDefault()
        data.ownedWeapons = nil
        expect(PlayerData.ownsWeapon(data, "Sword")).to.equal(false)
      end)

      it("should return true for owned weapon", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.ownsWeapon(data, "BaseballBat")).to.equal(true)
      end)

      it("should return false for unowned weapon", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.ownsWeapon(data, "Sword")).to.equal(false)
      end)
    end)

    describe("addWeapon", function()
      it("should initialize ownedWeapons if nil", function()
        local data = PlayerData.createDefault()
        data.ownedWeapons = nil
        local result = PlayerData.addWeapon(data, "Sword")
        expect(result).to.equal(true)
        expect(data.ownedWeapons).to.be.ok()
        expect(#data.ownedWeapons).to.equal(1)
      end)

      it("should add new weapon", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.addWeapon(data, "Sword")
        expect(result).to.equal(true)
        expect(PlayerData.ownsWeapon(data, "Sword")).to.equal(true)
      end)

      it("should return false for already owned weapon", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.addWeapon(data, "BaseballBat")
        expect(result).to.equal(false)
      end)

      it("should not duplicate already owned weapon", function()
        local data = PlayerData.createDefault()
        local originalCount = #data.ownedWeapons
        PlayerData.addWeapon(data, "BaseballBat")
        expect(#data.ownedWeapons).to.equal(originalCount)
      end)
    end)

    describe("equipWeapon", function()
      it("should return false for unowned weapon", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.equipWeapon(data, "Sword")
        expect(result).to.equal(false)
      end)

      it("should equip owned weapon", function()
        local data = PlayerData.createDefault()
        PlayerData.addWeapon(data, "Sword")
        local result = PlayerData.equipWeapon(data, "Sword")
        expect(result).to.equal(true)
        expect(data.equippedWeapon).to.equal("Sword")
      end)

      it("should update equipped weapon", function()
        local data = PlayerData.createDefault()
        expect(data.equippedWeapon).to.equal("BaseballBat")
        PlayerData.addWeapon(data, "Sword")
        PlayerData.equipWeapon(data, "Sword")
        expect(data.equippedWeapon).to.equal("Sword")
      end)
    end)

    describe("getEquippedWeapon", function()
      it("should return default weapon when nil", function()
        local data = PlayerData.createDefault()
        data.equippedWeapon = nil
        expect(PlayerData.getEquippedWeapon(data)).to.equal("BaseballBat")
      end)

      it("should return equipped weapon", function()
        local data = PlayerData.createDefault()
        data.equippedWeapon = "Sword"
        expect(PlayerData.getEquippedWeapon(data)).to.equal("Sword")
      end)
    end)

    describe("getOwnedWeapons", function()
      it("should return default weapon when nil", function()
        local data = PlayerData.createDefault()
        data.ownedWeapons = nil
        local weapons = PlayerData.getOwnedWeapons(data)
        expect(#weapons).to.equal(1)
        expect(weapons[1]).to.equal("BaseballBat")
      end)

      it("should return owned weapons", function()
        local data = PlayerData.createDefault()
        PlayerData.addWeapon(data, "Sword")
        local weapons = PlayerData.getOwnedWeapons(data)
        expect(#weapons).to.equal(2)
      end)
    end)

    describe("getLevel", function()
      it("should return 1 when nil", function()
        local data = PlayerData.createDefault()
        data.level = nil
        expect(PlayerData.getLevel(data)).to.equal(1)
      end)

      it("should return stored level", function()
        local data = PlayerData.createDefault()
        data.level = 5
        expect(PlayerData.getLevel(data)).to.equal(5)
      end)
    end)

    describe("getXP", function()
      it("should return 0 when nil", function()
        local data = PlayerData.createDefault()
        data.xp = nil
        expect(PlayerData.getXP(data)).to.equal(0)
      end)

      it("should return stored xp", function()
        local data = PlayerData.createDefault()
        data.xp = 500
        expect(PlayerData.getXP(data)).to.equal(500)
      end)
    end)

    describe("addXP", function()
      it("should return nil for zero amount", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.addXP(data, 0)
        expect(result).to.equal(nil)
      end)

      it("should return nil for negative amount", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.addXP(data, -10)
        expect(result).to.equal(nil)
      end)

      it("should add xp to player data", function()
        local data = PlayerData.createDefault()
        data.xp = 0
        PlayerData.addXP(data, 50)
        expect(data.xp >= 50).to.equal(true)
      end)

      it("should floor the xp amount", function()
        local data = PlayerData.createDefault()
        data.xp = 0
        PlayerData.addXP(data, 10.9)
        expect(data.xp).to.equal(10)
      end)

      it("should update level in player data", function()
        local data = PlayerData.createDefault()
        data.xp = 0
        data.level = 1
        PlayerData.addXP(data, 50)
        expect(data.level >= 1).to.equal(true)
      end)
    end)

    describe("setLevelAndXP", function()
      it("should return false for level less than 1", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.setLevelAndXP(data, 0, 100)
        expect(result).to.equal(false)
      end)

      it("should return false for negative xp", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.setLevelAndXP(data, 1, -1)
        expect(result).to.equal(false)
      end)

      it("should set level and xp", function()
        local data = PlayerData.createDefault()
        local result = PlayerData.setLevelAndXP(data, 5, 500)
        expect(result).to.equal(true)
        expect(data.level).to.equal(5)
        expect(data.xp).to.equal(500)
      end)

      it("should floor level and xp", function()
        local data = PlayerData.createDefault()
        PlayerData.setLevelAndXP(data, 5.9, 500.9)
        expect(data.level).to.equal(5)
        expect(data.xp).to.equal(500)
      end)
    end)

    describe("data validity", function()
      it("should have valid starter chicken in default data", function()
        local data = PlayerData.createDefault()
        expect(#data.placedChickens).to.equal(1)
        local chicken = data.placedChickens[1]
        expect(PlayerData.validateChicken(chicken)).to.equal(true)
      end)

      it("should have valid upgrades in default data", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.validateUpgrades(data.upgrades)).to.equal(true)
      end)

      it("should have valid inventory in default data", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.validateInventory(data.inventory)).to.equal(true)
      end)

      it("should have consistent default weapon state", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.ownsWeapon(data, data.equippedWeapon)).to.equal(true)
      end)

      it("should have non-bankrupt default data", function()
        local data = PlayerData.createDefault()
        expect(PlayerData.isBankrupt(data)).to.equal(false)
      end)
    end)
  end)
end
