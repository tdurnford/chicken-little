# Contributing

Thanks for helping improve this project!

## Local setup

1. Install Aftman and run:

   ```bash
   aftman install
   ```

2. Start dev sync:

   ```bash
   rojo serve default.project.json
   ```

3. Before opening a PR, run:

   ```bash
   ./scripts/format-check.sh
   ./scripts/lint.sh
   ./scripts/build.sh
   ```

## Style

- Lua formatting is enforced by **StyLua** (`stylua.toml`)
- Lint is enforced by **Selene** (`selene.toml`)
- Prefer small, reviewable PRs.
