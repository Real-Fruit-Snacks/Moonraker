-- cp: copy files and directories.

local common = require("common")

local NAME = "cp"

local CHUNK = 64 * 1024

--- Copy a single file's bytes from src to dst (overwriting).
local function copy_file(src, dst)
  local in_fh, ierr = io.open(src, "rb")
  if not in_fh then return false, ierr end
  local out_fh, oerr = io.open(dst, "wb")
  if not out_fh then
    in_fh:close()
    return false, oerr
  end
  while true do
    local chunk = in_fh:read(CHUNK)
    if not chunk or chunk == "" then break end
    out_fh:write(chunk)
  end
  in_fh:close()
  out_fh:close()
  return true
end

local function copy_tree(src, dst)
  local lfs = common.try_lfs()
  if not lfs then return false, "luafilesystem required" end
  local attr = lfs.symlinkattributes(src)
  if not attr then return false, "source vanished" end
  if attr.mode == "directory" then
    if not lfs.attributes(dst) then
      local ok, err = lfs.mkdir(dst)
      if not ok then return false, err end
    end
    for entry in lfs.dir(src) do
      if entry ~= "." and entry ~= ".." then
        local sub_src = common.path_join(src, entry)
        local sub_dst = common.path_join(dst, entry)
        local ok, err = copy_tree(sub_src, sub_dst)
        if not ok then return false, err end
      end
    end
    return true
  else
    return copy_file(src, dst)
  end
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local recursive = false
  local force = false
  local verbose = false
  local interactive = false
  local no_clobber = false
  local update = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 then
      break
    end
    for ch in a:sub(2):gmatch(".") do
      if ch == "r" or ch == "R" then recursive = true
      elseif ch == "f" then force = true; interactive = false; no_clobber = false
      elseif ch == "v" then verbose = true
      elseif ch == "p" then
        -- preserve metadata; lfs doesn't expose chmod, treat as no-op
        recursive = recursive
      elseif ch == "a" then recursive = true
      elseif ch == "i" then interactive = true; no_clobber = false; force = false
      elseif ch == "n" then no_clobber = true; interactive = false
      elseif ch == "u" then update = true
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
  local dest_attr = lfs and lfs.attributes(dest)
  local dest_is_dir = dest_attr and dest_attr.mode == "directory"
  if #sources > 1 and not dest_is_dir then
    common.err(NAME, "target '" .. dest .. "' is not a directory")
    return 1
  end

  local rc = 0
  for _, src in ipairs(sources) do
    local src_attr = lfs and lfs.symlinkattributes(src)
    if not src_attr then
      common.err_path(NAME, src, "No such file or directory")
      rc = 1
    else
      local target = dest_is_dir and common.path_join(dest, common.basename(src)) or dest

      local proceed = common.should_overwrite(NAME, target, src, {
        no_clobber = no_clobber,
        update = update,
        interactive = interactive,
        force = force,
      })

      if proceed then
        local ok, err
        if src_attr.mode == "directory" then
          if not recursive then
            common.err(NAME, "-r not specified; omitting directory '" .. src .. "'")
            rc = 1
          else
            ok, err = copy_tree(src, target)
          end
        else
          ok, err = copy_file(src, target)
        end
        if ok == false then
          common.err_path(NAME, src, err or "copy failed")
          rc = 1
        elseif verbose and ok ~= nil then
          io.stdout:write(string.format("'%s' -> '%s'\n", src, target))
        end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = { "copy" },
  help = "copy files and directories",
  main = main,
}
