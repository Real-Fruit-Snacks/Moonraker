-- dd: convert and copy a file. POSIX-style key=value operands.

local common = require("common")

local NAME = "dd"

local SIZE_MULT_2 = {
  K = 1024,
  M = 1024 * 1024,
  G = 1024 * 1024 * 1024,
  T = 1024 * 1024 * 1024 * 1024,
  P = 1024 * 1024 * 1024 * 1024 * 1024,
}
local SIZE_MULT_10 = { k = 1000, m = 1000000, g = 1000000000 }

local function parse_size(s)
  if not s or s == "" then return nil end
  local last = s:sub(-1)
  local mult = 1
  local body = s
  if SIZE_MULT_2[last] then
    mult = SIZE_MULT_2[last]
    body = s:sub(1, -2)
  elseif SIZE_MULT_10[last] then
    mult = SIZE_MULT_10[last]
    body = s:sub(1, -2)
  elseif last == "B" then
    body = s:sub(1, -2)
  elseif last == "w" or last == "W" then
    mult = 2
    body = s:sub(1, -2)
  elseif last == "b" then
    mult = 512
    body = s:sub(1, -2)
  end
  local n = common.parse_int(body)
  if not n then return nil end
  return n * mult
end

local function convert(buf, conv)
  if conv.lcase then buf = buf:lower() end
  if conv.ucase then buf = buf:upper() end
  if conv.swab and #buf >= 2 then
    local out = {}
    local i = 1
    while i + 1 <= #buf do
      out[#out + 1] = buf:sub(i + 1, i + 1)
      out[#out + 1] = buf:sub(i, i)
      i = i + 2
    end
    if i <= #buf then out[#out + 1] = buf:sub(i, i) end
    buf = table.concat(out)
  end
  return buf
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local in_path, out_path
  local bs = 512
  local ibs, obs
  local count, skip, seek = nil, 0, 0
  local conv = {}
  local status_mode = "default"

  for _, a in ipairs(args) do
    local k, v = a:match("^([^=]+)=(.+)$")
    if not k then
      common.err(NAME, "bad operand: " .. a)
      return 2
    end
    if k == "if" then
      in_path = v
    elseif k == "of" then
      out_path = v
    elseif k == "bs" then
      local n = parse_size(v)
      if not n or n <= 0 then
        common.err(NAME, "invalid bs: " .. v)
        return 2
      end
      bs = n
    elseif k == "ibs" then
      local n = parse_size(v)
      if not n or n <= 0 then
        common.err(NAME, "invalid ibs: " .. v)
        return 2
      end
      ibs = n
    elseif k == "obs" then
      local n = parse_size(v)
      if not n or n <= 0 then
        common.err(NAME, "invalid obs: " .. v)
        return 2
      end
      obs = n
    elseif k == "count" then
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "invalid count: " .. v)
        return 2
      end
      count = n
    elseif k == "skip" then
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "invalid skip: " .. v)
        return 2
      end
      skip = n
    elseif k == "seek" then
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "invalid seek: " .. v)
        return 2
      end
      seek = n
    elseif k == "conv" then
      for piece in v:gmatch("[^,]+") do
        if
          piece == "notrunc"
          or piece == "noerror"
          or piece == "sync"
          or piece == "fdatasync"
          or piece == "fsync"
          or piece == "lcase"
          or piece == "ucase"
          or piece == "swab"
          or piece == "excl"
          or piece == "nocreat"
        then
          conv[piece] = true
        else
          common.err(NAME, "unknown conv: " .. piece)
          return 2
        end
      end
    elseif k == "status" then
      if v ~= "none" and v ~= "noxfer" and v ~= "progress" and v ~= "default" then
        common.err(NAME, "unknown status: " .. v)
        return 2
      end
      status_mode = v
    else
      common.err(NAME, "unknown operand: " .. k)
      return 2
    end
  end

  local in_bs = ibs or bs
  local out_bs = obs or bs

  local in_fh = in_path and io.open(in_path, "rb") or io.stdin
  if in_path and not in_fh then
    common.err_path(NAME, in_path, "could not open for reading")
    return 1
  end
  local out_fh
  if out_path then
    local mode = conv.notrunc and "r+b" or "wb"
    out_fh = io.open(out_path, mode)
    if not out_fh and not conv.notrunc then out_fh = io.open(out_path, "wb") end
    if not out_fh then
      common.err_path(NAME, out_path, "could not open for writing")
      if in_path then in_fh:close() end
      return 1
    end
  else
    out_fh = io.stdout
  end

  -- Skip / seek
  if skip > 0 then
    local remaining = skip * in_bs
    while remaining > 0 do
      local chunk = in_fh:read(math.min(remaining, 65536))
      if not chunk or chunk == "" then break end
      remaining = remaining - #chunk
    end
  end
  if seek > 0 and out_path then out_fh:seek("set", seek * out_bs) end

  local records_in_full, records_in_part = 0, 0
  local records_out_full, records_out_part = 0, 0
  local bytes_total = 0
  local start = os.clock()

  while true do
    if count and (records_in_full + records_in_part) >= count then break end
    local buf = in_fh:read(in_bs)
    if not buf or buf == "" then break end
    if #buf == in_bs then
      records_in_full = records_in_full + 1
    else
      records_in_part = records_in_part + 1
      if conv.sync then buf = buf .. string.rep("\0", in_bs - #buf) end
    end
    buf = convert(buf, conv)
    out_fh:write(buf)
    if #buf == out_bs then
      records_out_full = records_out_full + 1
    elseif #buf > 0 and (#buf % out_bs == 0) then
      records_out_full = records_out_full + math.floor(#buf / out_bs)
    else
      records_out_full = records_out_full + math.floor(#buf / out_bs)
      records_out_part = records_out_part + 1
    end
    bytes_total = bytes_total + #buf
  end

  if out_path then out_fh:close() end
  if in_path then in_fh:close() end

  if status_mode ~= "none" then
    io.stderr:write(string.format("%d+%d records in\n", records_in_full, records_in_part))
    io.stderr:write(string.format("%d+%d records out\n", records_out_full, records_out_part))
    if status_mode ~= "noxfer" then
      local elapsed = os.clock() - start
      local rate = elapsed > 0 and (bytes_total / elapsed) or 0
      io.stderr:write(string.format("%d bytes copied, %.4g s, %.3g B/s\n", bytes_total, elapsed, rate))
    end
  end

  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "convert and copy a file",
  main = main,
}
