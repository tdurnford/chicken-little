--[[
	Mocks/init.lua
	Pre-built mock objects for common game services and modules.
]]

local Mocks = {}

export type MockPlayer = {
  UserId: number,
  Name: string,
  DisplayName: string,
  Team: any?,
  Character: Model?,
  -- Methods
  GetAttribute: (self: MockPlayer, name: string) -> any,
  SetAttribute: (self: MockPlayer, name: string, value: any) -> (),
  Kick: (self: MockPlayer, message: string?) -> (),
}

export type MockCharacter = {
  Name: string,
  PrimaryPart: BasePart?,
  Humanoid: {
    Health: number,
    MaxHealth: number,
    WalkSpeed: number,
    JumpPower: number,
  },
  HumanoidRootPart: BasePart?,
}

-- Create a mock Player object
function Mocks.createMockPlayer(config: {
  UserId: number?,
  Name: string?,
  DisplayName: string?,
}?): MockPlayer
  config = config or {}

  local attributes: { [string]: any } = {}

  return {
    UserId = config.UserId or math.random(100000, 999999),
    Name = config.Name or "TestPlayer",
    DisplayName = config.DisplayName or config.Name or "TestPlayer",
    Team = nil,
    Character = nil,

    GetAttribute = function(self, name: string)
      return attributes[name]
    end,

    SetAttribute = function(self, name: string, value: any)
      attributes[name] = value
    end,

    Kick = function(self, message: string?)
      -- No-op in mock
    end,
  }
end

-- Create a mock ProfileService profile
function Mocks.createMockProfile(data: { [string]: any }?): {
  Data: { [string]: any },
  MetaData: { [string]: any },
  Release: () -> (),
  IsActive: () -> boolean,
  ListenToRelease: (callback: () -> ()) -> { Disconnect: () -> () },
}
  local isActive = true
  local releaseCallbacks: { () -> () } = {}

  return {
    Data = data or {},
    MetaData = {
      ProfileCreateTime = os.time(),
      SessionLoadCount = 1,
      ActiveSession = { 1, os.time() },
    },

    Release = function()
      isActive = false
      for _, callback in releaseCallbacks do
        callback()
      end
    end,

    IsActive = function()
      return isActive
    end,

    ListenToRelease = function(callback: () -> ())
      table.insert(releaseCallbacks, callback)
      return {
        Disconnect = function()
          local idx = table.find(releaseCallbacks, callback)
          if idx then
            table.remove(releaseCallbacks, idx)
          end
        end,
      }
    end,
  }
end

-- Create a mock RemoteEvent
function Mocks.createMockRemoteEvent(): {
  Name: string,
  OnServerEvent: {
    Connect: (callback: (player: Player, ...any) -> ()) -> { Disconnect: () -> () },
  },
  OnClientEvent: {
    Connect: (callback: (...any) -> ()) -> { Disconnect: () -> () },
  },
  FireServer: (...any) -> (),
  FireClient: (player: Player, ...any) -> (),
  FireAllClients: (...any) -> (),
}
  local serverCallbacks: { (player: Player, ...any) -> () } = {}
  local clientCallbacks: { (...any) -> () } = {}

  return {
    Name = "MockRemoteEvent",

    OnServerEvent = {
      Connect = function(callback)
        table.insert(serverCallbacks, callback)
        return {
          Disconnect = function()
            local idx = table.find(serverCallbacks, callback)
            if idx then
              table.remove(serverCallbacks, idx)
            end
          end,
        }
      end,
    },

    OnClientEvent = {
      Connect = function(callback)
        table.insert(clientCallbacks, callback)
        return {
          Disconnect = function()
            local idx = table.find(clientCallbacks, callback)
            if idx then
              table.remove(clientCallbacks, idx)
            end
          end,
        }
      end,
    },

    FireServer = function(...)
      -- In tests, would need to manually call server callbacks
    end,

    FireClient = function(player, ...)
      for _, callback in clientCallbacks do
        callback(...)
      end
    end,

    FireAllClients = function(...)
      for _, callback in clientCallbacks do
        callback(...)
      end
    end,
  }
end

-- Create a mock RemoteFunction
function Mocks.createMockRemoteFunction(serverHandler: ((player: Player, ...any) -> any)?): {
  Name: string,
  OnServerInvoke: ((player: Player, ...any) -> any)?,
  OnClientInvoke: ((...any) -> any)?,
  InvokeServer: (...any) -> any,
  InvokeClient: (player: Player, ...any) -> any,
}
  return {
    Name = "MockRemoteFunction",
    OnServerInvoke = serverHandler,
    OnClientInvoke = nil,

    InvokeServer = function(...)
      -- Would invoke OnServerInvoke in real implementation
      return nil
    end,

    InvokeClient = function(player, ...)
      -- Would invoke OnClientInvoke in real implementation
      return nil
    end,
  }
end

-- Create a mock GoodSignal
function Mocks.createMockSignal(): {
  Connect: (callback: (...any) -> ()) -> { Disconnect: () -> () },
  Once: (callback: (...any) -> ()) -> { Disconnect: () -> () },
  Wait: () -> ...any,
  Fire: (...any) -> (),
  DisconnectAll: () -> (),
}
  local connections: { (...any) -> () } = {}
  local onceConnections: { (...any) -> () } = {}
  local waitingThreads: { thread } = {}

  return {
    Connect = function(callback)
      table.insert(connections, callback)
      return {
        Disconnect = function()
          local idx = table.find(connections, callback)
          if idx then
            table.remove(connections, idx)
          end
        end,
      }
    end,

    Once = function(callback)
      table.insert(onceConnections, callback)
      return {
        Disconnect = function()
          local idx = table.find(onceConnections, callback)
          if idx then
            table.remove(onceConnections, idx)
          end
        end,
      }
    end,

    Wait = function()
      table.insert(waitingThreads, coroutine.running())
      return coroutine.yield()
    end,

    Fire = function(...)
      -- Fire to connections
      for _, callback in connections do
        task.spawn(callback, ...)
      end

      -- Fire to once connections and clear them
      local onceCopy = table.clone(onceConnections)
      onceConnections = {}
      for _, callback in onceCopy do
        task.spawn(callback, ...)
      end

      -- Resume waiting threads
      local threadsCopy = table.clone(waitingThreads)
      waitingThreads = {}
      for _, thread in threadsCopy do
        task.spawn(thread, ...)
      end
    end,

    DisconnectAll = function()
      connections = {}
      onceConnections = {}
    end,
  }
end

-- Create mock PlayerData
function Mocks.createMockPlayerData(): {
  money: number,
  level: number,
  xp: number,
  chickens: { [string]: number },
  eggs: { [string]: number },
  inventory: { [string]: number },
  stats: { [string]: number },
}
  return {
    money = 100,
    level = 1,
    xp = 0,
    chickens = {},
    eggs = {},
    inventory = {},
    stats = {
      eggsCollected = 0,
      chickensHatched = 0,
      predatorsDefeated = 0,
      moneyEarned = 0,
    },
  }
end

-- Create a mock Knit service
function Mocks.createMockKnitService(
  name: string,
  methods: { [string]: (...any) -> any }?
): {
  Name: string,
  Client: { [string]: any },
  [string]: any,
}
  methods = methods or {}

  local service = {
    Name = name,
    Client = {},
  }

  for methodName, methodFn in methods do
    service[methodName] = methodFn
    service.Client[methodName] = methodFn
  end

  return service
end

-- Create a mock Knit controller
function Mocks.createMockKnitController(
  name: string,
  methods: { [string]: (...any) -> any }?
): {
  Name: string,
  [string]: any,
}
  methods = methods or {}

  local controller = {
    Name = name,
  }

  for methodName, methodFn in methods do
    controller[methodName] = methodFn
  end

  return controller
end

return Mocks
