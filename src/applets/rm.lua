-- rm: remove files or directories.

local common = require("common")

local NAME = "rm"

--- Recursively remove a directory tree using lfs. Returns true on success.
local function remove_tree(lfs, path)
  for entry in lfs.dir(path) do
    if entry ~= "." and entry ~= ".." then
      local sub = path .. "/" .. entry
      local attr = lfs.symlinkattributes(sub)
      if attr and attr.mode == "directory" then
        local ok, err = remove_tree(lfs, sub)
        if not ok then
          return false, err
        end
      else
        local ok, err = os.remove(sub)
        if not ok then
          return false, err
        end
      end
    end
  end
  return lfs.rmdir(path)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local recursive = false
  local force = false
  local verbose = false
  local dir_only = false

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
      if ch == "r" or ch == "R" then
        recursive = true
      elseif ch == "f" then
        force = true
      elseif ch == "v" then
        verbose = true
      elseif ch == "d" then
        dir_only = true
      else
        common.err(NAME, "invalid option: -" .. ch)
        return 2
      end
    end
    i = i + 1
  end

  local targets = {}
  for j = i, #args do
    targets[#targets + 1] = args[j]
  end
  if #targets == 0 then
    if force then
      return 0
    end
    common.err(NAME, "missing operand")
    return 2
  end

  local lfs = common.try_lfs()
  local rc = 0

  for _, t in ipairs(targets) do
    local attr = lfs and lfs.symlinkattributes(t) or nil
    if not attr then
      if not force then
        common.err_path(NAME, t, "No such file or directory")
        rc = 1
      end
    else
      local is_dir = attr.mode == "directory"
      local ok, err
      if is_dir then
        if recursive then
          ok, err = remove_tree(lfs, t)
        elseif dir_only then
          ok, err = lfs.rmdir(t)
        else
          common.err(NAME, "cannot remove '" .. t .. "': Is a directory")
          rc = 1
          ok = false
        end
      else
        ok, err = os.remove(t)
      end
      if not ok then
        if not force then
          common.err_path(NAME, t, err or "remove failed")
          rc = 1
        end
      elseif verbose then
        io.stdout:write(string.format("removed '%s'\n", t))
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = { "del", "erase" },
  help = "remove files or directories",
  main = main,
}
