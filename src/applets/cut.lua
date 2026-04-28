-- cut: remove sections from each line of files.

local common = require("common")

local NAME = "cut"

local function parse_list(s)
  local ranges = {}
  for part in s:gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      local a, b = part:match("^(%d*)%-(%d*)$")
      local start, stop
      if a or b then
        start = (a == "" or a == nil) and 1 or tonumber(a)
        stop = (b == "" or b == nil) and -1 or tonumber(b)
      else
        local n = common.parse_int(part)
        if not n then
          return nil, "invalid range: " .. part
        end
        start, stop = n, n
      end
      if start == nil or start < 1 then
        return nil, "position must be >= 1: " .. part
      end
      ranges[#ranges + 1] = { start = start, stop = stop }
    end
  end
  if #ranges == 0 then
    return nil, "empty list"
  end
  return ranges
end

--- Returns sorted list of selected positions (1-indexed) for an `n`-element row.
local function positions(n, ranges)
  local set = {}
  for _, r in ipairs(ranges) do
    local stop = r.stop == -1 and n or math.min(r.stop, n)
    for p = r.start, stop do
      set[p] = true
    end
  end
  local out = {}
  for p in pairs(set) do
    out[#out + 1] = p
  end
  table.sort(out)
  return out
end

local function split_by(line, sep)
  if sep == "" then
    return { line }
  end
  local parts = {}
  local start = 1
  while true do
    local from = line:find(sep, start, true)
    if not from then
      parts[#parts + 1] = line:sub(start)
      break
    end
    parts[#parts + 1] = line:sub(start, from - 1)
    start = from + #sep
  end
  return parts
end

local function take_value(flag, args, idx)
  local a = args[idx]
  if #a > #flag then
    return a:sub(#flag + 1), idx + 1
  end
  if idx + 1 > #args then
    return nil, idx
  end
  return args[idx + 1], idx + 2
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local delim = "\t"
  local suppress = false
  local mode = nil
  local list_spec = nil
  local files = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do
        files[#files + 1] = args[j]
      end
      break
    end
    if a == "-d" or a:sub(1, 2) == "-d" then
      local v, ni = take_value("-d", args, i)
      if not v then
        common.err(NAME, "-d: missing argument")
        return 2
      end
      delim = v
      i = ni
    elseif a == "-f" or a:sub(1, 2) == "-f" then
      local v, ni = take_value("-f", args, i)
      if not v then
        common.err(NAME, "-f: missing argument")
        return 2
      end
      mode, list_spec = "f", v
      i = ni
    elseif a == "-c" or a:sub(1, 2) == "-c" then
      local v, ni = take_value("-c", args, i)
      if not v then
        common.err(NAME, "-c: missing argument")
        return 2
      end
      mode, list_spec = "c", v
      i = ni
    elseif a == "-s" then
      suppress = true
      i = i + 1
    elseif a == "-n" then
      i = i + 1 -- POSIX no-op (with -b)
    elseif a == "-" or a:sub(1, 1) ~= "-" then
      files[#files + 1] = a
      i = i + 1
    else
      common.err(NAME, "invalid option: " .. a)
      return 2
    end
  end

  if not mode or not list_spec then
    common.err(NAME, "must specify -f or -c")
    return 2
  end

  local ranges, errmsg = parse_list(list_spec)
  if not ranges then
    common.err(NAME, "invalid list '" .. list_spec .. "': " .. errmsg)
    return 2
  end

  if #files == 0 then
    files = { "-" }
  end

  local rc = 0
  for _, f in ipairs(files) do
    local fh, openerr = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, openerr)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local body = line:gsub("\n$", "")
        if mode == "f" then
          if not body:find(delim, 1, true) then
            if not suppress then
              io.stdout:write(body, "\n")
            end
          else
            local fields = split_by(body, delim)
            local pos = positions(#fields, ranges)
            local picked = {}
            for k, p in ipairs(pos) do
              picked[k] = fields[p]
            end
            io.stdout:write(table.concat(picked, delim), "\n")
          end
        else
          local pos = positions(#body, ranges)
          local picked = {}
          for k, p in ipairs(pos) do
            picked[k] = body:sub(p, p)
          end
          io.stdout:write(table.concat(picked), "\n")
        end
      end
      if f ~= "-" then
        fh:close()
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "remove sections from each line of files",
  main = main,
}
