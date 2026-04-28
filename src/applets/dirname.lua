-- dirname: strip the last component from a file name.

local common = require("common")

local NAME = "dirname"

local function rstrip_seps(s)
  return (s:gsub("[/\\]+$", ""))
end

local function dirname_str(s)
  local stripped = rstrip_seps(s)
  if stripped == "" then
    return s ~= "" and s or "."
  end
  local last = 0
  for i = #stripped, 1, -1 do
    local ch = stripped:sub(i, i)
    if ch == "/" or ch == "\\" then
      last = i
      break
    end
  end
  if last == 0 then
    return "."
  end
  if last == 1 then
    return stripped:sub(1, 1)
  end
  return stripped:sub(1, last - 1)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local zero = false
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-z" or a == "--zero" then
      zero = true
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

  local endch = zero and "\0" or "\n"
  for _, p in ipairs(paths) do
    io.stdout:write(dirname_str(p), endch)
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "strip last component from file name",
  main = main,
}
