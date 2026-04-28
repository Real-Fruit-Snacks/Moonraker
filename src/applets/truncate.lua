-- truncate: shrink or extend the size of a file to the specified size.
--
-- Lua has no native truncate. On POSIX we shell out to the system
-- `truncate` command. On Windows there's no exact equivalent, so we
-- approximate with rewrite/seek where possible (Lua's io.open + write
-- can't shrink files).

local common = require("common")

local NAME = "truncate"

local SIZE_MULT = {
  K = 1024, M = 1024 * 1024, G = 1024 * 1024 * 1024,
  T = 1024 * 1024 * 1024 * 1024, P = 1024 * 1024 * 1024 * 1024 * 1024,
}

--- Parse a size with optional operator. Returns (op, bytes) or nil.
local function parse_size(s)
  if not s or s == "" then return nil end
  local op = "="
  local first = s:sub(1, 1)
  if first == "+" or first == "-" or first == "<" or first == ">"
     or first == "/" or first == "%" then
    op = first
    s = s:sub(2)
  end
  if s == "" then return nil end
  local mult = 1
  local last = s:sub(-1):upper()
  if SIZE_MULT[last] then
    mult = SIZE_MULT[last]
    s = s:sub(1, -2)
  end
  local n = common.parse_int(s)
  if not n then return nil end
  return op, n * mult
end

local function new_size(op, val, current)
  if op == "=" then return math.max(0, val) end
  if op == "+" then return current + val end
  if op == "-" then return math.max(0, current - val) end
  if op == "<" then return math.min(current, val) end
  if op == ">" then return math.max(current, val) end
  if op == "/" and val ~= 0 then return math.floor(current / val) * val end
  if op == "%" and val ~= 0 then return math.ceil(current / val) * val end
  return nil
end

--- Truncate via system command (POSIX) or fallback for Windows.
local function truncate_path(path, target)
  if common.is_windows() then
    -- Read existing content, then write a new file of `target` bytes.
    local fh = io.open(path, "rb")
    local data = fh and fh:read("*a") or ""
    if fh then fh:close() end
    local out = io.open(path, "wb")
    if not out then return false, "could not open for writing" end
    if #data >= target then
      out:write(data:sub(1, target))
    else
      out:write(data)
      out:write(string.rep("\0", target - #data))
    end
    out:close()
    return true
  end
  local cmd = string.format('truncate -s %d "%s" 2>&1', target, path:gsub('"', '\\"'))
  local pipe = io.popen(cmd)
  if not pipe then return false, "could not invoke truncate" end
  local out = pipe:read("*a")
  local ok = pipe:close()
  if not ok then
    return false, (out and out ~= "") and out:gsub("\n$", "") or "truncate failed"
  end
  return true
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local size_arg, reference, no_create = nil, nil, false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if (a == "-s" or a == "--size") and i + 1 <= #args then
      size_arg = args[i + 1]
      i = i + 2
    elseif a:sub(1, 7) == "--size=" then
      size_arg = a:sub(8)
      i = i + 1
    elseif (a == "-r" or a == "--reference") and i + 1 <= #args then
      reference = args[i + 1]
      i = i + 2
    elseif a == "-c" or a == "--no-create" then
      no_create = true
      i = i + 1
    elseif a == "-o" or a == "--io-blocks" then
      i = i + 1 -- accepted but ignored
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
    common.err(NAME, "missing FILE operand")
    return 2
  end
  if size_arg == nil and reference == nil then
    common.err(NAME, "you must specify either '--size' or '--reference'")
    return 2
  end

  local op, val
  if size_arg then
    op, val = parse_size(size_arg)
    if op == nil then
      common.err(NAME, "invalid size: " .. size_arg)
      return 2
    end
  end

  local ref_size = 0
  if reference then
    local lfs = common.try_lfs()
    local attr = lfs and lfs.attributes(reference)
    if not attr then
      common.err_path(NAME, reference, "No such file or directory")
      return 1
    end
    ref_size = attr.size or 0
  end

  local lfs = common.try_lfs()
  local rc = 0
  for _, f in ipairs(files) do
    local exists = lfs and lfs.attributes(f)
    if exists or not no_create then
      local current = exists and (exists.size or 0) or 0
      local target
      if size_arg then
        target = new_size(op, val, current)
        if target == nil then
          common.err(NAME, "division by zero in size operator: " .. size_arg)
          rc = 1
        end
      else
        target = ref_size
      end

      if target ~= nil then
        if not exists then
          local fh = io.open(f, "wb")
          if fh then fh:close() end
        end
        local ok, errmsg = truncate_path(f, target)
        if not ok then
          common.err_path(NAME, f, errmsg or "truncate failed")
          rc = 1
        end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "shrink or extend the size of a file to the specified size",
  main = main,
}
