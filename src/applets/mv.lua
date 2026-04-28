-- mv: move (rename) files.

local common = require("common")

local NAME = "mv"

local function path_basename(p)
  return common.basename(p)
end

local function path_join(a, b)
  local sep = common.path_sep()
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. sep .. b
end

local function is_directory(lfs, path)
  if not lfs then return false end
  local attr = lfs.attributes(path)
  return attr ~= nil and attr.mode == "directory"
end

local function exists(lfs, path)
  if lfs then return lfs.symlinkattributes(path) ~= nil end
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

--- Best-effort move: prefer os.rename (atomic when possible), fall back to
--- copy+remove if rename fails (different filesystems).
local function move_one(src, dst)
  local ok, err = os.rename(src, dst)
  if ok then return true end
  -- Fallback: copy then unlink. Only handles regular files.
  local in_fh = io.open(src, "rb")
  if not in_fh then return false, err end
  local out_fh = io.open(dst, "wb")
  if not out_fh then
    in_fh:close()
    return false, "could not open destination"
  end
  while true do
    local chunk = in_fh:read(64 * 1024)
    if not chunk or chunk == "" then break end
    out_fh:write(chunk)
  end
  in_fh:close()
  out_fh:close()
  return os.remove(src)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local force = false
  local verbose = false
  local no_clobber = false
  local interactive = false
  local update = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 then break end
    for ch in a:sub(2):gmatch(".") do
      if ch == "f" then
        force = true
        no_clobber = false
        interactive = false
      elseif ch == "n" then
        no_clobber = true
        force = false
        interactive = false
      elseif ch == "i" then
        interactive = true
        force = false
        no_clobber = false
      elseif ch == "u" then
        update = true
      elseif ch == "v" then
        verbose = true
      else
        common.err(NAME, "invalid option: -" .. ch)
        return 2
      end
    end
    i = i + 1
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  if #positional < 2 then
    common.err(NAME, "missing file operand")
    return 2
  end

  local dest = positional[#positional]
  local sources = {}
  for j = 1, #positional - 1 do
    sources[j] = positional[j]
  end

  local lfs = common.try_lfs()
  local dest_is_dir = is_directory(lfs, dest)
  if #sources > 1 and not dest_is_dir then
    common.err(NAME, "target '" .. dest .. "' is not a directory")
    return 1
  end

  local rc = 0
  for _, src in ipairs(sources) do
    if not exists(lfs, src) then
      common.err_path(NAME, src, "No such file or directory")
      rc = 1
    else
      local target = dest_is_dir and path_join(dest, path_basename(src)) or dest

      local proceed = common.should_overwrite(NAME, target, src, {
        no_clobber = no_clobber,
        update = update,
        interactive = interactive,
        force = force,
      })

      if proceed then
        local ok, err = move_one(src, target)
        if not ok then
          common.err_path(NAME, src, err or "move failed")
          rc = 1
        elseif verbose then
          io.stdout:write(string.format("'%s' -> '%s'\n", src, target))
        end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = { "move", "ren", "rename" },
  help = "move (rename) files",
  main = main,
}
