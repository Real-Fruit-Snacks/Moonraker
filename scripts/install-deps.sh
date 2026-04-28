#!/usr/bin/env bash
# Install Lua development dependencies for Moonraker (POSIX).
#
# Assumes Lua 5.4 and luarocks are already installed via your system
# package manager. Installs project-level rocks to the user tree.
set -euo pipefail

echo "Installing Lua development tools..."
luarocks install --local busted
luarocks install --local luacheck
luarocks install --local luastatic
luarocks install --local luafilesystem

echo
echo "Installing stylua..."
if ! command -v stylua >/dev/null 2>&1; then
  echo "  stylua is not on PATH. Install it via:"
  echo "    cargo install stylua"
  echo "    # or download a release from https://github.com/JohnnyMorganz/StyLua/releases"
  exit 1
fi

echo
echo "Done. Run \`make help\` to see the available targets."
