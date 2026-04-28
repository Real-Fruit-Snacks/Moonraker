-- hostname: show the system's hostname.

local common = require("common")

local NAME = "hostname"

local function read_hostname()
  -- Try $HOSTNAME first (set by most shells), then `hostname` / `uname -n`.
  local env = os.getenv("HOSTNAME") or os.getenv("COMPUTERNAME")
  if env and env ~= "" then
    return env
  end
  local cmds = common.is_windows() and { "hostname" } or { "hostname", "uname -n" }
  for _, cmd in ipairs(cmds) do
    local p = io.popen(cmd .. " 2>" .. (common.is_windows() and "nul" or "/dev/null"))
    if p then
      local line = p:read("*l")
      p:close()
      if line and line ~= "" then
        return (line:gsub("[\r\n]+$", ""))
      end
    end
  end
  return nil
end

local function main(argv)
  local short, full = false, false

  for i = 1, #argv do
    local a = argv[i]
    if a == "-s" or a == "--short" then
      short = true
    elseif a == "-f" or a == "--fqdn" or a == "--long" then
      full = true
    elseif a:sub(1, 1) == "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      common.err(NAME, "setting hostname is not supported")
      return 2
    end
  end

  local host = read_hostname()
  if not host then
    common.err(NAME, "could not determine hostname")
    return 1
  end

  if short then
    host = host:match("^[^.]*") or host
  elseif full then
    -- Best-effort FQDN: if the host already has dots, return as-is. Otherwise
    -- try `hostname -f` (Linux) or fall back to the bare name.
    if not host:find(".", 1, true) and not common.is_windows() then
      local p = io.popen("hostname -f 2>/dev/null")
      if p then
        local f = p:read("*l")
        p:close()
        if f and f ~= "" then
          host = (f:gsub("[\r\n]+$", ""))
        end
      end
    end
  end

  io.stdout:write(host, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "show the system's hostname",
  main = main,
}
