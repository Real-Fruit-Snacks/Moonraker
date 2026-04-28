-- whoami: print the effective user name.

local common = require("common")

local NAME = "whoami"

--- Best-effort user detection across platforms. Order: USER, LOGNAME,
--- USERNAME, then `whoami` / `id -un` subprocesses.
local function get_user()
  local env = os.getenv("USER") or os.getenv("LOGNAME") or os.getenv("USERNAME")
  if env and env ~= "" then return env end
  local cmd = common.is_windows() and "echo %USERNAME%" or "id -un 2>/dev/null"
  local p = io.popen(cmd)
  if p then
    local line = p:read("*l")
    p:close()
    if line and line ~= "" then return (line:gsub("[\r\n]+$", "")) end
  end
  return nil
end

local function main(_argv)
  local user = get_user()
  if not user then
    common.err(NAME, "could not determine current user")
    return 1
  end
  io.stdout:write(user, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print effective user name",
  main = main,
}
