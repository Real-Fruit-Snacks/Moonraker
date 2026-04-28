-- stat: display file or filesystem status.

local common = require("common")

local NAME = "stat"

local function type_string(attr)
  if not attr then return "unknown" end
  local m = attr.mode
  if m == "file" then return "regular file" end
  if m == "directory" then return "directory" end
  if m == "link" then return "symbolic link" end
  if m == "char device" then return "character special file" end
  if m == "block device" then return "block special file" end
  if m == "named pipe" then return "fifo" end
  if m == "socket" then return "socket" end
  return "unknown"
end

local function filemode(attr)
  -- Build an `ls -l`-style mode string from lfs attr. lfs gives us
  -- attr.permissions as a string like "rwxr-xr-x"; just need to prepend
  -- the type letter.
  local type_char = "-"
  local m = attr.mode
  if m == "directory" then
    type_char = "d"
  elseif m == "link" then
    type_char = "l"
  elseif m == "char device" then
    type_char = "c"
  elseif m == "block device" then
    type_char = "b"
  elseif m == "named pipe" then
    type_char = "p"
  elseif m == "socket" then
    type_char = "s"
  end
  return type_char .. (attr.permissions or "?????????")
end

local function format_time(ts)
  return os.date("%Y-%m-%d %H:%M:%S", ts)
end

local function permissions_octal(attr)
  if not attr.permissions then return 0 end
  local p = attr.permissions
  local function bit(c, b)
    return (p:sub(c, c) ~= "-") and b or 0
  end
  return bit(1, 256)
    + bit(2, 128)
    + bit(3, 64)
    + bit(4, 32)
    + bit(5, 16)
    + bit(6, 8)
    + bit(7, 4)
    + bit(8, 2)
    + bit(9, 1)
end

local function default_output(path, attr)
  local size = attr.size or 0
  local mode_oct = permissions_octal(attr)
  local mode_str = filemode(attr)
  local lines = {
    string.format("  File: %s", path),
    string.format("  Size: %-12d  Type: %s", size, type_string(attr)),
    string.format("  Mode: (%04o/%s)  Uid: (%4d)  Gid: (%4d)", mode_oct, mode_str, attr.uid or 0, attr.gid or 0),
    string.format("Access: %s", format_time(attr.access or 0)),
    string.format("Modify: %s", format_time(attr.modification or 0)),
    string.format("Change: %s", format_time(attr.change or 0)),
  }
  return table.concat(lines, "\n")
end

local function apply_format(path, attr, fmt)
  local repl = {
    n = path,
    s = tostring(attr.size or 0),
    a = string.format("%o", permissions_octal(attr)),
    A = filemode(attr),
    u = tostring(attr.uid or 0),
    g = tostring(attr.gid or 0),
    F = type_string(attr),
    Y = tostring(math.floor(attr.modification or 0)),
    X = tostring(math.floor(attr.access or 0)),
    Z = tostring(math.floor(attr.change or 0)),
    y = format_time(attr.modification or 0),
    x = format_time(attr.access or 0),
    z = format_time(attr.change or 0),
    h = tostring(attr.nlink or 0),
    i = tostring(attr.ino or 0),
    ["%"] = "%",
  }
  local out = {}
  local i = 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c == "%" and i + 1 <= #fmt then
      local key = fmt:sub(i + 1, i + 1)
      if repl[key] then
        out[#out + 1] = repl[key]
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    elseif c == "\\" and i + 1 <= #fmt then
      local esc = ({ n = "\n", t = "\t", ["\\"] = "\\", r = "\r" })[fmt:sub(i + 1, i + 1)]
      if esc then
        out[#out + 1] = esc
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local fmt = nil
  local terse = false
  local dereference = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-c" and i + 1 <= #args then
      fmt = args[i + 1]
      i = i + 2
    elseif a:sub(1, 9) == "--format=" then
      fmt = a:sub(10)
      i = i + 1
    elseif a == "-t" or a == "--terse" then
      terse = true
      i = i + 1
    elseif a == "-L" or a == "--dereference" then
      dereference = true
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

  local lfs = common.try_lfs()
  if not lfs then
    common.err(NAME, "luafilesystem required")
    return 1
  end

  local rc = 0
  for _, path in ipairs(paths) do
    local attr
    if dereference then
      attr = lfs.attributes(path)
    else
      attr = lfs.symlinkattributes(path)
    end
    if not attr then
      common.err_path(NAME, path, "No such file or directory")
      rc = 1
    else
      if fmt then
        io.stdout:write(apply_format(path, attr, fmt), "\n")
      elseif terse then
        io.stdout:write(
          string.format(
            "%s %d %d %o %d %d %d %d %d\n",
            path,
            attr.size or 0,
            attr.nlink or 0,
            permissions_octal(attr),
            attr.uid or 0,
            attr.gid or 0,
            math.floor(attr.modification or 0),
            math.floor(attr.access or 0),
            math.floor(attr.change or 0)
          )
        )
      else
        io.stdout:write(default_output(path, attr), "\n")
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "display file or file system status",
  main = main,
}
