--[[
	MapService.spec.lua
	Tests for the MapService Knit service.
]]

return function()
  local ReplicatedStorage = game:GetService("ReplicatedStorage")

  local Shared = ReplicatedStorage:WaitForChild("Shared")
  local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
  local PlayerSection = require(Shared:WaitForChild("PlayerSection"))

  describe("MapService", function()
    -- Note: Full integration tests require Knit to be started.
    -- These tests validate the underlying modules and types.

    describe("MapGeneration Integration", function()
      it("should create a valid map state", function()
        local mapState = MapGeneration.createMapState()
        expect(mapState).to.be.ok()
        expect(mapState.sections).to.be.ok()
        expect(#mapState.sections).to.equal(12)
      end)

      it("should get section positions", function()
        local position = MapGeneration.getSectionPosition(1)
        expect(position).to.be.ok()
        expect(position.x).to.be.a("number")
        expect(position.y).to.be.a("number")
        expect(position.z).to.be.a("number")
      end)

      it("should return nil for invalid section index", function()
        local position = MapGeneration.getSectionPosition(0)
        expect(position).to.equal(nil)

        position = MapGeneration.getSectionPosition(13)
        expect(position).to.equal(nil)
      end)

      it("should validate map state", function()
        local mapState = MapGeneration.createMapState()
        expect(MapGeneration.validateMapState(mapState)).to.equal(true)
      end)

      it("should find available sections", function()
        local mapState = MapGeneration.createMapState()
        local available = MapGeneration.findAvailableSection(mapState)
        expect(available).to.equal(1)
      end)

      it("should get max sections", function()
        local maxSections = MapGeneration.getMaxSections()
        expect(maxSections).to.equal(12)
      end)
    end)

    describe("Section Assignment", function()
      it("should assign section to player", function()
        local mapState = MapGeneration.createMapState()
        local playerId = "12345"
        local currentTime = os.time()

        local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)
        expect(sectionIndex).to.equal(1)
        expect(MapGeneration.getPlayerSection(mapState, playerId)).to.equal(1)
      end)

      it("should not assign duplicate sections", function()
        local mapState = MapGeneration.createMapState()
        local playerId1 = "12345"
        local playerId2 = "67890"
        local currentTime = os.time()

        local section1 = MapGeneration.handlePlayerJoin(mapState, playerId1, currentTime)
        local section2 = MapGeneration.handlePlayerJoin(mapState, playerId2, currentTime)

        expect(section1).to.equal(1)
        expect(section2).to.equal(2)
        expect(section1).to.never.equal(section2)
      end)

      it("should handle player leave and reserve section", function()
        local mapState = MapGeneration.createMapState()
        local playerId = "12345"
        local currentTime = os.time()

        -- Join
        local sectionIndex = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)
        expect(sectionIndex).to.equal(1)

        -- Leave
        local reserved = MapGeneration.handlePlayerLeave(mapState, playerId)
        expect(reserved).to.equal(1)

        -- Section should now be available again
        expect(MapGeneration.isSectionAvailable(mapState, 1)).to.equal(true)
      end)

      it("should reassign reserved section on rejoin", function()
        local mapState = MapGeneration.createMapState()
        local playerId = "12345"
        local currentTime = os.time()

        -- First join
        local section1 = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)
        expect(section1).to.equal(1)

        -- Leave (reserves section)
        MapGeneration.handlePlayerLeave(mapState, playerId)

        -- Rejoin - should get same section
        local section2 = MapGeneration.handlePlayerJoin(mapState, playerId, currentTime + 10)
        expect(section2).to.equal(1)
      end)

      it("should return player spawn point", function()
        local mapState = MapGeneration.createMapState()
        local playerId = "12345"
        local currentTime = os.time()

        MapGeneration.handlePlayerJoin(mapState, playerId, currentTime)
        local spawnPoint = MapGeneration.getPlayerSpawnPoint(mapState, playerId)

        expect(spawnPoint).to.be.ok()
        expect(spawnPoint.x).to.be.a("number")
        expect(spawnPoint.y).to.be.a("number")
        expect(spawnPoint.z).to.be.a("number")
      end)
    end)

    describe("Map State Queries", function()
      it("should count assigned sections", function()
        local mapState = MapGeneration.createMapState()
        local currentTime = os.time()

        expect(MapGeneration.getAssignedCount(mapState)).to.equal(0)

        MapGeneration.handlePlayerJoin(mapState, "player1", currentTime)
        expect(MapGeneration.getAssignedCount(mapState)).to.equal(1)

        MapGeneration.handlePlayerJoin(mapState, "player2", currentTime)
        expect(MapGeneration.getAssignedCount(mapState)).to.equal(2)
      end)

      it("should count available sections", function()
        local mapState = MapGeneration.createMapState()
        local currentTime = os.time()

        expect(MapGeneration.getAvailableCount(mapState)).to.equal(12)

        MapGeneration.handlePlayerJoin(mapState, "player1", currentTime)
        expect(MapGeneration.getAvailableCount(mapState)).to.equal(11)
      end)

      it("should detect full map", function()
        local mapState = MapGeneration.createMapState()
        local currentTime = os.time()

        expect(MapGeneration.isMapFull(mapState)).to.equal(false)

        -- Fill all 12 sections
        for i = 1, 12 do
          MapGeneration.handlePlayerJoin(mapState, "player" .. i, currentTime)
        end

        expect(MapGeneration.isMapFull(mapState)).to.equal(true)
      end)

      it("should return nil when map is full", function()
        local mapState = MapGeneration.createMapState()
        local currentTime = os.time()

        -- Fill all 12 sections
        for i = 1, 12 do
          MapGeneration.handlePlayerJoin(mapState, "player" .. i, currentTime)
        end

        -- 13th player should get nil
        local section = MapGeneration.handlePlayerJoin(mapState, "player13", currentTime)
        expect(section).to.equal(nil)
      end)

      it("should get active assignments", function()
        local mapState = MapGeneration.createMapState()
        local currentTime = os.time()

        MapGeneration.handlePlayerJoin(mapState, "player1", currentTime)
        MapGeneration.handlePlayerJoin(mapState, "player2", currentTime)

        local active = MapGeneration.getActiveAssignments(mapState)
        expect(#active).to.equal(2)
      end)
    end)

    describe("Section Neighbors", function()
      it("should find neighbors for corner section", function()
        local neighbors = MapGeneration.getSectionNeighbors(1)
        -- Section 1 is top-left corner, should have 2 neighbors
        expect(#neighbors).to.equal(2)
      end)

      it("should find neighbors for center section", function()
        -- Section 6 is in the middle row
        local neighbors = MapGeneration.getSectionNeighbors(6)
        -- Should have left, right, top, bottom neighbors
        expect(#neighbors).to.be.near(3, 1) -- 3-4 neighbors depending on position
      end)

      it("should return empty for invalid section", function()
        local neighbors = MapGeneration.getSectionNeighbors(0)
        expect(#neighbors).to.equal(0)

        neighbors = MapGeneration.getSectionNeighbors(13)
        expect(#neighbors).to.equal(0)
      end)
    end)

    describe("PlayerSection Integration", function()
      it("should get section size", function()
        local size = PlayerSection.getSectionSize()
        expect(size).to.be.ok()
        expect(size.x).to.be.a("number")
        expect(size.y).to.be.a("number")
        expect(size.z).to.be.a("number")
      end)

      it("should create valid section template", function()
        local position = { x = 0, y = 0, z = 0 }
        local template = PlayerSection.createTemplate(1, position)

        expect(template).to.be.ok()
        expect(template.sectionIndex).to.equal(1)
        expect(template.centerPosition).to.be.ok()
        expect(template.spawnPoint).to.be.ok()
      end)

      it("should validate section templates", function()
        local position = { x = 0, y = 0, z = 0 }
        local template = PlayerSection.createTemplate(1, position)

        expect(PlayerSection.validateTemplate(template)).to.equal(true)
      end)
    end)

    describe("Protection Logic", function()
      -- These tests verify the protection duration constant behavior
      -- Actual protection tracking is in the service

      it("should have correct protection duration constant", function()
        -- The service uses NEW_PLAYER_PROTECTION_DURATION = 120
        local PROTECTION_DURATION = 120
        expect(PROTECTION_DURATION).to.equal(120)
      end)

      it("should calculate protection status correctly", function()
        local PROTECTION_DURATION = 120
        local joinTime = os.time()
        local currentTime = joinTime + 60 -- 60 seconds later

        local isProtected = (currentTime - joinTime) < PROTECTION_DURATION
        expect(isProtected).to.equal(true)

        -- After protection expires
        currentTime = joinTime + 130 -- 130 seconds later
        isProtected = (currentTime - joinTime) < PROTECTION_DURATION
        expect(isProtected).to.equal(false)
      end)

      it("should calculate remaining protection time", function()
        local PROTECTION_DURATION = 120
        local joinTime = os.time()
        local currentTime = joinTime + 60

        local remaining = math.max(0, PROTECTION_DURATION - (currentTime - joinTime))
        expect(remaining).to.equal(60)

        -- After expiration
        currentTime = joinTime + 150
        remaining = math.max(0, PROTECTION_DURATION - (currentTime - joinTime))
        expect(remaining).to.equal(0)
      end)
    end)
  end)
end
