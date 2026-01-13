# Roblox Game (Git + Rojo) — Starter Repo

A production-grade, **ready-to-clone** Roblox project template using:

- **Rojo** for filesystem ↔ Studio sync
- **Git**-friendly source layout (`src/`)
- **Selene** for linting
- **StyLua** for formatting
- **GitHub Actions** CI (lint + format check + build)
- **Aftman** toolchain pinning (one-command setup)

## Quick start

### 1) Install tools (recommended)

This repo pins CLI tool versions via **Aftman**.

- Install Aftman: https://github.com/LPGhatguy/aftman
- Then in this repo:

```bash
aftman install
```

### 2) Start Rojo (dev sync)

```bash
rojo serve default.project.json
```

In Roblox Studio:
1. Install the **Rojo** plugin
2. Click **Connect**
3. Your game will sync from `src/`

### 3) Lint / format / build

```bash
./scripts/lint.sh
./scripts/format.sh
./scripts/format-check.sh
./scripts/build.sh
```

## Repo layout

```text
src/
  client/   # StarterPlayerScripts
  server/   # ServerScriptService
  shared/   # ReplicatedStorage/Shared
  assets/   # (optional) non-code assets (kept minimal by default)
  tests/    # (optional) unit tests
```

## Notes

- Roblox binary `.rbxl/.rbxlx` files are intentionally **ignored**. Your source of truth is the filesystem.
- If you want to publish to Roblox, you typically:
  1) `rojo build` to `.rbxlx` and
  2) upload via Studio / release pipeline

## License

MIT — see [LICENSE](LICENSE).
