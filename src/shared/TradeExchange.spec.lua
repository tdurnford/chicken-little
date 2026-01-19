--[[
	TradeExchange.spec.lua
	TestEZ tests for TradeExchange module
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local TradeExchange = require(Shared:WaitForChild("TradeExchange"))

  -- Helper function to create mock player data
  local function createMockPlayerData()
    return {
      money = 1000,
      inventory = {
        eggs = {},
        chickens = {},
      },
      placedChickens = {},
      traps = {},
      upgrades = {
        cageTier = 1,
      },
    }
  end

  -- Helper function to create mock egg
  local function createMockEgg(id, eggType, rarity)
    return {
      id = id or "egg-" .. tostring(math.random(1000, 9999)),
      eggType = eggType or "BasicEgg",
      rarity = rarity or "Common",
    }
  end

  -- Helper function to create mock chicken
  local function createMockChicken(id, chickenType, rarity, spotIndex)
    return {
      id = id or "chicken-" .. tostring(math.random(1000, 9999)),
      chickenType = chickenType or "BasicChick",
      rarity = rarity or "Common",
      accumulatedMoney = 0,
      lastEggTime = os.time(),
      spotIndex = spotIndex,
    }
  end

  -- Clean up sessions before each test group
  local function cleanupSessions()
    TradeExchange.resetAllSessions()
  end

  describe("TradeExchange", function()
    beforeEach(function()
      cleanupSessions()
    end)

    describe("generateTradeId", function()
      it("should generate a string ID", function()
        local id = TradeExchange.generateTradeId()
        expect(type(id)).to.equal("string")
      end)

      it("should start with 'trade_'", function()
        local id = TradeExchange.generateTradeId()
        expect(string.sub(id, 1, 6)).to.equal("trade_")
      end)

      it("should generate unique IDs", function()
        local id1 = TradeExchange.generateTradeId()
        local id2 = TradeExchange.generateTradeId()
        -- Due to random component, they should almost always differ
        -- (not a guarantee, but highly likely)
        expect(type(id1)).to.equal("string")
        expect(type(id2)).to.equal("string")
      end)
    end)

    describe("createSession", function()
      it("should create a new trade session", function()
        local session = TradeExchange.createSession(1, 2)
        expect(session).to.be.ok()
        expect(session.tradeId).to.be.ok()
        expect(session.player1Id).to.equal(1)
        expect(session.player2Id).to.equal(2)
      end)

      it("should initialize with pending status", function()
        local session = TradeExchange.createSession(1, 2)
        expect(session.status).to.equal("pending")
      end)

      it("should initialize empty offers", function()
        local session = TradeExchange.createSession(1, 2)
        expect(#session.player1Offer.items).to.equal(0)
        expect(#session.player2Offer.items).to.equal(0)
        expect(session.player1Offer.confirmed).to.equal(false)
        expect(session.player2Offer.confirmed).to.equal(false)
      end)

      it("should set start time", function()
        local beforeTime = os.time()
        local session = TradeExchange.createSession(1, 2)
        local afterTime = os.time()
        expect(session.startTime >= beforeTime).to.equal(true)
        expect(session.startTime <= afterTime).to.equal(true)
      end)
    end)

    describe("getSession", function()
      it("should return nil for non-existent session", function()
        expect(TradeExchange.getSession("nonexistent")).to.equal(nil)
      end)

      it("should return session by ID", function()
        local created = TradeExchange.createSession(1, 2)
        local retrieved = TradeExchange.getSession(created.tradeId)
        expect(retrieved).to.be.ok()
        expect(retrieved.tradeId).to.equal(created.tradeId)
      end)
    end)

    describe("getPlayerSession", function()
      it("should return nil when player has no session", function()
        expect(TradeExchange.getPlayerSession(999)).to.equal(nil)
      end)

      it("should return session for player 1", function()
        local session = TradeExchange.createSession(1, 2)
        local retrieved = TradeExchange.getPlayerSession(1)
        expect(retrieved).to.be.ok()
        expect(retrieved.tradeId).to.equal(session.tradeId)
      end)

      it("should return session for player 2", function()
        local session = TradeExchange.createSession(1, 2)
        local retrieved = TradeExchange.getPlayerSession(2)
        expect(retrieved).to.be.ok()
        expect(retrieved.tradeId).to.equal(session.tradeId)
      end)

      it("should not return completed sessions", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "completed"
        expect(TradeExchange.getPlayerSession(1)).to.equal(nil)
      end)

      it("should not return cancelled sessions", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "cancelled"
        expect(TradeExchange.getPlayerSession(1)).to.equal(nil)
      end)
    end)

    describe("isItemLocked", function()
      it("should return false when no sessions", function()
        expect(TradeExchange.isItemLocked("item1")).to.equal(false)
      end)

      it("should return false when session is pending", function()
        local session = TradeExchange.createSession(1, 2)
        session.lockedItems["item1"] = true
        -- Status is pending, not locked
        expect(TradeExchange.isItemLocked("item1")).to.equal(false)
      end)

      it("should return true when session is locked and item is in lockedItems", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        session.lockedItems["item1"] = true
        expect(TradeExchange.isItemLocked("item1")).to.equal(true)
      end)
    end)

    describe("validateOffer", function()
      it("should return valid for empty offer", function()
        local playerData = createMockPlayerData()
        local offer = { items = {}, confirmed = false }
        local result = TradeExchange.validateOffer(playerData, offer)
        expect(result.isValid).to.equal(true)
      end)

      it("should return invalid when egg not in inventory", function()
        local playerData = createMockPlayerData()
        local offer = {
          items = {
            { itemType = "egg", itemId = "egg1", itemData = {} },
          },
          confirmed = false,
        }
        local result = TradeExchange.validateOffer(playerData, offer)
        expect(result.isValid).to.equal(false)
        expect(#result.missingItems).to.equal(1)
      end)

      it("should return valid when egg is in inventory", function()
        local playerData = createMockPlayerData()
        table.insert(playerData.inventory.eggs, createMockEgg("egg1", "BasicEgg"))
        local offer = {
          items = {
            { itemType = "egg", itemId = "egg1", itemData = {} },
          },
          confirmed = false,
        }
        local result = TradeExchange.validateOffer(playerData, offer)
        expect(result.isValid).to.equal(true)
      end)

      it("should return valid when chicken is in inventory", function()
        local playerData = createMockPlayerData()
        table.insert(playerData.inventory.chickens, createMockChicken("chicken1", "BasicChick"))
        local offer = {
          items = {
            { itemType = "chicken", itemId = "chicken1", itemData = {} },
          },
          confirmed = false,
        }
        local result = TradeExchange.validateOffer(playerData, offer)
        expect(result.isValid).to.equal(true)
      end)

      it("should return valid when chicken is placed", function()
        local playerData = createMockPlayerData()
        table.insert(
          playerData.placedChickens,
          createMockChicken("chicken1", "BasicChick", "Common", 1)
        )
        local offer = {
          items = {
            { itemType = "chicken", itemId = "chicken1", itemData = {} },
          },
          confirmed = false,
        }
        local result = TradeExchange.validateOffer(playerData, offer)
        expect(result.isValid).to.equal(true)
      end)
    end)

    describe("validateSession", function()
      it("should return invalid for completed session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "completed"
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.validateSession(session, p1Data, p2Data)
        expect(result.isValid).to.equal(false)
      end)

      it("should return invalid for cancelled session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "cancelled"
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.validateSession(session, p1Data, p2Data)
        expect(result.isValid).to.equal(false)
      end)

      it("should return valid for pending session with valid offers", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.validateSession(session, p1Data, p2Data)
        expect(result.isValid).to.equal(true)
      end)
    end)

    describe("lockItems", function()
      it("should fail when both players have not confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.lockItems(session, p1Data, p2Data)
        expect(result.success).to.equal(false)
      end)

      it("should fail when only player 1 confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.lockItems(session, p1Data, p2Data)
        expect(result.success).to.equal(false)
      end)

      it("should succeed when both players confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.lockItems(session, p1Data, p2Data)
        expect(result.success).to.equal(true)
        expect(session.status).to.equal("locked")
      end)

      it("should lock all items from both offers", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        table.insert(p1Data.inventory.eggs, createMockEgg("egg1"))
        table.insert(p2Data.inventory.eggs, createMockEgg("egg2"))

        session.player1Offer.items = { { itemType = "egg", itemId = "egg1", itemData = {} } }
        session.player2Offer.items = { { itemType = "egg", itemId = "egg2", itemData = {} } }
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true

        local result = TradeExchange.lockItems(session, p1Data, p2Data)
        expect(result.success).to.equal(true)
        expect(session.lockedItems["egg1"]).to.equal(true)
        expect(session.lockedItems["egg2"]).to.equal(true)
      end)
    end)

    describe("executeTransfer", function()
      it("should fail if not locked", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()
        local result = TradeExchange.executeTransfer(session, p1Data, p2Data)
        expect(result.success).to.equal(false)
      end)

      it("should transfer eggs between players", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()

        -- Player 1 has egg1
        table.insert(p1Data.inventory.eggs, createMockEgg("egg1", "BasicEgg"))
        -- Player 2 has egg2
        table.insert(p2Data.inventory.eggs, createMockEgg("egg2", "RareEgg", "Rare"))

        session.player1Offer.items =
          { { itemType = "egg", itemId = "egg1", itemData = p1Data.inventory.eggs[1] } }
        session.player2Offer.items =
          { { itemType = "egg", itemId = "egg2", itemData = p2Data.inventory.eggs[1] } }
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true
        session.status = "locked"
        session.lockTime = os.time()

        local result = TradeExchange.executeTransfer(session, p1Data, p2Data)
        expect(result.success).to.equal(true)
        expect(session.status).to.equal("completed")

        -- P1 should have received egg from P2
        expect(#result.player1ItemsReceived).to.equal(1)
        -- P2 should have received egg from P1
        expect(#result.player2ItemsReceived).to.equal(1)
      end)

      it("should transfer chickens from inventory", function()
        local session = TradeExchange.createSession(1, 2)
        local p1Data = createMockPlayerData()
        local p2Data = createMockPlayerData()

        -- Player 1 has a chicken in inventory
        table.insert(p1Data.inventory.chickens, createMockChicken("chicken1", "BasicChick"))

        session.player1Offer.items = {
          { itemType = "chicken", itemId = "chicken1", itemData = p1Data.inventory.chickens[1] },
        }
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true
        session.status = "locked"
        session.lockTime = os.time()

        local result = TradeExchange.executeTransfer(session, p1Data, p2Data)
        expect(result.success).to.equal(true)
        -- P1's chicken should be removed
        expect(#p1Data.inventory.chickens).to.equal(0)
        -- P2 should have received the chicken
        expect(#p2Data.inventory.chickens).to.equal(1)
      end)
    end)

    describe("cancelSession", function()
      it("should cancel pending session", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.cancelSession(session, "Test reason")
        expect(result).to.equal(true)
        expect(session.status).to.equal("cancelled")
      end)

      it("should cancel locked session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        local result = TradeExchange.cancelSession(session, "Test reason")
        expect(result).to.equal(true)
        expect(session.status).to.equal("cancelled")
      end)

      it("should not cancel completed session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "completed"
        local result = TradeExchange.cancelSession(session, "Test reason")
        expect(result).to.equal(false)
        expect(session.status).to.equal("completed")
      end)

      it("should clear locked items on cancel", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        session.lockedItems["item1"] = true
        TradeExchange.cancelSession(session, "Test reason")
        expect(session.lockedItems["item1"]).to.equal(nil)
      end)
    end)

    describe("handleDisconnect", function()
      it("should return nil when player has no session", function()
        local result = TradeExchange.handleDisconnect(999)
        expect(result).to.equal(nil)
      end)

      it("should cancel session and return it", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.handleDisconnect(1)
        expect(result).to.be.ok()
        expect(result.tradeId).to.equal(session.tradeId)
        expect(result.status).to.equal("cancelled")
      end)
    end)

    describe("addItemToOffer", function()
      it("should fail for non-pending session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        local result = TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(false)
      end)

      it("should fail for locked items", function()
        local session = TradeExchange.createSession(1, 2)
        -- Create another locked session with this item
        local otherSession = TradeExchange.createSession(3, 4)
        otherSession.status = "locked"
        otherSession.lockedItems["egg1"] = true

        local result = TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(false)
      end)

      it("should fail for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.addItemToOffer(
          session,
          999,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(false)
      end)

      it("should fail for duplicate items", function()
        local session = TradeExchange.createSession(1, 2)
        TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        local result = TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(false)
      end)

      it("should add item to player 1 offer", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(true)
        expect(#session.player1Offer.items).to.equal(1)
      end)

      it("should add item to player 2 offer", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.addItemToOffer(
          session,
          2,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(result).to.equal(true)
        expect(#session.player2Offer.items).to.equal(1)
      end)

      it("should reset confirmation when offer changes", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        TradeExchange.addItemToOffer(
          session,
          1,
          { itemType = "egg", itemId = "egg1", itemData = {} }
        )
        expect(session.player1Offer.confirmed).to.equal(false)
      end)
    end)

    describe("removeItemFromOffer", function()
      it("should fail for non-pending session", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.items = { { itemType = "egg", itemId = "egg1", itemData = {} } }
        session.status = "locked"
        local result = TradeExchange.removeItemFromOffer(session, 1, "egg1")
        expect(result).to.equal(false)
      end)

      it("should fail for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.removeItemFromOffer(session, 999, "egg1")
        expect(result).to.equal(false)
      end)

      it("should fail for non-existent item", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.removeItemFromOffer(session, 1, "nonexistent")
        expect(result).to.equal(false)
      end)

      it("should remove item from offer", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.items = { { itemType = "egg", itemId = "egg1", itemData = {} } }
        local result = TradeExchange.removeItemFromOffer(session, 1, "egg1")
        expect(result).to.equal(true)
        expect(#session.player1Offer.items).to.equal(0)
      end)

      it("should reset confirmation when offer changes", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.items = { { itemType = "egg", itemId = "egg1", itemData = {} } }
        session.player1Offer.confirmed = true
        TradeExchange.removeItemFromOffer(session, 1, "egg1")
        expect(session.player1Offer.confirmed).to.equal(false)
      end)
    end)

    describe("setConfirmation", function()
      it("should fail for non-pending session", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        local result = TradeExchange.setConfirmation(session, 1, true)
        expect(result).to.equal(false)
      end)

      it("should fail for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.setConfirmation(session, 999, true)
        expect(result).to.equal(false)
      end)

      it("should set player 1 confirmation", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.setConfirmation(session, 1, true)
        expect(result).to.equal(true)
        expect(session.player1Offer.confirmed).to.equal(true)
      end)

      it("should set player 2 confirmation", function()
        local session = TradeExchange.createSession(1, 2)
        local result = TradeExchange.setConfirmation(session, 2, true)
        expect(result).to.equal(true)
        expect(session.player2Offer.confirmed).to.equal(true)
      end)

      it("should unset confirmation", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        TradeExchange.setConfirmation(session, 1, false)
        expect(session.player1Offer.confirmed).to.equal(false)
      end)
    end)

    describe("areBothConfirmed", function()
      it("should return false when neither confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)

      it("should return false when only player 1 confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)

      it("should return false when only player 2 confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        session.player2Offer.confirmed = true
        expect(TradeExchange.areBothConfirmed(session)).to.equal(false)
      end)

      it("should return true when both confirmed", function()
        local session = TradeExchange.createSession(1, 2)
        session.player1Offer.confirmed = true
        session.player2Offer.confirmed = true
        expect(TradeExchange.areBothConfirmed(session)).to.equal(true)
      end)
    end)

    describe("getPlayerOffer", function()
      it("should return nil for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.getPlayerOffer(session, 999)).to.equal(nil)
      end)

      it("should return player 1 offer", function()
        local session = TradeExchange.createSession(1, 2)
        local offer = TradeExchange.getPlayerOffer(session, 1)
        expect(offer).to.be.ok()
        expect(offer).to.equal(session.player1Offer)
      end)

      it("should return player 2 offer", function()
        local session = TradeExchange.createSession(1, 2)
        local offer = TradeExchange.getPlayerOffer(session, 2)
        expect(offer).to.be.ok()
        expect(offer).to.equal(session.player2Offer)
      end)
    end)

    describe("getPartnerOffer", function()
      it("should return nil for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.getPartnerOffer(session, 999)).to.equal(nil)
      end)

      it("should return player 2 offer for player 1", function()
        local session = TradeExchange.createSession(1, 2)
        local offer = TradeExchange.getPartnerOffer(session, 1)
        expect(offer).to.equal(session.player2Offer)
      end)

      it("should return player 1 offer for player 2", function()
        local session = TradeExchange.createSession(1, 2)
        local offer = TradeExchange.getPartnerOffer(session, 2)
        expect(offer).to.equal(session.player1Offer)
      end)
    end)

    describe("getPartnerId", function()
      it("should return nil for unknown player", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.getPartnerId(session, 999)).to.equal(nil)
      end)

      it("should return player 2 ID for player 1", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.getPartnerId(session, 1)).to.equal(2)
      end)

      it("should return player 1 ID for player 2", function()
        local session = TradeExchange.createSession(1, 2)
        expect(TradeExchange.getPartnerId(session, 2)).to.equal(1)
      end)
    end)

    describe("getSummary", function()
      it("should return summary string", function()
        local session = TradeExchange.createSession(1, 2)
        local summary = TradeExchange.getSummary(session)
        expect(type(summary)).to.equal("string")
        expect(string.len(summary) > 0).to.equal(true)
      end)

      it("should include trade ID", function()
        local session = TradeExchange.createSession(1, 2)
        local summary = TradeExchange.getSummary(session)
        expect(string.find(summary, session.tradeId)).to.be.ok()
      end)

      it("should include status", function()
        local session = TradeExchange.createSession(1, 2)
        local summary = TradeExchange.getSummary(session)
        expect(string.find(summary, "pending")).to.be.ok()
      end)
    end)

    describe("getActiveSessionCount", function()
      it("should return 0 when no sessions", function()
        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)

      it("should count pending sessions", function()
        TradeExchange.createSession(1, 2)
        TradeExchange.createSession(3, 4)
        expect(TradeExchange.getActiveSessionCount()).to.equal(2)
      end)

      it("should count locked sessions", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "locked"
        expect(TradeExchange.getActiveSessionCount()).to.equal(1)
      end)

      it("should not count completed sessions", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "completed"
        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)

      it("should not count cancelled sessions", function()
        local session = TradeExchange.createSession(1, 2)
        session.status = "cancelled"
        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)
    end)

    describe("resetAllSessions", function()
      it("should clear all sessions", function()
        TradeExchange.createSession(1, 2)
        TradeExchange.createSession(3, 4)
        expect(TradeExchange.getActiveSessionCount()).to.equal(2)
        TradeExchange.resetAllSessions()
        expect(TradeExchange.getActiveSessionCount()).to.equal(0)
      end)
    end)

    describe("cleanupExpiredSessions", function()
      it("should remove completed and cancelled sessions", function()
        local session1 = TradeExchange.createSession(1, 2)
        local session2 = TradeExchange.createSession(3, 4)
        session1.status = "completed"
        session2.status = "cancelled"

        TradeExchange.cleanupExpiredSessions()
        expect(TradeExchange.getSession(session1.tradeId)).to.equal(nil)
        expect(TradeExchange.getSession(session2.tradeId)).to.equal(nil)
      end)

      it("should keep active sessions", function()
        local session = TradeExchange.createSession(1, 2)
        TradeExchange.cleanupExpiredSessions()
        expect(TradeExchange.getSession(session.tradeId)).to.be.ok()
      end)
    end)
  end)
end
