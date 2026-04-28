-- install-aliases: bulk-create per-applet symlinks.
--
-- After running this, the user can type `ls`, `cat`, `grep` etc. and
-- moonraker's multi-call dispatch handles the request — no need to type
-- `moonraker` every time.

local common = require("common")
local registry = require("registry")

local NAME = "install-aliases"

-- Lifecycle applets: skipped by default. Typing `update` to mean
-- "self-update moonraker" isn't obvious. Use --all to include them.
local LIFECYCLE = {
  ["completions"] = true,
  ["update"] = true,
  ["install-aliases"] = true,
}

local function running_binary_path()
  -- arg[0] is the dispatcher's view of the program name. The applet's
  -- argv[0] is the applet name, not the binary, so we can't use it here.
  -- Reach for the real binary via /proc/self/exe on Linux, or fall back
  -- to `which moonraker`.
  local lfs = common.try_lfs()
  if lfs and lfs.attributes("/proc/self/exe") then
    local link = lfs.attributes("/proc/self/exe")
    if link then
      -- lfs doesn't expose readlink; shell out
      local p = io.popen("readlink -f /proc/self/exe 2>/dev/null")
      if p then
        local line = p:read("*l")
        p:close()
        if line and line ~= "" then return (line:gsub("[\r\n]+$", "")) end
      end
    end
  end
  -- Fall back to `which moonraker`
  local cmd = common.is_windows() and "where moonraker" or "command -v moonraker"
  local p = io.popen(cmd .. " 2>" .. (common.is_windows() and "nul" or "/dev/null"))
  if p then
    local line = p:read("*l")
    p:close()
    if line and line ~= "" then return (line:gsub("[\r\n]+$", "")) end
  end
  return nil
end

local function default_target_dir()
  if common.is_windows() then
    local local_app = os.getenv("LOCALAPPDATA") or os.getenv("USERPROFILE") or "."
    return common.path_join(local_app, "moonraker\\bin")
  end
  local home = os.getenv("HOME") or "."
  return common.path_join(home, ".local/bin")
end

local function file_exists(path)
  local lfs = common.try_lfs()
  if lfs then return lfs.symlinkattributes(path) ~= nil end
  local fh = io.open(path, "rb")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function create_link(source, target)
  local lfs = common.try_lfs()
  if lfs and lfs.link then
    -- Try symlink first
    local ok = lfs.link(source, target, true)
    if ok then return "symlink" end
    -- Try hardlink
    ok = lfs.link(source, target, false)
    if ok then return "hardlink" end
  end
  -- Fall back to copy via shell
  local cp_cmd
  if common.is_windows() then
    cp_cmd = string.format('copy /Y "%s" "%s" >nul', source:gsub("/", "\\"), target:gsub("/", "\\"))
  else
    cp_cmd = string.format('cp "%s" "%s"', source, target)
  end
  if os.execute(cp_cmd) == true or os.execute(cp_cmd) == 0 then return "copy" end
  return nil
end

local function ensure_dir(path)
  local lfs = common.try_lfs()
  if lfs and lfs.attributes(path) then return true end
  if common.is_windows() then
    os.execute(string.format('mkdir "%s" 2>nul', path:gsub("/", "\\")))
  else
    os.execute(string.format('mkdir -p "%s"', path))
  end
  return lfs and lfs.attributes(path) ~= nil
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local target_dir = nil
  local include_aliases = false
  local include_all = false
  local dry_run = false
  local force = false
  local quiet = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--aliases" then
      include_aliases = true
      i = i + 1
    elseif a == "--all" then
      include_all = true
      i = i + 1
    elseif a == "-n" or a == "--dry-run" or a == "--check" then
      dry_run = true
      i = i + 1
    elseif a == "-f" or a == "--force" then
      force = true
      i = i + 1
    elseif a == "-q" or a == "--quiet" then
      quiet = true
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if target_dir then
        common.err(NAME, "too many arguments")
        return 2
      end
      target_dir = a
      i = i + 1
    end
  end

  target_dir = target_dir or default_target_dir()

  local self_path = running_binary_path()
  if not self_path then
    common.err(NAME, "could not locate the moonraker binary; " .. "make sure it's on PATH")
    return 2
  end

  -- Collect names from registry, skipping lifecycle unless --all.
  local names = {}
  for _, applet in registry.iter_sorted() do
    if applet.name ~= NAME then
      if include_all or not LIFECYCLE[applet.name] then
        names[#names + 1] = applet.name
        if include_aliases then
          for _, alias in ipairs(applet.aliases) do
            names[#names + 1] = alias
          end
        end
      end
    end
  end

  if not dry_run and not ensure_dir(target_dir) then
    common.err(NAME, "cannot create " .. target_dir)
    return 1
  end

  if not quiet then
    io.stdout:write("source: ", self_path, "\n")
    io.stdout:write("target: ", target_dir, "\n")
    if dry_run then io.stdout:write("(dry-run; no files created)\n") end
    io.stdout:write("\n")
  end

  local suffix = ""
  if common.is_windows() and self_path:sub(-4):lower() == ".exe" then suffix = ".exe" end

  local created, skipped, failed = 0, 0, 0
  local methods = {}

  for _, name in ipairs(names) do
    local link = common.path_join(target_dir, name .. suffix)
    if file_exists(link) then
      if not force then
        if not quiet then
          io.stdout:write(string.format("skip   %-14s  (exists; pass --force to overwrite)\n", name))
        end
        skipped = skipped + 1
      else
        if not dry_run then
          local ok = os.remove(link)
          if not ok then
            common.err_path(NAME, link, "cannot remove existing")
            failed = failed + 1
          end
        end
      end
    end
    if not file_exists(link) or force then
      if dry_run then
        if not quiet then io.stdout:write(string.format("would  %-14s  -> %s\n", name, link)) end
        created = created + 1
      else
        local method = create_link(self_path, link)
        if not method then
          common.err_path(NAME, link, "could not create link")
          failed = failed + 1
        else
          methods[method] = (methods[method] or 0) + 1
          created = created + 1
          if not quiet then io.stdout:write(string.format("%-8s %-14s  -> %s\n", method, name, link)) end
        end
      end
    end
  end

  if not quiet then
    io.stdout:write("\n")
    if dry_run then
      io.stdout:write(string.format("would create %d, skip %d\n", created, skipped))
    else
      local parts = {}
      for k, v in pairs(methods) do
        parts[#parts + 1] = string.format("%s=%d", k, v)
      end
      table.sort(parts)
      io.stdout:write(
        string.format("created %d (%s), skipped %d, failed %d\n", created, table.concat(parts, ", "), skipped, failed)
      )
    end
  end

  return failed == 0 and 0 or 1
end

return {
  name = NAME,
  aliases = {},
  help = "create per-applet symlinks (so `ls` runs moonraker's ls)",
  main = main,
}
