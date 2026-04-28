-- unzip: extract files from a .zip archive.
--
-- Reads central directory, decompresses each entry (stored or
-- deflated), and writes to disk. -l lists, -p pipes to stdout.

local common = require("common")
local zip = require("applets.zip")

local NAME = "unzip"

local read_archive = zip._internal.read_archive
local inflate_bytes = zip._internal.inflate_bytes
local METHOD_STORE = zip._internal.METHOD_STORE
local METHOD_DEFLATE = zip._internal.METHOD_DEFLATE

local function decompress(entry)
  if entry.method == METHOD_STORE then return entry.payload end
  if entry.method == METHOD_DEFLATE then
    local out, err = inflate_bytes(entry.payload)
    if not out then return nil, err end
    return out
  end
  return nil, "unsupported compression method " .. tostring(entry.method)
end

local function format_dos_datetime(date, time)
  if date == 0 and time == 0 then return "0000-00-00 00:00" end
  local year = math.floor(date / 512) + 1980
  local month = math.floor(date / 32) % 16
  local day = date % 32
  local hour = math.floor(time / 2048)
  local minute = math.floor(time / 32) % 64
  return string.format("%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
end

local function ensure_parent_dir(path)
  local lfs = common.try_lfs()
  if not lfs then return true end
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return true end
  if lfs.attributes(dir) then return true end
  local sep = common.path_sep()
  local parts = {}
  for p in dir:gmatch("[^/\\]+") do
    parts[#parts + 1] = p
  end
  local cur = dir:sub(1, 1) == "/" and "/" or ""
  for _, p in ipairs(parts) do
    cur = (cur == "" or cur == "/") and (cur .. p) or (cur .. sep .. p)
    if not lfs.attributes(cur) then
      local ok = lfs.mkdir(cur)
      if not ok then return false end
    end
  end
  return true
end

local function is_dir_entry(name)
  return name:sub(-1) == "/" or name:sub(-1) == "\\"
end

local function safe_path(dest, name)
  -- Prevent path-escape via ../../ payloads. Reject names that, when
  -- joined with dest and resolved, fall outside dest.
  if name:find("%.%.[/\\]") or name:sub(1, 3) == "../" or name:sub(1, 3) == "..\\" then return nil end
  if name:sub(1, 1) == "/" or name:sub(1, 1) == "\\" or name:match("^[A-Za-z]:") then
    return nil -- absolute path, refuse
  end
  return common.path_join(dest, name)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local dest = "."
  local list_only = false
  local overwrite = nil
  local pipe_mode = false
  local quiet = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    elseif a == "-d" then
      if not args[i + 1] then
        common.err(NAME, "-d: missing argument")
        return 2
      end
      dest = args[i + 1]
      i = i + 2
    elseif a == "-l" then
      list_only = true
      i = i + 1
    elseif a == "-o" then
      overwrite = true
      i = i + 1
    elseif a == "-n" then
      overwrite = false
      i = i + 1
    elseif a == "-p" then
      pipe_mode = true
      i = i + 1
    elseif a == "-q" or a == "-qq" then
      quiet = true
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
    common.err(NAME, "missing archive")
    return 2
  end
  local archive = positional[1]
  local requested = nil
  if positional[2] then
    requested = {}
    for j = 2, #positional do
      requested[positional[j]] = true
    end
  end

  local entries, err = read_archive(archive)
  if not entries then
    common.err_path(NAME, archive, err or "unreadable")
    return 1
  end

  if list_only then
    io.stdout:write("Archive:  ", archive, "\n")
    io.stdout:write("  Length      Date    Time   Name\n")
    io.stdout:write("---------  ---------- -----  ----\n")
    local total, count = 0, 0
    for _, e in ipairs(entries) do
      if not requested or requested[e.name] then
        local dt = format_dos_datetime(e.dos_date, e.dos_time)
        io.stdout:write(string.format("%9d  %s  %s\n", e.usize, dt, e.name))
        total = total + e.usize
        count = count + 1
      end
    end
    io.stdout:write("---------                    -------\n")
    local plural = count == 1 and "" or "s"
    io.stdout:write(string.format("%9d                    %d file%s\n", total, count, plural))
    return 0
  end

  if pipe_mode then
    for _, e in ipairs(entries) do
      if not requested or requested[e.name] then
        local data, derr = decompress(e)
        if not data then
          common.err_path(NAME, e.name, derr or "decompress failed")
          return 1
        end
        io.stdout:write(data)
      end
    end
    return 0
  end

  -- Extract mode
  local lfs = common.try_lfs()
  if lfs and not lfs.attributes(dest) then
    local ok = lfs.mkdir(dest)
    if not ok then
      common.err_path(NAME, dest, "cannot create directory")
      return 1
    end
  end

  local rc = 0
  for _, e in ipairs(entries) do
    if not requested or requested[e.name] then
      local target = safe_path(dest, e.name)
      if not target then
        common.err(NAME, "unsafe path skipped: " .. e.name)
        rc = 1
      elseif is_dir_entry(e.name) then
        ensure_parent_dir(common.path_join(target, "x"))
      else
        local skip_existing = lfs and lfs.attributes(target) and overwrite == false
        if not skip_existing then
          if not ensure_parent_dir(target) then
            common.err_path(NAME, target, "could not create parent directory")
            rc = 1
          else
            local data, derr = decompress(e)
            if not data then
              common.err_path(NAME, e.name, derr or "decompress failed")
              rc = 1
            else
              local fh, ferr = io.open(target, "wb")
              if not fh then
                common.err_path(NAME, target, ferr or "open failed")
                rc = 1
              else
                fh:write(data)
                fh:close()
                if not quiet then io.stdout:write("  extracting: ", e.name, "\n") end
              end
            end
          end
        end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "extract files from a .zip archive",
  main = main,
}
