-- Applet registry. Mirrors mainsail/registry.py.
--
-- An applet is a table:
--   { name = "<str>", aliases = {<strs>}, help = "<str>", main = function(argv) ... end }
--
-- Aliases share the same applet entry; iter_sorted yields each applet once.

local M = {}

local by_name = {}
local primary = {}

--- Register an applet. Wires up its primary name and any aliases.
function M.register(applet)
  assert(type(applet) == "table", "applet must be a table")
  assert(type(applet.name) == "string" and applet.name ~= "", "applet.name required")
  assert(type(applet.main) == "function", "applet.main required")
  applet.aliases = applet.aliases or {}
  applet.help = applet.help or ""

  by_name[applet.name] = applet
  for _, alias in ipairs(applet.aliases) do
    by_name[alias] = applet
  end
  primary[#primary + 1] = applet
end

--- Look up an applet by primary name or alias. Returns nil if unknown.
function M.get(name)
  return by_name[name]
end

--- Iterator yielding (idx, applet) for each unique applet, sorted by name.
function M.iter_sorted()
  local sorted = {}
  for _, a in ipairs(primary) do
    sorted[#sorted + 1] = a
  end
  table.sort(sorted, function(a, b)
    return a.name < b.name
  end)
  return ipairs(sorted)
end

--- Total number of unique applets.
function M.count()
  return #primary
end

--- Test-only: clear the registry between specs.
function M._reset()
  by_name = {}
  primary = {}
end

return M
