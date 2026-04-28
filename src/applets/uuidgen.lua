-- uuidgen: generate a UUID.
--
-- Phase 9 implementation: random (v4) UUIDs only. -t (time) and -m/-s
-- (md5/sha1 namespace) variants would require either a crypto-grade RNG
-- or careful HMAC construction; deferred. The v4 generator uses
-- math.random + a per-process seed mixed from os.time and os.clock.

local common = require("common")

local NAME = "uuidgen"

local seeded = false
local function rand_byte()
  if not seeded then
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))
    seeded = true
  end
  return math.random(0, 255)
end

local function v4()
  local bytes = {}
  for i = 1, 16 do
    bytes[i] = rand_byte()
  end
  -- Set version (4) and variant (10xx)
  bytes[7] = (bytes[7] - (bytes[7] - (bytes[7] % 16))) + 64
  bytes[7] = (bytes[7] % 16) + 64
  bytes[9] = (bytes[9] % 64) + 128
  return string.format(
    "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    bytes[1],
    bytes[2],
    bytes[3],
    bytes[4],
    bytes[5],
    bytes[6],
    bytes[7],
    bytes[8],
    bytes[9],
    bytes[10],
    bytes[11],
    bytes[12],
    bytes[13],
    bytes[14],
    bytes[15],
    bytes[16]
  )
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local upper = false
  local no_dashes = false
  local count = 1

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-r" or a == "--random" then
      i = i + 1 -- only mode supported
    elseif a == "-t" or a == "--time" or a == "-m" or a == "--md5" or a == "-s" or a == "--sha1" then
      common.err(NAME, "only random (v4) UUIDs are supported in this build")
      return 2
    elseif a == "--upper" then
      upper = true
      i = i + 1
    elseif a == "--hex" then
      no_dashes = true
      i = i + 1
    elseif (a == "-c" or a == "--count") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n or n < 1 then
        common.err(NAME, "invalid count: " .. args[i + 1])
        return 2
      end
      count = n
      i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  for _ = 1, count do
    local u = v4()
    if no_dashes then u = u:gsub("-", "") end
    if upper then u = u:upper() end
    io.stdout:write(u, "\n")
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "generate a UUID",
  main = main,
}
