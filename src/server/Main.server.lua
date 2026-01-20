--[[
	Main.server.lua
	Server-side entry point.
	
	Initializes:
	- ProfileManager for data persistence
	- KnitServer for service-based architecture
	
	All game logic is handled by Knit services in the Services/ directory:
	- MapService: Map state, section assignment, player spawning
	- PlayerDataService: Player data access and persistence
	- GameStateService: Day/night cycle, time management
	- GameLoopService: Main game loop coordination
	- ChickenService: Chicken placement, pickup, selling
	- EggService: Egg hatching, world eggs, egg purchases
	- PredatorService: Predator spawning, AI, combat
	- CombatService: Weapons, damage, shields
	- StoreService: Store inventory, buy/sell operations
	- TrapService: Trap placement and catching
	- TradeService: Player trading
	- LevelService: XP and leveling
]]

local ServerScriptService = game:GetService("ServerScriptService")

-- Initialize ProfileManager first (handles player data loading/saving)
local ProfileManager = require(ServerScriptService:WaitForChild("ProfileManager"))
ProfileManager.start()
print("[Main.server] ProfileManager initialized")

-- Start Knit server (loads and starts all services)
local KnitServer = require(ServerScriptService:WaitForChild("KnitServer"))
KnitServer.start()
print("[Main.server] Server started successfully")
