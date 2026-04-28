-- yes: repeatedly output a line with the given STRING (or 'y').

local NAME = "yes"

-- Module table — exposed on the returned applet so tests can bound the loop.
local M = { max_iter = nil }

function M.main(argv)
  local parts = {}
  for i = 1, #argv do
    parts[i] = argv[i]
  end
  local text = #parts > 0 and table.concat(parts, " ") or "y"
  local line = text .. "\n"

  -- Chunk writes for throughput. Lua's io.stdout:write doesn't surface
  -- broken-pipe errors as exceptions on POSIX (the process is killed by
  -- SIGPIPE before a return value comes back), so the loop runs until the
  -- shell tears it down.
  local chunk = string.rep(line, 64)

  -- Tests set M.max_iter to bound the loop. Production callers leave it nil.
  -- An env var fallback exists for binary-level smoke tests.
  local limit = M.max_iter or tonumber(os.getenv("MOONRAKER_YES_LIMIT") or "")
  local iter = 0
  while true do
    local ok = pcall(function()
      io.stdout:write(chunk)
      io.stdout:flush()
    end)
    if not ok then break end
    iter = iter + 1
    if limit and iter >= limit then break end
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "repeatedly output a line with the given STRING (or 'y')",
  main = M.main,
  _module = M,
}
