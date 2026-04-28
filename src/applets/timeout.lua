-- timeout: run a command with a time limit.
--
-- Lua's stdlib has no signal/kill. We delegate to the system `timeout`
-- binary (universally available on POSIX, less so on Windows). This is
-- a pragmatic compromise — the value is in the wrapper, not in
-- reimplementing process control from scratch.

local common = require("common")

local NAME = "timeout"

local function parse_duration(s)
  if not s or s == "" then return nil end
  local mult = 1
  local last = s:sub(-1):lower()
  if last == "s" then s = s:sub(1, -2)
  elseif last == "m" then mult = 60; s = s:sub(1, -2)
  elseif last == "h" then mult = 3600; s = s:sub(1, -2)
  elseif last == "d" then mult = 86400; s = s:sub(1, -2)
  end
  local n = tonumber(s)
  if not n then return nil end
  return n * mult
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local sig = "TERM"
  local kill_after = nil
  local preserve_status = false
  local foreground = false
  local verbose = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if (a == "-s" or a == "--signal") and i + 1 <= #args then
      sig = args[i + 1]
      i = i + 2
    elseif a:sub(1, 9) == "--signal=" then
      sig = a:sub(10); i = i + 1
    elseif (a == "-k" or a == "--kill-after") and i + 1 <= #args then
      local d = parse_duration(args[i + 1])
      if not d then
        common.err(NAME, "invalid kill-after: " .. args[i + 1])
        return 125
      end
      kill_after = d
      i = i + 2
    elseif a == "--preserve-status" then preserve_status = true; i = i + 1
    elseif a == "--foreground" then foreground = true; i = i + 1
    elseif a == "-v" or a == "--verbose" then verbose = true; i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1
        and not a:sub(2):match("^[%d%.]+$") then
      common.err(NAME, "unknown option: " .. a)
      return 125
    else
      break
    end
  end

  local rest = {}
  for j = i, #args do rest[#rest + 1] = args[j] end
  if #rest < 2 then
    common.err(NAME, "usage: timeout DURATION COMMAND [ARG]...")
    return 125
  end

  local duration = parse_duration(rest[1])
  if not duration then
    common.err(NAME, "invalid duration: " .. rest[1])
    return 125
  end

  if common.is_windows() then
    common.err(NAME, "timeout is not supported on Windows in this build")
    return 125
  end

  -- Build POSIX `timeout` invocation.
  local parts = { "timeout" }
  parts[#parts + 1] = "--signal=" .. sig
  if kill_after then
    parts[#parts + 1] = "--kill-after=" .. tostring(kill_after)
  end
  if preserve_status then parts[#parts + 1] = "--preserve-status" end
  if foreground then parts[#parts + 1] = "--foreground" end
  if verbose then parts[#parts + 1] = "--verbose" end
  parts[#parts + 1] = tostring(duration)
  for j = 2, #rest do parts[#parts + 1] = shell_quote(rest[j]) end

  local _, _, code = os.execute(table.concat(parts, " "))
  return tonumber(code) or 0
end

return {
  name = NAME,
  aliases = {},
  help = "run a command with a time limit",
  main = main,
}
