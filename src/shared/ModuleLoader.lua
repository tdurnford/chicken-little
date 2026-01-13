--[[
	ModuleLoader - Utility for loading modules with error handling and logging.
	Provides a consistent way to require modules with graceful error handling.
]]

local ModuleLoader = {}

-- Loaded modules cache
local loadedModules: { [string]: any } = {}
local loadErrors: { [string]: string } = {}

-- Log prefix for debugging
local LOG_PREFIX = "[ModuleLoader]"

--[[
	Safely requires a module with error handling.
	@param parent Instance - Parent folder containing the module
	@param moduleName string - Name of the module to require
	@param timeout number? - Optional timeout for WaitForChild (default 5)
	@return any? - The loaded module, or nil if loading failed
]]
function ModuleLoader.require(parent: Instance, moduleName: string, timeout: number?): any?
  -- Check cache first
  local cacheKey = parent:GetFullName() .. "/" .. moduleName
  if loadedModules[cacheKey] then
    return loadedModules[cacheKey]
  end

  -- Check if we already failed to load this module
  if loadErrors[cacheKey] then
    return nil
  end

  local waitTime = timeout or 5

  -- Find the module
  local moduleInstance = parent:WaitForChild(moduleName, waitTime)
  if not moduleInstance then
    local errorMsg =
      string.format("%s Module '%s' not found in %s", LOG_PREFIX, moduleName, parent:GetFullName())
    warn(errorMsg)
    loadErrors[cacheKey] = errorMsg
    return nil
  end

  -- Require the module with pcall
  local success, result = pcall(function()
    return require(moduleInstance)
  end)

  if not success then
    local errorMsg =
      string.format("%s Failed to load '%s': %s", LOG_PREFIX, moduleName, tostring(result))
    warn(errorMsg)
    loadErrors[cacheKey] = errorMsg
    return nil
  end

  -- Cache and return
  loadedModules[cacheKey] = result
  print(string.format("%s Loaded '%s'", LOG_PREFIX, moduleName))
  return result
end

--[[
	Loads multiple modules from a parent folder.
	@param parent Instance - Parent folder containing the modules
	@param moduleNames {string} - Array of module names to load
	@param timeout number? - Optional timeout for each module (default 5)
	@return {[string]: any} - Table mapping module names to loaded modules
]]
function ModuleLoader.requireAll(
  parent: Instance,
  moduleNames: { string },
  timeout: number?
): { [string]: any }
  local modules: { [string]: any } = {}
  local failedCount = 0

  for _, moduleName in ipairs(moduleNames) do
    local loadedModule = ModuleLoader.require(parent, moduleName, timeout)
    if loadedModule then
      modules[moduleName] = loadedModule
    else
      failedCount += 1
    end
  end

  if failedCount > 0 then
    warn(
      string.format(
        "%s %d module(s) failed to load from %s",
        LOG_PREFIX,
        failedCount,
        parent:GetFullName()
      )
    )
  end

  print(
    string.format(
      "%s Loaded %d/%d modules from %s",
      LOG_PREFIX,
      #moduleNames - failedCount,
      #moduleNames,
      parent:GetFullName()
    )
  )

  return modules
end

--[[
	Loads all ModuleScripts in a folder.
	@param parent Instance - Parent folder to scan
	@param timeout number? - Optional timeout for each module (default 5)
	@return {[string]: any} - Table mapping module names to loaded modules
]]
function ModuleLoader.requireFolder(parent: Instance, timeout: number?): { [string]: any }
  local moduleNames: { string } = {}

  for _, child in ipairs(parent:GetChildren()) do
    if child:IsA("ModuleScript") then
      table.insert(moduleNames, child.Name)
    end
  end

  return ModuleLoader.requireAll(parent, moduleNames, timeout)
end

--[[
	Gets any load errors that occurred.
	@return {[string]: string} - Table mapping cache keys to error messages
]]
function ModuleLoader.getErrors(): { [string]: string }
  return loadErrors
end

--[[
	Checks if a module loaded successfully.
	@param parent Instance - Parent folder containing the module
	@param moduleName string - Name of the module
	@return boolean - True if the module is loaded
]]
function ModuleLoader.isLoaded(parent: Instance, moduleName: string): boolean
  local cacheKey = parent:GetFullName() .. "/" .. moduleName
  return loadedModules[cacheKey] ~= nil
end

--[[
	Gets a previously loaded module from cache.
	@param parent Instance - Parent folder containing the module
	@param moduleName string - Name of the module
	@return any? - The loaded module, or nil if not in cache
]]
function ModuleLoader.get(parent: Instance, moduleName: string): any?
  local cacheKey = parent:GetFullName() .. "/" .. moduleName
  return loadedModules[cacheKey]
end

--[[
	Clears the module cache (useful for hot-reloading in development).
]]
function ModuleLoader.clearCache()
  loadedModules = {}
  loadErrors = {}
  print(LOG_PREFIX, "Cache cleared")
end

return ModuleLoader
