-- hexdump: ASCII, decimal, hexadecimal, octal dump.

local common = require("common")

local NAME = "hexdump"

local function printable_char(b)
  if b >= 0x20 and b < 0x7F then return string.char(b) end
  return "."
end

local function chunk_at(data, i, n)
  return data:sub(i, i + n - 1)
end

local function canonical(data, base)
  local out = {}
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local first8, second8 = {}, {}
    for c = 1, math.min(8, #chunk) do
      first8[#first8 + 1] = string.format("%02x", chunk:byte(c))
    end
    for c = 9, math.min(16, #chunk) do
      second8[#second8 + 1] = string.format("%02x", chunk:byte(c))
    end
    local hex_field = table.concat(first8, " ") .. "  " .. table.concat(second8, " ")
    -- pad to 48 cols for alignment
    if #hex_field < 48 then
      hex_field = hex_field .. string.rep(" ", 48 - #hex_field)
    end
    local ascii = {}
    for c = 1, #chunk do
      ascii[#ascii + 1] = printable_char(chunk:byte(c))
    end
    out[#out + 1] = string.format("%08x  %s  |%s|", base + k - 1, hex_field, table.concat(ascii))
  end
  out[#out + 1] = string.format("%08x", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function two_byte_hex(data, base)
  local out = {}
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local words = {}
    for j = 1, #chunk, 2 do
      if j + 1 <= #chunk then
        local lo, hi = chunk:byte(j), chunk:byte(j + 1)
        words[#words + 1] = string.format("%04x", lo + hi * 256)
      else
        words[#words + 1] = string.format("%02x", chunk:byte(j))
      end
    end
    out[#out + 1] = string.format("%07x %s", base + k - 1, table.concat(words, " "))
  end
  out[#out + 1] = string.format("%07x", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function decimal_words(data, base)
  local out = {}
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local words = {}
    for j = 1, #chunk, 2 do
      if j + 1 <= #chunk then
        local lo, hi = chunk:byte(j), chunk:byte(j + 1)
        words[#words + 1] = string.format("%5d", lo + hi * 256)
      else
        words[#words + 1] = string.format("  %3d", chunk:byte(j))
      end
    end
    out[#out + 1] = string.format("%07x %s", base + k - 1, table.concat(words, " "))
  end
  out[#out + 1] = string.format("%07x", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function octal_byte(data, base)
  local out = {}
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local bytes = {}
    for c = 1, #chunk do
      bytes[#bytes + 1] = string.format("%03o", chunk:byte(c))
    end
    out[#out + 1] = string.format("%07o %s", base + k - 1, table.concat(bytes, " "))
  end
  out[#out + 1] = string.format("%07o", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function octal_word(data, base)
  local out = {}
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local words = {}
    for j = 1, #chunk, 2 do
      if j + 1 <= #chunk then
        local lo, hi = chunk:byte(j), chunk:byte(j + 1)
        words[#words + 1] = string.format("%06o", lo + hi * 256)
      else
        words[#words + 1] = string.format("%03o", chunk:byte(j))
      end
    end
    out[#out + 1] = string.format("%07o %s", base + k - 1, table.concat(words, " "))
  end
  out[#out + 1] = string.format("%07o", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function char_format(data, base)
  local out = {}
  local special = { [0] = "\\0", [7] = "\\a", [8] = "\\b", [9] = "\\t",
    [10] = "\\n", [11] = "\\v", [12] = "\\f", [13] = "\\r" }
  for k = 1, #data, 16 do
    local chunk = chunk_at(data, k, 16)
    local cells = {}
    for c = 1, #chunk do
      local b = chunk:byte(c)
      if b >= 0x20 and b < 0x7F then
        cells[#cells + 1] = "  " .. string.char(b)
      elseif special[b] then
        cells[#cells + 1] = string.format("%3s", special[b])
      else
        cells[#cells + 1] = string.format("%03o", b)
      end
    end
    out[#out + 1] = string.format("%07x %s", base + k - 1, table.concat(cells, " "))
  end
  out[#out + 1] = string.format("%07x", base + #data)
  return table.concat(out, "\n") .. "\n"
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local fmt = "default"
  local skip = 0
  local length = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-C" or a == "--canonical" then fmt = "canonical"; i = i + 1
    elseif a == "-b" then fmt = "octal_byte"; i = i + 1
    elseif a == "-c" then fmt = "char"; i = i + 1
    elseif a == "-d" then fmt = "decimal"; i = i + 1
    elseif a == "-x" then fmt = "default"; i = i + 1
    elseif a == "-o" then fmt = "octal_word"; i = i + 1
    elseif a == "-v" then i = i + 1
    elseif (a == "-s" or a == "--skip") and i + 1 <= #args then
      local n = tonumber(args[i + 1])
      if not n then
        common.err(NAME, "invalid skip: " .. args[i + 1])
        return 2
      end
      skip = n
      i = i + 2
    elseif (a == "-n" or a == "--length") and i + 1 <= #args then
      local n = tonumber(args[i + 1])
      if not n then
        common.err(NAME, "invalid length: " .. args[i + 1])
        return 2
      end
      length = n
      i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local files = {}
  for j = i, #args do files[#files + 1] = args[j] end
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

  if fmt == "canonical" then
    io.stdout:write(canonical(data, skip))
  elseif fmt == "decimal" then
    io.stdout:write(decimal_words(data, skip))
  elseif fmt == "octal_byte" then
    io.stdout:write(octal_byte(data, skip))
  elseif fmt == "octal_word" then
    io.stdout:write(octal_word(data, skip))
  elseif fmt == "char" then
    io.stdout:write(char_format(data, skip))
  else
    io.stdout:write(two_byte_hex(data, skip))
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "ASCII, decimal, hexadecimal, octal dump",
  main = main,
}
