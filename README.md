# Roblox Game (Git + Rojo) — Starter Repo

A production-grade, **ready-to-clone** Roblox project template using:

- **Rojo** for filesystem ↔ Studio sync
- **Git**-friendly source layout (`src/`)
- **Selene** for linting
- **StyLua** for formatting
- **GitHub Actions** CI (lint + format check + build)
- **Aftman** toolchain pinning (one-command setup)
- **Knit** game framework for organized services and controllers

## Quick start

### 1) Install tools (recommended)

This repo pins CLI tool versions via **Aftman**.

- Install Aftman: https://github.com/LPGhatguy/aftman
- Then in this repo:

```bash
aftman install
```

### 2) Install Wally packages

This project uses **Wally** for package management, including the **Knit** framework.

```bash
wally install
```

This will install:
- `sleitnick/knit@1.7.0` - Lightweight game framework for organizing services and controllers

> **Note:** A stub implementation of Knit is included in `Packages/Knit.lua` for development without Wally. Running `wally install` will replace it with the official package.

### 3) Start Rojo (dev sync)

```bash
rojo serve default.project.json
```

In Roblox Studio:
1. Install the **Rojo** plugin
2. Click **Connect**
3. Your game will sync from `src/`

### 4) Lint / format / build

```bash
./scripts/lint.sh
./scripts/format.sh
./scripts/format-check.sh
./scripts/build.sh
```

## Repo layout

```text
src/
  client/             # StarterPlayerScripts
    Controllers/      # Knit client controllers
    Main.client.lua   # Legacy client entry (being migrated)
    KnitClient.client.lua  # Knit client bootstrap
  server/             # ServerScriptService
    Services/         # Knit server services
    Main.server.lua   # Legacy server entry (being migrated)
    KnitServer.server.lua  # Knit server bootstrap
  shared/             # ReplicatedStorage/Shared
Packages/             # Wally packages (install via wally install)
```

## Knit Framework

This project uses [Knit](https://sleitnick.github.io/Knit/) for code organization:

### Server Services (`src/server/Services/`)
- **PlayerService** - Player data management, XP, leveling
- **StoreService** - Buy/sell operations, store inventory
- **ChickenService** - Chicken placement, hatching, egg collection
- **GameStateService** - Per-player game state, predator spawning
- **CombatService** - Combat, shields, traps

### Client Controllers (`src/client/Controllers/`)
- **MainController** - Player data sync, UI coordination
- **ChickenController** - Chicken/egg visuals and interactions

### Benefits of Knit
- Automatic remote event/function management
- Clean service/controller architecture
- Type-safe client-server communication
- Scalable code organization

## Notes

- Roblox binary `.rbxl/.rbxlx` files are intentionally **ignored**. Your source of truth is the filesystem.
- If you want to publish to Roblox, you typically:
  1) `rojo build` to `.rbxlx` and
  2) upload via Studio / release pipeline

## License

MIT — see [LICENSE](LICENSE).
