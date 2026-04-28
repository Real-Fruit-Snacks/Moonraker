-- printf: format and print data.
--
-- Mirrors POSIX printf. Backslash escapes in the format string are
-- expanded; %-specifiers consume args. The format is repeated when
-- there are leftover args (POSIX behavior).

local common = require("common")

local NAME = "printf"

local ESCAPES = {
  n = "\n", t = "\t", r = "\r", ["\\"] = "\\",
  a = "\a", b = "\b", f = "\f", v = "\v",
  ["0"] = "\0", ["'"] = "'", ['"'] = '"',
}

local function process_escapes(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i + 1 <= #s then
      local nxt = s:sub(i + 1, i + 1)
      if ESCAPES[nxt] then
        out[#out + 1] = ESCAPES[nxt]
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function coerce_int(arg)
  if not arg or arg == "" then return 0 end
  local n = tonumber(arg)
  if n then return math.floor(n) end
  -- Try base auto-detection (0x, 0o)
  if arg:sub(1, 2) == "0x" or arg:sub(1, 2) == "0X" then
    return tonumber(arg:sub(3), 16) or 0
  end
  return 0
end

local function coerce_float(arg)
  if not arg or arg == "" then return 0 end
  return tonumber(arg) or 0
end

--- Apply the format once. Returns (output, had_specs, args_consumed).
local function apply_once(fmt, values, start_idx)
  local out = {}
  local pos = 1
  local consumed = 0
  local had_spec = false

  while pos <= #fmt do
    local pct = fmt:find("%%", pos)
    if not pct then
      out[#out + 1] = fmt:sub(pos)
      break
    end
    out[#out + 1] = fmt:sub(pos, pct - 1)

    -- Parse the spec: %[flags][width][.precision]<letter>
    local i = pct + 1
    local flags, width, precision = "", "", ""
    while i <= #fmt and fmt:sub(i, i):match("[%-+ #0]") do
      flags = flags .. fmt:sub(i, i)
      i = i + 1
    end
    while i <= #fmt and fmt:sub(i, i):match("%d") do
      width = width .. fmt:sub(i, i)
      i = i + 1
    end
    if i <= #fmt and fmt:sub(i, i) == "." then
      i = i + 1
      while i <= #fmt and fmt:sub(i, i):match("%d") do
        precision = precision .. fmt:sub(i, i)
        i = i + 1
      end
    end
    if i > #fmt then
      out[#out + 1] = fmt:sub(pct)
      break
    end
    local spec = fmt:sub(i, i)
    pos = i + 1

    if spec == "%" then
      out[#out + 1] = "%"
    else
      had_spec = true
      local arg = values[start_idx + consumed]
      if arg == nil then arg = "" end
      consumed = consumed + 1

      local letter = spec == "u" and "d" or spec
      local fmtspec = "%" .. flags .. width
        .. (precision ~= "" and "." .. precision or "") .. letter

      local ok, formatted = pcall(function()
        if spec == "d" or spec == "i" or spec == "u"
           or spec == "o" or spec == "x" or spec == "X" then
          return string.format(fmtspec, coerce_int(arg))
        elseif spec == "e" or spec == "E" or spec == "f"
               or spec == "g" or spec == "G" then
          return string.format(fmtspec, coerce_float(arg))
        elseif spec == "c" then
          return string.format(fmtspec, arg:sub(1, 1))
        elseif spec == "s" then
          return string.format(fmtspec, arg)
        elseif spec == "b" then
          return process_escapes(arg)
        end
        return arg
      end)
      out[#out + 1] = ok and formatted or arg
    end
  end

  return table.concat(out), had_spec, consumed
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  if #args == 0 then
    common.err(NAME, "missing format")
    return 2
  end
  local fmt = process_escapes(args[1])
  local values = {}
  for j = 2, #args do values[#values + 1] = args[j] end

  local idx = 1
  local text, had_spec, consumed = apply_once(fmt, values, idx)
  io.stdout:write(text)
  idx = idx + consumed

  while had_spec and idx <= #values do
    text, had_spec, consumed = apply_once(fmt, values, idx)
    io.stdout:write(text)
    if consumed == 0 then break end
    idx = idx + consumed
  end

  io.stdout:flush()
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "format and print data",
  main = main,
}
