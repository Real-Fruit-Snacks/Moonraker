-- env: run a program in a modified environment, or print the environment.
--
-- Lua's stdlib has no execve. We shell out via os.execute, prefixing env
-- variables in shell-native syntax. POSIX uses `KEY=val cmd args`; Windows
-- uses `set "KEY=val" && cmd args`.

local common = require("common")

local NAME = "env"

local function shell_quote_posix(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function shell_quote_cmd(s)
  return '"' .. s:gsub('"', '\\"') .. '"'
end

local function read_environ()
  -- Lua has no native way to enumerate the environment. Shell out.
  if common.is_windows() then
    local out = {}
    local p = io.popen("set 2>nul")
    if p then
      for line in p:lines() do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then out[k] = v end
      end
      p:close()
    end
    return out
  end
  local out = {}
  -- `printenv -0` separates with NUL — robust for values containing newlines
  -- but Lua's lines() doesn't split on NUL. Use printenv with newline parsing
  -- as a best effort.
  local p = io.popen("env 2>/dev/null")
  if p then
    for line in p:lines() do
      local k, v = line:match("^([^=]+)=(.*)$")
      if k then out[k] = v end
    end
    p:close()
  end
  return out
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local ignore_env = false
  local unsets = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    end
    if a == "-i" or a == "--ignore-environment" then
      ignore_env = true
      i = i + 1
    elseif (a == "-u" or a == "--unset") and i + 1 <= #args then
      unsets[#unsets + 1] = args[i + 1]
      i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 and a:sub(1, 2) ~= "--" then
      for ch in a:sub(2):gmatch(".") do
        if ch == "i" then ignore_env = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    else
      break
    end
  end

  local env = ignore_env and {} or read_environ()
  for _, u in ipairs(unsets) do
    env[u] = nil
  end

  -- KEY=val pairs before the command
  while i <= #args and args[i]:find("=", 1, true) and args[i]:sub(1, 1) ~= "=" do
    local k, v = args[i]:match("^([^=]+)=(.*)$")
    env[k] = v
    i = i + 1
  end

  local remaining = {}
  for j = i, #args do remaining[#remaining + 1] = args[j] end
  if #remaining == 0 then
    -- Print the (possibly modified) environment
    local keys = {}
    for k in pairs(env) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      io.stdout:write(k, "=", env[k], "\n")
    end
    return 0
  end

  -- Build shell command
  local parts = {}
  if common.is_windows() then
    -- cmd: set "K=V" && cmd args
    for k, v in pairs(env) do
      parts[#parts + 1] = string.format('set "%s=%s"', k, v)
    end
    local cmd_parts = {}
    for _, a in ipairs(remaining) do
      cmd_parts[#cmd_parts + 1] = shell_quote_cmd(a)
    end
    parts[#parts + 1] = table.concat(cmd_parts, " ")
    local cmd = table.concat(parts, " && ")
    local _, _, code = os.execute(cmd)
    return tonumber(code) or 0
  else
    -- POSIX: env -i K=V ... cmd args (use real env binary if ignore_env, else inline)
    local prefix = {}
    if ignore_env then
      prefix[#prefix + 1] = "env -i"
    end
    for k, v in pairs(env) do
      prefix[#prefix + 1] = string.format("%s=%s", k, shell_quote_posix(v))
    end
    local cmd_parts = {}
    for _, a in ipairs(remaining) do
      cmd_parts[#cmd_parts + 1] = shell_quote_posix(a)
    end
    local cmd = table.concat(prefix, " ") .. " " .. table.concat(cmd_parts, " ")
    local ok, _, code = os.execute(cmd)
    if ok == true then return 0 end
    return tonumber(code) or 1
  end
end

return {
  name = NAME,
  aliases = {},
  help = "run a program in a modified environment, or print the environment",
  main = main,
}
