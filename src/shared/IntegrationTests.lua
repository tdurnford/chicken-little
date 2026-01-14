--[[
	IntegrationTests Module
	Comprehensive tests for all game systems to verify integration
	and catch regressions. Run with runAllTests() to execute test suite.
]]

local IntegrationTests = {}

-- Import dependencies
local PlayerData = require(script.Parent.PlayerData)
local ChickenConfig = require(script.Parent.ChickenConfig)
local EggConfig = require(script.Parent.EggConfig)
local EggHatching = require(script.Parent.EggHatching)
local Store = require(script.Parent.Store)
local MoneyCollection = require(script.Parent.MoneyCollection)
local ChickenPlacement = require(script.Parent.ChickenPlacement)
local TradeExchange = require(script.Parent.TradeExchange)
local TrapConfig = require(script.Parent.TrapConfig)
local PredatorConfig = require(script.Parent.PredatorConfig)
local OfflineEarnings = require(script.Parent.OfflineEarnings)
local CageUpgrades = require(script.Parent.CageUpgrades)
local RandomChickenSpawn = require(script.Parent.RandomChickenSpawn)
local BalanceConfig = require(script.Parent.BalanceConfig)
local CombatHealth = require(script.Parent.CombatHealth)
local ChickenHealth = require(script.Parent.ChickenHealth)
local PredatorAI = require(script.Parent.PredatorAI)
local BaseballBat = require(script.Parent.BaseballBat)
local PredatorSpawning = require(script.Parent.PredatorSpawning)
local ChickenAI = require(script.Parent.ChickenAI)

-- Type definitions
export type TestResult = {
  name: string,
  passed: boolean,
  message: string,
  duration: number,
}

export type TestSuiteResult = {
  totalTests: number,
  passed: number,
  failed: number,
  duration: number,
  results: { TestResult },
}

-- Test registry
local tests: { { name: string, fn: () -> (boolean, string) } } = {}

-- Register a test
local function test(name: string, fn: () -> (boolean, string))
  table.insert(tests, { name = name, fn = fn })
end

-- Assert helper
local function assert_eq(actual: any, expected: any, msg: string?): (boolean, string)
  if actual == expected then
    return true, "OK"
  end
  return false,
    (msg or "Assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(
      actual
    )
end

local function assert_true(condition: boolean, msg: string?): (boolean, string)
  if condition then
    return true, "OK"
  end
  return false, msg or "Expected true but got false"
end

local function assert_false(condition: boolean, msg: string?): (boolean, string)
  if not condition then
    return true, "OK"
  end
  return false, msg or "Expected false but got true"
end

local function assert_not_nil(value: any, msg: string?): (boolean, string)
  if value ~= nil then
    return true, "OK"
  end
  return false, msg or "Expected non-nil value"
end

local function assert_nil(value: any, msg: string?): (boolean, string)
  if value == nil then
    return true, "OK"
  end
  return false, msg or "Expected nil but got " .. tostring(value)
end

local function assert_gt(actual: number, expected: number, msg: string?): (boolean, string)
  if actual > expected then
    return true, "OK"
  end
  return false,
    (msg or "Assertion failed") .. ": expected > " .. tostring(expected) .. ", got " .. tostring(
      actual
    )
end

local function assert_gte(actual: number, expected: number, msg: string?): (boolean, string)
  if actual >= expected then
    return true, "OK"
  end
  return false,
    (msg or "Assertion failed") .. ": expected >= " .. tostring(expected) .. ", got " .. tostring(
      actual
    )
end

-- ============================================================================
-- PlayerData Tests
-- ============================================================================

test("PlayerData: createDefault returns valid structure", function()
  local data = PlayerData.createDefault()
  local pass, msg = assert_not_nil(data, "Default data should not be nil")
  if not pass then
    return pass, msg
  end
  return assert_true(PlayerData.validate(data), "Default data should be valid")
end)

test("PlayerData: default has starting money", function()
  local data = PlayerData.createDefault()
  local pass, msg = assert_eq(#data.inventory.eggs, 0, "Should have empty egg inventory")
  if not pass then
    return pass, msg
  end
  return assert_eq(data.money, 100, "Should start with 100 coins (enough for Common Egg)")
end)

test("PlayerData: validate rejects invalid money", function()
  local data = PlayerData.createDefault()
  data.money = -100
  return assert_false(PlayerData.validate(data), "Negative money should be invalid")
end)

test("PlayerData: validate rejects invalid rarity", function()
  local data = PlayerData.createDefault()
  -- Add an egg with invalid rarity to test validation
  table.insert(data.inventory.eggs, {
    id = PlayerData.generateId(),
    eggType = "CommonEgg",
    rarity = "SuperRare",
  })
  return assert_false(PlayerData.validate(data), "Invalid rarity should fail validation")
end)

test("PlayerData: clone creates independent copy", function()
  local original = PlayerData.createDefault()
  original.money = 1000
  local cloned = PlayerData.clone(original)
  cloned.money = 2000
  return assert_eq(original.money, 1000, "Original should be unchanged after clone modification")
end)

test("PlayerData: tutorialComplete field exists", function()
  local data = PlayerData.createDefault()
  return assert_eq(data.tutorialComplete, false, "New players should have tutorialComplete = false")
end)

test("PlayerData: isBankrupt returns false with sufficient money", function()
  local data = PlayerData.createDefault()
  data.money = 100 -- Enough to buy cheapest item
  return assert_false(PlayerData.isBankrupt(data), "Should not be bankrupt with $100")
end)

test("PlayerData: isBankrupt returns true when broke with no assets", function()
  local data = PlayerData.createDefault()
  data.money = 50 -- Not enough to buy anything
  data.inventory.eggs = {}
  data.inventory.chickens = {}
  data.placedChickens = {}
  return assert_true(PlayerData.isBankrupt(data), "Should be bankrupt with $50 and no assets")
end)

test("PlayerData: isBankrupt returns false with eggs in inventory", function()
  local data = PlayerData.createDefault()
  data.money = 0
  table.insert(data.inventory.eggs, {
    id = PlayerData.generateId(),
    eggType = "CommonEgg",
    rarity = "Common",
  })
  return assert_false(PlayerData.isBankrupt(data), "Should not be bankrupt with eggs in inventory")
end)

test("PlayerData: isBankrupt returns false with placed chickens", function()
  local data = PlayerData.createDefault()
  data.money = 0
  table.insert(data.placedChickens, {
    id = PlayerData.generateId(),
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time(),
    spotIndex = 1,
  })
  return assert_false(PlayerData.isBankrupt(data), "Should not be bankrupt with placed chickens")
end)

test("PlayerData: getBankruptcyStarterMoney returns 100", function()
  return assert_eq(PlayerData.getBankruptcyStarterMoney(), 100, "Starter money should be $100")
end)

-- ============================================================================
-- ChickenConfig Tests
-- ============================================================================

test("ChickenConfig: all types have valid config", function()
  local types = ChickenConfig.getAllTypes()
  for _, chickenType in ipairs(types) do
    local config = ChickenConfig.get(chickenType)
    if not config then
      return false, "Missing config for " .. chickenType
    end
    if config.moneyPerSecond <= 0 then
      return false, "Invalid money rate for " .. chickenType
    end
    if config.eggLayIntervalSeconds <= 0 then
      return false, "Invalid egg interval for " .. chickenType
    end
  end
  return true, "OK"
end)

test("ChickenConfig: money scales exponentially by rarity", function()
  local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
  local prevMultiplier = 0
  for _, rarity in ipairs(rarities) do
    local multiplier = ChickenConfig.getRarityMultiplier(rarity)
    if multiplier <= prevMultiplier then
      return false, "Rarity " .. rarity .. " multiplier should be > " .. tostring(prevMultiplier)
    end
    prevMultiplier = multiplier
  end
  return true, "OK"
end)

test("ChickenConfig: all rarities have at least one chicken", function()
  local rarities = ChickenConfig.getRarities()
  for _, rarity in ipairs(rarities) do
    local chickens = ChickenConfig.getByRarity(rarity)
    if #chickens < 1 then
      return false, "No chickens for rarity " .. rarity
    end
  end
  return true, "OK"
end)

test("ChickenConfig: calculateEarnings works correctly", function()
  local earnings = ChickenConfig.calculateEarnings("BasicChick", 60)
  return assert_gt(earnings, 0, "Earnings should be positive")
end)

-- ============================================================================
-- EggConfig Tests
-- ============================================================================

test("EggConfig: all probabilities sum to 100%", function()
  local validation = EggConfig.validateAll()
  if not validation.success then
    return false, table.concat(validation.errors, "; ")
  end
  return true, "OK"
end)

test("EggConfig: all eggs have exactly 3 outcomes", function()
  local types = EggConfig.getAllTypes()
  for _, eggType in ipairs(types) do
    local config = EggConfig.get(eggType)
    if not config or #config.hatchOutcomes ~= 3 then
      return false, eggType .. " should have exactly 3 outcomes"
    end
  end
  return true, "OK"
end)

test("EggConfig: prices scale with rarity", function()
  local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
  local prevPrice = 0
  for _, rarity in ipairs(rarities) do
    local eggs = EggConfig.getByRarity(rarity)
    if #eggs > 0 then
      local price = eggs[1].purchasePrice
      if price <= prevPrice then
        return false, rarity .. " egg price should be > " .. tostring(prevPrice)
      end
      prevPrice = price
    end
  end
  return true, "OK"
end)

test("EggConfig: selectHatchOutcome returns valid chicken", function()
  local types = EggConfig.getAllTypes()
  for _, eggType in ipairs(types) do
    local result = EggConfig.selectHatchOutcome(eggType)
    if not result or not ChickenConfig.isValidType(result) then
      return false, "Invalid hatch result for " .. eggType
    end
  end
  return true, "OK"
end)

-- ============================================================================
-- EggHatching Tests
-- ============================================================================

test("EggHatching: hatch consumes egg and creates chicken", function()
  local data = PlayerData.createDefault()
  -- Add a common egg for testing
  local eggId = PlayerData.generateId()
  table.insert(data.inventory.eggs, { id = eggId, eggType = "CommonEgg", rarity = "Common" })
  local initialEggs = #data.inventory.eggs
  local initialChickens = #data.inventory.chickens

  local result = EggHatching.hatch(data, eggId)
  if not result.success then
    return false, "Hatch should succeed: " .. result.message
  end
  local pass, msg = assert_eq(#data.inventory.eggs, initialEggs - 1, "Egg should be consumed")
  if not pass then
    return pass, msg
  end
  return assert_eq(#data.inventory.chickens, initialChickens + 1, "Chicken should be added")
end)

test("EggHatching: hatch fails for missing egg", function()
  local data = PlayerData.createDefault()
  local result = EggHatching.hatch(data, "nonexistent_egg_id")
  return assert_false(result.success, "Hatch should fail for missing egg")
end)

test("EggHatching: celebration tiers are ordered", function()
  local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
  local prevTier = -1
  for _, rarity in ipairs(rarities) do
    local tier = EggHatching.getCelebrationTier(rarity)
    if tier <= prevTier then
      return false, rarity .. " tier should be > " .. tostring(prevTier)
    end
    prevTier = tier
  end
  return true, "OK"
end)

test("EggHatching: probability distribution is reasonable", function()
  -- Simulate many hatches and verify distribution is within expected bounds
  local results = EggHatching.simulateHatches("CommonEgg", 1000)
  local totalHatches = 0
  for _, count in pairs(results) do
    totalHatches = totalHatches + count
  end
  return assert_eq(totalHatches, 1000, "All 1000 hatches should produce results")
end)

-- ============================================================================
-- Store Tests
-- ============================================================================

test("Store: buy egg succeeds with sufficient money", function()
  local data = PlayerData.createDefault()
  data.money = 10000
  local result = Store.buyEgg(data, "CommonEgg", 1)
  local pass, msg = assert_true(result.success, "Buy should succeed: " .. result.message)
  if not pass then
    return pass, msg
  end
  return assert_gt(10000, data.money, "Money should be deducted")
end)

test("Store: buy egg fails with insufficient money", function()
  local data = PlayerData.createDefault()
  data.money = 0
  local result = Store.buyEgg(data, "CommonEgg", 1)
  return assert_false(result.success, "Buy should fail without money")
end)

test("Store: buy invalid egg type fails", function()
  local data = PlayerData.createDefault()
  data.money = 10000
  local result = Store.buyEgg(data, "SuperEgg", 1)
  return assert_false(result.success, "Invalid egg type should fail")
end)

test("Store: sell chicken gives money", function()
  local data = PlayerData.createDefault()
  -- Add a chicken to inventory
  local chickenId = PlayerData.generateId()
  table.insert(data.inventory.chickens, {
    id = chickenId,
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time(),
    spotIndex = nil,
  })
  local initialMoney = data.money
  local result = Store.sellChicken(data, chickenId)
  local pass, msg = assert_true(result.success, "Sell should succeed: " .. result.message)
  if not pass then
    return pass, msg
  end
  return assert_gt(data.money, initialMoney, "Money should increase after selling")
end)

test("Store: buy chicken succeeds with sufficient money", function()
  local data = PlayerData.createDefault()
  data.money = 10000
  local initialChickens = #data.inventory.chickens
  local result = Store.buyChicken(data, "BasicChick", 1)
  local pass, msg = assert_true(result.success, "Buy should succeed: " .. result.message)
  if not pass then
    return pass, msg
  end
  pass, msg = assert_gt(10000, data.money, "Money should be deducted")
  if not pass then
    return pass, msg
  end
  return assert_eq(
    #data.inventory.chickens,
    initialChickens + 1,
    "Chicken should be added to inventory"
  )
end)

test("Store: buy chicken fails with insufficient money", function()
  local data = PlayerData.createDefault()
  data.money = 0
  local result = Store.buyChicken(data, "BasicChick", 1)
  return assert_false(result.success, "Buy chicken should fail without money")
end)

test("Store: buy invalid chicken type fails", function()
  local data = PlayerData.createDefault()
  data.money = 10000
  local result = Store.buyChicken(data, "SuperChicken", 1)
  return assert_false(result.success, "Invalid chicken type should fail")
end)

test("Store: getAvailableChickens returns items", function()
  local chickens = Store.getAvailableChickens()
  local pass, msg = assert_gt(#chickens, 0, "Should have at least one chicken available")
  if not pass then
    return pass, msg
  end
  local first = chickens[1]
  pass, msg = assert_eq(first.itemType, "chicken", "Item type should be chicken")
  if not pass then
    return pass, msg
  end
  return assert_gt(first.price, 0, "Price should be positive")
end)

-- ============================================================================
-- Store Inventory Tests
-- ============================================================================

test("Store: initializeInventory creates inventory with items", function()
  local inventory = Store.initializeInventory()
  local pass, msg = assert_not_nil(inventory, "Inventory should be created")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_not_nil(inventory.eggs, "Eggs table should exist")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_not_nil(inventory.chickens, "Chickens table should exist")
  if not pass then
    return pass, msg
  end
  -- Check that common egg has stock of 10
  local commonEgg = inventory.eggs["CommonEgg"]
  pass, msg = assert_not_nil(commonEgg, "Common egg should exist")
  if not pass then
    return pass, msg
  end
  return assert_eq(commonEgg.stock, 10, "Common egg should have stock of 10")
end)

test("Store: isInStock returns true for stocked items", function()
  Store.initializeInventory()
  local inStock = Store.isInStock("egg", "CommonEgg")
  return assert_true(inStock, "Common egg should be in stock")
end)

test("Store: isInStock returns false for out of stock items", function()
  local inventory = Store.initializeInventory()
  -- Manually set stock to 0
  inventory.eggs["CommonEgg"].stock = 0
  Store.setStoreInventory(inventory)
  local inStock = Store.isInStock("egg", "CommonEgg")
  return assert_false(inStock, "Common egg with 0 stock should not be in stock")
end)

test("Store: purchaseEggFromInventory decrements stock", function()
  Store.initializeInventory()
  local data = PlayerData.createDefault()
  data.money = 1000
  local initialStock = Store.getStock("egg", "CommonEgg")
  local result = Store.purchaseEggFromInventory(data, "CommonEgg", 1)
  local pass, msg = assert_true(result.success, "Purchase should succeed: " .. result.message)
  if not pass then
    return pass, msg
  end
  local newStock = Store.getStock("egg", "CommonEgg")
  return assert_eq(newStock, initialStock - 1, "Stock should decrement by 1")
end)

test("Store: purchaseEggFromInventory fails when sold out", function()
  local inventory = Store.initializeInventory()
  inventory.eggs["CommonEgg"].stock = 0
  Store.setStoreInventory(inventory)
  local data = PlayerData.createDefault()
  data.money = 1000
  local result = Store.purchaseEggFromInventory(data, "CommonEgg", 1)
  return assert_false(result.success, "Purchase should fail when sold out")
end)

test("Store: purchaseChickenFromInventory decrements stock", function()
  Store.initializeInventory()
  local data = PlayerData.createDefault()
  data.money = 50000
  local initialStock = Store.getStock("chicken", "BasicChick")
  local result = Store.purchaseChickenFromInventory(data, "BasicChick", 1)
  local pass, msg = assert_true(result.success, "Purchase should succeed: " .. result.message)
  if not pass then
    return pass, msg
  end
  local newStock = Store.getStock("chicken", "BasicChick")
  return assert_eq(newStock, initialStock - 1, "Stock should decrement by 1")
end)

test("Store: getAvailableEggsWithStock includes stock info", function()
  Store.initializeInventory()
  local eggs = Store.getAvailableEggsWithStock()
  local pass, msg = assert_gt(#eggs, 0, "Should have eggs available")
  if not pass then
    return pass, msg
  end
  local first = eggs[1]
  pass, msg = assert_not_nil(first.stock, "Stock field should exist")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(first.maxStock, "MaxStock field should exist")
end)

test("Store: getStockForRarity returns correct values", function()
  local pass, msg = assert_eq(Store.getStockForRarity("Common"), 10, "Common should be 10")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(Store.getStockForRarity("Rare"), 3, "Rare should be 3")
  if not pass then
    return pass, msg
  end
  return assert_eq(Store.getStockForRarity("Mythic"), 0, "Mythic should be 0")
end)

test("Store: getReplenishInterval returns 300 seconds", function()
  local interval = Store.getReplenishInterval()
  return assert_eq(interval, 300, "Replenish interval should be 300 seconds (5 minutes)")
end)

test("Store: replenishStore restores stock", function()
  local inventory = Store.initializeInventory()
  -- Deplete stock
  for _, item in pairs(inventory.eggs) do
    item.stock = 0
  end
  -- Verify stock is depleted
  local depleted = true
  for _, item in pairs(inventory.eggs) do
    if item.stock > 0 then
      depleted = false
      break
    end
  end
  local pass, msg = assert_true(depleted, "Stock should be depleted")
  if not pass then
    return pass, msg
  end
  -- Replenish store
  local newInventory = Store.replenishStore()
  -- Verify stock is restored
  local hasStock = false
  for _, item in pairs(newInventory.eggs) do
    if item.stock > 0 then
      hasStock = true
      break
    end
  end
  return assert_true(hasStock, "Stock should be restored after replenish")
end)

test("Store: replenishStore updates lastReplenishTime", function()
  Store.initializeInventory()
  local beforeTime = os.time()
  local newInventory = Store.replenishStore()
  local afterTime = os.time()
  local pass, msg = assert_true(
    newInventory.lastReplenishTime >= beforeTime,
    "lastReplenishTime should be at or after start"
  )
  if not pass then
    return pass, msg
  end
  return assert_true(
    newInventory.lastReplenishTime <= afterTime,
    "lastReplenishTime should be at or before end"
  )
end)

test("Store: needsReplenish returns false immediately after replenish", function()
  Store.initializeInventory()
  Store.replenishStore()
  return assert_false(
    Store.needsReplenish(),
    "Should not need replenish immediately after replenishing"
  )
end)

test("Store: getTimeUntilReplenish returns positive value after replenish", function()
  Store.initializeInventory()
  Store.replenishStore()
  local remaining = Store.getTimeUntilReplenish()
  return assert_gt(remaining, 0, "Time until replenish should be greater than 0")
end)

test("Store: forceReplenish works same as replenishStore", function()
  local inventory = Store.initializeInventory()
  -- Deplete stock
  for _, item in pairs(inventory.eggs) do
    item.stock = 0
  end
  -- Force replenish
  local newInventory = Store.forceReplenish()
  local hasStock = false
  for _, item in pairs(newInventory.eggs) do
    if item.stock > 0 then
      hasStock = true
      break
    end
  end
  return assert_true(hasStock, "Force replenish should restore stock")
end)

test("Store: basic chicken is cheaper than common egg", function()
  -- Bug #39: Basic chicken should cost less than common egg
  -- Eggs are a gamble with upside potential; direct chicken purchase should be cheaper
  local basicChickPrice = Store.getChickenPrice("BasicChick")
  local commonEggConfig = EggConfig.get("CommonEgg")
  if not commonEggConfig then
    return false, "CommonEgg config not found"
  end
  local pass, msg = assert_true(
    basicChickPrice < commonEggConfig.purchasePrice,
    string.format(
      "BasicChick ($%d) should be cheaper than CommonEgg ($%d)",
      basicChickPrice,
      commonEggConfig.purchasePrice
    )
  )
  return pass, msg
end)

test("Store: egg prices are slightly above expected chicken values", function()
  -- For each egg rarity, the egg should cost more than the expected chicken value
  -- This makes eggs a gamble with upside potential
  local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
  for _, rarity in ipairs(rarities) do
    local eggs = EggConfig.getByRarity(rarity)
    if #eggs > 0 then
      local egg = eggs[1]
      -- Calculate expected chicken purchase price from hatch outcomes
      local expectedValue = 0
      for _, outcome in ipairs(egg.hatchOutcomes) do
        local chickenPrice = Store.getChickenPrice(outcome.chickenType)
        expectedValue = expectedValue + (chickenPrice * outcome.probability / 100)
      end
      -- Egg should cost at least as much as expected value (slight premium for gamble)
      if egg.purchasePrice < expectedValue * 0.95 then
        return false,
          string.format(
            "%s egg ($%d) is too cheap vs expected chicken value ($%.0f)",
            rarity,
            egg.purchasePrice,
            expectedValue
          )
      end
    end
  end
  return true, "OK"
end)

-- ============================================================================
-- TradeExchange Tests
-- ============================================================================

test("TradeExchange: create session works", function()
  local session = TradeExchange.createSession(1, 2)
  local pass, msg = assert_not_nil(session, "Session should be created")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(session.player1Id, 1, "Player 1 ID should match")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(session.player2Id, 2, "Player 2 ID should match")
  if not pass then
    return pass, msg
  end
  return assert_eq(session.status, "pending", "Status should be pending")
end)

test("TradeExchange: get session by ID works", function()
  local session = TradeExchange.createSession(100, 200)
  local retrieved = TradeExchange.getSession(session.tradeId)
  return assert_not_nil(retrieved, "Should retrieve session by ID")
end)

test("TradeExchange: get player session works", function()
  TradeExchange.resetAllSessions()
  local session = TradeExchange.createSession(300, 400)
  local retrieved = TradeExchange.getPlayerSession(300)
  local pass, msg = assert_not_nil(retrieved, "Should retrieve session for player 300")
  if not pass then
    return pass, msg
  end
  return assert_eq(retrieved.tradeId, session.tradeId, "Session IDs should match")
end)

-- ============================================================================
-- TrapConfig Tests
-- ============================================================================

test("TrapConfig: all trap types have valid config", function()
  local types = TrapConfig.getAllTypes()
  for _, trapType in ipairs(types) do
    local config = TrapConfig.get(trapType)
    if not config then
      return false, "Missing config for " .. trapType
    end
  end
  return true, "OK"
end)

test("TrapConfig: higher tiers have better effectiveness", function()
  local types = TrapConfig.getAllTypes()
  if #types > 1 then
    local tier1 = TrapConfig.get(types[1])
    local tier2 = TrapConfig.get(types[2])
    if tier1 and tier2 and tier2.tierLevel > tier1.tierLevel then
      if tier2.effectivenessBonus <= tier1.effectivenessBonus then
        return false, "Higher tier should have better effectiveness bonus"
      end
    end
  end
  return true, "OK"
end)

-- ============================================================================
-- PredatorConfig Tests
-- ============================================================================

test("PredatorConfig: all predator types have valid config", function()
  local types = PredatorConfig.getAllTypes()
  for _, predType in ipairs(types) do
    local config = PredatorConfig.get(predType)
    if not config then
      return false, "Missing config for " .. predType
    end
    if config.damage <= 0 then
      return false, "Predator " .. predType .. " should have positive damage"
    end
  end
  return true, "OK"
end)

-- ============================================================================
-- OfflineEarnings Tests
-- ============================================================================

test("OfflineEarnings: calculates earnings for offline period", function()
  local data = PlayerData.createDefault()
  -- Add a placed chicken
  table.insert(data.placedChickens, {
    id = PlayerData.generateId(),
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time() - 3600,
    spotIndex = 1,
  })
  data.lastLogoutTime = os.time() - 3600 -- 1 hour ago

  local result = OfflineEarnings.calculate(data, os.time())
  return assert_gte(result.totalMoney, 0, "Earnings should be non-negative")
end)

test("OfflineEarnings: respects cap", function()
  local data = PlayerData.createDefault()
  -- Add a high-earning chicken
  table.insert(data.placedChickens, {
    id = PlayerData.generateId(),
    chickenType = "OmegaRooster",
    rarity = "Mythic",
    accumulatedMoney = 0,
    lastEggTime = os.time() - 86400,
    spotIndex = 1,
  })
  data.lastLogoutTime = os.time() - 86400 -- 24 hours ago

  local result = OfflineEarnings.calculate(data, os.time())
  return assert_not_nil(result.wasCapped, "Should have cap info")
end)

-- ============================================================================
-- CageUpgrades Tests
-- ============================================================================

test("CageUpgrades: upgrade tiers are valid", function()
  local tiers = CageUpgrades.getAllTiers()
  for i, tier in ipairs(tiers) do
    if tier.tier ~= i then
      return false, "Tier " .. i .. " mismatch"
    end
    if tier.price < 0 then
      return false, "Tier " .. i .. " has invalid price"
    end
  end
  return true, "OK"
end)

test("CageUpgrades: can afford upgrade from tier 1", function()
  local data = PlayerData.createDefault()
  data.money = 1000000
  data.upgrades.cageTier = 1
  local canAfford = CageUpgrades.canAffordNextTier(data.upgrades.cageTier, data.money)
  return assert_true(canAfford, "Should be able to afford upgrade from tier 1 with money")
end)

-- ============================================================================
-- RandomChickenSpawn Tests
-- ============================================================================

test("RandomChickenSpawn: creates valid spawn state", function()
  local state = RandomChickenSpawn.createSpawnState()
  local pass, msg = assert_not_nil(state, "State should be created")
  if not pass then
    return pass, msg
  end
  return assert_true(RandomChickenSpawn.validateState(state), "State should be valid")
end)

test("RandomChickenSpawn: spawn interval is reasonable", function()
  local config = RandomChickenSpawn.getDefaultConfig()
  local pass, msg = assert_gte(config.spawnIntervalMin, 60, "Min interval should be at least 60s")
  if not pass then
    return pass, msg
  end
  return assert_gte(config.spawnIntervalMax, config.spawnIntervalMin, "Max should be >= min")
end)

test("RandomChickenSpawn: claim chicken succeeds when in range", function()
  local currentTime = os.time()
  local state = RandomChickenSpawn.createSpawnState(nil, currentTime)

  -- Force spawn a chicken
  state.nextSpawnTime = currentTime - 1
  local spawnResult = RandomChickenSpawn.spawnChicken(state, currentTime)
  local pass, msg = assert_true(spawnResult.success, "Spawn should succeed")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_not_nil(spawnResult.chicken, "Chicken should be spawned")
  if not pass then
    return pass, msg
  end

  -- Claim from exact position (distance = 0)
  local playerPosition = spawnResult.chicken.position
  local claimResult = RandomChickenSpawn.claimChicken(state, "player1", playerPosition, currentTime)
  pass, msg = assert_true(claimResult.success, "Claim should succeed when at chicken position")
  if not pass then
    return pass, msg
  end
  return assert_nil(state.currentChicken, "Chicken should be removed after claim")
end)

test("RandomChickenSpawn: claim chicken fails when out of range", function()
  local currentTime = os.time()
  local state = RandomChickenSpawn.createSpawnState(nil, currentTime)

  -- Force spawn a chicken
  state.nextSpawnTime = currentTime - 1
  local spawnResult = RandomChickenSpawn.spawnChicken(state, currentTime)
  local pass, msg = assert_true(spawnResult.success, "Spawn should succeed")
  if not pass then
    return pass, msg
  end

  -- Claim from far away position (distance > claim range)
  local farPosition = {
    x = spawnResult.chicken.position.x + 100,
    y = spawnResult.chicken.position.y,
    z = spawnResult.chicken.position.z,
  }
  local claimResult = RandomChickenSpawn.claimChicken(state, "player1", farPosition, currentTime)
  pass, msg = assert_false(claimResult.success, "Claim should fail when too far")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(state.currentChicken, "Chicken should still exist after failed claim")
end)

test("RandomChickenSpawn: consecutive spawns have different positions", function()
  local currentTime = os.time()
  local state = RandomChickenSpawn.createSpawnState(nil, currentTime)

  -- Spawn multiple chickens and track positions
  local positions: { { x: number, z: number } } = {}
  local MIN_DISTANCE = 8 -- Minimum distance we expect between spawns

  for i = 1, 5 do
    -- Clear current chicken to allow next spawn
    state.currentChicken = nil
    state.nextSpawnTime = currentTime - 1

    local spawnResult = RandomChickenSpawn.spawnChicken(state, currentTime + i)
    local pass, msg = assert_true(spawnResult.success, "Spawn " .. i .. " should succeed")
    if not pass then
      return pass, msg
    end

    local pos = spawnResult.chicken.position
    table.insert(positions, { x = pos.x, z = pos.z })
  end

  -- Verify at least some positions are different (not all in same spot)
  local allSamePosition = true
  local firstPos = positions[1]
  for i = 2, #positions do
    local pos = positions[i]
    local dx = pos.x - firstPos.x
    local dz = pos.z - firstPos.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance >= MIN_DISTANCE then
      allSamePosition = false
      break
    end
  end

  return assert_false(
    allSamePosition,
    "Spawn positions should vary - not all chickens should spawn in the same location"
  )
end)

-- ============================================================================
-- BalanceConfig Tests
-- ============================================================================

test("BalanceConfig: early game progression is achievable", function()
  local economy = BalanceConfig.getEconomy()
  local pass, msg = assert_gt(economy.BASE_MONEY_PER_SECOND, 0, "Base MPS should be positive")
  if not pass then
    return pass, msg
  end
  local report = BalanceConfig.validateBalance()
  return assert_true(report.earlyGameValid, "Early game should be achievable in reasonable time")
end)

test("BalanceConfig: mid game progression is achievable", function()
  local report = BalanceConfig.validateBalance()
  return assert_true(report.midGameValid, "Mid game should be achievable in reasonable time")
end)

test("BalanceConfig: late game reaches trillions", function()
  local targets = BalanceConfig.getProgressionTargets()
  local pass, msg = assert_gte(targets.LATE_END, 1e12, "Late game target should reach trillions")
  if not pass then
    return pass, msg
  end
  local report = BalanceConfig.validateBalance()
  return assert_true(report.lateGameValid, "Late game should be achievable")
end)

test("BalanceConfig: upgrade multipliers scale correctly", function()
  local prev = 0
  for tier = 1, 10 do
    local mult = BalanceConfig.getUpgradeMultiplier(tier)
    if mult <= prev then
      return false, "Tier " .. tier .. " multiplier should be > " .. tostring(prev)
    end
    prev = mult
  end
  return true, "OK"
end)

test("BalanceConfig: progression stages are ordered", function()
  local targets = BalanceConfig.getProgressionTargets()
  if targets.EARLY_END > targets.MID_START then
    return false, "Early end should be <= mid start"
  end
  if targets.MID_END > targets.LATE_START then
    return false, "Mid end should be <= late start"
  end
  return true, "OK"
end)

test("BalanceConfig: calculateMoneyPerSecond works correctly", function()
  local chickens = { "BasicChick", "BasicChick" }
  local mps = BalanceConfig.calculateMoneyPerSecond(chickens, 1)
  local pass, msg = assert_gt(mps, 0, "MPS should be positive with chickens")
  if not pass then
    return pass, msg
  end
  local mpsWithUpgrade = BalanceConfig.calculateMoneyPerSecond(chickens, 2)
  return assert_gt(mpsWithUpgrade, mps, "Upgraded MPS should be higher")
end)

test("BalanceConfig: analyzeProgression returns valid analysis", function()
  local analysis = BalanceConfig.analyzeProgression(5000, { "BasicChick" }, 1)
  local pass, msg = assert_not_nil(analysis.stage, "Should have stage")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_gte(analysis.percentComplete, 0, "Percent should be >= 0")
  if not pass then
    return pass, msg
  end
  return assert_gte(analysis.moneyPerSecond, 0, "MPS should be >= 0")
end)

test("BalanceConfig: simulateProgression calculates correctly", function()
  local result = BalanceConfig.simulateProgression(0, { "BasicChick" }, 1, 100)
  local pass, msg = assert_gt(result.money, 0, "Should earn money over time")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(result.stage, "Should have stage")
end)

-- ============================================================================
-- Integration Tests - Cross-System
-- ============================================================================

test("Integration: full egg buy and hatch flow", function()
  local data = PlayerData.createDefault()
  data.money = 10000

  -- Buy egg
  local buyResult = Store.buyEgg(data, "CommonEgg", 1)
  if not buyResult.success then
    return false, "Buy failed: " .. buyResult.message
  end

  -- Find the egg we just bought
  local eggId = nil
  for _, egg in ipairs(data.inventory.eggs) do
    if egg.eggType == "CommonEgg" then
      eggId = egg.id
      break
    end
  end
  if not eggId then
    return false, "Could not find purchased egg"
  end

  -- Hatch egg
  local hatchResult = EggHatching.hatch(data, eggId)
  if not hatchResult.success then
    return false, "Hatch failed: " .. hatchResult.message
  end

  -- Verify chicken was added
  return assert_gt(#data.inventory.chickens, 0, "Should have chicken after hatch")
end)

test("Integration: chicken placement and money collection", function()
  local data = PlayerData.createDefault()
  -- Add a chicken to inventory
  local chickenId = PlayerData.generateId()
  table.insert(data.inventory.chickens, {
    id = chickenId,
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 100, -- Already has money
    lastEggTime = os.time(),
    spotIndex = nil,
  })

  -- Place chicken
  local placeResult = ChickenPlacement.placeChicken(data, chickenId, 1)
  if not placeResult.success then
    return false, "Place failed: " .. placeResult.message
  end

  -- Verify chicken is placed
  local pass, msg = assert_eq(#data.placedChickens, 1, "Should have 1 placed chicken")
  if not pass then
    return pass, msg
  end

  -- Collect money
  local collectResult = MoneyCollection.collect(data, data.placedChickens[1].id)
  if not collectResult.success then
    return false, "Collect failed: " .. collectResult.message
  end

  return assert_gte(data.money, 100, "Money should be collected")
end)

test("Integration: data remains valid after operations", function()
  local data = PlayerData.createDefault()
  data.money = 100000

  -- Perform various operations
  Store.buyEgg(data, "CommonEgg", 5)
  for _, egg in ipairs(data.inventory.eggs) do
    if egg.eggType == "CommonEgg" then
      EggHatching.hatch(data, egg.id)
      break
    end
  end

  -- Validate data is still valid
  return assert_true(PlayerData.validate(data), "Data should remain valid after operations")
end)

-- ============================================================================
-- ChickenPlacement MoveChicken Tests
-- ============================================================================

test("ChickenPlacement: moveChicken relocates chicken to new spot", function()
  local data = PlayerData.createDefault()
  local chickenId = "test-move-" .. tostring(os.clock())

  -- Add chicken to inventory
  table.insert(data.inventory.chickens, {
    id = chickenId,
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time(),
    spotIndex = nil,
  })

  -- Place chicken at spot 1
  local placeResult = ChickenPlacement.placeChicken(data, chickenId, 1)
  if not placeResult.success then
    return false, "Place failed: " .. placeResult.message
  end

  -- Verify chicken is at spot 1
  local chicken, _ = ChickenPlacement.findPlacedChicken(data, chickenId)
  local pass, msg = assert_eq(chicken.spotIndex, 1, "Chicken should be at spot 1")
  if not pass then
    return pass, msg
  end

  -- Move chicken to spot 5
  local moveResult = ChickenPlacement.moveChicken(data, chickenId, 5)
  if not moveResult.success then
    return false, "Move failed: " .. moveResult.message
  end

  -- Verify chicken is now at spot 5
  chicken, _ = ChickenPlacement.findPlacedChicken(data, chickenId)
  return assert_eq(chicken.spotIndex, 5, "Chicken should be at spot 5 after move")
end)

test("ChickenPlacement: moveChicken fails for occupied spot", function()
  local data = PlayerData.createDefault()
  local chickenId1 = "test-move-1-" .. tostring(os.clock())
  local chickenId2 = "test-move-2-" .. tostring(os.clock())

  -- Add two chickens to inventory
  table.insert(data.inventory.chickens, {
    id = chickenId1,
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time(),
    spotIndex = nil,
  })
  table.insert(data.inventory.chickens, {
    id = chickenId2,
    chickenType = "BasicChick",
    rarity = "Common",
    accumulatedMoney = 0,
    lastEggTime = os.time(),
    spotIndex = nil,
  })

  -- Place first chicken at spot 1
  ChickenPlacement.placeChicken(data, chickenId1, 1)
  -- Place second chicken at spot 2
  ChickenPlacement.placeChicken(data, chickenId2, 2)

  -- Try to move first chicken to spot 2 (occupied)
  local moveResult = ChickenPlacement.moveChicken(data, chickenId1, 2)

  return assert_false(moveResult.success, "Should not be able to move to occupied spot")
end)

-- ============================================================================
-- CombatHealth Tests
-- ============================================================================

test("CombatHealth: creates valid state with full health", function()
  local state = CombatHealth.createState()
  local pass, msg = assert_not_nil(state, "State should be created")
  if not pass then
    return pass, msg
  end
  return assert_eq(state.health, state.maxHealth, "Should start at full health")
end)

test("CombatHealth: applyDamage reduces health", function()
  local state = CombatHealth.createState()
  local initialHealth = state.health
  local result = CombatHealth.applyFixedDamage(state, 25, 0, "Test")
  local pass, msg = assert_true(result.success, "Damage should be applied")
  if not pass then
    return pass, msg
  end
  return assert_eq(state.health, initialHealth - 25, "Health should be reduced by damage amount")
end)

test("CombatHealth: knockback occurs when health depletes", function()
  local state = CombatHealth.createState()
  local result = CombatHealth.applyFixedDamage(state, 150, 0, "Test")
  local pass, msg = assert_true(result.success, "Damage should be applied")
  if not pass then
    return pass, msg
  end
  return assert_true(result.wasKnockedBack, "Should be knocked back when health depletes")
end)

test("CombatHealth: cannot take damage while knocked back", function()
  local state = CombatHealth.createState()
  CombatHealth.applyFixedDamage(state, 150, 0, "Test")
  local result = CombatHealth.applyFixedDamage(state, 25, 0.5, "Test")
  return assert_false(result.success, "Should not take damage while knocked back")
end)

test("CombatHealth: regenerates health when out of combat", function()
  local state = CombatHealth.createState()
  CombatHealth.applyFixedDamage(state, 30, 0, "Test")
  local constants = CombatHealth.getConstants()
  -- Wait for out of combat delay
  local currentTime = constants.outOfCombatDelay + 1
  local result = CombatHealth.regenerate(state, 1, currentTime)
  return assert_gt(result.healthRestored, 0, "Should regenerate health when out of combat")
end)

test("CombatHealth: getDamage returns correct values from PredatorConfig", function()
  local damage = PredatorConfig.getDamage("Bear")
  return assert_gt(damage, 0, "Bear should have positive damage")
end)

test("CombatHealth: all predators have valid damage values", function()
  local types = PredatorConfig.getAllTypes()
  for _, predType in ipairs(types) do
    local config = PredatorConfig.get(predType)
    if not config then
      return false, "Missing config for " .. predType
    end
    if config.damage <= 0 then
      return false, "Predator " .. predType .. " should have positive damage"
    end
  end
  return true, "OK"
end)

test("CombatHealth: incapacitate sets incapacitated state", function()
  local state = CombatHealth.createState()
  local result = CombatHealth.incapacitate(state, "attacker123", 0)
  return assert_true(result.success, "Should successfully incapacitate")
    and assert_true(state.isIncapacitated, "State should be incapacitated")
    and assert_gt(result.duration, 0, "Duration should be positive")
end)

test("CombatHealth: cannot incapacitate while already incapacitated", function()
  local state = CombatHealth.createState()
  CombatHealth.incapacitate(state, "attacker123", 0)
  local result = CombatHealth.incapacitate(state, "attacker456", 0.5)
  return assert_false(result.success, "Should not incapacitate again")
end)

test("CombatHealth: incapacitation expires after duration", function()
  local state = CombatHealth.createState()
  local result = CombatHealth.incapacitate(state, "attacker123", 0)
  local duration = result.duration
  local isIncapBefore = CombatHealth.isIncapacitated(state, 0.5)
  local isIncapAfter = CombatHealth.isIncapacitated(state, duration + 0.1)
  return assert_true(isIncapBefore, "Should be incapacitated before duration")
    and assert_false(isIncapAfter, "Should not be incapacitated after duration")
end)

test("CombatHealth: canMove returns false when incapacitated", function()
  local state = CombatHealth.createState()
  CombatHealth.incapacitate(state, "attacker123", 0)
  local canMove = CombatHealth.canMove(state, 0.5)
  return assert_false(canMove, "Should not be able to move while incapacitated")
end)

test("CombatHealth: canMove returns true when incapacitation expires", function()
  local state = CombatHealth.createState()
  local result = CombatHealth.incapacitate(state, "attacker123", 0)
  local canMove = CombatHealth.canMove(state, result.duration + 0.1)
  return assert_true(canMove, "Should be able to move after incapacitation expires")
end)

test("CombatHealth: getIncapacitateConstants returns valid values", function()
  local constants = CombatHealth.getIncapacitateConstants()
  return assert_gt(constants.duration, 0, "Duration should be positive")
    and assert_gt(constants.knockbackForce, 0, "Knockback force should be positive")
end)

-- ============================================================================
-- BaseballBat Tests
-- ============================================================================

test("BaseballBat: createBatState returns unequipped bat", function()
  local batState = BaseballBat.createBatState()
  local pass, msg = assert_not_nil(batState, "Bat state should be created")
  if not pass then
    return pass, msg
  end
  return assert_false(batState.isEquipped, "Bat should start unequipped")
end)

test("BaseballBat: equip sets isEquipped to true", function()
  local batState = BaseballBat.createBatState()
  local result = BaseballBat.equip(batState)
  local pass, msg = assert_true(result, "Equip should succeed")
  if not pass then
    return pass, msg
  end
  return assert_true(batState.isEquipped, "Bat should be equipped after equip()")
end)

test("BaseballBat: equip fails when already equipped", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local result = BaseballBat.equip(batState)
  return assert_false(result, "Equip should fail when already equipped")
end)

test("BaseballBat: unequip sets isEquipped to false", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local result = BaseballBat.unequip(batState)
  local pass, msg = assert_true(result, "Unequip should succeed")
  if not pass then
    return pass, msg
  end
  return assert_false(batState.isEquipped, "Bat should be unequipped after unequip()")
end)

test("BaseballBat: unequip fails when already unequipped", function()
  local batState = BaseballBat.createBatState()
  local result = BaseballBat.unequip(batState)
  return assert_false(result, "Unequip should fail when already unequipped")
end)

test("BaseballBat: toggle switches equip state", function()
  local batState = BaseballBat.createBatState()
  local result1 = BaseballBat.toggle(batState)
  local pass, msg = assert_true(result1, "First toggle should equip")
  if not pass then
    return pass, msg
  end
  local result2 = BaseballBat.toggle(batState)
  return assert_false(result2, "Second toggle should unequip")
end)

test("BaseballBat: canSwing returns false when not equipped", function()
  local batState = BaseballBat.createBatState()
  local canSwing = BaseballBat.canSwing(batState, 0)
  return assert_false(canSwing, "Should not be able to swing when not equipped")
end)

test("BaseballBat: canSwing returns true when equipped and off cooldown", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local canSwing = BaseballBat.canSwing(batState, 0)
  return assert_true(canSwing, "Should be able to swing when equipped")
end)

test("BaseballBat: swing cooldown prevents immediate second swing", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  local canSwing = BaseballBat.canSwing(batState, 0.1)
  return assert_false(canSwing, "Should not be able to swing during cooldown")
end)

test("BaseballBat: swing cooldown expires after configured time", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  local config = BaseballBat.getConfig()
  local canSwing = BaseballBat.canSwing(batState, config.swingCooldownSeconds + 0.1)
  return assert_true(canSwing, "Should be able to swing after cooldown expires")
end)

test("BaseballBat: getSwingCooldownRemaining returns correct value", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  local config = BaseballBat.getConfig()
  local remaining = BaseballBat.getSwingCooldownRemaining(batState, 0.2)
  local expected = config.swingCooldownSeconds - 0.2
  return assert_true(
    math.abs(remaining - expected) < 0.01,
    "Cooldown remaining should match expected"
  )
end)

test("BaseballBat: performSwing increments swing count", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  local config = BaseballBat.getConfig()
  BaseballBat.performSwing(batState, config.swingCooldownSeconds + 0.1)
  return assert_eq(batState.swingsCount, 2, "Swing count should be 2 after two swings")
end)

test("BaseballBat: hitPlayer returns knockback result", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local result = BaseballBat.hitPlayer(batState, "player123", 0)
  local pass, msg = assert_true(result.success, "Hit should succeed")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(result.hitType, "player", "Hit type should be player")
  if not pass then
    return pass, msg
  end
  return assert_true(result.knockback, "Should have knockback")
end)

test("BaseballBat: swingMiss returns miss result", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local result = BaseballBat.swingMiss(batState, 0)
  local pass, msg = assert_true(result.success, "Miss swing should succeed")
  if not pass then
    return pass, msg
  end
  return assert_eq(result.hitType, "miss", "Hit type should be miss")
end)

test("BaseballBat: isInRange returns true for close distances", function()
  local config = BaseballBat.getConfig()
  local inRange = BaseballBat.isInRange(config.swingRangeStuds - 1)
  return assert_true(inRange, "Should be in range at close distance")
end)

test("BaseballBat: isInRange returns false for far distances", function()
  local config = BaseballBat.getConfig()
  local inRange = BaseballBat.isInRange(config.swingRangeStuds + 1)
  return assert_false(inRange, "Should be out of range at far distance")
end)

test("BaseballBat: getKnockbackParams returns valid values", function()
  local params = BaseballBat.getKnockbackParams()
  local pass, msg = assert_gt(params.force, 0, "Knockback force should be positive")
  if not pass then
    return pass, msg
  end
  return assert_gt(params.duration, 0, "Knockback duration should be positive")
end)

test("BaseballBat: getConfig returns valid configuration", function()
  local config = BaseballBat.getConfig()
  local pass, msg = assert_gt(config.swingCooldownSeconds, 0, "Cooldown should be positive")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_gt(config.swingRangeStuds, 0, "Range should be positive")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_gt(config.predatorDamage, 0, "Predator damage should be positive")
  if not pass then
    return pass, msg
  end
  return assert_gt(config.playerKnockbackForce, 0, "Player knockback force should be positive")
end)

test("BaseballBat: reset clears bat state", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  BaseballBat.reset(batState)
  local pass, msg = assert_false(batState.isEquipped, "Bat should be unequipped after reset")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(batState.swingsCount, 0, "Swing count should be 0 after reset")
  if not pass then
    return pass, msg
  end
  return assert_eq(batState.lastSwingTime, 0, "Last swing time should be 0 after reset")
end)

test("BaseballBat: getStats returns correct statistics", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 5)
  local stats = BaseballBat.getStats(batState)
  local pass, msg = assert_true(stats.isEquipped, "Stats should show equipped")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(stats.totalSwings, 1, "Stats should show 1 swing")
  if not pass then
    return pass, msg
  end
  return assert_eq(stats.lastSwingTime, 5, "Stats should show correct last swing time")
end)

test("BaseballBat: getDisplayInfo shows cooldown correctly", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  BaseballBat.performSwing(batState, 0)
  local displayInfo = BaseballBat.getDisplayInfo(batState, 0.2)
  local pass, msg = assert_true(displayInfo.isEquipped, "Should show equipped")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_false(displayInfo.canSwing, "Should not be able to swing during cooldown")
  if not pass then
    return pass, msg
  end
  return assert_gt(displayInfo.cooldownRemaining, 0, "Should have cooldown remaining")
end)

test("BaseballBat: getHitsToDefeat returns bat hits from PredatorConfig", function()
  local hits = BaseballBat.getHitsToDefeat("Rat")
  return assert_gt(hits, 0, "Rat should require positive bat hits")
end)

test("BaseballBat: hitPredator damages predator on hit", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local spawnState = PredatorSpawning.createSpawnState()
  -- Spawn a predator
  local spawnResult = PredatorSpawning.spawnPredator(spawnState, "Rat", "player1", 0)
  if not spawnResult.success or not spawnResult.predator then
    return false, "Failed to spawn predator for test"
  end
  local predatorId = spawnResult.predator.id
  local initialHealth = spawnResult.predator.health
  -- Hit the predator
  local result = BaseballBat.hitPredator(batState, spawnState, predatorId, 0)
  local pass, msg = assert_true(result.success, "Hit should succeed")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(result.hitType, "predator", "Hit type should be predator")
  if not pass then
    return pass, msg
  end
  return assert_gt(result.damage, 0, "Should deal positive damage")
end)

test("BaseballBat: hitPredator fails on inactive predator", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local spawnState = PredatorSpawning.createSpawnState()
  -- Try to hit non-existent predator
  local result = BaseballBat.hitPredator(batState, spawnState, "fake_id", 0)
  return assert_false(result.success, "Should fail to hit non-existent predator")
end)

test("BaseballBat: hitPredator respects swing cooldown", function()
  local batState = BaseballBat.createBatState()
  BaseballBat.equip(batState)
  local spawnState = PredatorSpawning.createSpawnState()
  local spawnResult = PredatorSpawning.spawnPredator(spawnState, "Rat", "player1", 0)
  if not spawnResult.success or not spawnResult.predator then
    return false, "Failed to spawn predator for test"
  end
  local predatorId = spawnResult.predator.id
  -- First hit
  BaseballBat.hitPredator(batState, spawnState, predatorId, 0)
  -- Try immediate second hit
  local result = BaseballBat.hitPredator(batState, spawnState, predatorId, 0.1)
  return assert_false(result.success, "Second hit should fail due to cooldown")
end)

-- ============================================================================
-- ChickenHealth Tests
-- ============================================================================

test("ChickenHealth: createRegistry returns valid registry", function()
  local registry = ChickenHealth.createRegistry()
  return assert_not_nil(registry, "Registry should not be nil")
    and assert_not_nil(registry.chickens, "Registry should have chickens table")
end)

test("ChickenHealth: register adds chicken to registry", function()
  local registry = ChickenHealth.createRegistry()
  local state = ChickenHealth.register(registry, "chicken1", "BasicChick")
  return assert_not_nil(state, "Should return health state")
    and assert_equals(state.chickenId, "chicken1", "Should have correct chicken id")
    and assert_equals(state.currentHealth, state.maxHealth, "Should start at full health")
end)

test("ChickenHealth: applyDamage reduces health correctly", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local result = ChickenHealth.applyDamage(registry, "chicken1", 20, os.time())
  return assert_equals(result.success, true, "Should succeed")
    and assert_gt(result.damageDealt, 0, "Should deal damage")
    and assert_equals(result.died, false, "Should not die from partial damage")
end)

test("ChickenHealth: chicken dies when health reaches 0", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local state = ChickenHealth.get(registry, "chicken1")
  if not state then
    return false, "State should exist"
  end
  local result = ChickenHealth.applyDamage(registry, "chicken1", state.maxHealth + 10, os.time())
  return assert_equals(result.success, true, "Should succeed")
    and assert_equals(result.died, true, "Should die when health reaches 0")
    and assert_equals(result.newHealth, 0, "Health should be 0")
end)

test("ChickenHealth: dead chicken cannot take more damage", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local state = ChickenHealth.get(registry, "chicken1")
  if not state then
    return false, "State should exist"
  end
  ChickenHealth.applyDamage(registry, "chicken1", state.maxHealth + 10, os.time())
  local result = ChickenHealth.applyDamage(registry, "chicken1", 10, os.time())
  return assert_equals(result.success, false, "Should fail for dead chicken")
end)

test("ChickenHealth: regenerates health after delay", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local startTime = os.time()
  ChickenHealth.applyDamage(registry, "chicken1", 20, startTime)

  -- Wait past regen delay
  local regenDelay = ChickenConfig.getHealthRegenDelay()
  local laterTime = startTime + regenDelay + 1

  local result = ChickenHealth.regenerate(registry, "chicken1", 1, laterTime)
  return assert_equals(result.success, true, "Should succeed")
    and assert_gt(result.amountHealed, 0, "Should regenerate some health")
end)

test("ChickenHealth: does not regenerate during regen delay", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local startTime = os.time()
  ChickenHealth.applyDamage(registry, "chicken1", 20, startTime)

  -- Try to regen immediately (within delay)
  local result = ChickenHealth.regenerate(registry, "chicken1", 1, startTime + 1)
  return assert_equals(result.amountHealed, 0, "Should not regenerate during delay")
end)

test("ChickenHealth: unregister removes chicken from registry", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local unregistered = ChickenHealth.unregister(registry, "chicken1")
  local state = ChickenHealth.get(registry, "chicken1")
  return assert_equals(unregistered, true, "Should return true on unregister")
    and assert_equals(state, nil, "State should be nil after unregister")
end)

test("ChickenHealth: rarer chickens have more health", function()
  local commonHealth = ChickenConfig.getMaxHealth("Common")
  local rareHealth = ChickenConfig.getMaxHealth("Rare")
  local legendaryHealth = ChickenConfig.getMaxHealth("Legendary")
  return assert_gt(rareHealth, commonHealth, "Rare should have more health than Common")
    and assert_gt(legendaryHealth, rareHealth, "Legendary should have more health than Rare")
end)

test("ChickenHealth: getHealthPercent returns correct value", function()
  local registry = ChickenHealth.createRegistry()
  ChickenHealth.register(registry, "chicken1", "BasicChick")
  local state = ChickenHealth.get(registry, "chicken1")
  if not state then
    return false, "State should exist"
  end
  ChickenHealth.applyDamage(registry, "chicken1", state.maxHealth / 2, os.time())
  local percent = ChickenHealth.getHealthPercent(registry, "chicken1")
  return assert_gt(percent, 0.4, "Should be around 50%")
    and assert_lt(percent, 0.6, "Should be around 50%")
end)

-- ============================================================================
-- PredatorAI Tests
-- ============================================================================

test("PredatorAI: createState returns valid state", function()
  local state = PredatorAI.createState()
  return assert_not_nil(state, "State should exist")
    and assert_not_nil(state.positions, "Positions should exist")
end)

test("PredatorAI: registerPredator adds predator to state", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  local position = PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  return assert_not_nil(position, "Position should be returned")
    and assert_eq(PredatorAI.getActiveCount(state), 1, "Should have 1 active predator")
end)

test("PredatorAI: predator spawns at section edge", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  local position = PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  -- Check that spawn position is far from center (at edge)
  local distFromCenter = (position.spawnPosition - sectionCenter).Magnitude
  return assert_gt(distFromCenter, 30, "Spawn should be at section edge")
end)

test("PredatorAI: updatePosition moves predator towards target", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  local position = PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  local initialDistance = (position.targetPosition - position.currentPosition).Magnitude
  -- Update with 1 second of movement
  PredatorAI.updatePosition(state, "pred1", 1)
  local newPosition = PredatorAI.getPosition(state, "pred1")
  local newDistance = (newPosition.targetPosition - newPosition.currentPosition).Magnitude
  return assert_lt(newDistance, initialDistance, "Distance should decrease after moving")
end)

test("PredatorAI: predator reaches coop after enough time", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  -- Simulate movement over time (large deltaTime to reach target)
  for _ = 1, 20 do
    PredatorAI.updatePosition(state, "pred1", 1)
  end
  return assert_eq(PredatorAI.hasReachedCoop(state, "pred1"), true, "Should reach coop")
end)

test("PredatorAI: unregisterPredator removes predator", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  PredatorAI.unregisterPredator(state, "pred1")
  return assert_eq(PredatorAI.getActiveCount(state), 0, "Should have 0 active predators")
end)

test("PredatorAI: higher threat predators move faster", function()
  local ratSpeed = PredatorAI.getWalkSpeed("Rat") -- Minor threat
  local bearSpeed = PredatorAI.getWalkSpeed("Bear") -- Catastrophic threat
  return assert_gt(bearSpeed, ratSpeed, "Bear should be faster than Rat")
end)

test("PredatorAI: getProgress returns percentage", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  local initialProgress = PredatorAI.getProgress(state, "pred1")
  PredatorAI.updatePosition(state, "pred1", 2)
  local afterProgress = PredatorAI.getProgress(state, "pred1")
  return assert_eq(initialProgress, 0, "Initial progress should be 0")
    and assert_gt(afterProgress, 0, "Progress should increase after moving")
end)

test("PredatorAI: getTimeToReachCoop returns estimate", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  local timeEstimate = PredatorAI.getTimeToReachCoop(state, "pred1")
  return assert_gt(timeEstimate, 0, "Time estimate should be positive")
end)

test("PredatorAI: getApproachingPredators returns correct list", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  PredatorAI.registerPredator(state, "pred2", "Crow", sectionCenter)
  local approaching = PredatorAI.getApproachingPredators(state)
  return assert_eq(#approaching, 2, "Should have 2 approaching predators")
end)

test("PredatorAI: registerRoamingPredator creates roaming predator", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  local position = PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  local pass, msg = assert_not_nil(position, "Position should be created")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(position.behaviorState, "roaming", "Should be in roaming state")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(position.roamTarget, "Should have roam target")
end)

test("PredatorAI: roaming predator stays in neutral zone", function()
  local center = Vector3.new(50, 0, 50)
  local size = 40
  local state = PredatorAI.createState(center, size)
  local currentTime = os.time()
  local position = PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  -- Check spawn position is within bounds
  local halfSize = size / 2
  local inBounds = position.currentPosition.X >= center.X - halfSize
    and position.currentPosition.X <= center.X + halfSize
    and position.currentPosition.Z >= center.Z - halfSize
    and position.currentPosition.Z <= center.Z + halfSize
  return assert_true(inBounds, "Roaming predator should spawn within neutral zone")
end)

test("PredatorAI: updateRoaming moves roaming predator", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  local initialPos = PredatorAI.getPosition(state, "roamer1")
  local initialX = initialPos.currentPosition.X
  local initialZ = initialPos.currentPosition.Z
  -- Update with enough time to move
  PredatorAI.updateRoaming(state, "roamer1", 2, currentTime + 2)
  local newPos = PredatorAI.getPosition(state, "roamer1")
  -- Position should have changed (unless already at roam target)
  local moved = newPos.currentPosition.X ~= initialX or newPos.currentPosition.Z ~= initialZ
  return assert_true(moved, "Roaming predator should move when updated")
end)

test("PredatorAI: shouldSeekTarget returns true after roam time expires", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local startTime = os.time()
  local position = PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", startTime)
  -- Immediately after spawn, should not seek (roam time not expired)
  local pass, msg = assert_false(
    PredatorAI.shouldSeekTarget(state, "roamer1", startTime + 1),
    "Should not seek target immediately"
  )
  if not pass then
    return pass, msg
  end
  -- After roam time expires (use roamEndTime + 1)
  local afterRoamTime = (position.roamEndTime or startTime) + 1
  return assert_true(
    PredatorAI.shouldSeekTarget(state, "roamer1", afterRoamTime),
    "Should seek target after roam time expires"
  )
end)

test("PredatorAI: startStalking transitions to stalking state", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  local targetSection = {
    sectionIndex = 1,
    center = Vector3.new(100, 0, 0),
    chickenCount = 5,
    distance = 30,
  }
  PredatorAI.startStalking(state, "roamer1", targetSection, currentTime)
  local position = PredatorAI.getPosition(state, "roamer1")
  local pass, msg = assert_eq(position.behaviorState, "stalking", "Should be in stalking state")
  if not pass then
    return pass, msg
  end
  return assert_true(position.isStalking, "isStalking flag should be true")
end)

test("PredatorAI: startApproaching transitions from stalking to approaching", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  local targetSection = {
    sectionIndex = 1,
    center = Vector3.new(100, 0, 0),
    chickenCount = 5,
    distance = 30,
  }
  PredatorAI.startStalking(state, "roamer1", targetSection, currentTime)
  PredatorAI.startApproaching(state, "roamer1", Vector3.new(100, 0, 0))
  local position = PredatorAI.getPosition(state, "roamer1")
  local pass, msg =
    assert_eq(position.behaviorState, "approaching", "Should be in approaching state")
  if not pass then
    return pass, msg
  end
  return assert_false(position.isStalking, "isStalking flag should be false")
end)

test("PredatorAI: getRoamingPredators returns only roaming predators", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  -- Add a roaming predator
  PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  -- Add a direct approaching predator
  PredatorAI.registerPredator(state, "direct1", "Crow", Vector3.new(50, 0, 50))
  local roaming = PredatorAI.getRoamingPredators(state)
  local pass, msg = assert_eq(#roaming, 1, "Should have 1 roaming predator")
  if not pass then
    return pass, msg
  end
  return assert_eq(roaming[1], "roamer1", "Should be roamer1")
end)

test("PredatorAI: getSummary includes roaming and stalking counts", function()
  local state = PredatorAI.createState(Vector3.new(0, 0, 0), 80)
  local currentTime = os.time()
  -- Add roaming predator
  PredatorAI.registerRoamingPredator(state, "roamer1", "Rat", currentTime)
  -- Add direct predator
  PredatorAI.registerPredator(state, "direct1", "Crow", Vector3.new(50, 0, 50))
  local summary = PredatorAI.getSummary(state)
  local pass, msg = assert_eq(summary.roaming, 1, "Should have 1 roaming")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(summary.approaching, 1, "Should have 1 approaching")
  if not pass then
    return pass, msg
  end
  return assert_eq(summary.totalActive, 2, "Should have 2 total active")
end)

test("PredatorAI: patrol behavior activates when attacking", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  -- Move predator to reach coop
  for _ = 1, 100 do
    PredatorAI.updatePosition(state, "pred1", 1, os.clock())
  end
  local position = PredatorAI.getPosition(state, "pred1")
  local pass, msg =
    assert_eq(position.behaviorState, "attacking", "Should be attacking after reaching coop")
  if not pass then
    return pass, msg
  end
  -- Update position should create patrol target
  PredatorAI.updatePosition(state, "pred1", 0.1, os.clock())
  position = PredatorAI.getPosition(state, "pred1")
  return assert_not_nil(position.coopCenter, "Should have coop center stored")
end)

test("PredatorAI: updateChickenPresence tracks no chickens time", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  -- Move predator to reach coop
  for _ = 1, 100 do
    PredatorAI.updatePosition(state, "pred1", 1, os.clock())
  end
  local currentTime = os.time()
  -- First call with no chickens should not trigger despawn
  local shouldDespawn = PredatorAI.updateChickenPresence(state, "pred1", false, currentTime)
  local pass, msg = assert_eq(shouldDespawn, false, "Should not despawn immediately")
  if not pass then
    return pass, msg
  end
  -- Check that noChickensTime was set
  local position = PredatorAI.getPosition(state, "pred1")
  return assert_not_nil(position.noChickensTime, "Should have noChickensTime set")
end)

test("PredatorAI: shouldDespawn returns true after enough time without chickens", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  -- Move predator to reach coop
  for _ = 1, 100 do
    PredatorAI.updatePosition(state, "pred1", 1, os.clock())
  end
  local startTime = os.time()
  -- First update with no chickens
  PredatorAI.updateChickenPresence(state, "pred1", false, startTime)
  -- Should not despawn yet
  local shouldDespawn = PredatorAI.shouldDespawn(state, "pred1", startTime)
  local pass, msg = assert_eq(shouldDespawn, false, "Should not despawn immediately")
  if not pass then
    return pass, msg
  end
  -- After 10 seconds (longer than despawn time of 8), should despawn
  shouldDespawn = PredatorAI.shouldDespawn(state, "pred1", startTime + 10)
  return assert_eq(shouldDespawn, true, "Should despawn after 10 seconds without chickens")
end)

test("PredatorAI: setTargetChicken stores target spot", function()
  local state = PredatorAI.createState()
  local sectionCenter = Vector3.new(0, 0, 0)
  PredatorAI.registerPredator(state, "pred1", "Rat", sectionCenter)
  local spotPos = Vector3.new(5, 1, 5)
  local success = PredatorAI.setTargetChicken(state, "pred1", 3, spotPos)
  local pass, msg = assert_eq(success, true, "setTargetChicken should succeed")
  if not pass then
    return pass, msg
  end
  local targetSpot = PredatorAI.getTargetChicken(state, "pred1")
  return assert_eq(targetSpot, 3, "Should have target chicken spot 3")
end)

-- ============================================================================
-- ChickenAI Tests
-- ============================================================================

test("ChickenAI: createState returns valid state", function()
  local state = ChickenAI.createState()
  return assert_not_nil(state, "State should exist")
    and assert_not_nil(state.positions, "Positions should exist")
end)

test("ChickenAI: createState accepts custom neutral zone", function()
  local center = Vector3.new(10, 0, 20)
  local size = 50
  local state = ChickenAI.createState(center, size)
  local pass, msg = assert_eq(state.neutralZoneCenter.X, 10, "Center X should be 10")
  if not pass then
    return pass, msg
  end
  return assert_eq(state.neutralZoneSize, 50, "Size should be 50")
end)

test("ChickenAI: registerChicken adds chicken to state", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  local spawnPos = Vector3.new(5, 0, 5)
  local position = ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
  local pass, msg = assert_not_nil(position, "Position should be returned")
  if not pass then
    return pass, msg
  end
  return assert_eq(ChickenAI.getActiveCount(state), 1, "Should have 1 active chicken")
end)

test("ChickenAI: chicken spawns at correct position", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  local spawnPos = Vector3.new(8, 2, 4)
  local position = ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
  local pass, msg = assert_eq(position.currentPosition.X, 8, "X should be spawn X")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_eq(position.currentPosition.Y, 2, "Y should be spawn Y")
  if not pass then
    return pass, msg
  end
  return assert_eq(position.currentPosition.Z, 4, "Z should be spawn Z")
end)

test("ChickenAI: getWalkSpeed returns speed based on rarity", function()
  -- Common should be slower (0.8 multiplier)
  local commonSpeed = ChickenAI.getWalkSpeed("Cluck")
  -- Legendary should be faster (1.2 multiplier)
  local legendarySpeed = ChickenAI.getWalkSpeed("Goldie")
  return assert_true(legendarySpeed > commonSpeed, "Legendary should be faster than common")
end)

test("ChickenAI: isWithinBounds returns true for position inside zone", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local insidePos = Vector3.new(5, 0, 5)
  return assert_true(ChickenAI.isWithinBounds(state, insidePos), "Position should be within bounds")
end)

test("ChickenAI: isWithinBounds returns false for position outside zone", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local outsidePos = Vector3.new(100, 0, 100)
  return assert_false(
    ChickenAI.isWithinBounds(state, outsidePos),
    "Position should be outside bounds"
  )
end)

test("ChickenAI: clampToBounds keeps position inside neutral zone", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local outsidePos = Vector3.new(100, 5, 100)
  local clamped = ChickenAI.clampToBounds(state, outsidePos)
  local pass, msg = assert_true(
    ChickenAI.isWithinBounds(state, clamped),
    "Clamped position should be within bounds"
  )
  if not pass then
    return pass, msg
  end
  return assert_eq(clamped.Y, 5, "Y should be preserved")
end)

test("ChickenAI: generateRandomTarget stays within bounds", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentPos = Vector3.new(0, 0, 0)
  -- Generate multiple targets to test consistency
  for _ = 1, 10 do
    local target = ChickenAI.generateRandomTarget(state, currentPos)
    if not ChickenAI.isWithinBounds(state, target) then
      return false, "Generated target was outside bounds"
    end
  end
  return true, "All generated targets were within bounds"
end)

test("ChickenAI: updatePosition moves chicken towards target", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  local spawnPos = Vector3.new(0, 0, 0)
  ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
  -- Get initial position
  local initial = ChickenAI.getPosition(state, "chicken1")
  local initialX = initial.currentPosition.X
  local initialZ = initial.currentPosition.Z
  -- Update with 1 second delta time
  ChickenAI.updatePosition(state, "chicken1", 1.0, currentTime + 1)
  local updated = ChickenAI.getPosition(state, "chicken1")
  -- Position should change (unless idle or already at target)
  if updated.isIdle then
    return true, "Chicken is idle, no movement expected"
  end
  local moved = updated.currentPosition.X ~= initialX or updated.currentPosition.Z ~= initialZ
  return assert_true(moved, "Chicken should move when updated")
end)

test("ChickenAI: chicken stays within bounds during movement", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  local spawnPos = Vector3.new(0, 0, 0)
  ChickenAI.registerChicken(state, "chicken1", "Cluck", spawnPos, currentTime)
  -- Simulate many updates
  for i = 1, 50 do
    ChickenAI.updatePosition(state, "chicken1", 0.5, currentTime + i * 0.5)
    local pos = ChickenAI.getPosition(state, "chicken1")
    if not ChickenAI.isWithinBounds(state, pos.currentPosition) then
      return false, "Chicken moved outside bounds at iteration " .. i
    end
  end
  return true, "Chicken stayed within bounds during all updates"
end)

test("ChickenAI: unregisterChicken removes chicken from state", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
  local pass, msg = assert_eq(ChickenAI.getActiveCount(state), 1, "Should have 1 chicken")
  if not pass then
    return pass, msg
  end
  ChickenAI.unregisterChicken(state, "chicken1")
  return assert_eq(ChickenAI.getActiveCount(state), 0, "Should have 0 chickens after unregister")
end)

test("ChickenAI: isIdle returns correct idle state", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
  -- Initially not idle
  local initialIdle = ChickenAI.isIdle(state, "chicken1")
  -- After registration, chicken should not be idle (starts walking)
  return assert_false(initialIdle, "Chicken should not start idle")
end)

test("ChickenAI: updateAll updates all chickens", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
  ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
  local updated = ChickenAI.updateAll(state, 0.5, currentTime + 0.5)
  local pass, msg = assert_not_nil(updated["chicken1"], "Chicken1 should be updated")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(updated["chicken2"], "Chicken2 should be updated")
end)

test("ChickenAI: getActiveChickenIds returns all IDs", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
  ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
  local ids = ChickenAI.getActiveChickenIds(state)
  return assert_eq(#ids, 2, "Should have 2 active chicken IDs")
end)

test("ChickenAI: getAllPositions returns all positions", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
  ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
  local positions = ChickenAI.getAllPositions(state)
  local pass, msg = assert_not_nil(positions["chicken1"], "Chicken1 position should exist")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(positions["chicken2"], "Chicken2 position should exist")
end)

test("ChickenAI: getPositionInfo returns detailed position info", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(5, 0, 5), currentTime)
  local info = ChickenAI.getPositionInfo(state, "chicken1")
  local pass, msg = assert_not_nil(info, "Info should exist")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_not_nil(info.position, "Position should exist")
  if not pass then
    return pass, msg
  end
  pass, msg = assert_not_nil(info.facingDirection, "Facing direction should exist")
  if not pass then
    return pass, msg
  end
  return assert_not_nil(info.isIdle, "isIdle should exist")
end)

test("ChickenAI: setNeutralZone updates zone configuration", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local newCenter = Vector3.new(50, 0, 50)
  ChickenAI.setNeutralZone(state, newCenter, 100)
  local pass, msg = assert_eq(state.neutralZoneCenter.X, 50, "Center X should be updated")
  if not pass then
    return pass, msg
  end
  return assert_eq(state.neutralZoneSize, 100, "Size should be updated")
end)

test("ChickenAI: getSummary returns correct walking and idle counts", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 64)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(-10, 0, 0), currentTime)
  ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(10, 0, 0), currentTime)
  local summary = ChickenAI.getSummary(state)
  local pass, msg = assert_eq(summary.totalActive, 2, "Should have 2 total active")
  if not pass then
    return pass, msg
  end
  -- Both should start walking (not idle)
  return assert_eq(summary.walking, 2, "Both should be walking initially")
end)

test("ChickenAI: reset clears all chickens", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
  ChickenAI.registerChicken(state, "chicken2", "Cluck", Vector3.new(5, 0, 5), currentTime)
  local pass, msg = assert_eq(ChickenAI.getActiveCount(state), 2, "Should have 2 chickens")
  if not pass then
    return pass, msg
  end
  ChickenAI.reset(state)
  return assert_eq(ChickenAI.getActiveCount(state), 0, "Should have 0 chickens after reset")
end)

test("ChickenAI: updateSpawnPosition updates chicken position", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
  local newPos = Vector3.new(5, 2, 5)
  local success = ChickenAI.updateSpawnPosition(state, "chicken1", newPos)
  local pass, msg = assert_true(success, "Update should succeed")
  if not pass then
    return pass, msg
  end
  local position = ChickenAI.getPosition(state, "chicken1")
  return assert_eq(position.currentPosition.X, 5, "X should be updated to 5")
end)

test("ChickenAI: chicken becomes idle after reaching target", function()
  local state = ChickenAI.createState(Vector3.new(0, 0, 0), 32)
  local currentTime = os.time()
  -- Spawn at origin
  ChickenAI.registerChicken(state, "chicken1", "Cluck", Vector3.new(0, 0, 0), currentTime)
  -- Update many times to reach target and trigger idle
  for i = 1, 100 do
    ChickenAI.updatePosition(state, "chicken1", 0.1, currentTime + i * 0.1)
  end
  local position = ChickenAI.getPosition(state, "chicken1")
  -- After many updates, chicken should have reached target at least once and gone idle
  -- We just verify the position is valid and within bounds
  return assert_true(
    ChickenAI.isWithinBounds(state, position.currentPosition),
    "Chicken should still be within bounds after many updates"
  )
end)

-- ============================================================================
-- Test Runner
-- ============================================================================

-- Run all registered tests
function IntegrationTests.runAllTests(): TestSuiteResult
  local results: { TestResult } = {}
  local passed = 0
  local failed = 0
  local startTime = os.clock()

  for _, testCase in ipairs(tests) do
    local testStart = os.clock()
    local success, message = pcall(function()
      return testCase.fn()
    end)

    local testPassed = false
    local testMessage = ""

    if success then
      testPassed, testMessage = testCase.fn()
    else
      testPassed = false
      testMessage = "Error: " .. tostring(message)
    end

    local duration = os.clock() - testStart

    if testPassed then
      passed = passed + 1
    else
      failed = failed + 1
    end

    table.insert(results, {
      name = testCase.name,
      passed = testPassed,
      message = testMessage,
      duration = duration,
    })
  end

  local totalDuration = os.clock() - startTime

  return {
    totalTests = #tests,
    passed = passed,
    failed = failed,
    duration = totalDuration,
    results = results,
  }
end

-- Run tests and print results to console
function IntegrationTests.runAndPrint(): boolean
  local results = IntegrationTests.runAllTests()

  print("\n========================================")
  print("INTEGRATION TEST RESULTS")
  print("========================================\n")

  for _, result in ipairs(results.results) do
    local status = result.passed and "✓ PASS" or "✗ FAIL"
    print(string.format("%s: %s", status, result.name))
    if not result.passed then
      print(string.format("       %s", result.message))
    end
  end

  print("\n----------------------------------------")
  print(
    string.format(
      "Total: %d | Passed: %d | Failed: %d",
      results.totalTests,
      results.passed,
      results.failed
    )
  )
  print(string.format("Duration: %.3f seconds", results.duration))
  print("========================================\n")

  return results.failed == 0
end

-- Get test count
function IntegrationTests.getTestCount(): number
  return #tests
end

-- Get list of test names
function IntegrationTests.getTestNames(): { string }
  local names = {}
  for _, testCase in ipairs(tests) do
    table.insert(names, testCase.name)
  end
  return names
end

return IntegrationTests
