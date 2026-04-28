-- id: print user and group IDs.
--
-- Lua has no pwd/grp bindings. We shell out to system `id` (POSIX) or
-- `whoami` (Windows). The full uid/gid output requires `id`; on Windows
-- we report what we can.

local common = require("common")

local NAME = "id"

local function probe(cmd)
  local p = io.popen(cmd .. " 2>" .. (common.is_windows() and "nul" or "/dev/null"))
  if not p then return nil end
  local line = p:read("*l")
  p:close()
  if line and line ~= "" then return (line:gsub("[\r\n]+$", "")) end
  return nil
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local show_user = false
  local show_group = false
  local show_all_groups = false
  local name_only = false
  local user_arg = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-u" or a == "--user" then
      show_user = true
      i = i + 1
    elseif a == "-g" or a == "--group" then
      show_group = true
      i = i + 1
    elseif a == "-G" or a == "--groups" then
      show_all_groups = true
      i = i + 1
    elseif a == "-n" or a == "--name" then
      name_only = true
      i = i + 1
    elseif a == "-r" or a == "--real" then
      i = i + 1 -- accepted, no-op
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if user_arg ~= nil then
        common.err(NAME, "extra operand")
        return 2
      end
      user_arg = a
      i = i + 1
    end
  end

  if common.is_windows() then
    local username = user_arg or os.getenv("USERNAME") or os.getenv("USER") or "?"
    if show_user then
      io.stdout:write(name_only and username or "0", "\n")
      return 0
    end
    if show_group or show_all_groups then
      io.stdout:write("?\n")
      return 0
    end
    io.stdout:write(string.format("uid=?(%s) gid=? groups=?\n", username))
    return 0
  end

  -- POSIX: shell out to `id`.
  local cmd = "id"
  if user_arg then cmd = cmd .. " " .. user_arg:gsub('"', '\\"') end
  if show_user then
    cmd = cmd .. (name_only and " -un" or " -u")
  elseif show_group then
    cmd = cmd .. (name_only and " -gn" or " -g")
  elseif show_all_groups then
    cmd = cmd .. (name_only and " -Gn" or " -G")
  end

  local result = probe(cmd)
  if not result then
    common.err(NAME, "no such user")
    return 1
  end
  io.stdout:write(result, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print user and group IDs",
  main = main,
}
