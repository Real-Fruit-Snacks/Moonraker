-- basename: strip directory components from a filename.

local common = require("common")

local NAME = "basename"

local function rstrip_seps(s)
  return (s:gsub("[/\\]+$", ""))
end

local function basename_str(s)
  local stripped = rstrip_seps(s)
  if stripped == "" then return s ~= "" and s:sub(1, 1) or "" end
  -- Find the last separator (either / or \) by scanning right-to-left.
  local last = 0
  for i = #stripped, 1, -1 do
    local ch = stripped:sub(i, i)
    if ch == "/" or ch == "\\" then
      last = i
      break
    end
  end
  if last > 0 then return stripped:sub(last + 1) end
  return stripped
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local multiple = false
  local suffix_all = nil
  local zero = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-a" or a == "--multiple" then
      multiple = true
      i = i + 1
    elseif a == "-s" and i + 1 <= #args then
      suffix_all = args[i + 1]
      multiple = true
      i = i + 2
    elseif a:sub(1, 9) == "--suffix=" then
      suffix_all = a:sub(10)
      multiple = true
      i = i + 1
    elseif a == "-z" or a == "--zero" then
      zero = true
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  local remaining = {}
  for j = i, #args do
    remaining[#remaining + 1] = args[j]
  end
  if #remaining == 0 then
    common.err(NAME, "missing operand")
    return 2
  end

  local endch = zero and "\0" or "\n"
  local paths, suffix
  if multiple then
    paths = remaining
    suffix = suffix_all or ""
  else
    paths = { remaining[1] }
    suffix = remaining[2] or ""
  end

  for _, p in ipairs(paths) do
    local name = basename_str(p)
    if suffix ~= "" and name ~= suffix and name:sub(-#suffix) == suffix then name = name:sub(1, -(#suffix + 1)) end
    io.stdout:write(name, endch)
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "strip directory components from a filename",
  main = main,
}
