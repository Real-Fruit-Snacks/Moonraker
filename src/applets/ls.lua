-- ls: list directory contents.

local common = require("common")

local NAME = "ls"

local function classify(attr)
  if not attr then return "" end
  if attr.mode == "directory" then return "/" end
  if attr.mode == "link" then return "@" end
  if attr.mode == "named pipe" then return "|" end
  if attr.mode == "socket" then return "=" end
  if attr.mode == "file" and attr.permissions and attr.permissions:find("x") then return "*" end
  return ""
end

local function filemode(attr)
  if not attr then return "?????????" end
  local type_char = "-"
  local m = attr.mode
  if m == "directory" then
    type_char = "d"
  elseif m == "link" then
    type_char = "l"
  elseif m == "named pipe" then
    type_char = "p"
  elseif m == "socket" then
    type_char = "s"
  elseif m == "char device" then
    type_char = "c"
  elseif m == "block device" then
    type_char = "b"
  end
  return type_char .. (attr.permissions or "?????????")
end

local function format_long(name, attr)
  local mode = filemode(attr)
  local nlink = attr.nlink or 1
  local uid = attr.uid or 0
  local gid = attr.gid or 0
  local size = attr.size or 0
  local mtime = attr.modification or 0
  local ts
  local age = os.time() - mtime
  if math.abs(age) > 180 * 86400 then
    ts = os.date("%b %d  %Y", mtime)
  else
    ts = os.date("%b %d %H:%M", mtime)
  end
  return string.format("%s %2d %s %s %8d %s %s", mode, nlink, tostring(uid), tostring(gid), size, ts, name)
end

local function format_columns(names, term_width)
  if #names == 0 then return {} end
  local max_w = 0
  for _, n in ipairs(names) do
    if #n > max_w then max_w = #n end
  end
  max_w = max_w + 2
  local cols = math.max(1, math.floor(term_width / max_w))
  local rows = math.ceil(#names / cols)
  local out = {}
  for r = 1, rows do
    local parts = {}
    for c = 1, cols do
      local idx = (c - 1) * rows + r
      if idx <= #names then
        local s = names[idx]
        parts[#parts + 1] = s .. string.rep(" ", max_w - #s)
      end
    end
    out[#out + 1] = (table.concat(parts):gsub("%s+$", ""))
  end
  return out
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local long_fmt = false
  local show_all = false
  local show_almost_all = false
  local one_per_line = false
  local recursive = false
  local do_classify = false
  local sort_size = false
  local sort_time = false
  local reverse = false
  local paths = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do
        paths[#paths + 1] = args[j]
      end
      break
    end
    if a == "-" or a:sub(1, 1) ~= "-" or #a < 2 then
      paths[#paths + 1] = a
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "l" then
          long_fmt = true
        elseif ch == "a" then
          show_all = true
        elseif ch == "A" then
          show_almost_all = true
        elseif ch == "1" then
          one_per_line = true
        elseif ch == "R" then
          recursive = true
        elseif ch == "F" then
          do_classify = true
        elseif ch == "S" then
          sort_size = true
        elseif ch == "t" then
          sort_time = true
        elseif ch == "r" then
          reverse = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
    end
    i = i + 1
  end

  if #paths == 0 then paths = { "." } end

  local term_width = tonumber(os.getenv("COLUMNS") or "") or 80
  local lfs = common.try_lfs()
  if not lfs then
    common.err(NAME, "luafilesystem required")
    return 1
  end

  local rc = 0
  local need_stat = long_fmt or do_classify or sort_size or sort_time

  local function list_one(root, header)
    if header then io.stdout:write(root, ":\n") end
    local root_attr = lfs.symlinkattributes(root)
    if not root_attr then
      common.err_path(NAME, root, "No such file or directory")
      rc = 1
      return
    end

    if root_attr.mode ~= "directory" then
      local name = common.basename(root)
      local suffix = do_classify and classify(root_attr) or ""
      if long_fmt then
        io.stdout:write(format_long(name .. suffix, root_attr), "\n")
      else
        io.stdout:write(name, suffix, "\n")
      end
      return
    end

    local names = {}
    local ok, err = pcall(function()
      for entry in lfs.dir(root) do
        names[#names + 1] = entry
      end
    end)
    if not ok then
      common.err_path(NAME, root, err or "could not read directory")
      rc = 1
      return
    end
    if not (show_all or show_almost_all) then
      local filtered = {}
      for _, n in ipairs(names) do
        if n:sub(1, 1) ~= "." then filtered[#filtered + 1] = n end
      end
      names = filtered
    elseif show_almost_all and not show_all then
      local filtered = {}
      for _, n in ipairs(names) do
        if n ~= "." and n ~= ".." then filtered[#filtered + 1] = n end
      end
      names = filtered
    end
    table.sort(names)

    -- Optionally enrich with attributes
    local entries = {}
    for _, n in ipairs(names) do
      local path = common.path_join(root, n)
      local attr = need_stat and lfs.symlinkattributes(path) or nil
      entries[#entries + 1] = { name = n, attr = attr, path = path }
    end

    if sort_size then
      table.sort(entries, function(a, b)
        return (a.attr and a.attr.size or 0) > (b.attr and b.attr.size or 0)
      end)
    elseif sort_time then
      table.sort(entries, function(a, b)
        return (a.attr and a.attr.modification or 0) > (b.attr and b.attr.modification or 0)
      end)
    end
    if reverse then
      local rev = {}
      for k = #entries, 1, -1 do
        rev[#rev + 1] = entries[k]
      end
      entries = rev
    end

    if long_fmt then
      for _, e in ipairs(entries) do
        local suffix = do_classify and classify(e.attr) or ""
        io.stdout:write(format_long((e.name .. suffix), e.attr or {}), "\n")
      end
    elseif one_per_line then
      for _, e in ipairs(entries) do
        local suffix = do_classify and classify(e.attr) or ""
        io.stdout:write(e.name, suffix, "\n")
      end
    else
      local display = {}
      for _, e in ipairs(entries) do
        local suffix = do_classify and classify(e.attr) or ""
        display[#display + 1] = e.name .. suffix
      end
      for _, line in ipairs(format_columns(display, term_width)) do
        io.stdout:write(line, "\n")
      end
    end

    if recursive then
      for _, e in ipairs(entries) do
        local attr = e.attr or lfs.symlinkattributes(e.path)
        if attr and attr.mode == "directory" then
          io.stdout:write("\n")
          list_one(e.path, true)
        end
      end
    end
  end

  local multi = #paths > 1 or recursive
  for idx, p in ipairs(paths) do
    if multi and idx > 1 then io.stdout:write("\n") end
    list_one(p, multi)
  end
  return rc
end

return {
  name = NAME,
  aliases = { "dir" },
  help = "list directory contents",
  main = main,
}
