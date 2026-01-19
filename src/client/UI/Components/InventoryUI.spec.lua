--[[
	InventoryUI.spec.lua
	TestEZ tests for the Fusion InventoryUI component.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Players = game:GetService("Players")

  local Packages = ReplicatedStorage:WaitForChild("Packages")
  local Fusion = require(Packages:WaitForChild("Fusion"))

  -- Get the component (relative import)
  local InventoryUI = require(script.Parent.InventoryUI)

  -- Helper to wait for creation
  local function waitForGui(timeout: number?): ScreenGui?
    local elapsed = 0
    local maxTime = timeout or 1
    while elapsed < maxTime do
      local gui = InventoryUI.getScreenGui()
      if gui then
        return gui
      end
      task.wait(0.05)
      elapsed = elapsed + 0.05
    end
    return nil
  end

  describe("InventoryUI", function()
    afterEach(function()
      -- Clean up after each test
      InventoryUI.destroy()
    end)

    describe("create()", function()
      it("should create successfully", function()
        local result = InventoryUI.create()
        expect(result).to.equal(true)
      end)

      it("should return false if already created", function()
        InventoryUI.create()
        local secondResult = InventoryUI.create()
        expect(secondResult).to.equal(false)
      end)

      it("should create a ScreenGui", function()
        InventoryUI.create()
        local gui = InventoryUI.getScreenGui()
        expect(gui).to.be.ok()
        expect(gui.Name).to.equal("InventoryUI")
      end)

      it("should create InventoryFrame", function()
        InventoryUI.create()
        local gui = InventoryUI.getScreenGui()
        expect(gui).to.be.ok()
        local frame = gui:FindFirstChild("InventoryFrame")
        expect(frame).to.be.ok()
      end)
    end)

    describe("destroy()", function()
      it("should cleanup resources", function()
        InventoryUI.create()
        expect(InventoryUI.isCreated()).to.equal(true)

        InventoryUI.destroy()
        expect(InventoryUI.isCreated()).to.equal(false)
        expect(InventoryUI.getScreenGui()).to.equal(nil)
      end)

      it("should handle double destroy gracefully", function()
        InventoryUI.create()
        InventoryUI.destroy()
        -- Should not error on second destroy
        InventoryUI.destroy()
        expect(InventoryUI.isCreated()).to.equal(false)
      end)
    end)

    describe("visibility", function()
      it("should start hidden", function()
        InventoryUI.create()
        expect(InventoryUI.isVisible()).to.equal(false)
      end)

      it("should set visibility", function()
        InventoryUI.create()
        InventoryUI.setVisible(true)
        expect(InventoryUI.isVisible()).to.equal(true)

        InventoryUI.setVisible(false)
        expect(InventoryUI.isVisible()).to.equal(false)
      end)

      it("should toggle visibility", function()
        InventoryUI.create()
        expect(InventoryUI.isVisible()).to.equal(false)

        InventoryUI.toggle()
        expect(InventoryUI.isVisible()).to.equal(true)

        InventoryUI.toggle()
        expect(InventoryUI.isVisible()).to.equal(false)
      end)

      it("should call onVisibilityChanged callback", function()
        local callbackCalled = false
        local callbackValue = nil

        InventoryUI.create({
          onVisibilityChanged = function(visible)
            callbackCalled = true
            callbackValue = visible
          end,
        })

        InventoryUI.setVisible(true)
        expect(callbackCalled).to.equal(true)
        expect(callbackValue).to.equal(true)
      end)
    end)

    describe("tabs", function()
      it("should default to eggs tab", function()
        InventoryUI.create()
        expect(InventoryUI.getCurrentTab()).to.equal("eggs")
      end)

      it("should change tabs", function()
        InventoryUI.create()

        InventoryUI.setTab("chickens")
        expect(InventoryUI.getCurrentTab()).to.equal("chickens")

        InventoryUI.setTab("traps")
        expect(InventoryUI.getCurrentTab()).to.equal("traps")

        InventoryUI.setTab("eggs")
        expect(InventoryUI.getCurrentTab()).to.equal("eggs")
      end)

      it("should clear selection when changing tabs", function()
        InventoryUI.create()
        -- Note: Can't easily test selection without actual items,
        -- but we verify the tab clears any existing selection
        InventoryUI.setTab("chickens")
        expect(InventoryUI.getSelectedItem()).to.equal(nil)
      end)
    end)

    describe("selection", function()
      it("should start with no selection", function()
        InventoryUI.create()
        expect(InventoryUI.getSelectedItem()).to.equal(nil)
      end)

      it("should clear selection", function()
        InventoryUI.create()
        InventoryUI.clearSelection()
        expect(InventoryUI.getSelectedItem()).to.equal(nil)
      end)
    end)

    describe("callbacks", function()
      it("should accept onAction callback", function()
        local called = false
        InventoryUI.create()
        InventoryUI.onAction(function()
          called = true
        end)
        -- Note: Action requires selection, so we just verify no error
        expect(InventoryUI.isCreated()).to.equal(true)
      end)

      it("should accept onItemSelected callback", function()
        local called = false
        InventoryUI.create()
        InventoryUI.onItemSelected(function()
          called = true
        end)
        -- Verify no error
        expect(InventoryUI.isCreated()).to.equal(true)
      end)
    end)

    describe("getRarityColors", function()
      it("should return rarity colors", function()
        local colors = InventoryUI.getRarityColors()
        expect(colors).to.be.ok()
        expect(colors.Common).to.be.ok()
        expect(colors.Legendary).to.be.ok()
        expect(typeof(colors.Common)).to.equal("Color3")
      end)
    end)

    describe("getItemCounts", function()
      it("should count items from player data", function()
        local mockData = {
          inventory = {
            eggs = { {}, {}, {} },
            chickens = { {}, {} },
          },
          traps = { {} },
        }

        local counts = InventoryUI.getItemCounts(mockData)
        expect(counts.eggs).to.equal(3)
        expect(counts.chickens).to.equal(2)
        expect(counts.traps).to.equal(1)
      end)

      it("should handle empty data", function()
        local mockData = {}
        local counts = InventoryUI.getItemCounts(mockData)
        expect(counts.eggs).to.equal(0)
        expect(counts.chickens).to.equal(0)
        expect(counts.traps).to.equal(0)
      end)
    end)

    describe("updateFromPlayerData", function()
      it("should not error (legacy compatibility)", function()
        InventoryUI.create()
        -- Should be a no-op but not error
        InventoryUI.updateFromPlayerData({})
        expect(InventoryUI.isCreated()).to.equal(true)
      end)
    end)

    describe("structure", function()
      it("should have TabFrame with three tabs", function()
        InventoryUI.create()
        InventoryUI.setVisible(true)
        local gui = InventoryUI.getScreenGui()
        local frame = gui:FindFirstChild("InventoryFrame")
        expect(frame).to.be.ok()

        local contentContainer = frame:FindFirstChild("ContentContainer")
        expect(contentContainer).to.be.ok()

        local tabFrame = contentContainer:FindFirstChild("TabFrame")
        expect(tabFrame).to.be.ok()

        expect(tabFrame:FindFirstChild("eggsTab")).to.be.ok()
        expect(tabFrame:FindFirstChild("chickensTab")).to.be.ok()
        expect(tabFrame:FindFirstChild("trapsTab")).to.be.ok()
      end)

      it("should have ContentFrame", function()
        InventoryUI.create()
        local gui = InventoryUI.getScreenGui()
        local frame = gui:FindFirstChild("InventoryFrame")
        local contentContainer = frame:FindFirstChild("ContentContainer")
        local contentFrame = contentContainer:FindFirstChild("ContentFrame")
        expect(contentFrame).to.be.ok()
        expect(contentFrame:IsA("ScrollingFrame")).to.equal(true)
      end)

      it("should have ActionFrame", function()
        InventoryUI.create()
        local gui = InventoryUI.getScreenGui()
        local frame = gui:FindFirstChild("InventoryFrame")
        local contentContainer = frame:FindFirstChild("ContentContainer")
        local actionFrame = contentContainer:FindFirstChild("ActionFrame")
        expect(actionFrame).to.be.ok()
      end)

      it("should have close button", function()
        InventoryUI.create()
        local gui = InventoryUI.getScreenGui()
        local frame = gui:FindFirstChild("InventoryFrame")
        local titleBar = frame:FindFirstChild("TitleBar")
        expect(titleBar).to.be.ok()

        local closeButton = titleBar:FindFirstChild("CloseButton")
        expect(closeButton).to.be.ok()
      end)
    end)
  end)
end
