# Install Lua development dependencies for Moonraker (Windows).
#
# Assumes Lua 5.4 and luarocks are installed and on PATH. Installs
# project-level rocks to the user tree.
$ErrorActionPreference = "Stop"

Write-Host "Installing Lua development tools..."
luarocks install --local busted
luarocks install --local luacheck
luarocks install --local luastatic
luarocks install --local luafilesystem

Write-Host ""
Write-Host "Checking for stylua..."
if (-not (Get-Command stylua -ErrorAction SilentlyContinue)) {
  Write-Host "  stylua is not on PATH. Install it via:"
  Write-Host "    cargo install stylua"
  Write-Host "    # or download a release from https://github.com/JohnnyMorganz/StyLua/releases"
  exit 1
}

Write-Host ""
Write-Host "Done. Run \`make help\` (Git Bash / WSL) or invoke build.lua / busted directly."
