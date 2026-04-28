-- base64: encode/decode base64 data.

local common = require("common")

local NAME = "base64"

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, #ALPHABET do
  DECODE[ALPHABET:byte(i)] = i - 1
end

local function encode(data)
  local out = {}
  local n = #data
  for i = 1, n, 3 do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1)
    local b3 = data:byte(i + 2)
    local n1 = math.floor(b1 / 4)
    local n2 = (b1 % 4) * 16 + math.floor((b2 or 0) / 16)
    local n3 = ((b2 or 0) % 16) * 4 + math.floor((b3 or 0) / 64)
    local n4 = (b3 or 0) % 64
    out[#out + 1] = ALPHABET:sub(n1 + 1, n1 + 1)
    out[#out + 1] = ALPHABET:sub(n2 + 1, n2 + 1)
    if b2 then
      out[#out + 1] = ALPHABET:sub(n3 + 1, n3 + 1)
    else
      out[#out + 1] = "="
    end
    if b3 then
      out[#out + 1] = ALPHABET:sub(n4 + 1, n4 + 1)
    else
      out[#out + 1] = "="
    end
  end
  return table.concat(out)
end

local function decode(data)
  -- Strip "=" padding for processing; we infer length from the source.
  data = data:gsub("=", "")
  local out = {}
  local n = #data
  for i = 1, n, 4 do
    local c1 = DECODE[data:byte(i)]
    local c2 = DECODE[data:byte(i + 1)]
    local c3 = DECODE[data:byte(i + 2) or 0]
    local c4 = DECODE[data:byte(i + 3) or 0]
    if not c1 or not c2 then return nil, "invalid input" end
    out[#out + 1] = string.char(c1 * 4 + math.floor(c2 / 16))
    if i + 2 <= n then
      if not c3 then return nil, "invalid input" end
      out[#out + 1] = string.char((c2 % 16) * 16 + math.floor(c3 / 4))
      if i + 3 <= n then
        if not c4 then return nil, "invalid input" end
        out[#out + 1] = string.char((c3 % 4) * 64 + c4)
      end
    end
  end
  return table.concat(out)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local do_decode = false
  local wrap = 76
  local ignore_garbage = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-d" or a == "--decode" then
      do_decode = true
      i = i + 1
    elseif (a == "-w" or a == "--wrap") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if n == nil or n < 0 then
        common.err(NAME, "invalid wrap: " .. args[i + 1])
        return 2
      end
      wrap = n
      i = i + 2
    elseif a:sub(1, 7) == "--wrap=" then
      local n = common.parse_int(a:sub(8))
      if n == nil or n < 0 then
        common.err(NAME, "invalid wrap: " .. a:sub(8))
        return 2
      end
      wrap = n
      i = i + 1
    elseif a == "-i" or a == "--ignore-garbage" then
      ignore_garbage = true
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
  if #files > 1 then
    common.err(NAME, "extra operand")
    return 2
  end

  local fh, ferr = common.open_input(files[1], "rb")
  if not fh then
    common.err_path(NAME, files[1], ferr)
    return 1
  end
  local data = common.read_all(fh)
  if files[1] ~= "-" then fh:close() end

  if do_decode then
    if ignore_garbage then
      data = data:gsub("[^A-Za-z0-9+/=]", "")
    else
      data = data:gsub("[ \t\n\r]", "")
    end
    local out, err = decode(data)
    if not out then
      common.err(NAME, "invalid input: " .. err)
      return 1
    end
    io.stdout:write(out)
  else
    local encoded = encode(data)
    if wrap == 0 then
      io.stdout:write(encoded)
    else
      for j = 1, #encoded, wrap do
        io.stdout:write(encoded:sub(j, j + wrap - 1), "\n")
      end
      if encoded == "" then io.stdout:write("\n") end
    end
  end
  io.stdout:flush()
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "encode/decode base64 data",
  main = main,
}
