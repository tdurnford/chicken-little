--[[
	ChickenService
	Knit service that handles all chicken-related server logic.
	
	Provides:
	- Chicken placement and pickup operations
	- Chicken selling
	- Money collection from chickens
	- Event broadcasting for visual updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local GoodSignal = require(Packages:WaitForChild("GoodSignal"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChickenPlacement = require(Shared:WaitForChild("ChickenPlacement"))
local MoneyCollection = require(Shared:WaitForChild("MoneyCollection"))
local ChickenHealth = require(Shared:WaitForChild("ChickenHealth"))
local ChickenAI = require(Shared:WaitForChild("ChickenAI"))
local MapGeneration = require(Shared:WaitForChild("MapGeneration"))
local PlayerSection = require(Shared:WaitForChild("PlayerSection"))
local Store = require(Shared:WaitForChild("Store"))

-- Services will be retrieved after Knit starts
local PlayerDataService

-- Create the service
local ChickenService = Knit.CreateService({
  Name = "ChickenService",

  -- Client-exposed methods and events
  Client = {
    -- Signals that fire to clients
    ChickenPlaced = Knit.CreateSignal(), -- Fires to all clients when chicken placed
    ChickenPickedUp = Knit.CreateSignal(), -- Fires to all clients when chicken picked up
    ChickenMoved = Knit.CreateSignal(), -- Fires to all clients when chicken moved
    ChickenSold = Knit.CreateSignal(), -- Fires to owner when chicken sold
    MoneyCollected = Knit.CreateSignal(), -- Fires to owner when money collected
  },
})

-- Server-side signals (for other services to listen to)
ChickenService.ChickenAdded = GoodSignal.new() -- (userId: number, chicken: ChickenData)
ChickenService.ChickenRemoved = GoodSignal.new() -- (userId: number, chickenId: string, reason: string)
ChickenService.MoneyGenerated = GoodSignal.new() -- (userId: number, amount: number, chickenId: string)

-- Per-player chicken state tracking (health registry, AI state, etc.)
local playerChickenStates: {
  [number]: {
    healthRegistry: ChickenHealth.ChickenHealthRegistry,
    aiState: any?, -- ChickenAI state
  },
} =
  {}

--[[
	Initialize the service.
	Called automatically by Knit before Start.
]]
function ChickenService:KnitInit()
  print("[ChickenService] Initialized")
end

--[[
	Start the service.
	Called automatically by Knit after all services are initialized.
]]
function ChickenService:KnitStart()
  -- Get reference to PlayerDataService
  PlayerDataService = Knit.GetService("PlayerDataService")

  -- Get reference to MapService for section assignment events
  local MapService = Knit.GetService("MapService")

  -- Setup player connections
  Players.PlayerAdded:Connect(function(player)
    self:_initializePlayerState(player.UserId)
  end)

  Players.PlayerRemoving:Connect(function(player)
    self:_cleanupPlayerState(player.UserId)
  end)

  -- Initialize state for existing players (in case of late start)
  for _, player in ipairs(Players:GetPlayers()) do
    self:_initializePlayerState(player.UserId)
  end

  -- Listen for section assignments to spawn player's chickens in the world
  MapService.PlayerSectionAssigned:Connect(function(userId: number, sectionIndex: number)
    self:_onPlayerSectionAssigned(userId, sectionIndex)
  end)

  print("[ChickenService] Started")
end

--[[
	Initialize chicken state for a player.
	@param userId number - The user ID
]]
function ChickenService:_initializePlayerState(userId: number)
  if playerChickenStates[userId] then
    return -- Already initialized
  end

  playerChickenStates[userId] = {
    healthRegistry = ChickenHealth.createRegistry(),
    aiState = nil, -- Will be initialized when section is assigned
  }
end

--[[
	Initialize AI state for a player with their section info.
	@param userId number - The user ID
	@param sectionIndex number - The player's section index
]]
function ChickenService:InitializeAIState(userId: number, sectionIndex: number)
  local state = playerChickenStates[userId]
  if not state then
    self:_initializePlayerState(userId)
    state = playerChickenStates[userId]
  end

  local sectionCenter = MapGeneration.getSectionPosition(sectionIndex)
  if sectionCenter then
    state.aiState = ChickenAI.createState(sectionCenter)
  end
end

--[[
	Cleanup chicken state for a player.
	@param userId number - The user ID
]]
function ChickenService:_cleanupPlayerState(userId: number)
  playerChickenStates[userId] = nil
end

--[[
	Internal: Handle player section assignment.
	Initializes AI state and spawns all loaded chickens (including starter chicken).
	@param userId number - The user ID
	@param sectionIndex number - The assigned section index
]]
function ChickenService:_onPlayerSectionAssigned(userId: number, sectionIndex: number)
  -- Initialize AI state for the player's section
  self:InitializeAIState(userId, sectionIndex)

  -- Get player data to spawn their chickens
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    warn(string.format("[ChickenService] No player data for userId %d during section assignment", userId))
    return
  end

  -- Register all placed chickens (includes starter chicken for new players)
  if playerData.placedChickens and #playerData.placedChickens > 0 then
    local player = Players:GetPlayerByUserId(userId)
    local state = playerChickenStates[userId]

    for _, chicken in ipairs(playerData.placedChickens) do
      -- Register chicken with health and AI systems
      self:RegisterChicken(userId, chicken)

      -- Get position from AI for the visual event
      local position = nil
      if state and state.aiState then
        local aiPos = ChickenAI.getPosition(state.aiState, chicken.id)
        if aiPos then
          position = aiPos.currentPosition
        end
      end

      -- Fire ChickenPlaced event to all clients so visuals are created
      self.Client.ChickenPlaced:FireAll({
        playerId = userId,
        chicken = chicken,
        spotIndex = nil,
        position = position,
      })

      -- Fire server signal
      self.ChickenAdded:Fire(userId, chicken)
    end

    print(string.format("[ChickenService] Spawned %d chickens for player %s", #playerData.placedChickens, player and player.Name or tostring(userId)))
  end
end

--[[
	Get the chicken state for a player.
	@param userId number - The user ID
	@return ChickenState? - The player's chicken state
]]
function ChickenService:GetPlayerState(userId: number)
  return playerChickenStates[userId]
end

--[[
	CLIENT: Place a chicken from inventory into the world.
	
	@param player Player - The player placing the chicken
	@param chickenId string - The chicken's ID
	@return PlacementResult
]]
function ChickenService.Client:PlaceChicken(player: Player, chickenId: string)
  return ChickenService:PlaceChicken(player.UserId, chickenId)
end

--[[
	SERVER: Place a chicken from inventory into the world.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@return PlacementResult
]]
function ChickenService:PlaceChicken(
  userId: number,
  chickenId: string
): ChickenPlacement.PlacementResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  -- Check chicken limit before placing
  if ChickenPlacement.isAtChickenLimit(playerData) then
    local limitInfo = ChickenPlacement.getChickenLimitInfo(playerData)
    return {
      success = false,
      message = "Area full! Maximum " .. limitInfo.max .. " chickens per area.",
      atLimit = true,
    }
  end

  -- Place the chicken using free-roaming placement
  local result = ChickenPlacement.placeChickenFreeRoaming(playerData, chickenId)
  if result.success then
    local state = playerChickenStates[userId]

    -- Register chicken with health system
    if result.chicken and result.chicken.chickenType and state then
      ChickenHealth.register(state.healthRegistry, chickenId, result.chicken.chickenType)
    end

    -- Register chicken with AI for free-roaming behavior
    if state and state.aiState and result.chicken then
      local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
      if sectionCenter then
        local spawnPos = PlayerSection.getRandomPositionInSection(sectionCenter)
        local spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
        ChickenAI.registerChicken(
          state.aiState,
          chickenId,
          result.chicken.chickenType,
          spawnPosV3,
          os.clock()
        )
      end
    end

    -- Get initial position from AI for event
    local initialPosition = nil
    if state and state.aiState then
      local aiPos = ChickenAI.getPosition(state.aiState, chickenId)
      if aiPos then
        initialPosition = aiPos.currentPosition
      end
    end

    -- Fire event to all clients
    self.Client.ChickenPlaced:FireAll({
      playerId = userId,
      chicken = result.chicken,
      spotIndex = nil, -- No longer using spots
      position = initialPosition,
    })

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.ChickenAdded:Fire(userId, result.chicken)
  end

  return result
end

--[[
	CLIENT: Pick up a placed chicken back to inventory.
	
	@param player Player - The player picking up the chicken
	@param chickenId string - The chicken's ID
	@return PlacementResult
]]
function ChickenService.Client:PickupChicken(player: Player, chickenId: string)
  return ChickenService:PickupChicken(player.UserId, chickenId)
end

--[[
	SERVER: Pick up a placed chicken back to inventory.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@return PlacementResult
]]
function ChickenService:PickupChicken(
  userId: number,
  chickenId: string
): ChickenPlacement.PlacementResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  -- Get the spot index before pickup for the event (legacy)
  local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
  local spotIndex = chicken and chicken.spotIndex or nil

  local result = ChickenPlacement.pickupChicken(playerData, chickenId)
  if result.success then
    local state = playerChickenStates[userId]

    -- Unregister chicken from health system
    if state then
      ChickenHealth.unregister(state.healthRegistry, chickenId)
    end

    -- Unregister chicken from AI (free-roaming)
    if state and state.aiState then
      ChickenAI.unregisterChicken(state.aiState, chickenId)
    end

    -- Fire event to all clients
    self.Client.ChickenPickedUp:FireAll({
      playerId = userId,
      chickenId = chickenId,
      spotIndex = spotIndex,
    })

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.ChickenRemoved:Fire(userId, chickenId, "pickup")
  end

  return result
end

--[[
	CLIENT: Move a chicken to a different spot.
	
	@param player Player - The player moving the chicken
	@param chickenId string - The chicken's ID
	@param newSpotIndex number - The new spot index
	@return PlacementResult
]]
function ChickenService.Client:MoveChicken(player: Player, chickenId: string, newSpotIndex: number)
  return ChickenService:MoveChicken(player.UserId, chickenId, newSpotIndex)
end

--[[
	SERVER: Move a chicken to a different spot.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@param newSpotIndex number - The new spot index
	@return PlacementResult
]]
function ChickenService:MoveChicken(
  userId: number,
  chickenId: string,
  newSpotIndex: number
): ChickenPlacement.PlacementResult
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  -- Get the old spot index before the move
  local chicken, _ = ChickenPlacement.findPlacedChicken(playerData, chickenId)
  local oldSpotIndex = chicken and chicken.spotIndex or nil

  local result = ChickenPlacement.moveChicken(playerData, chickenId, newSpotIndex)
  if result.success then
    -- Fire event to all clients
    self.Client.ChickenMoved:FireAll({
      playerId = userId,
      chickenId = chickenId,
      oldSpotIndex = oldSpotIndex,
      newSpotIndex = newSpotIndex,
      chicken = result.chicken,
    })

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)
  end

  return result
end

--[[
	CLIENT: Sell a chicken for money.
	
	@param player Player - The player selling the chicken
	@param chickenId string - The chicken's ID
	@return SellResult
]]
function ChickenService.Client:SellChicken(player: Player, chickenId: string)
  return ChickenService:SellChicken(player.UserId, chickenId)
end

--[[
	SERVER: Sell a chicken for money.
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@return SellResult
]]
function ChickenService:SellChicken(userId: number, chickenId: string)
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result = Store.sellChicken(playerData, chickenId)
  if result.success then
    -- Fire event to client
    local player = Players:GetPlayerByUserId(userId)
    if player then
      self.Client.ChickenSold:Fire(player, {
        chickenId = chickenId,
        message = result.message,
      })
    end

    -- Update player data
    PlayerDataService:UpdateData(userId, playerData)

    -- Fire server signal
    self.ChickenRemoved:Fire(userId, chickenId, "sold")
  end

  return result
end

--[[
	CLIENT: Collect accumulated money from chickens.
	
	@param player Player - The player collecting money
	@param chickenId string? - Optional specific chicken ID (nil = collect all)
	@return CollectionResult
]]
function ChickenService.Client:CollectMoney(player: Player, chickenId: string?)
  return ChickenService:CollectMoney(player.UserId, chickenId)
end

--[[
	SERVER: Collect accumulated money from chickens.
	
	@param userId number - The user ID
	@param chickenId string? - Optional specific chicken ID (nil = collect all)
	@return CollectionResult
]]
function ChickenService:CollectMoney(userId: number, chickenId: string?)
  local playerData = PlayerDataService:GetData(userId)
  if not playerData then
    return { success = false, message = "Player data not found" }
  end

  local result
  if chickenId then
    -- Collect from a specific chicken
    result = MoneyCollection.collect(playerData, chickenId)
  else
    -- Collect from all chickens
    result = MoneyCollection.collectAll(playerData)
  end

  if result.success then
    local amountCollected = result.amountCollected or result.totalCollected or 0
    if amountCollected > 0 then
      -- Fire event to client
      local player = Players:GetPlayerByUserId(userId)
      if player then
        self.Client.MoneyCollected:Fire(player, amountCollected, nil)
      end

      -- Update player data
      PlayerDataService:UpdateData(userId, playerData)

      -- Fire server signal
      self.MoneyGenerated:Fire(userId, amountCollected, chickenId)
    end
  end

  return result
end

--[[
	SERVER: Get the health registry for a player's chickens.
	Used by other services (e.g., PredatorService) to damage chickens.
	
	@param userId number - The user ID
	@return ChickenHealthRegistry?
]]
function ChickenService:GetHealthRegistry(userId: number): ChickenHealth.ChickenHealthRegistry?
  local state = playerChickenStates[userId]
  if state then
    return state.healthRegistry
  end
  return nil
end

--[[
	SERVER: Get the AI state for a player's chickens.
	Used by other services to get chicken positions.
	
	@param userId number - The user ID
	@return ChickenAIState?
]]
function ChickenService:GetAIState(userId: number)
  local state = playerChickenStates[userId]
  if state then
    return state.aiState
  end
  return nil
end

--[[
	SERVER: Register a chicken with health and AI systems.
	Used when chickens are loaded from saved data.
	
	@param userId number - The user ID
	@param chicken ChickenData - The chicken data
	@param position Vector3? - Optional initial position
]]
function ChickenService:RegisterChicken(userId: number, chicken: any, position: Vector3?)
  local state = playerChickenStates[userId]
  if not state then
    return
  end

  -- Register with health system
  ChickenHealth.register(state.healthRegistry, chicken.id, chicken.chickenType)

  -- Register with AI system
  if state.aiState then
    local playerData = PlayerDataService:GetData(userId)
    if playerData then
      local sectionCenter = MapGeneration.getSectionPosition(playerData.sectionIndex or 1)
      if sectionCenter then
        local spawnPos = position or PlayerSection.getRandomPositionInSection(sectionCenter)
        local spawnPosV3
        if typeof(spawnPos) == "Vector3" then
          spawnPosV3 = spawnPos
        else
          spawnPosV3 = Vector3.new(spawnPos.x, spawnPos.y, spawnPos.z)
        end
        ChickenAI.registerChicken(
          state.aiState,
          chicken.id,
          chicken.chickenType,
          spawnPosV3,
          os.clock()
        )
      end
    end
  end
end

--[[
	SERVER: Unregister a chicken from health and AI systems.
	Used when chickens are removed (stolen, killed, etc.)
	
	@param userId number - The user ID
	@param chickenId string - The chicken's ID
	@param reason string - Reason for removal (for signal)
]]
function ChickenService:UnregisterChicken(userId: number, chickenId: string, reason: string?)
  local state = playerChickenStates[userId]
  if not state then
    return
  end

  -- Unregister from health system
  ChickenHealth.unregister(state.healthRegistry, chickenId)

  -- Unregister from AI system
  if state.aiState then
    ChickenAI.unregisterChicken(state.aiState, chickenId)
  end

  -- Fire server signal
  self.ChickenRemoved:Fire(userId, chickenId, reason or "removed")
end

return ChickenService
