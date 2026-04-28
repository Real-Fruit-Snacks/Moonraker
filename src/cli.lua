-- Multi-call dispatcher. Mirrors mainsail/cli.py.
--
-- Two entry modes:
--   1. Multi-call:  argv[0] basename matches an applet (e.g. via symlink).
--   2. Wrapper:     `moonraker <applet> [args...]` from any program name.
--
-- The dispatcher intercepts `--help` (long form only — `-h` is overloaded
-- by several applets such as `df -h` for human-readable output).

local registry = require("registry")
local version = require("version")
local usage = require("usage")
local common = require("common")

local M = {}

--- Lowercase the basename of argv0 with `.exe` and `.lua` suffixes stripped.
--- Used to detect multi-call mode.
local function program_stem(argv0)
  local stem = common.basename(argv0 or "moonraker")
  stem = stem:lower()
  stem = (stem:gsub("%.exe$", ""))
  stem = (stem:gsub("%.lua$", ""))
  return stem
end

local function print_top_help(out)
  out:write(string.format("moonraker %s - cross-platform multi-call utility binary\n",
    version.version))
  out:write("\n")
  out:write("Usage:\n")
  out:write("  moonraker <applet> [args...]\n")
  out:write("  moonraker <applet> --help       show help for <applet>\n")
  out:write("  <applet> [args...]              (when installed as hardlink/symlink)\n")
  out:write("\n")
  out:write("Top-level options:\n")
  out:write("  --list           list available applets\n")
  out:write("  --help, -h       show this help\n")
  out:write("  --version        show version\n")
end

local function print_applet_help(applet, out)
  out:write(applet.name, " - ", applet.help, "\n")
  local body = usage[applet.name]
  if body and body ~= "" then
    out:write("\n", body)
    if body:sub(-1) ~= "\n" then
      out:write("\n")
    end
  end
  if #applet.aliases > 0 then
    out:write("\nAliases: ", table.concat(applet.aliases, ", "), "\n")
  end
end

local function print_list(out)
  local names = {}
  local width = 0
  for _, a in registry.iter_sorted() do
    names[#names + 1] = a
    if #a.name > width then
      width = #a.name
    end
  end
  for _, a in ipairs(names) do
    local pad = string.rep(" ", width - #a.name)
    local suffix = ""
    if #a.aliases > 0 then
      suffix = string.format("  (aliases: %s)", table.concat(a.aliases, ", "))
    end
    out:write("  ", a.name, pad, "  ", a.help, suffix, "\n")
  end
end

--- Build the argv table forwarded to an applet's main(). The applet sees
--- argv[0] = its canonical name; argv[1..n] = the user-supplied args.
local function forward_argv(name, source, source_start)
  local out = { [0] = name }
  local out_idx = 1
  for i = source_start, #source do
    out[out_idx] = source[i]
    out_idx = out_idx + 1
  end
  return out
end

--- Run Moonraker.
---
--- argv is a Lua-style table where argv[0] is the program name and
--- argv[1..n] are positional arguments (matching how the global `arg`
--- table is laid out).
function M.main(argv)
  argv = argv or {}
  local out, errout = io.stdout, io.stderr

  -- Multi-call: argv[0] basename matches a known applet (and isn't moonraker)
  local stem = program_stem(argv[0])
  local applet = registry.get(stem)
  if applet ~= nil and stem ~= "moonraker" then
    if argv[1] == "--help" then
      print_applet_help(applet, out)
      return 0
    end
    return applet.main(forward_argv(stem, argv, 1))
  end

  -- Wrapper mode
  local first = argv[1]
  if first == nil then
    print_top_help(out)
    return 0
  end
  if first == "--help" or first == "-h" then
    if argv[2] then
      local sub = registry.get(argv[2])
      if sub ~= nil then
        print_applet_help(sub, out)
        return 0
      end
    end
    print_top_help(out)
    return 0
  end
  if first == "--version" then
    out:write("moonraker ", version.version, "\n")
    return 0
  end
  if first == "--list" then
    print_list(out)
    return 0
  end

  applet = registry.get(first)
  if applet == nil then
    errout:write("moonraker: unknown applet '", first, "'\n")
    errout:write("try 'moonraker --list' to see all applets\n")
    return 1
  end
  if argv[2] == "--help" then
    print_applet_help(applet, out)
    return 0
  end
  return applet.main(forward_argv(first, argv, 2))
end

return M
