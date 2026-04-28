-- uname: print system information.
--
-- We probe via the system `uname` command on POSIX (it's universally
-- available there). On Windows we synthesize fields from %OS%, %PROCESSOR_*%
-- and `ver`.

local common = require("common")

local NAME = "uname"

local function probe_posix(flag)
  local p = io.popen("uname " .. flag .. " 2>/dev/null")
  if not p then return nil end
  local line = p:read("*l")
  p:close()
  if line and line ~= "" then
    return (line:gsub("[\r\n]+$", ""))
  end
  return nil
end

local function field(ch)
  if common.is_windows() then
    if ch == "s" then return "Windows" end
    if ch == "n" then return os.getenv("COMPUTERNAME") or "unknown" end
    if ch == "r" or ch == "v" then
      local p = io.popen("ver 2>nul")
      if p then
        local out = p:read("*a")
        p:close()
        return (out or "unknown"):gsub("[\r\n]+$", "")
      end
      return "unknown"
    end
    if ch == "m" or ch == "p" or ch == "i" then
      return os.getenv("PROCESSOR_ARCHITECTURE") or "unknown"
    end
    if ch == "o" then return "Windows" end
    return "unknown"
  end
  local flag_map = {
    s = "-s", n = "-n", r = "-r", v = "-v",
    m = "-m", p = "-p", i = "-i", o = "-o",
  }
  return probe_posix(flag_map[ch]) or "unknown"
end

local function add(set, list, ch)
  if not set[ch] then
    set[ch] = true
    list[#list + 1] = ch
  end
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local seen = {}
  local wanted = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then break end
    if a == "-a" or a == "--all" then
      for ch in ("snrvmpio"):gmatch(".") do add(seen, wanted, ch) end
      i = i + 1
    elseif a == "--kernel-name" then add(seen, wanted, "s"); i = i + 1
    elseif a == "--nodename" then add(seen, wanted, "n"); i = i + 1
    elseif a == "--kernel-release" then add(seen, wanted, "r"); i = i + 1
    elseif a == "--kernel-version" then add(seen, wanted, "v"); i = i + 1
    elseif a == "--machine" then add(seen, wanted, "m"); i = i + 1
    elseif a == "--processor" then add(seen, wanted, "p"); i = i + 1
    elseif a == "--hardware-platform" then add(seen, wanted, "i"); i = i + 1
    elseif a == "--operating-system" then add(seen, wanted, "o"); i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
      if not a:sub(2):match("^[snrvmpioa]+$") then
        common.err(NAME, "invalid option: " .. a)
        return 2
      end
      for ch in a:sub(2):gmatch(".") do
        if ch == "a" then
          for c in ("snrvmpio"):gmatch(".") do add(seen, wanted, c) end
        else
          add(seen, wanted, ch)
        end
      end
      i = i + 1
    else
      break
    end
  end

  if #wanted == 0 then wanted = { "s" } end

  local parts = {}
  for _, ch in ipairs(wanted) do
    parts[#parts + 1] = field(ch)
  end
  io.stdout:write(table.concat(parts, " "), "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print system information",
  main = main,
}
