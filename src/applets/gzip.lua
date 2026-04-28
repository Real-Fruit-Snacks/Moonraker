-- gzip: compress or decompress files (.gz).
--
-- Backed by the vendored lua-zlib binding (src/cdeps/zlib/lua_zlib.c),
-- which wraps zlib's deflate/inflate streams. Gzip framing is enabled by
-- passing windowBits = MAXIMUM_WINDOWBITS + GZIP_WINDOWBITS (= 31).

local common = require("common")

local NAME = "gzip"

local zlib = require("zlib")
local GZIP_BITS = zlib.MAXIMUM_WINDOWBITS + zlib.GZIP_WINDOWBITS
local CHUNK = 64 * 1024

local function compress_stream(input_fh, output_fh, level)
  local d = zlib.deflate(level, GZIP_BITS)
  while true do
    local data = input_fh:read(CHUNK)
    if not data or data == "" then break end
    local out = d(data)
    if out and out ~= "" then output_fh:write(out) end
  end
  local final = d("", "finish")
  if final and final ~= "" then output_fh:write(final) end
end

local function decompress_stream(input_fh, output_fh)
  local i = zlib.inflate(GZIP_BITS)
  while true do
    local data = input_fh:read(CHUNK)
    if not data or data == "" then break end
    local ok, out = pcall(i, data)
    if not ok then
      return false, tostring(out)
    end
    if out and out ~= "" then output_fh:write(out) end
  end
  return true
end

local function lfs_attributes(p)
  local lfs = common.try_lfs()
  return lfs and lfs.attributes(p) or nil
end

local function compress_file(path, level, keep, force, to_stdout)
  if to_stdout then
    local fh, err = io.open(path, "rb")
    if not fh then
      common.err_path(NAME, path, err)
      return 1
    end
    compress_stream(fh, io.stdout, level)
    fh:close()
    return 0
  end

  local out_path = path .. ".gz"
  if lfs_attributes(out_path) and not force then
    common.err(NAME, out_path .. " already exists; use -f to overwrite")
    return 1
  end
  local in_fh, ierr = io.open(path, "rb")
  if not in_fh then
    common.err_path(NAME, path, ierr)
    return 1
  end
  local out_fh, oerr = io.open(out_path, "wb")
  if not out_fh then
    in_fh:close()
    common.err_path(NAME, out_path, oerr)
    return 1
  end
  compress_stream(in_fh, out_fh, level)
  in_fh:close()
  out_fh:close()
  if not keep then
    local ok, rerr = os.remove(path)
    if not ok then
      common.err_path(NAME, path, rerr or "remove failed")
      return 1
    end
  end
  return 0
end

local function decompress_file(path, keep, force, to_stdout, test_only)
  local has_gz = path:sub(-3) == ".gz"
  if not has_gz and not force and not to_stdout and not test_only then
    common.err(NAME, path .. ": unknown suffix; skipping (use -f to force)")
    return 1
  end

  local out_path = has_gz and path:sub(1, -4) or (path .. ".out")

  if test_only or to_stdout then
    local fh, err = io.open(path, "rb")
    if not fh then
      common.err_path(NAME, path, err)
      return 1
    end
    if to_stdout then
      local ok, derr = decompress_stream(fh, io.stdout)
      fh:close()
      if not ok then
        common.err_path(NAME, path, derr)
        return 1
      end
    else
      -- test: discard output
      local sink = { write = function() end }
      local ok, derr = decompress_stream(fh, sink)
      fh:close()
      if not ok then
        common.err_path(NAME, path, derr)
        return 1
      end
    end
    return 0
  end

  if lfs_attributes(out_path) and not force then
    common.err(NAME, out_path .. " already exists; use -f to overwrite")
    return 1
  end
  local in_fh, ierr = io.open(path, "rb")
  if not in_fh then
    common.err_path(NAME, path, ierr)
    return 1
  end
  local out_fh, oerr = io.open(out_path, "wb")
  if not out_fh then
    in_fh:close()
    common.err_path(NAME, out_path, oerr)
    return 1
  end
  local ok, derr = decompress_stream(in_fh, out_fh)
  in_fh:close()
  out_fh:close()
  if not ok then
    pcall(os.remove, out_path)
    common.err_path(NAME, path, derr)
    return 1
  end
  if not keep then
    local rok, rerr = os.remove(path)
    if not rok then
      common.err_path(NAME, path, rerr or "remove failed")
      return 1
    end
  end
  return 0
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local decompress, to_stdout = false, false
  local keep, force, test_only = false, false, false
  local level = 6

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-d" or a == "--decompress" or a == "--uncompress" then
      decompress = true
    elseif a == "-c" or a == "--stdout" or a == "--to-stdout" then
      to_stdout = true; keep = true
    elseif a == "-k" or a == "--keep" then
      keep = true
    elseif a == "-f" or a == "--force" then
      force = true
    elseif a == "-t" or a == "--test" then
      test_only = true; decompress = true
    elseif a == "-q" or a == "--quiet" or a == "-v" or a == "--verbose" then
      level = level -- no-op
    elseif a:match("^%-[1-9]$") then
      level = tonumber(a:sub(2))
    elseif a:sub(1, 1) == "-" and a ~= "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
    i = i + 1
  end

  local files = {}
  for j = i, #args do files[#files + 1] = args[j] end

  -- stdin -> stdout when no files
  if #files == 0 or (#files == 1 and files[1] == "-") then
    if decompress then
      local ok, derr = decompress_stream(io.stdin, io.stdout)
      if not ok then
        common.err(NAME, derr)
        return 1
      end
    else
      compress_stream(io.stdin, io.stdout, level)
    end
    return 0
  end

  local rc = 0
  for _, f in ipairs(files) do
    local r
    if decompress then
      r = decompress_file(f, keep, force, to_stdout, test_only)
    else
      r = compress_file(f, level, keep, force, to_stdout)
    end
    if r ~= 0 then rc = r end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "compress or decompress files (.gz)",
  main = main,
}
