-- ln: create links between files.
--
-- lfs.link(target, link, [symlink]) handles both hard and symbolic links
-- where supported. On Windows symlinks need admin privileges; we surface
-- the underlying error rather than silently failing.

local common = require("common")

local NAME = "ln"

local function exists_or_link(path)
  local lfs = common.try_lfs()
  if lfs then return lfs.symlinkattributes(path) ~= nil end
  local fh = io.open(path, "rb")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function is_directory(path)
  local lfs = common.try_lfs()
  local attr = lfs and lfs.attributes(path)
  return attr ~= nil and attr.mode == "directory"
end

local function make_link(target, link, symbolic)
  local lfs = common.try_lfs()
  if not lfs or not lfs.link then return false, "luafilesystem does not support link()" end
  return lfs.link(target, link, symbolic)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local symbolic = false
  local force = false
  local verbose = false
  local no_target_dir = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 or a == "-" then break end
    if not a:sub(2):match("^[sfvrT]+$") then
      common.err(NAME, "invalid option: " .. a)
      return 2
    end
    for ch in a:sub(2):gmatch(".") do
      if ch == "s" then
        symbolic = true
      elseif ch == "f" then
        force = true
      elseif ch == "v" then
        verbose = true
      elseif ch == "r" then
        -- `-r` (relative target) is accepted but doesn't currently rewrite
        -- the target — proper computation needs absolute path resolution
        -- that lfs alone doesn't expose. TODO(phase4+).
        symbolic = true
      elseif ch == "T" then
        no_target_dir = true
      end
    end
    i = i + 1
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  if #positional == 0 then
    common.err(NAME, "missing operand")
    return 2
  end

  -- Build (target, link) pairs
  local pairs_list = {}
  if #positional == 1 then
    local target = positional[1]
    pairs_list[#pairs_list + 1] = { target, common.basename(target) }
  elseif #positional == 2 and (no_target_dir or not is_directory(positional[2])) then
    pairs_list[#pairs_list + 1] = { positional[1], positional[2] }
  else
    local dest_dir = positional[#positional]
    if not is_directory(dest_dir) then
      common.err(NAME, "target '" .. dest_dir .. "' is not a directory")
      return 1
    end
    for j = 1, #positional - 1 do
      local target = positional[j]
      pairs_list[#pairs_list + 1] = { target, common.path_join(dest_dir, common.basename(target)) }
    end
  end

  --- Create one link. Returns true on success, false on error.
  local function make_one(target, link)
    if exists_or_link(link) then
      if force then
        local ok, err = os.remove(link)
        if not ok then
          common.err_path(NAME, link, err or "could not unlink")
          return false
        end
      else
        common.err(NAME, string.format("failed to create link '%s': File exists", link))
        return false
      end
    end
    -- Note: relative-target computation for `-r` requires absolute path
    -- resolution that lfs alone doesn't expose cleanly. TODO(phase4+).
    local ok, err = make_link(target, link, symbolic)
    if not ok then
      common.err_path(NAME, link, err or "link failed")
      return false
    end
    if verbose then
      local arrow = symbolic and " -> " or " => "
      io.stdout:write(string.format("'%s'%s'%s'\n", link, arrow, target))
    end
    return true
  end

  local rc = 0
  for _, pair in ipairs(pairs_list) do
    if not make_one(pair[1], pair[2]) then rc = 1 end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "create links between files",
  main = main,
}
