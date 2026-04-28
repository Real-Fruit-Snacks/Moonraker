-- tar: create, extract, or list tar archives (POSIX ustar).
--
-- Optional compression filters: gzip via the vendored lua-zlib binding
-- (-z / .tar.gz / .tgz), bz2 via the vendored libbzip2 binding
-- (-j / .tar.bz2 / .tbz2). xz (-J) is still accepted at the parser
-- level but rejected — adding it needs a vendored xz/lzma library.

local common = require("common")

local NAME = "tar"

local zlib = require("zlib")
-- bzip2 binding is only available in the bundled binary (vendored
-- src/cdeps/bzip2). Load lazily so the unit-test environment, which
-- doesn't ship bzip2 to the system Lua, can still require this applet.
local function load_bzip2()
  local ok, mod = pcall(require, "bzip2")
  if ok then return mod end
  return nil
end
local GZIP_BITS = zlib.MAXIMUM_WINDOWBITS + zlib.GZIP_WINDOWBITS
local BLOCK = 512

-- ---------------------------------------------------------------------
-- Header helpers
-- ---------------------------------------------------------------------

local function octal(n, width)
  local s = string.format("%0" .. (width - 1) .. "o", n)
  return s .. "\0"
end

local function parse_octal(s)
  local clean = s:match("([0-7]+)") or "0"
  return tonumber(clean, 8) or 0
end

local function compute_checksum(header_with_blanks)
  local sum = 0
  for j = 1, #header_with_blanks do
    sum = sum + header_with_blanks:byte(j)
  end
  return sum
end

local function build_header(name, size, mode, mtime, typeflag, linkname)
  -- Build with zeros, then fill, then compute checksum
  local fields = {
    string.sub(name, 1, 100) .. string.rep("\0", 100 - #string.sub(name, 1, 100)),
    octal(mode, 8),
    octal(0, 8), -- uid
    octal(0, 8), -- gid
    octal(size, 12),
    octal(mtime or os.time(), 12),
    string.rep(" ", 8), -- checksum placeholder (8 spaces)
    typeflag or "0",
    string.sub(linkname or "", 1, 100) .. string.rep("\0", 100 - #string.sub(linkname or "", 1, 100)),
    "ustar\0",
    "00",
    string.rep("\0", 32), -- uname
    string.rep("\0", 32), -- gname
    octal(0, 8), -- devmajor
    octal(0, 8), -- devminor
    string.rep("\0", 155), -- prefix
    string.rep("\0", 12), -- pad
  }
  local header = table.concat(fields)
  -- pad to 512
  if #header < BLOCK then header = header .. string.rep("\0", BLOCK - #header) end
  -- compute checksum
  local sum = compute_checksum(header)
  local cksum_field = string.format("%06o\0 ", sum)
  return header:sub(1, 148) .. cksum_field .. header:sub(157)
end

local function parse_header(block)
  if #block < BLOCK then return nil, "truncated header" end
  -- Detect end-of-archive (all-zero block)
  if block == string.rep("\0", BLOCK) then return nil, "eof" end

  local function field(start, len)
    return block:sub(start, start + len - 1)
  end
  local function nullstrip(s)
    local nul = s:find("\0", 1, true)
    if nul then return s:sub(1, nul - 1) end
    return s
  end

  local name = nullstrip(field(1, 100))
  local mode = parse_octal(field(101, 8))
  local size = parse_octal(field(125, 12))
  local mtime = parse_octal(field(137, 12))
  local typeflag = field(157, 1)
  local linkname = nullstrip(field(158, 100))
  local prefix = nullstrip(field(346, 155))
  if prefix ~= "" then name = prefix .. "/" .. name end
  return {
    name = name,
    mode = mode,
    size = size,
    mtime = mtime,
    typeflag = typeflag,
    linkname = linkname,
  }
end

-- ---------------------------------------------------------------------
-- Stream wrappers (raw or gzip)
-- ---------------------------------------------------------------------

local function open_writer(path, compression)
  local fh
  if path == "-" then
    fh = io.stdout
  else
    local err
    fh, err = io.open(path, "wb")
    if not fh then return nil, err end
  end
  if compression == nil then
    return {
      write = function(_, s)
        fh:write(s)
      end,
      close = function()
        if path ~= "-" then fh:close() end
      end,
    }
  end
  if compression == "gz" then
    local d = zlib.deflate(zlib.DEFAULT_COMPRESSION, GZIP_BITS)
    return {
      write = function(_, s)
        local out = d(s)
        if out and out ~= "" then fh:write(out) end
      end,
      close = function()
        local final = d("", "finish")
        if final and final ~= "" then fh:write(final) end
        if path ~= "-" then fh:close() end
      end,
    }
  end
  if compression == "bz2" then
    local bzip2 = load_bzip2()
    if not bzip2 then
      if path ~= "-" then fh:close() end
      return nil, "bz2 not available in this build"
    end
    -- bzip2 is one-shot in our binding (no streaming API). Buffer
    -- everything in memory, then compress at close time. Tar archives
    -- big enough to make this painful are uncommon; if someone hits it
    -- we can extend lua_bzip2.c with a streaming API.
    local buf = {}
    return {
      write = function(_, s)
        buf[#buf + 1] = s
      end,
      close = function()
        local plain = table.concat(buf)
        local ok, compressed = pcall(bzip2.compress, plain, 9)
        if ok and compressed then fh:write(compressed) end
        if path ~= "-" then fh:close() end
      end,
    }
  end
  return nil, "unknown compression: " .. tostring(compression)
end

local function read_full(path, compression)
  local fh
  if path == "-" then
    fh = io.stdin
  else
    local err
    fh, err = io.open(path, "rb")
    if not fh then return nil, err end
  end
  local raw = fh:read("*a") or ""
  if path ~= "-" then fh:close() end
  if compression == nil then return raw end
  if compression == "gz" then
    local i = zlib.inflate(GZIP_BITS)
    local ok, decoded = pcall(i, raw)
    if not ok then return nil, tostring(decoded) end
    return decoded
  end
  if compression == "bz2" then
    local bzip2 = load_bzip2()
    if not bzip2 then return nil, "bz2 not available in this build" end
    local data, derr = bzip2.decompress(raw)
    if not data then return nil, derr end
    return data
  end
  return nil, "unknown compression: " .. tostring(compression)
end

-- ---------------------------------------------------------------------
-- Operations: create / extract / list
-- ---------------------------------------------------------------------

local function fnmatch_any(name, patterns)
  for _, p in ipairs(patterns) do
    if common.fnmatch(p, common.basename(name)) or common.fnmatch(p, name) then return true end
  end
  return false
end

local function read_file_bytes(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a") or ""
  fh:close()
  return data
end

local function add_entry(writer, abs_path, arc_name, lfs, excludes, verbose)
  local attr = lfs.symlinkattributes(abs_path)
  if not attr then return false, "cannot stat" end
  if fnmatch_any(arc_name, excludes) then return true end
  if verbose then io.stderr:write(arc_name, "\n") end

  if attr.mode == "directory" then
    local header = build_header(
      arc_name .. "/",
      0,
      tonumber(attr.permissions and string.format("%o", 0) or "755", 8) or 493,
      math.floor(attr.modification or os.time()),
      "5",
      ""
    )
    writer:write(header)
    -- Recurse
    local entries = {}
    for entry in lfs.dir(abs_path) do
      if entry ~= "." and entry ~= ".." then entries[#entries + 1] = entry end
    end
    table.sort(entries)
    for _, entry in ipairs(entries) do
      local sub = abs_path .. "/" .. entry
      add_entry(writer, sub, arc_name .. "/" .. entry, lfs, excludes, verbose)
    end
  elseif attr.mode == "file" then
    local data, derr = read_file_bytes(abs_path)
    if not data then return false, derr end
    local header = build_header(
      arc_name,
      #data,
      420, -- mode 0o644
      math.floor(attr.modification or os.time()),
      "0",
      ""
    )
    writer:write(header)
    writer:write(data)
    -- Pad to 512
    local pad = (BLOCK - (#data % BLOCK)) % BLOCK
    if pad > 0 then writer:write(string.rep("\0", pad)) end
  elseif attr.mode == "link" then
    local target = lfs.attributes(abs_path)
    -- lfs has no readlink; skip symlinks gracefully
    local _ = target
  end
  return true
end

local function op_create(archive, paths, verbose, excludes, cwd, compression)
  local lfs = common.try_lfs()
  if not lfs then
    common.err(NAME, "luafilesystem required")
    return 1
  end
  local original_dir
  if cwd then
    original_dir = lfs.currentdir()
    if not lfs.chdir(cwd) then
      common.err_path(NAME, cwd, "cannot chdir")
      return 1
    end
  end
  local writer, werr = open_writer(archive, compression)
  if not writer then
    if original_dir then lfs.chdir(original_dir) end
    common.err_path(NAME, archive, werr)
    return 1
  end
  local rc = 0
  for _, p in ipairs(paths) do
    local ok, err = add_entry(writer, p, p, lfs, excludes, verbose)
    if not ok then
      common.err_path(NAME, p, err or "add failed")
      rc = 1
    end
  end
  -- Two zero blocks as end marker
  writer:write(string.rep("\0", BLOCK * 2))
  writer:close()
  if original_dir then lfs.chdir(original_dir) end
  return rc
end

local function op_extract(archive, verbose, excludes, cwd, compression)
  local data, err = read_full(archive, compression)
  if not data then
    common.err_path(NAME, archive, err)
    return 1
  end
  local lfs = common.try_lfs()
  local original_dir
  if cwd then
    original_dir = lfs and lfs.currentdir() or nil
    if lfs and not lfs.chdir(cwd) then
      common.err_path(NAME, cwd, "cannot chdir")
      return 1
    end
  end

  local pos = 1
  local rc = 0
  while pos + BLOCK - 1 <= #data do
    local block = data:sub(pos, pos + BLOCK - 1)
    local h, herr = parse_header(block)
    pos = pos + BLOCK
    if not h then
      if herr == "eof" then break end
      common.err(NAME, "bad header: " .. tostring(herr))
      rc = 1
      break
    end
    if not fnmatch_any(h.name, excludes) then
      if verbose then io.stderr:write(h.name, "\n") end
      if h.typeflag == "5" then
        -- directory
        if lfs then lfs.mkdir(h.name:gsub("/$", "")) end
      elseif h.typeflag == "0" or h.typeflag == "" or h.typeflag == "\0" then
        -- regular file
        local content = data:sub(pos, pos + h.size - 1)
        -- ensure parent dir exists
        local parent = common.dirname(h.name)
        if parent ~= "." and parent ~= "" and lfs then
          local seg = ""
          for piece in parent:gmatch("[^/]+") do
            seg = seg == "" and piece or (seg .. "/" .. piece)
            lfs.mkdir(seg)
          end
        end
        local fh, ferr = io.open(h.name, "wb")
        if fh then
          fh:write(content)
          fh:close()
        else
          common.err_path(NAME, h.name, ferr or "cannot create")
          rc = 1
        end
      end
    end
    -- advance past content (rounded up to BLOCK)
    local skip = math.ceil(h.size / BLOCK) * BLOCK
    pos = pos + skip
  end

  if original_dir then lfs.chdir(original_dir) end
  return rc
end

local function op_list(archive, verbose, compression)
  local data, err = read_full(archive, compression)
  if not data then
    common.err_path(NAME, archive, err)
    return 1
  end
  local pos = 1
  while pos + BLOCK - 1 <= #data do
    local block = data:sub(pos, pos + BLOCK - 1)
    local h, herr = parse_header(block)
    pos = pos + BLOCK
    if not h then
      if herr == "eof" then break end
      common.err(NAME, "bad header: " .. tostring(herr))
      return 1
    end
    if verbose then
      io.stdout:write(
        string.format("%-10s %10d %s\n", h.typeflag == "5" and "drwxr-xr-x" or "-rw-r--r--", h.size, h.name)
      )
    else
      io.stdout:write(h.name, "\n")
    end
    pos = pos + math.ceil(h.size / BLOCK) * BLOCK
  end
  return 0
end

-- ---------------------------------------------------------------------
-- Argument parsing
-- ---------------------------------------------------------------------

local function expand_bundled(args)
  if #args == 0 then return args end
  local first = args[1]
  if first:sub(1, 2) == "--" or first == "-" then return args end
  local bundled = first:sub(1, 1) == "-" and first:sub(2) or first
  if bundled == "" or not bundled:match("^[cxtrvzjJfkpaoC]+$") then return args end
  local value_taking = "fC"
  local need = 0
  for ch in bundled:gmatch(".") do
    if value_taking:find(ch, 1, true) then need = need + 1 end
  end
  if #args < 1 + need then return args end
  local values = {}
  for k = 2, 1 + need do
    values[#values + 1] = args[k]
  end
  local rest = {}
  for k = 2 + need, #args do
    rest[#rest + 1] = args[k]
  end
  local out = {}
  local v_idx = 1
  for ch in bundled:gmatch(".") do
    out[#out + 1] = "-" .. ch
    if value_taking:find(ch, 1, true) then
      out[#out + 1] = values[v_idx]
      v_idx = v_idx + 1
    end
  end
  for _, r in ipairs(rest) do
    out[#out + 1] = r
  end
  return out
end

local function main(argv)
  local raw = {}
  for i = 1, #argv do
    raw[i] = argv[i]
  end
  local args = expand_bundled(raw)

  local op, archive = nil, nil
  local verbose = false
  local compression = nil -- nil | "gz" | "bz2"
  local change_dir = nil
  local excludes = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    end
    if a == "-c" or a == "--create" then
      op = "c"
      i = i + 1
    elseif a == "-x" or a == "--extract" then
      op = "x"
      i = i + 1
    elseif a == "-t" or a == "--list" then
      op = "t"
      i = i + 1
    elseif a == "-v" or a == "--verbose" then
      verbose = true
      i = i + 1
    elseif a == "-z" or a == "--gzip" then
      compression = "gz"
      i = i + 1
    elseif a == "-j" or a == "--bzip2" then
      compression = "bz2"
      i = i + 1
    elseif a == "-J" or a == "--xz" then
      common.err(NAME, "xz not supported in this build")
      return 2
    elseif a == "-f" then
      if i + 1 > #args then
        common.err(NAME, "-f: missing argument")
        return 2
      end
      archive = args[i + 1]
      i = i + 2
    elseif a:sub(1, 7) == "--file=" then
      archive = a:sub(8)
      i = i + 1
    elseif a == "-C" then
      if i + 1 > #args then
        common.err(NAME, "-C: missing argument")
        return 2
      end
      change_dir = args[i + 1]
      i = i + 2
    elseif a:sub(1, 12) == "--directory=" then
      change_dir = a:sub(13)
      i = i + 1
    elseif a == "--exclude" then
      if i + 1 > #args then
        common.err(NAME, "--exclude: missing argument")
        return 2
      end
      excludes[#excludes + 1] = args[i + 1]
      i = i + 2
    elseif a:sub(1, 10) == "--exclude=" then
      excludes[#excludes + 1] = a:sub(11)
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  if not op then
    common.err(NAME, "must specify one of -c, -x, -t")
    return 2
  end
  if not archive then
    common.err(NAME, "-f is required")
    return 2
  end

  local paths = {}
  for j = i, #args do
    paths[#paths + 1] = args[j]
  end

  -- Auto-detect compression from extension when reading
  if (op == "x" or op == "t") and not compression then
    if archive:sub(-3) == ".gz" or archive:sub(-4) == ".tgz" then
      compression = "gz"
    elseif archive:sub(-4) == ".bz2" or archive:sub(-5) == ".tbz2" or archive:sub(-4) == ".tbz" then
      compression = "bz2"
    end
  end

  if op == "c" then
    if #paths == 0 then
      common.err(NAME, "nothing to archive")
      return 2
    end
    return op_create(archive, paths, verbose, excludes, change_dir, compression)
  elseif op == "x" then
    return op_extract(archive, verbose, excludes, change_dir, compression)
  elseif op == "t" then
    return op_list(archive, verbose, compression)
  end
  return 2
end

return {
  name = NAME,
  aliases = {},
  help = "create, extract, or list tar archives",
  main = main,
}
