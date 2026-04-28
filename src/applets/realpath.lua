-- realpath: resolve a path to its canonical absolute form.
--
-- Lua/lfs have no built-in realpath. On POSIX we shell out to `readlink -f`
-- (universally available on modern systems). On Windows we approximate with
-- absolute path resolution via lfs.currentdir.

local common = require("common")

local NAME = "realpath"

local function abspath(p)
  local lfs = common.try_lfs()
  if not lfs then return p end
  -- Already absolute?
  if common.is_windows() then
    if p:match("^[A-Za-z]:[/\\]") or p:sub(1, 2) == "\\\\" then return p end
  else
    if p:sub(1, 1) == "/" then return p end
  end
  local cwd = lfs.currentdir() or "."
  return common.path_join(cwd, p)
end

local function readlink_f(p)
  if common.is_windows() then return abspath(p) end
  local quoted = "'" .. p:gsub("'", "'\\''") .. "'"
  local pipe = io.popen("readlink -f " .. quoted .. " 2>/dev/null")
  if not pipe then return abspath(p) end
  local line = pipe:read("*l")
  pipe:close()
  if line and line ~= "" then return (line:gsub("[\r\n]+$", "")) end
  return abspath(p)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local require_exist = false
  local no_symlink = false
  local zero = false
  local relative_to = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-e" or a == "--canonicalize-existing" then
      require_exist = true
      i = i + 1
    elseif a == "-m" or a == "--canonicalize-missing" then
      i = i + 1 -- accepted; readlink -f handles missing components
    elseif a == "-s" or a == "-L" or a == "--strip" or a == "--no-symlinks" then
      no_symlink = true
      i = i + 1
    elseif a == "-z" or a == "--zero" then
      zero = true
      i = i + 1
    elseif a == "--relative-to" and i + 1 <= #args then
      relative_to = args[i + 1]
      i = i + 2
    elseif a:sub(1, 14) == "--relative-to=" then
      relative_to = a:sub(15)
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  local paths = {}
  for j = i, #args do
    paths[#paths + 1] = args[j]
  end
  if #paths == 0 then
    common.err(NAME, "missing operand")
    return 2
  end

  local lfs = common.try_lfs()
  local endch = zero and "\0" or "\n"
  local rc = 0

  for _, p in ipairs(paths) do
    local result
    if no_symlink then
      result = abspath(p)
    else
      result = readlink_f(p)
    end
    if require_exist and lfs and not lfs.attributes(result) then
      common.err_path(NAME, p, "No such file or directory")
      rc = 1
    else
      if relative_to then
        -- Best-effort: strip prefix when result starts with relative_to.
        local base = readlink_f(relative_to)
        if base:sub(-1) ~= "/" then base = base .. "/" end
        if result:sub(1, #base) == base then result = result:sub(#base + 1) end
      end
      io.stdout:write(result, endch)
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "resolve a path to its canonical absolute form",
  main = main,
}
