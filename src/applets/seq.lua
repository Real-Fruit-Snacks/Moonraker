-- seq: print a sequence of numbers.

local common = require("common")

local NAME = "seq"

local function is_int_literal(s)
  if not s or s == "" then return false end
  local body = (s:sub(1, 1) == "+" or s:sub(1, 1) == "-") and s:sub(2) or s
  return body:match("^%d+$") ~= nil
end

local function take_value(flag, args, idx)
  local a = args[idx]
  if #a > #flag then
    return a:sub(#flag + 1), idx + 1
  end
  if idx + 1 > #args then return nil, idx end
  return args[idx + 1], idx + 2
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local separator = "\n"
  local fmt = nil
  local equal_width = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    end
    if a == "-s" or (a:sub(1, 2) == "-s" and not is_int_literal(a)) then
      local v, ni = take_value("-s", args, i)
      if not v then
        common.err(NAME, "-s: missing argument")
        return 2
      end
      separator = v
      i = ni
    elseif a == "-f" or (a:sub(1, 2) == "-f" and not is_int_literal(a)) then
      local v, ni = take_value("-f", args, i)
      if not v then
        common.err(NAME, "-f: missing argument")
        return 2
      end
      fmt = v
      i = ni
    elseif a == "-w" or a == "--equal-width" then
      equal_width = true
      i = i + 1
    else
      break
    end
  end

  local nums = {}
  for j = i, #args do nums[#nums + 1] = args[j] end

  local start_s, incr_s, end_s
  if #nums == 1 then
    start_s, incr_s, end_s = "1", "1", nums[1]
  elseif #nums == 2 then
    start_s, incr_s, end_s = nums[1], "1", nums[2]
  elseif #nums == 3 then
    start_s, incr_s, end_s = nums[1], nums[2], nums[3]
  else
    common.err(NAME, "usage: seq [-s SEP] [-f FMT] [-w] [FIRST [INCR]] LAST")
    return 2
  end

  local start = tonumber(start_s)
  local incr = tonumber(incr_s)
  local last = tonumber(end_s)
  if not start or not incr or not last then
    common.err(NAME, "invalid numeric argument")
    return 2
  end
  if incr == 0 then
    common.err(NAME, "increment must be non-zero")
    return 2
  end

  local all_int = is_int_literal(start_s) and is_int_literal(incr_s) and is_int_literal(end_s)
  local values = {}
  local current = start
  if incr > 0 then
    while current <= last + 1e-12 do
      values[#values + 1] = current
      current = current + incr
    end
  else
    while current >= last - 1e-12 do
      values[#values + 1] = current
      current = current + incr
    end
  end

  local function format_one(v)
    if fmt then
      local ok, s = pcall(string.format, fmt, v)
      if ok then return s end
      return fmt
    end
    if all_int then return tostring(math.floor(v + 0.5)) end
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%g", v)
  end

  local formatted = {}
  for _, v in ipairs(values) do
    formatted[#formatted + 1] = format_one(v)
  end

  if equal_width and #formatted > 0 and not fmt then
    local max_len = 0
    for _, s in ipairs(formatted) do
      local body = s:sub(1, 1) == "-" and s:sub(2) or s
      if #body > max_len then max_len = #body end
    end
    for k, s in ipairs(formatted) do
      if s:sub(1, 1) == "-" then
        formatted[k] = "-" .. string.rep("0", max_len - (#s - 1)) .. s:sub(2)
      else
        formatted[k] = string.rep("0", max_len - #s) .. s
      end
    end
  end

  if #formatted > 0 then
    io.stdout:write(table.concat(formatted, separator), "\n")
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print a sequence of numbers",
  main = main,
}
