-- split: split a file into pieces.

local common = require("common")

local NAME = "split"

local SIZE_MULT = { K = 1024, M = 1024 * 1024, G = 1024 * 1024 * 1024 }

local function parse_size(s)
  if not s or s == "" then return nil end
  local last = s:sub(-1)
  local mult = 1
  local body = s
  if SIZE_MULT[last:upper()] then
    mult = SIZE_MULT[last:upper()]
    body = s:sub(1, -2)
  elseif last == "b" or last == "B" then
    mult = 512
    body = s:sub(1, -2)
  end
  local n = common.parse_int(body)
  if not n then return nil end
  return n * mult
end

--- Generate the n-th alphabetic suffix: aa, ab, ..., az, ba, ...
local function suffix(n, length)
  local out = {}
  for _ = 1, length do
    out[#out + 1] = string.char(string.byte("a") + (n % 26))
    n = math.floor(n / 26)
  end
  -- reverse
  local rev = {}
  for k = #out, 1, -1 do
    rev[#rev + 1] = out[k]
  end
  return table.concat(rev)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local lines = nil
  local bytes_per = nil
  local suffix_length = 2
  local additional_suffix = ""
  local numeric = false
  local prefix = "x"
  local in_file = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if (a == "-l" or a == "--lines") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid number of lines: " .. args[i + 1])
        return 2
      end
      lines = n
      i = i + 2
    elseif a:sub(1, 2) == "-l" and #a > 2 and a:sub(3):match("^%d+$") then
      lines = tonumber(a:sub(3))
      i = i + 1
    elseif (a == "-b" or a == "--bytes") and i + 1 <= #args then
      local v = parse_size(args[i + 1])
      if not v then
        common.err(NAME, "invalid byte count: " .. args[i + 1])
        return 2
      end
      bytes_per = v
      i = i + 2
    elseif (a == "-a" or a == "--suffix-length") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid suffix length: " .. args[i + 1])
        return 2
      end
      suffix_length = n
      i = i + 2
    elseif a == "-d" or a == "--numeric-suffixes" then
      numeric = true
      i = i + 1
    elseif a == "--additional-suffix" and i + 1 <= #args then
      additional_suffix = args[i + 1]
      i = i + 2
    elseif a:sub(1, 21) == "--additional-suffix=" then
      additional_suffix = a:sub(22)
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      lines = tonumber(a:sub(2))
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local rest = {}
  for j = i, #args do
    rest[#rest + 1] = args[j]
  end
  if rest[1] then
    in_file = rest[1]
  end
  if rest[2] then
    prefix = rest[2]
  end

  if lines == nil and bytes_per == nil then
    lines = 1000
  end

  local fh, errmsg
  if in_file == nil or in_file == "-" then
    fh = io.stdin
  else
    fh, errmsg = io.open(in_file, "rb")
    if not fh then
      common.err_path(NAME, in_file, errmsg)
      return 1
    end
  end
  local data = common.read_all(fh)
  if fh ~= io.stdin then fh:close() end

  local chunks = {}
  if bytes_per then
    for j = 1, #data, bytes_per do
      chunks[#chunks + 1] = data:sub(j, j + bytes_per - 1)
    end
  else
    local cur = {}
    local line_count = 0
    for k = 1, #data do
      local b = data:sub(k, k)
      cur[#cur + 1] = b
      if b == "\n" then
        line_count = line_count + 1
        if line_count >= lines then
          chunks[#chunks + 1] = table.concat(cur)
          cur = {}
          line_count = 0
        end
      end
    end
    if #cur > 0 then
      chunks[#chunks + 1] = table.concat(cur)
    end
  end

  local rc = 0
  for idx, chunk in ipairs(chunks) do
    local suf
    if numeric then
      suf = string.format("%0" .. suffix_length .. "d", idx - 1)
    else
      suf = suffix(idx - 1, suffix_length)
    end
    local outname = prefix .. suf .. additional_suffix
    local oh, oerr = io.open(outname, "wb")
    if not oh then
      common.err_path(NAME, outname, oerr)
      rc = 1
    else
      oh:write(chunk)
      oh:close()
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "split a file into pieces",
  main = main,
}
