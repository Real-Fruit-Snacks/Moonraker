-- tac: concatenate and print files in reverse.

local common = require("common")

local NAME = "tac"

local function reverse_array(t)
  local n = #t
  for i = 1, math.floor(n / 2) do
    t[i], t[n - i + 1] = t[n - i + 1], t[i]
  end
  return t
end

local function split_keep_empty(s, sep)
  local parts = {}
  if sep == "" then
    parts[1] = s
    return parts
  end
  local start = 1
  while true do
    local from = s:find(sep, start, true)
    if not from then
      parts[#parts + 1] = s:sub(start)
      break
    end
    parts[#parts + 1] = s:sub(start, from - 1)
    start = from + #sep
  end
  return parts
end

local function process_buffer(data, sep, before)
  if data == "" then return "" end
  local parts = split_keep_empty(data, sep)
  local trailing = data:sub(-#sep) == sep
  if trailing and parts[#parts] == "" then parts[#parts] = nil end
  reverse_array(parts)

  if before then
    local pieces = {}
    for _, p in ipairs(parts) do
      pieces[#pieces + 1] = sep .. p
    end
    local out = table.concat(pieces)
    if out:sub(1, #sep) == sep and data:sub(1, #sep) ~= sep then out = out:sub(#sep + 1) end
    return out
  end

  local out = table.concat(parts, sep)
  if trailing then out = out .. sep end
  return out
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local sep = "\n"
  local before = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-b" or a == "--before" then
      before = true
      i = i + 1
    elseif a == "-s" and i + 1 <= #args then
      sep = args[i + 1]
      i = i + 2
    elseif a:sub(1, 12) == "--separator=" then
      sep = a:sub(13)
      i = i + 1
    elseif a == "-r" or a == "--regex" then
      -- accepted for compat; literal sep is the default in GNU tac too
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

  local rc = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      local data = common.read_all(fh)
      if f ~= "-" then fh:close() end
      io.stdout:write(process_buffer(data, sep, before))
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "concatenate and print files in reverse",
  main = main,
}
