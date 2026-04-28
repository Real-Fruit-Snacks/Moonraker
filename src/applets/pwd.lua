-- pwd: print name of current/working directory.
--
-- Phase 0 implementation: prefers lfs.currentdir() when LuaFileSystem is
-- available, falling back to the PWD env var, then to a popen("pwd"/"cd")
-- subprocess. The popen path is a stopgap; Phase 4 (filesystem applets)
-- will link LuaFileSystem via cdeps/ for a clean primitive.

local common = require("common")

local NAME = "pwd"

local function getcwd()
  local ok, lfs = pcall(require, "lfs")
  if ok and type(lfs) == "table" and type(lfs.currentdir) == "function" then
    local dir = lfs.currentdir()
    if dir and dir ~= "" then
      return dir
    end
  end

  local env_pwd = os.getenv("PWD")
  if env_pwd and env_pwd ~= "" then
    return env_pwd
  end

  -- Windows shells set %CD% to the current directory automatically.
  if common.is_windows() then
    local env_cd = os.getenv("CD")
    if env_cd and env_cd ~= "" then
      return env_cd
    end
  end

  local cmd = common.is_windows() and "cd" or "pwd"
  local pipe = io.popen(cmd)
  if pipe then
    local line = pipe:read("*l")
    pipe:close()
    if line and line ~= "" then
      return (line:gsub("[\r\n]+$", ""))
    end
  end

  return "."
end

local function main(argv)
  local physical = false

  for i = 1, #argv do
    local a = argv[i]
    if a == "-L" then
      physical = false
    elseif a == "-P" then
      physical = true
    elseif a == "--help" or a == "-h" then
      io.stdout:write("usage: pwd [-LP]\n")
      return 0
    else
      common.err(NAME, "invalid option: " .. a)
      return 2
    end
  end

  local cwd = getcwd()

  if physical then
    -- TODO(phase4): resolve symlinks once LuaFileSystem is linked. For now
    -- we return the same value as -L, which is correct on systems where
    -- the cwd was not reached via a symlink (the common case).
    io.stdout:write(cwd, "\n")
    return 0
  end

  local env_pwd = os.getenv("PWD")
  if env_pwd and env_pwd:match("^[/\\]") then
    io.stdout:write(env_pwd, "\n")
    return 0
  end
  io.stdout:write(cwd, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print name of current/working directory",
  main = main,
}
