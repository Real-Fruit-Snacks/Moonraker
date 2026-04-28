-- du: estimate file space usage.

local common = require("common")

local NAME = "du"

local function format_human(n)
  local units = { "", "K", "M", "G", "T", "P" }
  local v = n
  local i = 1
  while v >= 1024 and i < #units do
    v = v / 1024
    i = i + 1
  end
  if i == 1 then return tostring(math.floor(v)) end
  return string.format("%.1f%s", v, units[i])
end

local function format_size(n, human, bytes_exact, block_size)
  if human then return format_human(n) end
  if bytes_exact then return tostring(n) end
  return tostring(math.ceil(n / block_size))
end

--- Compute depth of `sub` relative to `root`. Returns 0 for root itself.
local function depth_of(root, sub)
  if sub == root then return 0 end
  local prefix = root
  if prefix:sub(-1) ~= "/" and prefix:sub(-1) ~= "\\" then
    prefix = prefix .. common.path_sep()
  end
  if sub:sub(1, #prefix) ~= prefix then
    return 0
  end
  local rel = sub:sub(#prefix + 1)
  local depth = 0
  for _ in rel:gmatch("[/\\]") do
    depth = depth + 1
  end
  return depth + 1
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local summary = false
  local all_files = false
  local human = false
  local bytes_exact = false
  local max_depth = nil
  local grand_total = false
  local block_size = 1024

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "--max-depth" and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid max-depth: " .. args[i + 1])
        return 2
      end
      max_depth = n
      i = i + 2
    elseif a:sub(1, 12) == "--max-depth=" then
      local n = common.parse_int(a:sub(13))
      if not n then
        common.err(NAME, "invalid max-depth: " .. a:sub(13))
        return 2
      end
      max_depth = n
      i = i + 1
    elseif a:sub(1, 1) ~= "-" or #a < 2 or a == "-" then
      break
    elseif not a:sub(2):match("^[sahbckm]+$") then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "s" then summary = true
        elseif ch == "a" then all_files = true
        elseif ch == "h" then human = true
        elseif ch == "b" then bytes_exact = true
        elseif ch == "c" then grand_total = true
        elseif ch == "k" then block_size = 1024
        elseif ch == "m" then block_size = 1024 * 1024
        end
      end
      i = i + 1
    end
  end

  local paths = {}
  for j = i, #args do
    paths[#paths + 1] = args[j]
  end
  if #paths == 0 then
    paths = { "." }
  end

  local lfs = common.try_lfs()
  local rc = 0
  local running_total = 0

  local function emit(size, path)
    io.stdout:write(format_size(size, human, bytes_exact, block_size), "\t", path, "\n")
  end

  for _, root in ipairs(paths) do
    local attr = lfs and lfs.symlinkattributes(root)
    if not attr then
      common.err_path(NAME, root, "No such file or directory")
      rc = 1
    elseif attr.mode ~= "directory" or attr.mode == "link" then
      local sz = attr.size or 0
      emit(sz, root)
      running_total = running_total + sz
    else
      -- Bottom-up walk: accumulate sizes per directory
      local totals = {}
      common.walk(root, function(p, a)
        if a.mode == "directory" and a.mode ~= "link" then
          totals[p] = totals[p] or 0
        else
          local sz = a.size or 0
          local parent = common.dirname(p)
          totals[parent] = (totals[parent] or 0) + sz
          if all_files and not summary then
            local d = depth_of(root, p)
            if not max_depth or d <= max_depth then
              emit(sz, p)
            end
          end
        end
      end, { bottom_up = true })

      -- Propagate child dir sizes upward
      common.walk(root, function(p, a)
        if a.mode == "directory" then
          local parent = common.dirname(p)
          if p ~= root and totals[parent] then
            totals[parent] = totals[parent] + (totals[p] or 0)
          end
          if not summary then
            local d = depth_of(root, p)
            if not max_depth or d <= max_depth then
              emit(totals[p] or 0, p)
            end
          end
        end
      end, { bottom_up = true })

      local total = totals[root] or 0
      if summary then
        emit(total, root)
      end
      running_total = running_total + total
    end
  end

  if grand_total then
    emit(running_total, "total")
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "estimate file space usage",
  main = main,
}
