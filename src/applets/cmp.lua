-- cmp: compare two files byte by byte.

local common = require("common")

local NAME = "cmp"

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local silent = false
  local print_chars = false
  local print_all = false
  local skip1, skip2 = 0, 0
  local bytes_limit = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-s" or a == "--quiet" or a == "--silent" then
      silent = true
      i = i + 1
    elseif a == "-b" or a == "--print-bytes" then
      print_chars = true
      i = i + 1
    elseif a == "-l" or a == "--verbose" then
      print_all = true
      i = i + 1
    elseif (a == "-n" or a == "--bytes") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid byte count: " .. args[i + 1])
        return 2
      end
      bytes_limit = n
      i = i + 2
    elseif a == "-i" and i + 1 <= #args then
      local spec = args[i + 1]
      if spec:find(":", 1, true) then
        local a1, a2 = spec:match("^(%-?%d+):(%-?%d+)$")
        if not a1 then
          common.err(NAME, "invalid skip: " .. spec)
          return 2
        end
        skip1, skip2 = tonumber(a1), tonumber(a2)
      else
        local n = common.parse_int(spec)
        if not n then
          common.err(NAME, "invalid skip: " .. spec)
          return 2
        end
        skip1, skip2 = n, n
      end
      i = i + 2
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
  if #rest < 2 then
    common.err(NAME, "missing operand")
    return 2
  end
  local f1, f2 = rest[1], rest[2]
  if rest[3] then
    skip1 = common.parse_int(rest[3]) or skip1
  end
  if rest[4] then
    skip2 = common.parse_int(rest[4]) or skip2
  end

  local h1, e1 = common.open_input(f1, "rb")
  if not h1 then
    common.err_path(NAME, f1, e1)
    return 2
  end
  local h2, e2 = common.open_input(f2, "rb")
  if not h2 then
    common.err_path(NAME, f2, e2)
    if f1 ~= "-" then h1:close() end
    return 2
  end

  if skip1 > 0 then h1:read(skip1) end
  if skip2 > 0 then h2:read(skip2) end

  local offset = 0
  local lineno = 1
  local differ = false

  while true do
    if bytes_limit and offset >= bytes_limit then
      break
    end
    local b1 = h1:read(1)
    local b2 = h2:read(1)
    if (b1 == nil or b1 == "") and (b2 == nil or b2 == "") then
      break
    end
    if b1 == nil or b1 == "" then
      if not silent then
        common.err(NAME, string.format("EOF on %s after byte %d", f1, offset))
      end
      if f1 ~= "-" then h1:close() end
      if f2 ~= "-" then h2:close() end
      return 1
    end
    if b2 == nil or b2 == "" then
      if not silent then
        common.err(NAME, string.format("EOF on %s after byte %d", f2, offset))
      end
      if f1 ~= "-" then h1:close() end
      if f2 ~= "-" then h2:close() end
      return 1
    end
    if b1 ~= b2 then
      differ = true
      if silent then
        if f1 ~= "-" then h1:close() end
        if f2 ~= "-" then h2:close() end
        return 1
      end
      if print_all then
        io.stdout:write(string.format("%d %3o %3o\n", offset + 1, b1:byte(), b2:byte()))
      else
        if print_chars then
          local function safe(b)
            return (b >= 32 and b < 127) and string.char(b) or "."
          end
          io.stdout:write(string.format(
            "%s %s differ: byte %d, line %d is %3o %s %3o %s\n",
            f1, f2, offset + 1, lineno,
            b1:byte(), safe(b1:byte()), b2:byte(), safe(b2:byte())
          ))
        else
          io.stdout:write(string.format(
            "%s %s differ: byte %d, line %d\n", f1, f2, offset + 1, lineno
          ))
        end
        if f1 ~= "-" then h1:close() end
        if f2 ~= "-" then h2:close() end
        return 1
      end
    end
    if b1 == "\n" then lineno = lineno + 1 end
    offset = offset + 1
  end
  if f1 ~= "-" then h1:close() end
  if f2 ~= "-" then h2:close() end
  if differ and print_all then
    return 1
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "compare two files byte by byte",
  main = main,
}
