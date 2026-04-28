-- od: dump files in octal and other formats.

local common = require("common")

local NAME = "od"

local ESCAPES = {
  [0] = "\\0",
  [7] = "\\a",
  [8] = "\\b",
  [9] = "\\t",
  [10] = "\\n",
  [11] = "\\v",
  [12] = "\\f",
  [13] = "\\r",
}

local function fmt_oct(b)
  return string.format("%03o", b)
end
local function fmt_hex(b)
  return string.format("%02x", b)
end
local function fmt_dec(b)
  return string.format("%3d", b)
end
local function fmt_chr(b)
  if ESCAPES[b] then return string.format("%3s", ESCAPES[b]) end
  if b >= 0x20 and b < 0x7F then return "  " .. string.char(b) end
  return string.format("%03o", b)
end

local FORMATTERS = {
  o = fmt_oct,
  x = fmt_hex,
  d = fmt_dec,
  c = fmt_chr,
}

local function format_addr(radix, n)
  if radix == "n" then return "" end
  if radix == "d" then return string.format("%07d", n) end
  if radix == "x" then return string.format("%07x", n) end
  return string.format("%07o", n)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local fmt_letter = "o"
  local width = 16
  local address_radix = "o"
  local skip = 0
  local length = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-c" then
      fmt_letter = "c"
      i = i + 1
    elseif a == "-d" then
      fmt_letter = "d"
      i = i + 1
    elseif a == "-o" then
      fmt_letter = "o"
      i = i + 1
    elseif a == "-x" then
      fmt_letter = "x"
      i = i + 1
    elseif a == "-b" then
      fmt_letter = "o"
      i = i + 1
    elseif (a == "-A" or a == "--address-radix") and i + 1 <= #args then
      local r = args[i + 1]
      if r ~= "d" and r ~= "o" and r ~= "x" and r ~= "n" then
        common.err(NAME, "invalid address radix: " .. r)
        return 2
      end
      address_radix = r
      i = i + 2
    elseif a:sub(1, 2) == "-A" and #a == 3 and a:sub(3, 3):match("[doxn]") then
      address_radix = a:sub(3, 3)
      i = i + 1
    elseif a:sub(1, 16) == "--address-radix=" then
      local r = a:sub(17)
      if r ~= "d" and r ~= "o" and r ~= "x" and r ~= "n" then
        common.err(NAME, "invalid address radix: " .. r)
        return 2
      end
      address_radix = r
      i = i + 1
    elseif (a == "-w" or a == "--width") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid width: " .. args[i + 1])
        return 2
      end
      width = n
      i = i + 2
    elseif (a == "-N" or a == "--read-bytes") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid length: " .. args[i + 1])
        return 2
      end
      length = n
      i = i + 2
    elseif (a == "-j" or a == "--skip-bytes") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid skip: " .. args[i + 1])
        return 2
      end
      skip = n
      i = i + 2
    elseif a == "-v" then
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local files = {}
  for j = i, #args do
    files[#files + 1] = args[j]
  end
  if #files == 0 then files = { "-" } end

  local rc = 0
  local all = {}
  for _, f in ipairs(files) do
    local fh, ferr = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, ferr)
      rc = 1
    else
      all[#all + 1] = common.read_all(fh)
      if f ~= "-" then fh:close() end
    end
  end
  local data = table.concat(all)
  if skip > 0 then data = data:sub(skip + 1) end
  if length then data = data:sub(1, length) end

  local formatter = FORMATTERS[fmt_letter]
  local lines = {}
  for k = 1, #data, width do
    local chunk = data:sub(k, k + width - 1)
    local addr = format_addr(address_radix, skip + k - 1)
    local cells = {}
    for c = 1, #chunk do
      cells[#cells + 1] = formatter(chunk:byte(c))
    end
    local row = addr .. " " .. table.concat(cells, " ")
    lines[#lines + 1] = (row:gsub("%s+$", ""))
  end
  if address_radix ~= "n" then lines[#lines + 1] = format_addr(address_radix, skip + #data) end
  io.stdout:write(table.concat(lines, "\n"), "\n")
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "dump files in octal and other formats",
  main = main,
}
