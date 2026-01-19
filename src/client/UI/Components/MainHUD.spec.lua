--[[
	MainHUD.spec.lua
	Tests for the Fusion MainHUD component.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Players = game:GetService("Players")

  -- Module under test (will be required in beforeEach for isolation)
  local MainHUD

  -- Mock cleanup
  local mockCleanupList = {}

  beforeEach(function()
    -- Fresh require for each test
    MainHUD = require(script.Parent.MainHUD)
    mockCleanupList = {}
  end)

  afterEach(function()
    -- Cleanup any created HUD instances
    pcall(function()
      MainHUD.destroy()
    end)

    -- Cleanup any mock objects
    for _, item in ipairs(mockCleanupList) do
      pcall(function()
        item:Destroy()
      end)
    end
  end)

  describe("MainHUD", function()
    describe("create", function()
      it("should return true on successful creation", function()
        local result = MainHUD.create()
        expect(result).to.equal(true)
      end)

      it("should return false when called twice", function()
        MainHUD.create()
        local secondResult = MainHUD.create()
        expect(secondResult).to.equal(false)
      end)

      it("should set isCreated to true after creation", function()
        expect(MainHUD.isCreated()).to.equal(false)
        MainHUD.create()
        expect(MainHUD.isCreated()).to.equal(true)
      end)

      it("should accept optional props", function()
        local clickCount = 0
        local result = MainHUD.create({
          onInventoryClick = function()
            clickCount = clickCount + 1
          end,
        })
        expect(result).to.equal(true)
      end)
    end)

    describe("destroy", function()
      it("should set isCreated to false", function()
        MainHUD.create()
        expect(MainHUD.isCreated()).to.equal(true)
        MainHUD.destroy()
        expect(MainHUD.isCreated()).to.equal(false)
      end)

      it("should handle being called without create", function()
        -- Should not error
        expect(function()
          MainHUD.destroy()
        end).never.to.throw()
      end)

      it("should allow recreation after destroy", function()
        MainHUD.create()
        MainHUD.destroy()
        local result = MainHUD.create()
        expect(result).to.equal(true)
      end)
    end)

    describe("visibility", function()
      it("should be visible by default after creation", function()
        MainHUD.create()
        expect(MainHUD.isVisible()).to.equal(true)
      end)

      it("should allow setting visibility", function()
        MainHUD.create()
        MainHUD.setVisible(false)
        expect(MainHUD.isVisible()).to.equal(false)
        MainHUD.setVisible(true)
        expect(MainHUD.isVisible()).to.equal(true)
      end)

      it("should return false for isVisible when not created", function()
        expect(MainHUD.isVisible()).to.equal(false)
      end)
    end)

    describe("getScreenGui", function()
      it("should return nil when not created", function()
        expect(MainHUD.getScreenGui()).to.equal(nil)
      end)

      it("should return ScreenGui when created", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        expect(gui).to.be.ok()
        expect(gui:IsA("ScreenGui")).to.equal(true)
      end)

      it("should return ScreenGui named MainHUD", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        expect(gui.Name).to.equal("MainHUD")
      end)
    end)

    describe("notifications", function()
      it("should not error when showing notification without HUD", function()
        expect(function()
          MainHUD.showNotification("Test message")
        end).never.to.throw()
      end)

      it("should not error when showing level up without HUD", function()
        expect(function()
          MainHUD.showLevelUp(5)
        end).never.to.throw()
      end)

      it("should not error when showing XP gain without HUD", function()
        expect(function()
          MainHUD.showXPGain(100)
        end).never.to.throw()
      end)

      it("should not error when showing bankruptcy assistance without HUD", function()
        expect(function()
          MainHUD.showBankruptcyAssistance({
            moneyAwarded = 500,
            message = "Test assistance",
          })
        end).never.to.throw()
      end)

      it("should create notification with HUD present", function()
        MainHUD.create()
        -- Should not error
        expect(function()
          MainHUD.showNotification("Test notification", nil, 0.1)
        end).never.to.throw()
      end)

      it("should create level up notification with HUD present", function()
        MainHUD.create()
        expect(function()
          MainHUD.showLevelUp(10, { "New chicken type unlocked!" })
        end).never.to.throw()
      end)
    end)

    describe("HUD structure", function()
      it("should contain MoneyFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local moneyFrame = gui:FindFirstChild("MoneyFrame")
        expect(moneyFrame).to.be.ok()
      end)

      it("should contain LevelFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local levelFrame = gui:FindFirstChild("LevelFrame")
        expect(levelFrame).to.be.ok()
      end)

      it("should contain ChickenCountFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local chickenFrame = gui:FindFirstChild("ChickenCountFrame")
        expect(chickenFrame).to.be.ok()
      end)

      it("should have MoneyLabel inside MoneyFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local moneyFrame = gui:FindFirstChild("MoneyFrame")
        local moneyLabel = moneyFrame:FindFirstChild("MoneyLabel")
        expect(moneyLabel).to.be.ok()
        expect(moneyLabel:IsA("TextLabel")).to.equal(true)
      end)

      it("should have LevelLabel inside LevelFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local levelFrame = gui:FindFirstChild("LevelFrame")
        local levelLabel = levelFrame:FindFirstChild("LevelLabel")
        expect(levelLabel).to.be.ok()
        expect(levelLabel:IsA("TextLabel")).to.equal(true)
      end)

      it("should have XPProgressBar inside LevelFrame", function()
        MainHUD.create()
        local gui = MainHUD.getScreenGui()
        local levelFrame = gui:FindFirstChild("LevelFrame")
        local progressBar = levelFrame:FindFirstChild("XPProgressBar")
        expect(progressBar).to.be.ok()
        expect(progressBar:IsA("Frame")).to.equal(true)
      end)
    end)
  end)
end
