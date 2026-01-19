--[[
	PowerUpConfig.spec.lua
	TestEZ tests for PowerUpConfig module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local PowerUpConfig = require(Shared:WaitForChild("PowerUpConfig"))

  describe("PowerUpConfig", function()
    describe("get", function()
      it("should return config for valid power-up ID", function()
        local config = PowerUpConfig.get("HatchLuck15")
        expect(config).to.be.ok()
        expect(config.id).to.equal("HatchLuck15")
      end)

      it("should return nil for invalid power-up ID", function()
        local config = PowerUpConfig.get("InvalidPowerUp")
        expect(config).to.equal(nil)
      end)

      it("should return config with required fields", function()
        local config = PowerUpConfig.get("HatchLuck15")
        expect(config).to.be.ok()
        expect(config.id).to.be.ok()
        expect(config.name).to.be.ok()
        expect(config.displayName).to.be.ok()
        expect(config.description).to.be.ok()
        expect(config.icon).to.be.ok()
        expect(config.durationSeconds).to.be.ok()
        expect(config.robuxPrice).to.be.ok()
        expect(config.boostMultiplier).to.be.ok()
      end)
    end)

    describe("getAll", function()
      it("should return a table of power-ups", function()
        local all = PowerUpConfig.getAll()
        expect(typeof(all)).to.equal("table")
      end)

      it("should contain multiple power-ups", function()
        local all = PowerUpConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count > 0).to.equal(true)
      end)

      it("should have 6 power-ups (3 HatchLuck + 3 EggQuality)", function()
        local all = PowerUpConfig.getAll()
        local count = 0
        for _ in pairs(all) do
          count = count + 1
        end
        expect(count).to.equal(6)
      end)
    end)

    describe("getAllSorted", function()
      it("should return an array", function()
        local sorted = PowerUpConfig.getAllSorted()
        expect(typeof(sorted)).to.equal("table")
        expect(#sorted > 0).to.equal(true)
      end)

      it("should be sorted by robux price", function()
        local sorted = PowerUpConfig.getAllSorted()
        for i = 2, #sorted do
          expect(sorted[i].robuxPrice >= sorted[i - 1].robuxPrice).to.equal(true)
        end
      end)
    end)

    describe("getByType", function()
      it("should return HatchLuck power-ups", function()
        local hatchLuck = PowerUpConfig.getByType("HatchLuck")
        expect(#hatchLuck).to.equal(3)
        for _, config in ipairs(hatchLuck) do
          expect(string.find(config.id, "HatchLuck")).to.be.ok()
        end
      end)

      it("should return EggQuality power-ups", function()
        local eggQuality = PowerUpConfig.getByType("EggQuality")
        expect(#eggQuality).to.equal(3)
        for _, config in ipairs(eggQuality) do
          expect(string.find(config.id, "EggQuality")).to.be.ok()
        end
      end)

      it("should return empty array for invalid type", function()
        local invalid = PowerUpConfig.getByType("InvalidType" :: any)
        expect(#invalid).to.equal(0)
      end)
    end)

    describe("isValid", function()
      it("should return true for valid power-up IDs", function()
        expect(PowerUpConfig.isValid("HatchLuck15")).to.equal(true)
        expect(PowerUpConfig.isValid("HatchLuck60")).to.equal(true)
        expect(PowerUpConfig.isValid("HatchLuck240")).to.equal(true)
        expect(PowerUpConfig.isValid("EggQuality15")).to.equal(true)
        expect(PowerUpConfig.isValid("EggQuality60")).to.equal(true)
        expect(PowerUpConfig.isValid("EggQuality240")).to.equal(true)
      end)

      it("should return false for invalid power-up IDs", function()
        expect(PowerUpConfig.isValid("InvalidPowerUp")).to.equal(false)
        expect(PowerUpConfig.isValid("")).to.equal(false)
      end)
    end)

    describe("getPowerUpType", function()
      it("should return HatchLuck for HatchLuck power-ups", function()
        expect(PowerUpConfig.getPowerUpType("HatchLuck15")).to.equal("HatchLuck")
        expect(PowerUpConfig.getPowerUpType("HatchLuck60")).to.equal("HatchLuck")
        expect(PowerUpConfig.getPowerUpType("HatchLuck240")).to.equal("HatchLuck")
      end)

      it("should return EggQuality for EggQuality power-ups", function()
        expect(PowerUpConfig.getPowerUpType("EggQuality15")).to.equal("EggQuality")
        expect(PowerUpConfig.getPowerUpType("EggQuality60")).to.equal("EggQuality")
        expect(PowerUpConfig.getPowerUpType("EggQuality240")).to.equal("EggQuality")
      end)

      it("should return nil for invalid power-up ID", function()
        expect(PowerUpConfig.getPowerUpType("InvalidPowerUp")).to.equal(nil)
      end)
    end)

    describe("isActive", function()
      it("should return true for non-expired power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime,
          expiresAt = currentTime + 3600, -- expires in 1 hour
        }
        expect(PowerUpConfig.isActive(activePowerUp)).to.equal(true)
      end)

      it("should return false for expired power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime - 7200,
          expiresAt = currentTime - 3600, -- expired 1 hour ago
        }
        expect(PowerUpConfig.isActive(activePowerUp)).to.equal(false)
      end)
    end)

    describe("getRemainingTime", function()
      it("should return positive time for active power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime,
          expiresAt = currentTime + 3600,
        }
        local remaining = PowerUpConfig.getRemainingTime(activePowerUp)
        expect(remaining > 0).to.equal(true)
      end)

      it("should return 0 for expired power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime - 7200,
          expiresAt = currentTime - 3600,
        }
        local remaining = PowerUpConfig.getRemainingTime(activePowerUp)
        expect(remaining).to.equal(0)
      end)
    end)

    describe("activate", function()
      it("should return active power-up for valid ID", function()
        local active = PowerUpConfig.activate("HatchLuck15")
        expect(active).to.be.ok()
        expect(active.powerUpId).to.equal("HatchLuck15")
      end)

      it("should set correct expiry time", function()
        local config = PowerUpConfig.get("HatchLuck15")
        local active = PowerUpConfig.activate("HatchLuck15")
        expect(active).to.be.ok()
        expect(active.expiresAt).to.equal(active.activatedTime + config.durationSeconds)
      end)

      it("should return nil for invalid ID", function()
        local active = PowerUpConfig.activate("InvalidPowerUp")
        expect(active).to.equal(nil)
      end)
    end)

    describe("extend", function()
      it("should extend duration of same type power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime,
          expiresAt = currentTime + 900, -- 15 minutes from now
        }
        local extended = PowerUpConfig.extend(activePowerUp, "HatchLuck60")
        expect(extended).to.be.ok()
        expect(extended.expiresAt > activePowerUp.expiresAt).to.equal(true)
      end)

      it("should return nil for different type power-up", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime,
          expiresAt = currentTime + 900,
        }
        local extended = PowerUpConfig.extend(activePowerUp, "EggQuality15")
        expect(extended).to.equal(nil)
      end)

      it("should return nil for invalid power-up ID", function()
        local currentTime = os.time()
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = currentTime,
          expiresAt = currentTime + 900,
        }
        local extended = PowerUpConfig.extend(activePowerUp, "InvalidPowerUp")
        expect(extended).to.equal(nil)
      end)

      it("should keep original activation time", function()
        local currentTime = os.time()
        local originalActivationTime = currentTime - 500
        local activePowerUp = {
          powerUpId = "HatchLuck15",
          activatedTime = originalActivationTime,
          expiresAt = currentTime + 400,
        }
        local extended = PowerUpConfig.extend(activePowerUp, "HatchLuck15")
        expect(extended).to.be.ok()
        expect(extended.activatedTime).to.equal(originalActivationTime)
      end)
    end)

    describe("formatRemainingTime", function()
      it("should return Expired for 0 or negative seconds", function()
        expect(PowerUpConfig.formatRemainingTime(0)).to.equal("Expired")
        expect(PowerUpConfig.formatRemainingTime(-100)).to.equal("Expired")
      end)

      it("should format seconds correctly", function()
        local result = PowerUpConfig.formatRemainingTime(45)
        expect(string.find(result, "45s")).to.be.ok()
      end)

      it("should format minutes and seconds correctly", function()
        local result = PowerUpConfig.formatRemainingTime(125) -- 2m 5s
        expect(string.find(result, "2m")).to.be.ok()
        expect(string.find(result, "5s")).to.be.ok()
      end)

      it("should format hours and minutes correctly", function()
        local result = PowerUpConfig.formatRemainingTime(3720) -- 1h 2m
        expect(string.find(result, "1h")).to.be.ok()
        expect(string.find(result, "2m")).to.be.ok()
      end)
    end)

    describe("config data validity", function()
      it("should have positive duration for all power-ups", function()
        local all = PowerUpConfig.getAll()
        for id, config in pairs(all) do
          expect(config.durationSeconds > 0).to.equal(true)
        end
      end)

      it("should have positive robux price for all power-ups", function()
        local all = PowerUpConfig.getAll()
        for id, config in pairs(all) do
          expect(config.robuxPrice > 0).to.equal(true)
        end
      end)

      it("should have positive boost multiplier for all power-ups", function()
        local all = PowerUpConfig.getAll()
        for id, config in pairs(all) do
          expect(config.boostMultiplier > 0).to.equal(true)
        end
      end)

      it("should have matching id and name fields", function()
        local all = PowerUpConfig.getAll()
        for id, config in pairs(all) do
          expect(config.id).to.equal(id)
          expect(config.name).to.equal(id)
        end
      end)

      it("should have non-empty display names", function()
        local all = PowerUpConfig.getAll()
        for _, config in pairs(all) do
          expect(#config.displayName > 0).to.equal(true)
        end
      end)

      it("should have non-empty descriptions", function()
        local all = PowerUpConfig.getAll()
        for _, config in pairs(all) do
          expect(#config.description > 0).to.equal(true)
        end
      end)

      it("should have non-empty icons", function()
        local all = PowerUpConfig.getAll()
        for _, config in pairs(all) do
          expect(#config.icon > 0).to.equal(true)
        end
      end)

      it("should have longer durations cost more robux within same type", function()
        local hatchLuck = PowerUpConfig.getByType("HatchLuck")
        table.sort(hatchLuck, function(a, b)
          return a.durationSeconds < b.durationSeconds
        end)
        for i = 2, #hatchLuck do
          expect(hatchLuck[i].robuxPrice > hatchLuck[i - 1].robuxPrice).to.equal(true)
        end

        local eggQuality = PowerUpConfig.getByType("EggQuality")
        table.sort(eggQuality, function(a, b)
          return a.durationSeconds < b.durationSeconds
        end)
        for i = 2, #eggQuality do
          expect(eggQuality[i].robuxPrice > eggQuality[i - 1].robuxPrice).to.equal(true)
        end
      end)
    end)
  end)
end
