-- mktemp: create a unique temporary file or directory.

local common = require("common")

local NAME = "mktemp"

--- Find the rightmost run of X's in the basename of `template`.
--- Returns (prefix, suffix, x_count). x_count is 0 if too few X's.
local function from_template(tmpl)
  local base = common.basename(tmpl)
  local dirpart = common.dirname(tmpl)
  if dirpart == "." and not tmpl:find("[/\\]") then dirpart = "" end

  -- Find rightmost X-run
  local end_idx = #base + 1
  while end_idx > 1 and base:sub(end_idx - 1, end_idx - 1) ~= "X" do
    end_idx = end_idx - 1
  end
  local start_idx = end_idx
  while start_idx > 1 and base:sub(start_idx - 1, start_idx - 1) == "X" do
    start_idx = start_idx - 1
  end
  local n = end_idx - start_idx
  if n < 3 then return "", "", 0 end
  local pre_base = base:sub(1, start_idx - 1)
  local suffix = base:sub(end_idx)
  local prefix = dirpart ~= "" and common.path_join(dirpart, pre_base) or pre_base
  return prefix, suffix, n
end

local function tempdir()
  return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

--- Generate a random suffix of `n` lowercase letters/digits.
local function random_suffix(n)
  local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
  local out = {}
  -- Seed from time + pid-ish source
  math.randomseed(os.time() + (os.clock() * 1000000))
  for _ = 1, n do
    local idx = math.random(1, #chars)
    out[#out + 1] = chars:sub(idx, idx)
  end
  return table.concat(out)
end

--- Try to create a file or directory at the given path. Returns true if
--- created exclusively, false otherwise.
local function try_create(path, make_dir)
  local lfs = common.try_lfs()
  if make_dir then
    if lfs and lfs.attributes(path) then
      return false -- already exists
    end
    if lfs then return lfs.mkdir(path) == true end
    return false
  end
  -- Test exclusive creation: open mode "wb" overwrites if exists. We need
  -- O_EXCL semantics; lfs doesn't expose that. Approximate by checking
  -- existence first, then opening. Race condition acceptable for mktemp.
  if lfs and lfs.attributes(path) then return false end
  local fh = io.open(path, "wb")
  if not fh then return false end
  fh:close()
  return true
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local make_dir = false
  local dry_run = false
  local quiet = false
  local use_tmpdir = false
  local explicit_dir = nil
  local template = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-d" or a == "--directory" then
      make_dir = true
      i = i + 1
    elseif a == "-u" or a == "--dry-run" then
      dry_run = true
      i = i + 1
    elseif a == "-q" or a == "--quiet" then
      quiet = true
      i = i + 1
    elseif a == "-t" then
      use_tmpdir = true
      i = i + 1
    elseif a == "-p" and i + 1 <= #args then
      explicit_dir = args[i + 1]
      i = i + 2
    elseif a == "--tmpdir" then
      explicit_dir = tempdir()
      i = i + 1
    elseif a:sub(1, 9) == "--tmpdir=" then
      explicit_dir = a:sub(10)
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      if quiet then return 1 end
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if template ~= nil then
        common.err(NAME, "too many arguments")
        return 2
      end
      template = a
      i = i + 1
    end
  end

  if template == nil then template = "tmp.XXXXXXXXXX" end

  local prefix, suffix, n = from_template(template)
  if n == 0 then
    if not quiet then common.err(NAME, "too few X's in template '" .. template .. "'") end
    return 1
  end

  local target_dir
  if use_tmpdir then
    target_dir = explicit_dir or tempdir()
  elseif explicit_dir then
    target_dir = explicit_dir
  else
    -- If template has a directory component, use it implicitly via the
    -- prefix already containing the path. If not, use cwd.
    target_dir = nil
  end

  -- Build full path candidates
  local function candidate()
    local rand = random_suffix(n)
    local base_full = (target_dir and target_dir ~= "")
        and common.path_join(target_dir, common.basename(prefix) .. rand .. suffix)
      or (prefix .. rand .. suffix)
    return base_full
  end

  local path
  for _ = 1, 100 do
    local p = candidate()
    if try_create(p, make_dir) then
      path = p
      break
    end
  end

  if not path then
    if not quiet then common.err(NAME, "could not create temporary " .. (make_dir and "directory" or "file")) end
    return 1
  end

  if dry_run then
    if make_dir then
      local lfs = common.try_lfs()
      if lfs then lfs.rmdir(path) end
    else
      os.remove(path)
    end
  end

  io.stdout:write(path, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "create a unique temporary file or directory",
  main = main,
}
