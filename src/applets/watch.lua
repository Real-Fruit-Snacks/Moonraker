-- watch: re-run a command periodically and redraw output.
--
-- Pure Lua port of mainsail's watch.py. The Lua stdlib has no monotonic
-- clock or sub-second sleep, so we use os.time() (1s resolution) for the
-- elapsed check and shell out to `sleep` (POSIX) or PowerShell
-- Start-Sleep (Windows) for the inter-cycle pause.
--
-- Limitations vs the Python version:
--   * --precise drift compensation rounds to whole seconds.
--   * Ctrl-C is delivered to whichever process is in the foreground; on
--     Windows the child command may swallow SIGINT before we see it.

local common = require("common")

local NAME = "watch"

local function clear_screen(out)
  out:write("\27[2J\27[H")
end

local function format_now()
  return os.date("%a %b %d %H:%M:%S %Y")
end

local function shell_quote(s)
  if common.is_windows() then return '"' .. s:gsub('"', '\\"') .. '"' end
  if s:match("^[%w@%%+=:,./-]+$") then return s end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run_capture(cmd_args, exec_via_shell)
  -- Run the command, capture stdout+stderr together. Returns (output, ok).
  local cmdline
  if exec_via_shell and #cmd_args == 1 then
    cmdline = cmd_args[1]
  else
    local parts = {}
    for i = 1, #cmd_args do
      parts[i] = shell_quote(cmd_args[i])
    end
    cmdline = table.concat(parts, " ")
  end
  -- Merge stderr into stdout. Lua's io.popen only captures stdout;
  -- we use shell redirection to fold stderr in.
  local merged
  if common.is_windows() then
    merged = cmdline .. " 2>&1"
  else
    merged = cmdline .. " 2>&1"
  end
  local p = io.popen(merged, "r")
  if not p then return "watch: command failed to start\n", false end
  local out = p:read("*a") or ""
  p:close()
  return out, true
end

local function term_cols()
  if common.is_windows() then
    -- PowerShell: $Host.UI.RawUI.WindowSize.Width — too heavy. Default 80.
    return 80
  end
  local p = io.popen("tput cols 2>/dev/null")
  if p then
    local line = p:read("*l")
    p:close()
    local n = tonumber(line)
    if n and n > 0 then return n end
  end
  local cols = tonumber(os.getenv("COLUMNS") or "")
  return cols or 80
end

local function sleep_seconds(secs)
  if secs <= 0 then return end
  if common.is_windows() then
    os.execute(string.format('powershell -NoProfile -Command "Start-Sleep -Milliseconds %d"', math.floor(secs * 1000)))
  else
    os.execute(string.format("sleep %g", secs))
  end
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local interval = 2.0
  local no_title = false
  local exec_via_shell = true
  local exit_on_change = false
  local beep_on_change = false
  local precise = false
  local max_cycles = nil -- test hook

  local i = 1
  while i <= #args do
    local a = args[i]
    if (a == "-n" or a == "--interval") and args[i + 1] then
      local n = tonumber(args[i + 1])
      if not n then
        common.err(NAME, "invalid interval: " .. args[i + 1])
        return 2
      end
      if n < 0.1 then n = 0.1 end
      interval = n
      i = i + 2
    elseif a:sub(1, 2) == "-n" and #a > 2 then
      local n = tonumber(a:sub(3))
      if not n then
        common.err(NAME, "invalid interval: " .. a:sub(3))
        return 2
      end
      if n < 0.1 then n = 0.1 end
      interval = n
      i = i + 1
    elseif a == "-t" or a == "--no-title" then
      no_title = true
      i = i + 1
    elseif a == "-x" or a == "--exec" then
      exec_via_shell = false
      i = i + 1
    elseif a == "-g" or a == "--chgexit" then
      exit_on_change = true
      i = i + 1
    elseif a == "-b" or a == "--beep" then
      beep_on_change = true
      i = i + 1
    elseif a == "-p" or a == "--precise" then
      precise = true
      i = i + 1
    elseif a == "--max-cycles" and args[i + 1] then
      max_cycles = tonumber(args[i + 1])
      i = i + 2
    elseif a == "--" then
      i = i + 1
      break
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local cmd = {}
  for j = i, #args do
    cmd[#cmd + 1] = args[j]
  end
  if #cmd == 0 then
    common.err(NAME, "no command given")
    return 2
  end

  local cmd_display = table.concat(cmd, " ")
  local last_output = nil
  local cycle = 0

  while true do
    cycle = cycle + 1
    local cycle_start = os.time()
    local now = format_now()

    local output = run_capture(cmd, exec_via_shell)

    clear_screen(io.stdout)
    if not no_title then
      local left = string.format("Every %gs: %s", interval, cmd_display)
      local right = now
      local cols = term_cols()
      local gap = math.max(1, cols - #left - #right)
      if #left + gap + #right > cols then
        local cap = cols - #right - 4
        if cap > 0 then left = left:sub(1, cap) .. "..." end
        gap = math.max(1, cols - #left - #right)
      end
      io.stdout:write(left, string.rep(" ", gap), right, "\n\n")
    end
    io.stdout:write(output)
    io.stdout:flush()

    if last_output ~= nil and last_output ~= output then
      if beep_on_change then
        io.stdout:write("\7")
        io.stdout:flush()
      end
      if exit_on_change then return 0 end
    end
    last_output = output

    if max_cycles and cycle >= max_cycles then return 0 end

    local elapsed = os.difftime(os.time(), cycle_start)
    local nap = interval - (precise and elapsed or 0)
    if nap > 0 then sleep_seconds(nap) end
  end
end

return {
  name = NAME,
  aliases = {},
  help = "execute a command periodically, showing output",
  main = main,
}
