-- touch: change file timestamps (create if missing).
--
-- Phase 1 implementation: creates files when missing, updates timestamps
-- to "now" via lfs.touch. -r/-d/-t flags are accepted and parsed but
-- precise timestamp setting requires lfs.touch(path, atime, mtime), which
-- is supported on POSIX builds of LuaFileSystem. Windows builds fall back
-- to a touch-to-now.

local common = require("common")

local NAME = "touch"

local function parse_t(s)
  local secs = "00"
  if s:find(".", 1, true) then
    s, secs = s:match("^(.+)%.(%d+)$")
    if not s then return nil end
  end
  if not s:match("^%d+$") or not secs:match("^%d+$") then return nil end
  if #s == 8 then
    -- MMDDhhmm — current year
    s = string.format("%04d%s", tonumber(os.date("%Y")), s)
  elseif #s == 10 then
    -- YYMMDDhhmm — POSIX 1969 cutoff
    local yy = tonumber(s:sub(1, 2))
    s = (yy < 69 and "20" or "19") .. s
  end
  if #s ~= 12 then return nil end
  local ok, t = pcall(os.time, {
    year = tonumber(s:sub(1, 4)),
    month = tonumber(s:sub(5, 6)),
    day = tonumber(s:sub(7, 8)),
    hour = tonumber(s:sub(9, 10)),
    min = tonumber(s:sub(11, 12)),
    sec = tonumber(secs),
  })
  if not ok then return nil end
  return t
end

local function parse_d(s)
  s = s:match("^%s*(.-)%s*$")
  -- ISO 8601 "YYYY-MM-DDTHH:MM:SS" or "YYYY-MM-DD HH:MM:SS"
  local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ]?(%d?%d?):?(%d?%d?):?(%d?%d?)Z?$")
  if not y then
    -- Just a date
    y, mo, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    h, mi, se = "0", "0", "0"
  end
  local ok, t = pcall(os.time, {
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h ~= "" and h or 0),
    min = tonumber(mi ~= "" and mi or 0),
    sec = tonumber(se ~= "" and se or 0),
  })
  if not ok then return nil end
  return t
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local no_create = false
  local atime_only = false
  local mtime_only = false
  local ref_time = nil
  local target_time = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-r" and i + 1 <= #args then
      local lfs = common.try_lfs()
      if not lfs then
        common.err(NAME, "luafilesystem required for -r")
        return 1
      end
      local attr = lfs.attributes(args[i + 1])
      if not attr then
        common.err_path(NAME, args[i + 1], "No such file or directory")
        return 1
      end
      ref_time = attr.modification
      i = i + 2
    elseif a == "-d" and i + 1 <= #args then
      target_time = parse_d(args[i + 1])
      if not target_time then
        common.err(NAME, "invalid date: '" .. args[i + 1] .. "'")
        return 2
      end
      i = i + 2
    elseif a == "-t" and i + 1 <= #args then
      target_time = parse_t(args[i + 1])
      if not target_time then
        common.err(NAME, "invalid -t value: '" .. args[i + 1] .. "'")
        return 2
      end
      i = i + 2
    elseif a:sub(1, 1) ~= "-" or #a < 2 then
      break
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "c" then
          no_create = true
        elseif ch == "a" then
          atime_only = true
        elseif ch == "m" then
          mtime_only = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    end
  end

  local files = {}
  for j = i, #args do
    files[#files + 1] = args[j]
  end
  if #files == 0 then
    common.err(NAME, "missing file operand")
    return 2
  end

  local lfs = common.try_lfs()
  local rc = 0
  local now = os.time()
  local set_time = ref_time or target_time or now

  for _, f in ipairs(files) do
    local attr = lfs and lfs.attributes(f) or nil
    if not attr and not no_create then
      local fh, err = io.open(f, "ab")
      if not fh then
        common.err_path(NAME, f, err or "could not create")
        rc = 1
      else
        fh:close()
      end
    end
    -- After creation attempt, refresh attr in case the file now exists.
    if lfs and lfs.touch then
      local cur = lfs.attributes(f)
      if cur then
        local new_atime = (atime_only or not mtime_only) and set_time or cur.access
        local new_mtime = (mtime_only or not atime_only) and set_time or cur.modification
        local ok, err = lfs.touch(f, new_atime or set_time, new_mtime or set_time)
        if not ok then
          common.err_path(NAME, f, err or "touch failed")
          rc = 1
        end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "change file timestamps (create if missing)",
  main = main,
}
