-- sleep: delay for a specified amount of time.

local common = require("common")

local NAME = "sleep"

local MULT = { s = 1.0, m = 60.0, h = 3600.0, d = 86400.0 }

local function parse_duration(s)
  if not s or s == "" then return nil end
  local suffix = s:sub(-1)
  local body, mult
  if MULT[suffix] then
    body = s:sub(1, -2)
    mult = MULT[suffix]
  else
    body = s
    mult = 1.0
  end
  local n = tonumber(body)
  if n == nil then return nil end
  return n * mult
end

--- Cross-platform sleep. Lua's stdlib has no sleep; we rely on:
---   * lfs.sleep if available (rare)
---   * `sleep N` via os.execute on POSIX
---   * `timeout /t N /nobreak` on Windows
local function sleep_seconds(seconds)
  if seconds <= 0 then return end
  if common.is_windows() then
    -- timeout takes integer seconds; round up to honour minimum delay.
    local n = math.ceil(seconds)
    os.execute(string.format("timeout /t %d /nobreak >nul 2>&1", n))
  else
    os.execute(string.format("sleep %s", tostring(seconds)))
  end
end

local function main(argv)
  if #argv == 0 then
    common.err(NAME, "missing operand")
    return 2
  end

  local total = 0
  for i = 1, #argv do
    local d = parse_duration(argv[i])
    if d == nil or d < 0 then
      common.err(NAME, "invalid time interval: '" .. argv[i] .. "'")
      return 2
    end
    total = total + d
  end

  sleep_seconds(total)
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "delay for a specified amount of time",
  main = main,
}
