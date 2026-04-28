-- mkdir: make directories.

local common = require("common")

local NAME = "mkdir"

--- Recursively mkdir using lfs. Returns true or (false, errmsg).
local function mkdir_p(lfs, path)
  if path == "" or path == "." or path == "/" then return true end
  local attr = lfs.attributes(path)
  if attr and attr.mode == "directory" then return true end
  if attr then return false, "exists and is not a directory" end
  -- Recurse into parent
  local parent = path:match("^(.*)[/\\][^/\\]+$")
  if parent and parent ~= "" and parent ~= path then
    local ok, err = mkdir_p(lfs, parent)
    if not ok then return false, err end
  end
  return lfs.mkdir(path)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local parents = false
  local verbose = false
  local mode = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-m" and i + 1 <= #args then
      local n = tonumber(args[i + 1], 8)
      if not n then
        common.err(NAME, "invalid mode: '" .. args[i + 1] .. "'")
        return 2
      end
      mode = n
      i = i + 2
    elseif a:sub(1, 7) == "--mode=" then
      local n = tonumber(a:sub(8), 8)
      if not n then
        common.err(NAME, "invalid mode: '" .. a:sub(8) .. "'")
        return 2
      end
      mode = n
      i = i + 1
    elseif a:sub(1, 1) ~= "-" or #a < 2 then
      break
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "p" then
          parents = true
        elseif ch == "v" then
          verbose = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    end
  end

  local dirs = {}
  for j = i, #args do
    dirs[#dirs + 1] = args[j]
  end
  if #dirs == 0 then
    common.err(NAME, "missing operand")
    return 2
  end

  local lfs = common.try_lfs()
  if not lfs then
    common.err(NAME, "luafilesystem required for mkdir")
    return 1
  end

  local rc = 0
  for _, d in ipairs(dirs) do
    local ok, err
    if parents then
      ok, err = mkdir_p(lfs, d)
    else
      ok, err = lfs.mkdir(d)
    end
    if not ok then
      common.err_path(NAME, d, err or "mkdir failed")
      rc = 1
    else
      if mode and lfs.touch then
        -- lfs has no chmod; the C function chmod(2) is the right call.
        -- Best-effort via os.execute on POSIX. Windows ignores file mode bits.
        if not common.is_windows() then os.execute(string.format('chmod %o "%s"', mode, d)) end
      end
      if verbose then io.stdout:write(string.format("mkdir: created directory '%s'\n", d)) end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = { "md" },
  help = "make directories",
  main = main,
}
