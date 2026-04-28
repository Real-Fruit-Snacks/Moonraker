-- date: print or format the date and time.
--
-- Lua's os.date covers most of the strftime-style formatting we need.
-- Date parsing for `-d` accepts ISO 8601 variants only.

local common = require("common")

local NAME = "date"

local function parse_date(s)
  s = s:match("^%s*(.-)%s*$")
  -- Strip trailing Z (we treat as UTC marker)
  local utc = false
  if s:sub(-1) == "Z" then
    s = s:sub(1, -2)
    utc = true
  end
  local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ]?(%d?%d?):?(%d?%d?):?(%d?%d?)$")
  if not y then
    y, mo, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    h, mi, se = "0", "0", "0"
  end
  local t = {
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h ~= "" and h or 0),
    min = tonumber(mi ~= "" and mi or 0),
    sec = tonumber(se ~= "" and se or 0),
  }
  local ok, ts = pcall(os.time, t)
  if not ok then return nil end
  return ts, utc
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local utc = false
  local d_arg, r_arg, fmt, iso_spec = nil, nil, nil, nil
  local rfc_2822 = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then break end
    if a == "-u" or a == "--utc" or a == "--universal" then
      utc = true
      i = i + 1
    elseif a == "-d" or a == "--date" then
      if i + 1 > #args then
        common.err(NAME, a .. ": missing argument")
        return 2
      end
      d_arg = args[i + 1]
      i = i + 2
    elseif a:sub(1, 7) == "--date=" then
      d_arg = a:sub(8)
      i = i + 1
    elseif a == "-r" then
      if i + 1 > #args then
        common.err(NAME, "-r: missing argument")
        return 2
      end
      r_arg = args[i + 1]
      i = i + 2
    elseif a:sub(1, 12) == "--reference=" then
      r_arg = a:sub(13)
      i = i + 1
    elseif a == "-R" or a == "--rfc-2822" or a == "--rfc-email" then
      rfc_2822 = true
      i = i + 1
    elseif a == "-I" then
      iso_spec = "date"
      i = i + 1
    elseif a:sub(1, 2) == "-I" then
      local spec = a:sub(3)
      local valid = { date = true, hours = true, minutes = true, seconds = true, ns = true }
      if not valid[spec] then
        common.err(NAME, "invalid --iso-8601 arg: " .. spec)
        return 2
      end
      iso_spec = spec
      i = i + 1
    elseif a:sub(1, 10) == "--iso-8601" then
      local spec = "date"
      if a:find("=", 1, true) then spec = a:sub(a:find("=", 1, true) + 1) end
      local valid = { date = true, hours = true, minutes = true, seconds = true, ns = true }
      if not valid[spec] then
        common.err(NAME, "invalid --iso-8601 arg: " .. spec)
        return 2
      end
      iso_spec = spec
      i = i + 1
    elseif a:sub(1, 1) == "+" then
      fmt = a:sub(2)
      i = i + 1
    elseif a:sub(1, 1) == "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  local ts
  if r_arg then
    local lfs = common.try_lfs()
    local attr = lfs and lfs.attributes(r_arg)
    if not attr then
      common.err_path(NAME, r_arg, "No such file or directory")
      return 1
    end
    ts = attr.modification or 0
  elseif d_arg then
    local parsed, was_utc = parse_date(d_arg)
    if not parsed then
      common.err(NAME, "invalid date: '" .. d_arg .. "'")
      return 1
    end
    ts = parsed
    utc = utc or was_utc
  else
    ts = os.time()
  end

  local prefix = utc and "!" or ""
  local output
  if fmt then
    output = os.date(prefix .. fmt, ts)
  elseif rfc_2822 then
    output = os.date(prefix .. "%a, %d %b %Y %H:%M:%S %z", ts)
  elseif iso_spec then
    local patterns = {
      date = "%Y-%m-%d",
      hours = "%Y-%m-%dT%H%z",
      minutes = "%Y-%m-%dT%H:%M%z",
      seconds = "%Y-%m-%dT%H:%M:%S%z",
      ns = "%Y-%m-%dT%H:%M:%S.000000000%z",
    }
    output = os.date(prefix .. patterns[iso_spec], ts)
  else
    output = os.date(prefix .. "%a %b %d %H:%M:%S %Y", ts)
  end

  io.stdout:write(output, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print or format the date and time",
  main = main,
}
