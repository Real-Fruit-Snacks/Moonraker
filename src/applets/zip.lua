-- zip: package and compress files into a .zip archive.
--
-- Pure-Lua PKZip 2.0 writer on top of vendored zlib (raw DEFLATE).
-- Supports stored (-0) and deflated (-1..-9) entries, recursive
-- directory walks (-r), and junk-paths (-j). Append (-g) and
-- delete (-d) repack the archive.

local common = require("common")
local zlib = require("zlib")

local NAME = "zip"
local SIG_LFH = 0x04034b50
local SIG_CDR = 0x02014b50
local SIG_EOCD = 0x06054b50
local METHOD_STORE = 0
local METHOD_DEFLATE = 8
local RAW_WBITS = -zlib.MAXIMUM_WINDOWBITS -- raw deflate (no zlib/gzip header)

local function u16le(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32le(n)
  return string.char(
    n % 256,
    math.floor(n / 0x100) % 256,
    math.floor(n / 0x10000) % 256,
    math.floor(n / 0x1000000) % 256
  )
end

local function read_u16le(s, pos)
  local b1, b2 = s:byte(pos, pos + 1)
  return b1 + b2 * 256, pos + 2
end

local function read_u32le(s, pos)
  local b1, b2, b3, b4 = s:byte(pos, pos + 3)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216, pos + 4
end

local function dos_datetime(epoch)
  local t = os.date("*t", epoch)
  if t.year < 1980 then t.year = 1980 end
  local date = ((t.year - 1980) * 512) + (t.month * 32) + t.day
  local time = (t.hour * 2048) + (t.min * 32) + math.floor(t.sec / 2)
  return date, time
end

local function deflate_bytes(data, level)
  local d = zlib.deflate(level, RAW_WBITS)
  local first = d(data)
  local final = d("", "finish")
  return (first or "") .. (final or "")
end

local function inflate_bytes(data)
  -- The lua-zlib inflate stream auto-finalises when it sees the deflate
  -- end-of-block marker; calling the closure again after that errors
  -- with "stream was previously closed". Just feed once and let it
  -- finish on its own.
  local i = zlib.inflate(RAW_WBITS)
  local ok, out = pcall(i, data)
  if not ok then return nil, tostring(out) end
  return out or ""
end

local function write_local_header(fh, info)
  fh:write(u32le(SIG_LFH))
  fh:write(u16le(20)) -- version needed
  fh:write(u16le(0)) -- flags
  fh:write(u16le(info.method))
  fh:write(u16le(info.dos_time))
  fh:write(u16le(info.dos_date))
  fh:write(u32le(info.crc))
  fh:write(u32le(info.csize))
  fh:write(u32le(info.usize))
  fh:write(u16le(#info.name))
  fh:write(u16le(0)) -- extra length
  fh:write(info.name)
end

local function write_central_entry(fh, info)
  fh:write(u32le(SIG_CDR))
  fh:write(u16le(0x031e)) -- version made by (3.0 unix)
  fh:write(u16le(20)) -- version needed
  fh:write(u16le(0)) -- flags
  fh:write(u16le(info.method))
  fh:write(u16le(info.dos_time))
  fh:write(u16le(info.dos_date))
  fh:write(u32le(info.crc))
  fh:write(u32le(info.csize))
  fh:write(u32le(info.usize))
  fh:write(u16le(#info.name))
  fh:write(u16le(0)) -- extra length
  fh:write(u16le(0)) -- comment length
  fh:write(u16le(0)) -- disk number
  fh:write(u16le(0)) -- internal attrs
  fh:write(u32le(info.is_dir and 0x41ed0010 or 0x81a40000)) -- external attrs
  fh:write(u32le(info.lfh_offset))
  fh:write(info.name)
end

local function write_eocd(fh, count, cd_size, cd_offset)
  fh:write(u32le(SIG_EOCD))
  fh:write(u16le(0)) -- this disk
  fh:write(u16le(0)) -- start-of-cd disk
  fh:write(u16le(count))
  fh:write(u16le(count))
  fh:write(u32le(cd_size))
  fh:write(u32le(cd_offset))
  fh:write(u16le(0)) -- comment length
end

local function read_file_bytes(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a") or ""
  fh:close()
  return data
end

-- Compute the file's mtime as an epoch second; fall back to now.
local function mtime_of(path)
  local lfs = common.try_lfs()
  if lfs then
    local attr = lfs.attributes(path)
    if attr and attr.modification then return attr.modification end
  end
  return os.time()
end

local function add_one(zip_fh, src_path, arcname, level, entries)
  local data, err = read_file_bytes(src_path)
  if not data then return false, err end
  local crc = zlib.crc32(0, data)
  local method = (level == 0) and METHOD_STORE or METHOD_DEFLATE
  local payload
  if method == METHOD_DEFLATE then
    payload = deflate_bytes(data, level)
    -- If deflate didn't actually shrink the payload, fall back to STORE.
    -- This avoids spurious "compressed-larger-than-original" entries.
    if #payload >= #data then
      method = METHOD_STORE
      payload = data
    end
  else
    payload = data
  end
  local mtime = mtime_of(src_path)
  local dos_date, dos_time = dos_datetime(mtime)

  local lfh_offset = zip_fh:seek()
  local info = {
    name = arcname,
    method = method,
    dos_date = dos_date,
    dos_time = dos_time,
    crc = crc,
    csize = #payload,
    usize = #data,
    lfh_offset = lfh_offset,
    is_dir = false,
  }
  write_local_header(zip_fh, info)
  zip_fh:write(payload)
  entries[#entries + 1] = info
  return true
end

local function walk_dir(root, callback)
  local lfs = common.try_lfs()
  if not lfs then return false, "luafilesystem unavailable" end
  local function visit(p)
    local attr = lfs.attributes(p)
    if not attr then return end
    if attr.mode == "directory" then
      local entries = {}
      local ok = pcall(function()
        for entry in lfs.dir(p) do
          if entry ~= "." and entry ~= ".." then entries[#entries + 1] = entry end
        end
      end)
      if ok then
        table.sort(entries)
        for _, entry in ipairs(entries) do
          visit(common.path_join(p, entry))
        end
      end
    else
      callback(p)
    end
  end
  visit(root)
  return true
end

-- Read all entries from an existing archive. Returns
-- (entries_array, error_string_or_nil) where each entry is
-- { name, method, dos_time, dos_date, crc, csize, usize, lfh_offset, payload }.
local function read_archive(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local size = fh:seek("end")
  -- Search for EOCD signature (last 64KB max)
  local search_start = math.max(0, size - 65536 - 22)
  fh:seek("set", search_start)
  local tail = fh:read(size - search_start) or ""
  local eocd_pos = nil
  -- The EOCD signature is 4 bytes; the record itself is at least 22
  -- bytes (no comment). Scan backward from the last position where
  -- a signature could fit.
  for p = #tail - 3, 1, -1 do
    if tail:sub(p, p + 3) == "PK\5\6" then
      eocd_pos = p
      break
    end
  end
  if not eocd_pos then
    fh:close()
    return nil, "EOCD signature not found"
  end
  -- EOCD layout from eocd_pos: sig(4) + disk(2) + cd-disk(2) +
  -- entries-here(2) + total(2) + cd-size(4) + cd-offset(4) + ...
  local p = eocd_pos + 4 + 2 + 2 + 2 -- skip sig + 2 disk fields + entries-here
  local total
  total, p = read_u16le(tail, p)
  local cd_size
  cd_size, p = read_u32le(tail, p)
  local cd_offset = read_u32le(tail, p)

  -- Read central directory
  fh:seek("set", cd_offset)
  local cd = fh:read(cd_size) or ""
  local entries = {}
  local cp = 1
  for _ = 1, total do
    if cd:sub(cp, cp + 3) ~= "PK\1\2" then
      fh:close()
      return nil, "bad central directory entry"
    end
    cp = cp + 4 + 2 + 2 + 2 -- sig + version made/needed + flags
    local method
    method, cp = read_u16le(cd, cp)
    local dos_time
    dos_time, cp = read_u16le(cd, cp)
    local dos_date
    dos_date, cp = read_u16le(cd, cp)
    local crc
    crc, cp = read_u32le(cd, cp)
    local csize
    csize, cp = read_u32le(cd, cp)
    local usize
    usize, cp = read_u32le(cd, cp)
    local nlen
    nlen, cp = read_u16le(cd, cp)
    local elen
    elen, cp = read_u16le(cd, cp)
    local clen
    clen, cp = read_u16le(cd, cp)
    cp = cp + 2 + 2 + 4 -- disk + internal attrs + external attrs
    local lfh_offset
    lfh_offset, cp = read_u32le(cd, cp)
    local name = cd:sub(cp, cp + nlen - 1)
    cp = cp + nlen + elen + clen

    -- Read the payload via the local header
    fh:seek("set", lfh_offset)
    local lfh = fh:read(30) or ""
    if lfh:sub(1, 4) ~= "PK\3\4" then
      fh:close()
      return nil, "bad local header for " .. name
    end
    local lname_len = read_u16le(lfh, 27)
    local lextra_len = read_u16le(lfh, 29)
    fh:seek("set", lfh_offset + 30 + lname_len + lextra_len)
    local payload = fh:read(csize) or ""

    entries[#entries + 1] = {
      name = name,
      method = method,
      dos_time = dos_time,
      dos_date = dos_date,
      crc = crc,
      csize = csize,
      usize = usize,
      payload = payload,
    }
  end
  fh:close()
  return entries
end

local function rewrite_archive(path, entries)
  local fh, err = io.open(path, "wb")
  if not fh then return false, err end
  local kept = {}
  for _, e in ipairs(entries) do
    e.lfh_offset = fh:seek()
    e.is_dir = false
    write_local_header(fh, e)
    fh:write(e.payload or "")
    kept[#kept + 1] = e
  end
  local cd_offset = fh:seek()
  for _, e in ipairs(kept) do
    write_central_entry(fh, e)
  end
  local cd_size = fh:seek() - cd_offset
  write_eocd(fh, #kept, cd_size, cd_offset)
  fh:close()
  return true
end

local function delete_entries(archive, names)
  local entries, err = read_archive(archive)
  if not entries then
    common.err_path(NAME, archive, err or "unreadable")
    return 1
  end
  local drop = {}
  for _, n in ipairs(names) do
    drop[n] = true
  end
  local kept = {}
  for _, e in ipairs(entries) do
    if not drop[e.name] then kept[#kept + 1] = e end
  end
  local ok, werr = rewrite_archive(archive, kept)
  if not ok then
    common.err_path(NAME, archive, werr)
    return 1
  end
  return 0
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local recursive = false
  local junk_paths = false
  local delete_mode = false
  local append = false
  local level = 6

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    elseif a == "-r" or a == "--recurse-paths" then
      recursive = true
      i = i + 1
    elseif a == "-j" or a == "--junk-paths" then
      junk_paths = true
      i = i + 1
    elseif a == "-d" or a == "--delete" then
      delete_mode = true
      i = i + 1
    elseif a == "-g" or a == "--grow" then
      append = true
      i = i + 1
    elseif a:match("^%-[0-9]$") then
      level = tonumber(a:sub(2))
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  if #positional == 0 then
    common.err(NAME, "missing archive name")
    return 2
  end
  local archive = positional[1]
  local names = {}
  for j = 2, #positional do
    names[#names + 1] = positional[j]
  end

  if delete_mode then
    if #names == 0 then
      common.err(NAME, "no entries to delete")
      return 2
    end
    return delete_entries(archive, names)
  end

  if #names == 0 then
    common.err(NAME, "no files to archive")
    return 2
  end

  -- If appending, load the existing archive first so its entries get
  -- preserved in the rewrite. If the file doesn't exist yet, fall back
  -- to a fresh archive.
  local existing = {}
  if append then
    local lfs = common.try_lfs()
    if lfs and lfs.attributes(archive) then
      local ents, err = read_archive(archive)
      if not ents then
        common.err_path(NAME, archive, err or "unreadable")
        return 1
      end
      existing = ents
    end
  end

  local fh, ferr = io.open(archive, "wb")
  if not fh then
    common.err_path(NAME, archive, ferr)
    return 1
  end

  local entries = {}
  -- Carry over any existing entries (when -g and the archive existed).
  for _, e in ipairs(existing) do
    e.lfh_offset = fh:seek()
    e.is_dir = false
    write_local_header(fh, e)
    fh:write(e.payload or "")
    entries[#entries + 1] = e
  end

  local rc = 0
  local function add_path(src)
    local arcname = junk_paths and common.basename(src) or src
    local ok, err = add_one(fh, src, arcname, level, entries)
    if not ok then
      common.err_path(NAME, src, err or "add failed")
      rc = 1
    end
  end

  for _, name in ipairs(names) do
    local lfs = common.try_lfs()
    local attr = lfs and lfs.attributes(name)
    if not attr then
      common.err_path(NAME, name, "no such file or directory")
      rc = 1
    elseif attr.mode == "directory" then
      if not recursive then
        common.err(NAME, name .. " is a directory (use -r)")
        rc = 1
      else
        local ok, err = walk_dir(name, add_path)
        if not ok then
          common.err_path(NAME, name, err or "walk failed")
          rc = 1
        end
      end
    else
      add_path(name)
    end
  end

  local cd_offset = fh:seek()
  for _, e in ipairs(entries) do
    write_central_entry(fh, e)
  end
  local cd_size = fh:seek() - cd_offset
  write_eocd(fh, #entries, cd_size, cd_offset)
  fh:close()

  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "package and compress files into a .zip archive",
  main = main,
  -- Exported so unzip can share the format helpers.
  _internal = {
    read_archive = read_archive,
    inflate_bytes = inflate_bytes,
    METHOD_STORE = METHOD_STORE,
    METHOD_DEFLATE = METHOD_DEFLATE,
  },
}
