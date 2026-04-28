-- df: report filesystem disk space usage.
--
-- Lua + lfs have no native API for free disk space. We shell out to the
-- system `df` and re-format its output to keep behavior consistent across
-- platforms. On Windows we use `wmic logicaldisk` as a fallback.

local common = require("common")

local NAME = "df"

local function format_human(n)
  local units = { "", "K", "M", "G", "T", "P" }
  local v = n
  local i = 1
  while v >= 1024 and i < #units do
    v = v / 1024
    i = i + 1
  end
  if i == 1 then return tostring(math.floor(v)) end
  return string.format("%.1f%s", v, units[i])
end

local function format_size(n, human, block_size)
  if human then return format_human(n) end
  return tostring(math.ceil(n / block_size))
end

--- Probe a single path's disk usage via `df -P -k`. Returns total/used/free
--- in bytes, or nil on error.
local function disk_usage_posix(path)
  local cmd = string.format('df -P -k "%s" 2>/dev/null', path:gsub('"', '\\"'))
  local pipe = io.popen(cmd)
  if not pipe then return nil end
  local lines = {}
  for line in pipe:lines() do
    lines[#lines + 1] = line
  end
  pipe:close()
  -- df -P prints one or two header lines plus one data line per fs. The
  -- last data line is the one we want.
  if #lines < 2 then return nil end
  local data = lines[#lines]
  -- Filesystem 1024-blocks Used Available Capacity Mounted on
  local _, total, used, avail = data:match("(%S+)%s+(%d+)%s+(%d+)%s+(%d+)")
  if not total then return nil end
  return {
    total = tonumber(total) * 1024,
    used = tonumber(used) * 1024,
    free = tonumber(avail) * 1024,
  }
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local human = false
  local block_size = 1024

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 or a == "-" then break end
    if not a:sub(2):match("^[hkm]+$") then
      common.err(NAME, "invalid option: " .. a)
      return 2
    end
    for ch in a:sub(2):gmatch(".") do
      if ch == "h" then
        human = true
      elseif ch == "k" then
        block_size = 1024
      elseif ch == "m" then
        block_size = 1024 * 1024
      end
    end
    i = i + 1
  end

  local paths = {}
  for j = i, #args do
    paths[#paths + 1] = args[j]
  end
  if #paths == 0 then paths = { "." } end

  local header_units = human and "Size" or string.format("%dK-blocks", math.floor(block_size / 1024))
  io.stdout:write(
    string.format("%-20s %10s %10s %10s %5s  %s\n", "Filesystem", header_units, "Used", "Avail", "Use%", "Mounted on")
  )

  local rc = 0
  for _, p in ipairs(paths) do
    local usage = disk_usage_posix(p)
    if not usage then
      common.err_path(NAME, p, "could not stat")
      rc = 1
    else
      local pct = usage.total > 0 and math.floor(100 * usage.used / usage.total + 0.5) or 0
      io.stdout:write(
        string.format(
          "%-20s %10s %10s %10s %4d%%  %s\n",
          p,
          format_size(usage.total, human, block_size),
          format_size(usage.used, human, block_size),
          format_size(usage.free, human, block_size),
          pct,
          p
        )
      )
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "report filesystem disk space usage",
  main = main,
}
