-- nl: number lines of files.

local common = require("common")

local NAME = "nl"

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local width = 6
  local sep = "\t"
  local start = 1
  local increment = 1
  local body_style = "t" -- t=non-empty, a=all, n=none

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if (a == "-b" or a == "--body-numbering") and i + 1 <= #args then
      body_style = args[i + 1]
      if body_style ~= "a" and body_style ~= "t" and body_style ~= "n" then
        common.err(NAME, "invalid body-numbering style: " .. body_style)
        return 2
      end
      i = i + 2
    elseif (a == "-w" or a == "--number-width") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid width: " .. args[i + 1])
        return 2
      end
      width = n
      i = i + 2
    elseif (a == "-s" or a == "--number-separator") and i + 1 <= #args then
      sep = args[i + 1]
      i = i + 2
    elseif (a == "-v" or a == "--starting-line-number") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid starting line: " .. args[i + 1])
        return 2
      end
      start = n
      i = i + 2
    elseif (a == "-i" or a == "--line-increment") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid increment: " .. args[i + 1])
        return 2
      end
      increment = n
      i = i + 2
    elseif a == "-ba" then
      body_style = "a"
      i = i + 1
    elseif a == "-bt" then
      body_style = "t"
      i = i + 1
    elseif a == "-bn" then
      body_style = "n"
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local files = {}
  for j = i, #args do
    files[#files + 1] = args[j]
  end
  if #files == 0 then files = { "-" } end

  local n = start
  local rc = 0

  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local stripped = line:gsub("[\r\n]+$", "")
        local emit = true
        if body_style == "n" then
          emit = false
        elseif body_style == "t" and stripped == "" then
          emit = false
        end
        if emit then
          io.stdout:write(string.format("%" .. width .. "d%s%s\n", n, sep, stripped))
          n = n + increment
        else
          io.stdout:write(stripped, "\n")
        end
      end
      if f ~= "-" then fh:close() end
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "number lines of files",
  main = main,
}
