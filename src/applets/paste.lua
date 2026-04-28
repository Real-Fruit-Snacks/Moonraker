-- paste: merge corresponding lines of files.

local common = require("common")

local NAME = "paste"

local function split_chars(s)
  if s == "" then return { "\t" } end
  local out = {}
  for ch in s:gmatch(".") do
    out[#out + 1] = ch
  end
  return out
end

local function join_with_delims(parts, delims)
  if #parts == 0 then return "" end
  local out = parts[1]
  for j = 2, #parts do
    local d = delims[((j - 2) % #delims) + 1]
    out = out .. d .. parts[j]
  end
  return out
end

local function rstrip_nl(s)
  return (s:gsub("[\r\n]+$", ""))
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local delims = { "\t" }
  local serial = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if (a == "-d" or a == "--delimiters") and i + 1 <= #args then
      delims = split_chars(args[i + 1])
      i = i + 2
    elseif a:sub(1, 2) == "-d" and #a > 2 then
      delims = split_chars(a:sub(3))
      i = i + 1
    elseif a == "-s" or a == "--serial" then
      serial = true
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

  -- Read each file's lines into memory. Streaming round-robin would be
  -- preferred for large inputs, but Lua 5.1's stdio doesn't expose a
  -- clean readline-or-nil idiom across both file and pipe handles.
  local sources = {}
  local rc = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      local lines = {}
      for line in common.iter_lines_keep_nl(fh) do
        lines[#lines + 1] = rstrip_nl(line)
      end
      if f ~= "-" then fh:close() end
      sources[#sources + 1] = lines
    end
  end

  if serial then
    for _, lines in ipairs(sources) do
      if #lines > 0 then io.stdout:write(join_with_delims(lines, delims), "\n") end
    end
  else
    local max_len = 0
    for _, lines in ipairs(sources) do
      if #lines > max_len then max_len = #lines end
    end
    for r = 1, max_len do
      local row = {}
      for _, lines in ipairs(sources) do
        row[#row + 1] = lines[r] or ""
      end
      io.stdout:write(join_with_delims(row, delims), "\n")
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "merge corresponding lines of files",
  main = main,
}
