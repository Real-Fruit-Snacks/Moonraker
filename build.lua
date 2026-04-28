#!/usr/bin/env lua
-- Moonraker build orchestrator.
--
-- Wraps `luastatic` to produce a single static binary. luastatic must be
-- on PATH along with a working C toolchain (gcc, clang, or MSVC). Lua
-- development headers and `liblua.a` (or platform equivalent) must be
-- discoverable; on most systems luastatic finds them automatically.
--
-- Usage:
--   lua build.lua                         build full binary at dist/moonraker
--   lua build.lua --output dist/m         choose output path
--   lua build.lua --preset minimal        build with Phase 1 essentials
--   lua build.lua --applets echo,pwd      hand-pick applets
--   lua build.lua --regen-only            regenerate src/applets/init.lua
--                                         without invoking luastatic

local function path_sep_init()
  return package.config:sub(1, 1)
end
local IS_WINDOWS = path_sep_init() == "\\"
local DEVNULL = IS_WINDOWS and "nul" or "/dev/null"

--- Resolve an executable's full path via `where` (Windows) or `command -v`
--- (POSIX). Lua's spawned cmd subshells on Windows do not always resolve
--- bare command names via PATH the same way an interactive cmd does, so
--- the rest of the build invokes binaries by absolute path.
local function resolve_exe(name)
  local cmd
  if IS_WINDOWS then
    cmd = string.format("where %s 2>%s", name, DEVNULL)
  else
    cmd = string.format("command -v %s 2>%s", name, DEVNULL)
  end
  local p = io.popen(cmd)
  if not p then return nil end
  local line = p:read("*l")
  p:close()
  if line and line ~= "" then return line end
  return nil
end

-- Bootstrap luarocks paths into package.path / package.cpath if required
-- modules (e.g. luafilesystem) are not yet visible. Mirrors what luarocks
-- does inside its own bin shims (e.g. busted.bat). Without this,
-- `lua build.lua` from a plain shell can't see rocks-installed modules.
local function ensure_luarocks_paths()
  if pcall(require, "lfs") then return end
  local lr = resolve_exe("luarocks")
  if not lr then return end
  local p = io.popen(string.format('"%s" path 2>&1', lr))
  if not p then return end
  local out = p:read("*a")
  p:close()
  for line in out:gmatch("[^\r\n]+") do
    -- Windows: SET "VAR=value"
    -- POSIX:   export VAR='value'   or   export VAR="value"
    local key, val = line:match('^[Ss][Ee][Tt]%s+"([%w_]+)=([^"]*)"')
    if not key then
      key, val = line:match("^export%s+([%w_]+)='([^']*)'")
    end
    if not key then
      key, val = line:match('^export%s+([%w_]+)="([^"]*)"')
    end
    if key == "LUA_PATH" then
      package.path = val .. ";" .. package.path
    elseif key == "LUA_CPATH" then
      package.cpath = val .. ";" .. package.cpath
    end
  end
end
ensure_luarocks_paths()

local function die(msg)
  io.stderr:write("build: ", msg, "\n")
  os.exit(2)
end

local function info(msg)
  io.stderr:write("build: ", msg, "\n")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function path_sep()
  return package.config:sub(1, 1)
end

local function is_windows()
  return path_sep() == "\\"
end

local function listdir(path)
  local cmd
  if is_windows() then
    cmd = string.format('dir /b "%s" 2>nul', path:gsub("/", "\\"))
  else
    cmd = string.format('ls -1 "%s" 2>/dev/null', path)
  end
  local p = io.popen(cmd)
  if not p then return {} end
  local out = {}
  for line in p:lines() do
    if line ~= "" then out[#out + 1] = line end
  end
  p:close()
  return out
end

local function discover_applets()
  local names = {}
  for _, fname in ipairs(listdir("src/applets")) do
    local n = fname:match("^(.+)%.lua$")
    if n and n ~= "init" then names[#names + 1] = n end
  end
  table.sort(names)
  return names
end

-- Presets. `slim` and `full` are filled in dynamically once the applet set
-- has been discovered.
local PRESETS = {
  minimal = { "echo", "false", "pwd", "true" },
}

local function parse_args(argv)
  local opts = {
    output = nil,
    preset = nil,
    applets = nil,
    regen_only = false,
  }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--output" then
      i = i + 1
      opts.output = argv[i]
    elseif a == "--preset" then
      i = i + 1
      opts.preset = argv[i]
    elseif a == "--applets" then
      i = i + 1
      opts.applets = argv[i]
    elseif a == "--regen-only" then
      opts.regen_only = true
    elseif a == "--help" or a == "-h" then
      io.stdout:write([[usage: lua build.lua [options]

Options:
  --output PATH       output binary path (default: dist/moonraker[.exe])
  --preset NAME       'minimal', 'slim', or 'full' (default: full)
  --applets a,b,c     hand-pick applets (overrides --preset)
  --regen-only        regenerate src/applets/init.lua and exit
  --help, -h          show this help
]])
      os.exit(0)
    else
      die("unknown argument: " .. a)
    end
    i = i + 1
  end

  if opts.output == nil then opts.output = is_windows() and "dist/moonraker.exe" or "dist/moonraker" end
  return opts
end

local function select_applets(opts, all)
  if opts.applets then
    local out = {}
    for name in opts.applets:gmatch("[^,]+") do
      local trimmed = name:match("^%s*(.-)%s*$")
      if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return out
  end
  if opts.preset == "minimal" then return PRESETS.minimal end
  if opts.preset == nil or opts.preset == "full" or opts.preset == "slim" then
    -- slim is identical to full until Phase 5 onward; refined later.
    return all
  end
  die("unknown preset: " .. tostring(opts.preset))
end

local function generate_manifest(applets)
  local lines = {
    "-- Generated by build.lua. Edits will be overwritten.",
    "-- Run `lua build.lua --regen-only` to refresh after adding an applet.",
    "",
    'local registry = require("registry")',
    "",
    "local M = {}",
    "",
    "function M.load_all()",
  }
  for _, name in ipairs(applets) do
    lines[#lines + 1] = string.format('  registry.register(require("applets.%s"))', name)
  end
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return M"
  lines[#lines + 1] = ""

  local body = table.concat(lines, "\n")
  local f = assert(io.open("src/applets/init.lua", "wb"))
  f:write(body)
  f:close()
  info("regenerated src/applets/init.lua (" .. #applets .. " applets)")
end

local function ensure_dir(path)
  if path == nil or path == "" or path == "." then return end
  local cmd
  if is_windows() then
    cmd = string.format('if not exist "%s" mkdir "%s" >nul 2>nul', path:gsub("/", "\\"), path:gsub("/", "\\"))
  else
    cmd = string.format('mkdir -p "%s"', path)
  end
  os.execute(cmd)
end

local function shell(cmd)
  io.stderr:write("$ ", cmd, "\n")
  local ok, _, code = os.execute(cmd)
  if ok ~= true and ok ~= 0 then
    die("command failed: " .. cmd .. (code and (" (exit " .. tostring(code) .. ")") or ""))
  end
end

--- Run a command and capture its first stdout line. Returns nil on failure.
local function shellout_line(cmd)
  local p = io.popen(cmd)
  if not p then return nil end
  local line = p:read("*l")
  p:close()
  if line and line ~= "" then return line end
  return nil
end

--- Detect a Lua build variable from luarocks. We use this to find liblua.a
--- and lua.h so our vendored luastatic gets the right inputs regardless of
--- where Lua is installed.
local function luarocks_var(key)
  local lr = resolve_exe("luarocks")
  if not lr then return nil end
  local out = shellout_line(string.format('"%s" config variables.%s 2>%s', lr, key, DEVNULL))
  return out
end

--- List subdirectories of `parent` that exist on disk. Returns names only
--- (not full paths). Caller is responsible for joining.
local function list_subdirs(parent)
  local lfs_ok, lfs_mod = pcall(require, "lfs")
  if not lfs_ok then return {} end
  if not lfs_mod.attributes(parent) then return {} end
  local out = {}
  for entry in lfs_mod.dir(parent) do
    if entry ~= "." and entry ~= ".." then
      local attr = lfs_mod.attributes(parent .. "/" .. entry)
      if attr and attr.mode == "directory" then out[#out + 1] = entry end
    end
  end
  table.sort(out)
  return out
end

local function build(opts, applets)
  generate_manifest(applets)
  if opts.regen_only then return end

  -- luastatic derives module names from input paths (slashes → dots, .lua
  -- stripped). To get `require("applets.echo")` to resolve, the paths must
  -- be relative to src/. We chdir into src/ via lfs (rather than chaining
  -- shell commands) so the build is independent of cmd.exe quirks.
  -- Top-level project Lua modules. main.lua must be first; everything
  -- else in src/*.lua is auto-discovered so adding a new shared module
  -- (e.g. hashing.lua) doesn't require touching the build.
  local sources = { "main.lua" }
  local seen = { ["main.lua"] = true }
  local top_modules = {}
  for _, fname in ipairs(listdir("src")) do
    if fname:sub(-4) == ".lua" and not seen[fname] then
      top_modules[#top_modules + 1] = fname
      seen[fname] = true
    end
  end
  table.sort(top_modules)
  for _, fname in ipairs(top_modules) do
    sources[#sources + 1] = fname
  end
  sources[#sources + 1] = "applets/init.lua"
  for _, name in ipairs(applets) do
    sources[#sources + 1] = "applets/" .. name .. ".lua"
  end

  -- Vendored pure-Lua deps in src/vendor/ get bundled too. luastatic will
  -- expose them as `require("vendor.<name>")`.
  for _, fname in ipairs(listdir("src/vendor")) do
    if fname:sub(-4) == ".lua" then sources[#sources + 1] = "vendor/" .. fname end
  end

  for _, src in ipairs(sources) do
    if not exists("src/" .. src) then die("missing source: src/" .. src) end
  end

  ensure_dir(opts.output:match("^(.*)[\\/]") or ".")

  -- Locate the C toolchain. luastatic defaults CC to "cc" — on Windows the
  -- mingw binary is "gcc", so we promote that automatically when CC is unset
  -- and gcc is on PATH.
  if (os.getenv("CC") or "") == "" then
    if resolve_exe("gcc") then
      -- os.execute child processes inherit our env, but we need to pass
      -- CC=gcc in the env we've already resolved.
      local original_cc = os.getenv("CC")
      _G._BUILD_CC = "gcc"
      -- Tell luastatic via env. On Windows there's no setenv from Lua's
      -- stdlib, so we forward CC through the command prefix instead (see
      -- below).
      _G._ORIGINAL_CC = original_cc
    end
  end

  -- Resolve Lua headers and static lib via luarocks config variables, then
  -- fall back to common scoop / luarocks layouts if those aren't set.
  local lua_incdir = luarocks_var("LUA_INCDIR")
  local lua_libdir = luarocks_var("LUA_LIBDIR")
  if not lua_incdir or not lua_libdir then
    die(
      "could not detect Lua include/lib dirs via `luarocks config`. "
        .. "Set LUA_INCDIR / LUA_LIBDIR in your environment."
    )
  end

  -- Locate liblua's static archive. The exact filename varies:
  --   * mingw / scoop / generic builds:    liblua.a
  --   * Debian/Ubuntu liblua5.X-dev:        liblua5.1.a, liblua5.4.a
  --   * some distros:                       liblua51.a, liblua54.a
  local function find_liblua(libdir)
    local sep = is_windows() and "\\" or "/"
    local v = (_VERSION or "Lua 5.4"):match("(%d+%.%d+)") or "5.4"
    local v_no_dot = v:gsub("%.", "")
    local candidates = {
      libdir .. sep .. "liblua.a",
      libdir .. sep .. "liblua" .. v .. ".a",
      libdir .. sep .. "liblua" .. v_no_dot .. ".a",
    }
    for _, c in ipairs(candidates) do
      if exists(c) then return c end
    end
    return nil, candidates
  end

  local liblua_a, candidates = find_liblua(lua_libdir)
  if not liblua_a then
    die("could not find liblua static archive in " .. lua_libdir .. ". Tried: " .. table.concat(candidates, ", "))
  end

  local ok, lfs = pcall(require, "lfs")
  if not ok then die("luafilesystem not installed. Install with: luarocks install luafilesystem") end

  -- Compile any C dependencies in src/cdeps/<lib>/ to object files. Each
  -- .o file gets passed to luastatic afterwards; luastatic detects
  -- luaopen_* symbols and registers each module.
  --
  -- Each cdep dir may include a `cflags` text file: extra compiler flags
  -- (one per line) added when compiling .c files in that dir. Useful for
  -- per-library defines like -DLZLIB_COMPAT.
  local cdep_objects = {}
  local cc = _G._BUILD_CC or os.getenv("CC") or "gcc"
  for _, lib in ipairs(list_subdirs("src/cdeps")) do
    local lib_dir = "src/cdeps/" .. lib
    local extra_cflags = ""
    if exists(lib_dir .. "/cflags") then
      local cf = io.open(lib_dir .. "/cflags", "rb")
      if cf then
        for line in cf:lines() do
          local trimmed = line:match("^%s*(.-)%s*$")
          if trimmed and trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
            extra_cflags = extra_cflags .. " " .. trimmed
          end
        end
        cf:close()
      end
    end
    for _, fname in ipairs(listdir(lib_dir)) do
      if fname:sub(-2) == ".c" then
        local src_path = lib_dir .. "/" .. fname
        local obj_path = lib_dir .. "/" .. fname:sub(1, -3) .. ".o"
        local compile = string.format(
          '"%s" -c -O2 -I"%s" -I"%s"%s "%s" -o "%s"',
          cc,
          lua_incdir,
          lib_dir,
          extra_cflags,
          src_path,
          obj_path
        )
        shell(compile)
        -- After chdir into src/ below, paths must be relative to src/.
        cdep_objects[#cdep_objects + 1] = "cdeps/" .. lib .. "/" .. fname:sub(1, -3) .. ".o"
      end
    end
  end

  local original_dir = lfs.currentdir()
  local luastatic_rel = is_windows() and "\\scripts\\luastatic.lua" or "/scripts/luastatic.lua"
  local luastatic_script = original_dir .. luastatic_rel
  if not exists(luastatic_script) then die("vendored luastatic script not found at " .. luastatic_script) end
  local lua_exe = resolve_exe("lua")
  if not lua_exe then die("lua executable not found on PATH") end

  local chdir_ok, chdir_err = lfs.chdir("src")
  if not chdir_ok then die("cannot chdir to src: " .. tostring(chdir_err)) end

  local cflags = os.getenv("CFLAGS") or ""
  local ldflags = os.getenv("LDFLAGS") or ""

  -- Pre-set CC=gcc inline so the cmd subshell sees it. On Windows this
  -- becomes `set "CC=gcc" && lua ...`; on POSIX, `CC=gcc lua ...`.
  local cc_prefix = ""
  if _G._BUILD_CC == "gcc" then
    if is_windows() then
      cc_prefix = 'set "CC=gcc" && '
    else
      cc_prefix = "CC=gcc "
    end
  end

  local objs = ""
  if #cdep_objects > 0 then objs = " " .. table.concat(cdep_objects, " ") end

  local cmd = string.format(
    '%s"%s" "%s" %s%s "%s" -I"%s"',
    cc_prefix,
    lua_exe,
    luastatic_script,
    table.concat(sources, " "),
    objs,
    liblua_a,
    lua_incdir
  )
  if cflags ~= "" then cmd = cmd .. " " .. cflags end
  if ldflags ~= "" then cmd = cmd .. " " .. ldflags end
  shell(cmd)

  -- Restore CWD before any post-build actions so relative paths in opts
  -- (e.g. opts.output) resolve from the project root.
  lfs.chdir(original_dir)

  local emitted = is_windows() and "src/main.exe" or "src/main"
  if not exists(emitted) then die("luastatic did not produce expected output: " .. emitted) end

  local dst = opts.output
  if is_windows() and not dst:match("%.exe$") then dst = dst .. ".exe" end

  local mv
  if is_windows() then
    mv = string.format('move /Y "%s" "%s" >nul', emitted:gsub("/", "\\"), dst:gsub("/", "\\"))
  else
    mv = string.format('mv -f "%s" "%s"', emitted, dst)
  end
  shell(mv)

  -- luastatic also leaves an intermediate .luastatic.c file next to main.lua.
  local intermediate = "src/main.luastatic.c"
  if exists(intermediate) then
    if is_windows() then
      shell('del /Q "' .. intermediate:gsub("/", "\\") .. '" >nul')
    else
      shell('rm -f "' .. intermediate .. '"')
    end
  end

  info("built " .. dst .. " (" .. #applets .. " applets)")
end

local opts = parse_args(arg or {})
local all = discover_applets()
local applets = select_applets(opts, all)
build(opts, applets)
