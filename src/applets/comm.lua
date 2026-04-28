-- comm: compare two sorted files line by line.

local common = require("common")

local NAME = "comm"

local function rstrip_nl(s)
  return (s:gsub("[\r\n]+$", ""))
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local suppress = { false, false, false }
  local sep = "\t"
  local check_order = true

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) == "-" and #a >= 2 and a:sub(2):match("^[123]+$") then
      for ch in a:sub(2):gmatch(".") do
        suppress[tonumber(ch)] = true
      end
      i = i + 1
    elseif a == "--nocheck-order" then
      check_order = false
      i = i + 1
    elseif a == "--check-order" then
      check_order = true
      i = i + 1
    elseif a == "--output-delimiter" and i + 1 <= #args then
      sep = args[i + 1]
      i = i + 2
    elseif a:sub(1, 19) == "--output-delimiter=" then
      sep = a:sub(20)
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local rest = {}
  for j = i, #args do
    rest[#rest + 1] = args[j]
  end
  if #rest ~= 2 then
    common.err(NAME, "two file operands required")
    return 2
  end
  local f1, f2 = rest[1], rest[2]

  local h1, e1 = common.open_input(f1, "rb")
  if not h1 then
    common.err_path(NAME, f1, e1)
    return 1
  end
  local h2, e2 = common.open_input(f2, "rb")
  if not h2 then
    common.err_path(NAME, f2, e2)
    if f1 ~= "-" then h1:close() end
    return 1
  end

  local iter1 = common.iter_lines_keep_nl(h1)
  local iter2 = common.iter_lines_keep_nl(h2)
  local function readline(it)
    local ln = it()
    if not ln then return nil end
    return rstrip_nl(ln)
  end

  local rc = 0
  local a_line = readline(iter1)
  local b_line = readline(iter2)
  local prev_a, prev_b = nil, nil

  while a_line ~= nil or b_line ~= nil do
    if check_order then
      if prev_a and a_line and a_line < prev_a then
        common.err(NAME, "file 1 is not in sorted order")
        rc = 1
      end
      if prev_b and b_line and b_line < prev_b then
        common.err(NAME, "file 2 is not in sorted order")
        rc = 1
      end
    end
    local col, line
    if a_line == nil then
      col, line = 2, b_line
      prev_b = b_line
      b_line = readline(iter2)
    elseif b_line == nil then
      col, line = 1, a_line
      prev_a = a_line
      a_line = readline(iter1)
    elseif a_line == b_line then
      col, line = 3, a_line
      prev_a, prev_b = a_line, b_line
      a_line = readline(iter1)
      b_line = readline(iter2)
    elseif a_line < b_line then
      col, line = 1, a_line
      prev_a = a_line
      a_line = readline(iter1)
    else
      col, line = 2, b_line
      prev_b = b_line
      b_line = readline(iter2)
    end
    if not suppress[col] then
      local indent = 0
      for c = 1, col - 1 do
        if not suppress[c] then indent = indent + 1 end
      end
      io.stdout:write(string.rep(sep, indent), line, "\n")
    end
  end

  if f1 ~= "-" then h1:close() end
  if f2 ~= "-" then h2:close() end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "compare two sorted files line by line",
  main = main,
}
