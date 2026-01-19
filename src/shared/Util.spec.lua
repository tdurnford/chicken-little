--[[
	Util.spec.lua
	TestEZ tests for Util module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local Util = require(Shared:WaitForChild("Util"))

  describe("Util", function()
    describe("clamp", function()
      it("should return the value when within range", function()
        expect(Util.clamp(5, 0, 10)).to.equal(5)
        expect(Util.clamp(0, 0, 10)).to.equal(0)
        expect(Util.clamp(10, 0, 10)).to.equal(10)
      end)

      it("should return lo when value is below range", function()
        expect(Util.clamp(-5, 0, 10)).to.equal(0)
        expect(Util.clamp(-100, 0, 10)).to.equal(0)
      end)

      it("should return hi when value is above range", function()
        expect(Util.clamp(15, 0, 10)).to.equal(10)
        expect(Util.clamp(100, 0, 10)).to.equal(10)
      end)

      it("should handle negative ranges", function()
        expect(Util.clamp(-5, -10, -1)).to.equal(-5)
        expect(Util.clamp(0, -10, -1)).to.equal(-1)
        expect(Util.clamp(-15, -10, -1)).to.equal(-10)
      end)

      it("should handle decimal values", function()
        expect(Util.clamp(0.5, 0, 1)).to.equal(0.5)
        expect(Util.clamp(-0.5, 0, 1)).to.equal(0)
        expect(Util.clamp(1.5, 0, 1)).to.equal(1)
      end)

      it("should handle equal lo and hi", function()
        expect(Util.clamp(5, 3, 3)).to.equal(3)
        expect(Util.clamp(1, 3, 3)).to.equal(3)
      end)

      it("should handle edge case with zero range at zero", function()
        expect(Util.clamp(5, 0, 0)).to.equal(0)
        expect(Util.clamp(-5, 0, 0)).to.equal(0)
        expect(Util.clamp(0, 0, 0)).to.equal(0)
      end)

      it("should handle large numbers", function()
        expect(Util.clamp(1000000, 0, 999999)).to.equal(999999)
        expect(Util.clamp(-1000000, -500000, 500000)).to.equal(-500000)
      end)

      it("should handle very small decimal differences", function()
        expect(Util.clamp(0.0001, 0, 0.001)).to.equal(0.0001)
        expect(Util.clamp(0.0001, 0.001, 0.01)).to.equal(0.001)
      end)
    end)
  end)
end
