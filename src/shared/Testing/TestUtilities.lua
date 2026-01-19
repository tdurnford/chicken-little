--[[
	TestUtilities.lua
	Common utilities for TestEZ tests including mock helpers and assertions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestUtilities = {}

export type MockFunction = {
  calls: { { args: { any } } },
  returnValue: any,
  implementation: ((...any) -> any)?,
  call: (self: MockFunction, ...any) -> any,
  reset: (self: MockFunction) -> (),
  wasCalled: (self: MockFunction) -> boolean,
  wasCalledWith: (self: MockFunction, ...any) -> boolean,
  wasCalledTimes: (self: MockFunction, count: number) -> boolean,
  getCallCount: (self: MockFunction) -> number,
  getLastCall: (self: MockFunction) -> { args: { any } }?,
}

-- Create a mock function for testing
function TestUtilities.createMockFunction(returnValue: any?): MockFunction
  local mock = {
    calls = {},
    returnValue = returnValue,
    implementation = nil,
  }

  function mock:call(...: any): any
    local args = { ... }
    table.insert(self.calls, { args = args })

    if self.implementation then
      return self.implementation(...)
    end

    return self.returnValue
  end

  function mock:reset()
    self.calls = {}
  end

  function mock:wasCalled(): boolean
    return #self.calls > 0
  end

  function mock:wasCalledWith(...: any): boolean
    local expectedArgs = { ... }

    for _, callInfo in self.calls do
      local matches = true
      for i, arg in expectedArgs do
        if callInfo.args[i] ~= arg then
          matches = false
          break
        end
      end
      if matches then
        return true
      end
    end

    return false
  end

  function mock:wasCalledTimes(count: number): boolean
    return #self.calls == count
  end

  function mock:getCallCount(): number
    return #self.calls
  end

  function mock:getLastCall(): { args: { any } }?
    if #self.calls == 0 then
      return nil
    end
    return self.calls[#self.calls]
  end

  return mock
end

-- Create a spy that wraps an existing function
function TestUtilities.createSpy(originalFn: (...any) -> any): MockFunction
  local mock = TestUtilities.createMockFunction()
  mock.implementation = originalFn
  return mock
end

-- Wait for a condition with timeout
function TestUtilities.waitForCondition(
  condition: () -> boolean,
  timeout: number?,
  interval: number?
): boolean
  timeout = timeout or 5
  interval = interval or 0.1

  local elapsed = 0
  while elapsed < timeout do
    if condition() then
      return true
    end
    task.wait(interval)
    elapsed = elapsed + interval
  end

  return false
end

-- Wait for a value to change
function TestUtilities.waitForChange<T>(getter: () -> T, timeout: number?): (boolean, T, T)
  timeout = timeout or 5
  local initialValue = getter()

  local changed = TestUtilities.waitForCondition(function()
    return getter() ~= initialValue
  end, timeout)

  return changed, initialValue, getter()
end

-- Deep compare two tables
function TestUtilities.deepEqual(a: any, b: any): boolean
  if type(a) ~= type(b) then
    return false
  end

  if type(a) ~= "table" then
    return a == b
  end

  -- Check all keys in a exist in b with same values
  for key, value in pairs(a) do
    if not TestUtilities.deepEqual(value, b[key]) then
      return false
    end
  end

  -- Check all keys in b exist in a
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end

  return true
end

-- Create a shallow copy of a table
function TestUtilities.shallowCopy<T>(original: T): T
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original :: any) do
    copy[key] = value
  end

  return copy :: T
end

-- Create a deep copy of a table
function TestUtilities.deepCopy<T>(original: T): T
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original :: any) do
    copy[key] = TestUtilities.deepCopy(value)
  end

  return copy :: T
end

-- Assert that a table contains specific keys
function TestUtilities.assertHasKeys(tbl: { [any]: any }, keys: { string }): boolean
  for _, key in keys do
    if tbl[key] == nil then
      return false
    end
  end
  return true
end

-- Create a test instance (for testing purposes)
function TestUtilities.createTestInstance(
  className: string,
  properties: { [string]: any }?
): Instance
  local instance = Instance.new(className)

  if properties then
    for key, value in properties do
      (instance :: any)[key] = value
    end
  end

  return instance
end

-- Clean up test instances
function TestUtilities.cleanupInstances(instances: { Instance })
  for _, instance in instances do
    if instance.Parent then
      instance:Destroy()
    end
  end
end

-- Measure execution time of a function
function TestUtilities.measureTime(fn: () -> ()): number
  local start = os.clock()
  fn()
  return os.clock() - start
end

-- Generate a random string for test data
function TestUtilities.randomString(length: number?): string
  length = length or 8
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local result = ""

  for _ = 1, length do
    local index = math.random(1, #chars)
    result = result .. string.sub(chars, index, index)
  end

  return result
end

-- Generate a random number in range
function TestUtilities.randomNumber(min: number, max: number): number
  return math.random(min, max)
end

-- Async test helper - wraps a test that uses promises/yields
function TestUtilities.async(fn: () -> ()): () -> ()
  return function()
    local co = coroutine.create(fn)
    local success, err = coroutine.resume(co)
    if not success then
      error(err)
    end
  end
end

-- Defer execution helper for tests that need to wait for next frame
function TestUtilities.nextFrame(): ()
  task.wait()
end

-- Get the Packages folder for requiring dependencies in tests
function TestUtilities.getPackages(): Folder
  return ReplicatedStorage:WaitForChild("Packages") :: Folder
end

return TestUtilities
