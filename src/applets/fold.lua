-- fold: wrap each input line to fit a width.

local common = require("common")

local NAME = "fold"

local function emit_wrapped(line, width, space_break)
  while #line > width do
    local cut = width
    if space_break then
      -- last space at or before width+1 (1-indexed)
      local idx = nil
      for k = width + 1, 1, -1 do
        if line:sub(k, k) == " " then
          idx = k
          break
        end
      end
      if idx and idx > 1 then
        cut = idx
      end
    end
    io.stdout:write(line:sub(1, cut), "\n")
    line = line:sub(cut + 1)
  end
  io.stdout:write(line)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local width = 80
  local space_break = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if (a == "-w" or a == "--width") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n or n < 1 then
        common.err(NAME, "invalid width: " .. args[i + 1])
        return 2
      end
      width = n
      i = i + 2
    elseif a:sub(1, 2) == "-w" and #a > 2 then
      local n = common.parse_int(a:sub(3))
      if not n or n < 1 then
        common.err(NAME, "invalid width: " .. a:sub(3))
        return 2
      end
      width = n
      i = i + 1
    elseif a == "-s" or a == "--spaces" then
      space_break = true
      i = i + 1
    elseif a == "-b" or a == "--bytes" then
      -- accepted for compat; we always operate byte-wise
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      width = tonumber(a:sub(2))
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
  if #files == 0 then
    files = { "-" }
  end
  local rc = 0

  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local body, nl
        if line:sub(-2) == "\r\n" then
          body, nl = line:sub(1, -3), "\r\n"
        elseif line:sub(-1) == "\n" then
          body, nl = line:sub(1, -2), "\n"
        else
          body, nl = line, ""
        end
        emit_wrapped(body, width, space_break)
        io.stdout:write(nl)
      end
      if f ~= "-" then
        fh:close()
      end
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "wrap each input line to fit a width",
  main = main,
}
