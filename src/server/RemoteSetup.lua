--[[
	RemoteSetup Module
	Creates and manages all RemoteEvents and RemoteFunctions for client-server communication.
	All remotes are created in ReplicatedStorage/Remotes for accessibility from both client and server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = {}

-- List of all RemoteEvents to create
local REMOTE_EVENTS = {
  "PlayerDataChanged",
  "ChickenPlaced",
  "ChickenPickedUp",
  "ChickenMoved",
  "ChickenSold",
  "EggHatched",
  "MoneyCollected",
  "TrapPlaced",
  "TrapCaught",
  "PredatorSpawned",
  "PredatorDefeated",
  "LockActivated",
  "TradeRequested",
  "TradeUpdated",
  "TradeCompleted",
  "RandomChickenSpawned",
  "RandomChickenClaimed",
  "RandomChickenDespawned",
  "AlertTriggered",
  "EggLaid",
  "EggSpawned",
  "EggCollected",
  "EggDespawned",
  "OfflineEarningsAwarded",
  "CompleteTutorial",
  "BatEquipped",
  "StoreReplenished",
  "StoreOpened",
  "StoreInventoryUpdated",
  "WeaponEquipped",
  "ShieldActivated",
  "ShieldDeactivated",
  "PlayerDamaged",
  "PlayerKnockback",
  "PlayerHealthChanged",
  "PlayerIncapacitated",
  "ChickenDamaged",
  "ChickenHealthChanged",
  "ChickenDied",
  "PredatorPositionUpdated",
  "PredatorHealthUpdated",
  "RandomChickenPositionUpdated",
  "ChickenPositionUpdated",
  "ProtectionStatusChanged",
  "BankruptcyAssistance",
  "PowerUpActivated",
  "AdminWarning",
}

-- List of all RemoteFunctions to create
local REMOTE_FUNCTIONS = {
  "GetPlayerData",
  "PlaceChicken",
  "PickupChicken",
  "SellChicken",
  "SellEgg",
  "SellPredator",
  "HatchEgg",
  "CollectWorldEgg",
  "CollectMoney",
  "BuyEgg",
  "BuyChicken",
  "BuyTrap",
  "BuyWeapon",
  "PlaceTrap",
  "ActivateLock",
  "UpgradeCage",
  "RequestTrade",
  "AcceptTrade",
  "AddToTrade",
  "ConfirmTrade",
  "CancelTrade",
  "ClaimRandomChicken",
  "SwingBat",
  "StealChicken",
  "MoveChicken",
  "GetStoreInventory",
  "EquipWeapon",
  "ActivateShield",
  "ReplenishStoreWithRobux",
  "BuyItemWithRobux",
  "GetGlobalChickenCounts",
  "BuyPowerUp",
  "AdminCommand",
  "GetAdminStatus",
  "GetAdminLog",
  "GetOnlinePlayers",
}

-- Type for the created remotes container
export type RemotesContainer = {
  events: { [string]: RemoteEvent },
  functions: { [string]: RemoteFunction },
}

-- Internal storage for created remotes
local remotes: RemotesContainer? = nil

--[[
	Creates the Remotes folder in ReplicatedStorage if it doesn't exist.
	@return Folder - The Remotes folder
]]
local function getOrCreateRemotesFolder(): Folder
  local folder = ReplicatedStorage:FindFirstChild("Remotes")
  if not folder then
    folder = Instance.new("Folder")
    folder.Name = "Remotes"
    folder.Parent = ReplicatedStorage
  end
  return folder :: Folder
end

--[[
	Creates all RemoteEvents in the Remotes folder.
	@param folder Folder - The folder to create events in
	@return { [string]: RemoteEvent } - Dictionary of created events
]]
local function createRemoteEvents(folder: Folder): { [string]: RemoteEvent }
  local events: { [string]: RemoteEvent } = {}
  for _, name in ipairs(REMOTE_EVENTS) do
    local existing = folder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
      events[name] = existing
    else
      local event = Instance.new("RemoteEvent")
      event.Name = name
      event.Parent = folder
      events[name] = event
    end
  end
  return events
end

--[[
	Creates all RemoteFunctions in the Remotes folder.
	@param folder Folder - The folder to create functions in
	@return { [string]: RemoteFunction } - Dictionary of created functions
]]
local function createRemoteFunctions(folder: Folder): { [string]: RemoteFunction }
  local functions: { [string]: RemoteFunction } = {}
  for _, name in ipairs(REMOTE_FUNCTIONS) do
    local existing = folder:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then
      functions[name] = existing
    else
      local func = Instance.new("RemoteFunction")
      func.Name = name
      func.Parent = folder
      functions[name] = func
    end
  end
  return functions
end

--[[
	Initializes all RemoteEvents and RemoteFunctions.
	Should be called once on server start.
	@return RemotesContainer - Container with all created remotes
]]
function RemoteSetup.initialize(): RemotesContainer
  if remotes then
    return remotes
  end

  local folder = getOrCreateRemotesFolder()
  local events = createRemoteEvents(folder)
  local functions = createRemoteFunctions(folder)

  remotes = {
    events = events,
    functions = functions,
  }

  print(
    "[RemoteSetup] Initialized",
    #REMOTE_EVENTS,
    "RemoteEvents and",
    #REMOTE_FUNCTIONS,
    "RemoteFunctions"
  )

  return remotes
end

--[[
	Gets the remotes container. Must call initialize() first.
	@return RemotesContainer? - The remotes container or nil if not initialized
]]
function RemoteSetup.getRemotes(): RemotesContainer?
  return remotes
end

--[[
	Gets a specific RemoteEvent by name.
	@param name string - The name of the RemoteEvent
	@return RemoteEvent? - The RemoteEvent or nil if not found
]]
function RemoteSetup.getEvent(name: string): RemoteEvent?
  if not remotes then
    return nil
  end
  return remotes.events[name]
end

--[[
	Gets a specific RemoteFunction by name.
	@param name string - The name of the RemoteFunction
	@return RemoteFunction? - The RemoteFunction or nil if not found
]]
function RemoteSetup.getFunction(name: string): RemoteFunction?
  if not remotes then
    return nil
  end
  return remotes.functions[name]
end

--[[
	Gets list of all RemoteEvent names.
	@return { string } - Array of RemoteEvent names
]]
function RemoteSetup.getEventNames(): { string }
  return table.clone(REMOTE_EVENTS)
end

--[[
	Gets list of all RemoteFunction names.
	@return { string } - Array of RemoteFunction names
]]
function RemoteSetup.getFunctionNames(): { string }
  return table.clone(REMOTE_FUNCTIONS)
end

--[[
	Gets a summary of the RemoteSetup module.
	@return string - Summary description
]]
function RemoteSetup.getSummary(): string
  local initialized = remotes ~= nil and "Yes" or "No"
  return string.format(
    "RemoteSetup: %d events, %d functions, Initialized: %s",
    #REMOTE_EVENTS,
    #REMOTE_FUNCTIONS,
    initialized
  )
end

return RemoteSetup
