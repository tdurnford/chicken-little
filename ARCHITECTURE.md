# Chicken Coop Tycoon — Architecture

This document describes the architecture patterns, conventions, and structure used in this codebase.

## Overview

The project follows a service-oriented architecture using **Knit** for server-client communication, **ProfileService** for data persistence, and **TestEZ** for testing. Communication is event-driven using **GoodSignal** for efficient signal handling.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Knit | 1.6.3 | Service-based architecture |
| ProfileService | 2.1.5 | Data persistence with session locking |
| GoodSignal | 0.2.0 | Efficient signal implementation |
| Promise | 4.0.0 | Async operations (Knit dependency) |
| TestEZ | 0.4.1 | BDD-style testing framework |
| TopbarPlus | 3.4.0 | Topbar UI components |

## Folder Structure

```
src/
├── client/                    # Client-side code (StarterPlayerScripts)
│   ├── Controllers/           # Knit controllers
│   │   ├── PlayerDataController.lua
│   │   ├── ChickenController.lua
│   │   └── ...
│   ├── Main.client.lua        # Client entry point
│   ├── KnitClient.lua         # Knit client bootstrap
│   └── *UI.lua                # UI modules (MainHUD, InventoryUI, etc.)
│
├── server/                    # Server-side code (ServerScriptService)
│   ├── Services/              # Knit services
│   │   ├── PlayerDataService.lua
│   │   ├── ChickenService.lua
│   │   └── ...
│   ├── Main.server.lua        # Server entry point
│   ├── KnitServer.lua         # Knit server bootstrap
│   └── ProfileManager.lua     # Data persistence layer
│
└── shared/                    # Shared code (ReplicatedStorage)
    ├── Testing/               # Test infrastructure
    │   ├── TestRunner.lua
    │   ├── TestUtilities.lua
    │   └── Mocks/
    ├── *Config.lua            # Game configuration modules
    └── *.lua                  # Shared game logic
```

## Knit Services (Server)

Services handle server-side business logic and expose methods/signals to clients.

### Pattern

```lua
local Knit = require(ReplicatedStorage.Packages.Knit)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local MyService = Knit.CreateService({
    Name = "MyService",
    
    -- Client-exposed API (secure boundary)
    Client = {
        DataChanged = Knit.CreateSignal(),  -- Client can listen
    },
    
    -- Server-only signals
    InternalEvent = GoodSignal.new(),
})

-- Called during Knit.Start() - initialize dependencies
function MyService:KnitInit()
    -- Get other services
    self._otherService = Knit.GetService("OtherService")
end

-- Called after all services initialized - start logic
function MyService:KnitStart()
    -- Connect to events, start loops
end

-- Server-only method (not in Client table)
function MyService:DoServerThing(player, data)
    -- Business logic
    self.Client.DataChanged:Fire(player, data)
end

-- Client-callable method (in Client table)
function MyService.Client:GetData(player)
    return self.Server:_getPlayerData(player)
end

return MyService
```

### Key Conventions

1. **Separation**: `Client = {}` table defines the security boundary - only methods/signals inside are accessible to clients
2. **Signals**: Use `Knit.CreateSignal()` for client signals, `GoodSignal.new()` for server-only signals
3. **Lifecycle**: `KnitInit()` for setup, `KnitStart()` for runtime logic
4. **Type Safety**: Export Luau types for API clarity

### Services List

| Service | Responsibility |
|---------|----------------|
| PlayerDataService | Player data management, wraps ProfileManager |
| ChickenService | Chicken spawning, management |
| CombatService | Combat mechanics, damage |
| EggService | Egg spawning and hatching |
| GameLoopService | Core game loop |
| GameStateService | Game state management |
| LevelService | Player leveling |
| MapService | Map generation |
| PredatorService | Predator spawning and AI |
| StoreService | In-game store transactions |
| TradeService | Player trading |
| TrapService | Trap placement and catching |

## Knit Controllers (Client)

Controllers handle client-side logic, UI updates, and communicate with services.

### Pattern

```lua
local Knit = require(ReplicatedStorage.Packages.Knit)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local MyController = Knit.CreateController({
    Name = "MyController",
})

-- Local signals for UI updates
MyController.DataUpdated = GoodSignal.new()

-- Local cache
MyController._cachedData = nil

function MyController:KnitInit()
    -- Get service references
    self._service = Knit.GetService("MyService")
end

function MyController:KnitStart()
    -- Listen to server signals and re-broadcast locally
    self._service.DataChanged:Connect(function(data)
        self._cachedData = data
        self.DataUpdated:Fire(data)
    end)
end

-- Public API for UI modules
function MyController:GetCachedData()
    return self._cachedData
end

return MyController
```

### Key Conventions

1. **Caching**: Controllers cache server data for immediate UI access
2. **Re-broadcasting**: Server signals are re-broadcast as local GoodSignal events
3. **No Direct Access**: UI modules access data through controller methods, never directly from services

### Controllers List

| Controller | Paired Service |
|------------|----------------|
| PlayerDataController | PlayerDataService |
| ChickenController | ChickenService |
| CombatController | CombatService |
| EggController | EggService |
| GameStateController | GameStateService |
| PredatorController | PredatorService |
| StoreController | StoreService |
| TradeController | TradeService |
| TrapController | TrapService |

## Data Persistence (ProfileManager)

`ProfileManager` wraps ProfileService for robust data persistence with session locking.

### Features

- **Session Locking**: Prevents data duplication across servers
- **Data Migration**: Handles legacy data format conversion
- **Offline Earnings**: Calculates earnings since last session
- **Graceful Shutdown**: Releases profiles on server close

### Usage

```lua
local ProfileManager = require(ServerScriptService.ProfileManager)

-- Load player profile (called automatically by PlayerDataService)
local result = ProfileManager.loadProfile(player)
if result.success then
    local data = result.data
    -- Use player data
end

-- Get profile data
local data = ProfileManager.getProfile(player.UserId)

-- Update profile
ProfileManager.updateProfile(player.UserId, function(profile)
    profile.Data.money = profile.Data.money + 100
end)

-- Release on leave (automatic with BindToClose)
ProfileManager.releaseProfile(player.UserId)
```

### Data Schema

The player data template is defined in `src/shared/PlayerData.lua`:

```lua
{
    money = 0,
    level = 1,
    xp = 0,
    inventory = {},
    chickens = {},
    upgrades = {},
    lastLogin = 0,
    -- ... other fields
}
```

## Testing (TestEZ)

Tests are co-located with source files using the `.spec.lua` suffix.

### Pattern

```lua
-- MyModule.spec.lua
return function()
    local MyModule = require(script.Parent.MyModule)
    
    describe("MyModule", function()
        describe("myFunction", function()
            it("should return expected value", function()
                local result = MyModule.myFunction(input)
                expect(result).to.equal(expected)
            end)
            
            it("should handle edge cases", function()
                expect(function()
                    MyModule.myFunction(nil)
                end).to.throw()
            end)
        end)
    end)
end
```

### Conventions

1. **Co-location**: `Module.lua` paired with `Module.spec.lua`
2. **Structure**: `describe()` for grouping, `it()` for individual tests
3. **Assertions**: Use `expect()` with matchers (`.to.equal()`, `.to.throw()`, etc.)
4. **Coverage**: Test validation, type checking, edge cases

### Running Tests

Tests are run via the TestRunner module in Roblox Studio or through the test infrastructure in `src/shared/Testing/`.

## Signal Communication

### Server-Side (GoodSignal)

```lua
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

-- Create signal
local MySignal = GoodSignal.new()

-- Fire signal
MySignal:Fire(arg1, arg2)

-- Connect to signal
local connection = MySignal:Connect(function(arg1, arg2)
    -- Handle event
end)

-- Disconnect
connection:Disconnect()
```

### Client-Side (Knit Signals)

```lua
-- In service (server)
Client = {
    MyEvent = Knit.CreateSignal(),
}

-- Fire to specific client
self.Client.MyEvent:Fire(player, data)

-- In controller (client)
self._service.MyEvent:Connect(function(data)
    -- Handle event
end)
```

## Bootstrap Flow

### Server

1. `Main.server.lua` runs
2. `KnitServer.lua` requires all services from `Services/`
3. `Knit.Start()` called - services initialize (`KnitInit`) then start (`KnitStart`)
4. `ProfileManager` initializes when first player joins

### Client

1. `Main.client.lua` runs
2. `KnitClient.lua` requires all controllers from `Controllers/`
3. `Knit.Start()` called - controllers initialize then start
4. Controllers connect to service signals and cache data
5. UI modules read from controllers

## Best Practices

### General

- Use Luau type annotations for all public APIs
- Prefer GoodSignal over BindableEvents for internal communication
- Keep services/controllers focused - single responsibility
- Avoid circular dependencies by lazy-loading in `KnitInit`

### Data Flow

- Server → Client: Use Knit service signals (`Client.MyEvent`)
- Client → Server: Use Knit service methods (`service:DoThing()`)
- Within Client: Use controller GoodSignal events
- Within Server: Use service GoodSignal events

### Error Handling

- Validate all client inputs in service methods
- Return structured results: `{ success: boolean, data?: any, error?: string }`
- Use Promise for async operations

## Future Improvements

The following items are planned but not yet implemented:

- **Fusion UI**: Reactive UI framework with OnyxUI components (Work Items #21-29)
- State management will connect to controller signals for reactive updates
