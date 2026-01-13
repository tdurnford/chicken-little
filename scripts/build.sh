#!/usr/bin/env bash
set -euo pipefail

mkdir -p build
echo "Building place file to build/MyGame.rbxlx ..."
rojo build default.project.json -o build/MyGame.rbxlx
echo "OK"
