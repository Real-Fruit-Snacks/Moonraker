-- tr: translate, delete, or squeeze characters.

local common = require("common")

local NAME = "tr"

local ESCAPE = {
  n = "\n", t = "\t", r = "\r", ["\\"] = "\\",
  ["0"] = "\0", a = "\a", b = "\b", f = "\f", v = "\v",
}

local function ascii_letters()
  local s = {}
  for c = 65, 90 do s[#s + 1] = string.char(c) end
  for c = 97, 122 do s[#s + 1] = string.char(c) end
  return table.concat(s)
end

local function ascii_uppercase()
  local s = {}
  for c = 65, 90 do s[#s + 1] = string.char(c) end
  return table.concat(s)
end

local function ascii_lowercase()
  local s = {}
  for c = 97, 122 do s[#s + 1] = string.char(c) end
  return table.concat(s)
end

local function ascii_digits()
  return "0123456789"
end

local CLASSES = {
  alpha  = ascii_letters(),
  upper  = ascii_uppercase(),
  lower  = ascii_lowercase(),
  digit  = ascii_digits(),
  alnum  = ascii_letters() .. ascii_digits(),
  space  = " \t\n\v\f\r",
  blank  = " \t",
  punct  = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~",
  xdigit = "0123456789abcdefABCDEF",
}

--- Expand a tr SET specification to a literal byte string. Handles
--- backslash escapes, [:class:], and ranges (a-z).
local function expand_set(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i + 1 <= #s then
      local mapped = ESCAPE[s:sub(i + 1, i + 1)]
      if mapped then
        out[#out + 1] = mapped
        i = i + 2
      else
        out[#out + 1] = s:sub(i + 1, i + 1)
        i = i + 2
      end
    elseif c == "[" and i + 3 <= #s and s:sub(i + 1, i + 1) == ":" then
      local rb = s:find(":]", i + 2, true)
      if rb then
        local cls = s:sub(i + 2, rb - 1)
        if CLASSES[cls] then
          out[#out + 1] = CLASSES[cls]
          i = rb + 2
        else
          out[#out + 1] = c
          i = i + 1
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    elseif i + 2 <= #s and s:sub(i + 1, i + 1) == "-" and s:sub(i + 2, i + 2) ~= "]" then
      local a, b = s:byte(i), s:byte(i + 2)
      if a <= b then
        local chars = {}
        for k = a, b do chars[#chars + 1] = string.char(k) end
        out[#out + 1] = table.concat(chars)
        i = i + 3
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

--- Build a 256-entry boolean table where t[byte] is true if byte is in `s`.
local function byteset(s)
  local set = {}
  for i = 1, #s do
    set[s:byte(i)] = true
  end
  return set
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local delete, squeeze, complement, truncate = false, false, false, false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^[dscCt]+$") then
      for ch in a:sub(2):gmatch(".") do
        if ch == "d" then delete = true
        elseif ch == "s" then squeeze = true
        elseif ch == "c" or ch == "C" then complement = true
        elseif ch == "t" then truncate = true
        end
      end
      i = i + 1
    else
      break
    end
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  if #positional == 0 then
    common.err(NAME, "missing operand")
    return 2
  end
  if not delete and not squeeze and #positional < 2 then
    common.err(NAME, "when not deleting or squeezing, two arguments are required")
    return 2
  end

  local set1 = expand_set(positional[1])
  local set2 = positional[2] and expand_set(positional[2]) or ""

  local data = common.read_all(io.stdin)

  local out = {}
  if delete then
    local set = byteset(set1)
    for k = 1, #data do
      local b = data:byte(k)
      local in_set = set[b] == true
      local drop = (not complement and in_set) or (complement and not in_set)
      if not drop then
        out[#out + 1] = string.char(b)
      end
    end
    data = table.concat(out)
  elseif #positional >= 2 then
    local src = set1
    local dst = set2
    if truncate then
      src = src:sub(1, #dst)
    elseif #dst < #src then
      dst = dst .. string.rep(dst:sub(-1), #src - #dst)
    end
    out = {}
    if complement then
      local replacement = dst:sub(-1)
      local keep = byteset(src)
      for k = 1, #data do
        local b = data:byte(k)
        if keep[b] then
          out[#out + 1] = string.char(b)
        else
          out[#out + 1] = replacement
        end
      end
    else
      local tbl = {}
      for k = 1, #src do
        tbl[src:byte(k)] = dst:sub(k, k)
      end
      for k = 1, #data do
        local b = data:byte(k)
        out[#out + 1] = tbl[b] or string.char(b)
      end
    end
    data = table.concat(out)
  end

  if squeeze then
    local sq_bytes = (delete and #set2 > 0) and set2 or set1
    local sq_set = byteset(sq_bytes)
    if complement and not delete then
      local inv = {}
      for b = 0, 255 do
        if not sq_set[b] then inv[b] = true end
      end
      sq_set = inv
    end
    out = {}
    local prev = -1
    for k = 1, #data do
      local b = data:byte(k)
      if not (b == prev and sq_set[b]) then
        out[#out + 1] = string.char(b)
        prev = b
      end
    end
    data = table.concat(out)
  end

  io.stdout:write(data)
  io.stdout:flush()
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "translate, delete, or squeeze characters",
  main = main,
}
