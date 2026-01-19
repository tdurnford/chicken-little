--[[
	TestRunner.lua
	Entry point for running TestEZ tests across the codebase.
	
	Usage:
		local TestRunner = require(ReplicatedStorage.Shared.Testing.TestRunner)
		TestRunner.run() -- Run all tests
		TestRunner.runServer() -- Run server tests only
		TestRunner.runClient() -- Run client tests only
		TestRunner.runShared() -- Run shared tests only
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local TestEZ = require(Packages:WaitForChild("TestEZ"))

export type TestResult = {
  success: boolean,
  failureCount: number,
  skippedCount: number,
  successCount: number,
  errors: { string },
}

local TestRunner = {}

-- Recursively find all .spec.lua ModuleScripts in a container
local function findSpecFiles(container: Instance): { ModuleScript }
  local specFiles: { ModuleScript } = {}

  local function search(instance: Instance)
    for _, child in instance:GetChildren() do
      if child:IsA("ModuleScript") and child.Name:match("%.spec$") then
        table.insert(specFiles, child)
      end
      search(child)
    end
  end

  search(container)
  return specFiles
end

-- Convert TestEZ results to our result format
local function convertResults(results: any): TestResult
  local errors: { string } = {}

  local function collectErrors(node: any, path: string)
    path = path or ""
    local nodePath = path ~= ""
        and (path .. " > " .. (node.planNode and node.planNode.phrase or ""))
      or (node.planNode and node.planNode.phrase or "")

    if node.errors then
      for _, err in node.errors do
        table.insert(errors, nodePath .. ": " .. tostring(err))
      end
    end

    if node.children then
      for _, child in node.children do
        collectErrors(child, nodePath)
      end
    end
  end

  collectErrors(results)

  return {
    success = results.failureCount == 0,
    failureCount = results.failureCount or 0,
    skippedCount = results.skippedCount or 0,
    successCount = results.successCount or 0,
    errors = errors,
  }
end

-- Print test results to output
local function printResults(result: TestResult, label: string)
  print(string.format("\n========== %s Test Results ==========", label))
  print(string.format("✓ Passed: %d", result.successCount))
  print(string.format("✗ Failed: %d", result.failureCount))
  print(string.format("⊘ Skipped: %d", result.skippedCount))

  if #result.errors > 0 then
    print("\n--- Errors ---")
    for _, err in result.errors do
      print("  • " .. err)
    end
  end

  print(string.format("\n%s: %s", label, result.success and "PASSED ✓" or "FAILED ✗"))
  print("==========================================\n")
end

-- Run tests from a specific container
function TestRunner.runContainer(container: Instance, label: string?): TestResult
  label = label or container.Name

  local specFiles = findSpecFiles(container)

  if #specFiles == 0 then
    print(string.format("[TestRunner] No spec files found in %s", label))
    return {
      success = true,
      failureCount = 0,
      skippedCount = 0,
      successCount = 0,
      errors = {},
    }
  end

  print(string.format("[TestRunner] Found %d spec files in %s", #specFiles, label))

  local results = TestEZ.TestBootstrap:run(specFiles)
  local converted = convertResults(results)
  printResults(converted, label)

  return converted
end

-- Run all server-side tests
function TestRunner.runServer(): TestResult
  local serverContainer = ServerScriptService:FindFirstChild("server")
  if not serverContainer then
    print("[TestRunner] No server container found at ServerScriptService.server")
    return {
      success = true,
      failureCount = 0,
      skippedCount = 0,
      successCount = 0,
      errors = {},
    }
  end
  return TestRunner.runContainer(serverContainer, "Server")
end

-- Run all client-side tests (must be called from client)
function TestRunner.runClient(): TestResult
  local player = Players.LocalPlayer
  if not player then
    print("[TestRunner] runClient() must be called from client context")
    return {
      success = false,
      failureCount = 1,
      skippedCount = 0,
      successCount = 0,
      errors = { "runClient() called from server context" },
    }
  end

  local clientContainer = player.PlayerScripts:FindFirstChild("client")
  if not clientContainer then
    print("[TestRunner] No client container found")
    return {
      success = true,
      failureCount = 0,
      skippedCount = 0,
      successCount = 0,
      errors = {},
    }
  end
  return TestRunner.runContainer(clientContainer, "Client")
end

-- Run all shared tests
function TestRunner.runShared(): TestResult
  local sharedContainer = ReplicatedStorage:FindFirstChild("Shared")
  if not sharedContainer then
    print("[TestRunner] No Shared container found in ReplicatedStorage")
    return {
      success = true,
      failureCount = 0,
      skippedCount = 0,
      successCount = 0,
      errors = {},
    }
  end
  return TestRunner.runContainer(sharedContainer, "Shared")
end

-- Run all tests (server + shared)
-- Note: Client tests must be run separately from a client context
function TestRunner.run(): TestResult
  print("[TestRunner] Starting test run...")

  local serverResult = TestRunner.runServer()
  local sharedResult = TestRunner.runShared()

  -- Combine results
  local combinedResult: TestResult = {
    success = serverResult.success and sharedResult.success,
    failureCount = serverResult.failureCount + sharedResult.failureCount,
    skippedCount = serverResult.skippedCount + sharedResult.skippedCount,
    successCount = serverResult.successCount + sharedResult.successCount,
    errors = {},
  }

  for _, err in serverResult.errors do
    table.insert(combinedResult.errors, "[Server] " .. err)
  end
  for _, err in sharedResult.errors do
    table.insert(combinedResult.errors, "[Shared] " .. err)
  end

  printResults(combinedResult, "Combined")

  return combinedResult
end

-- Run specific spec files by module reference
function TestRunner.runModules(modules: { ModuleScript }): TestResult
  if #modules == 0 then
    return {
      success = true,
      failureCount = 0,
      skippedCount = 0,
      successCount = 0,
      errors = {},
    }
  end

  local results = TestEZ.TestBootstrap:run(modules)
  local converted = convertResults(results)
  printResults(converted, "Selected Modules")

  return converted
end

return TestRunner
