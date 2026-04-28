-- Shared helpers used by applets. Mirrors mainsail/common.py.

local M = {}

--- Write an error line to stderr in the form "<applet>: <msg>\n".
function M.err(applet, msg)
  io.stderr:write(applet, ": ", msg, "\n")
end

--- Write a path-related error line to stderr.
function M.err_path(applet, path, errmsg)
  io.stderr:write(applet, ": ", path, ": ", tostring(errmsg), "\n")
end

--- Open a file path for reading or return io.stdin for the "-" sentinel.
--- Returns the file handle on success, or (nil, errmsg) on failure.
function M.open_input(path, mode)
  mode = mode or "rb"
  if path == "-" then
    return io.stdin
  end
  return io.open(path, mode)
end

--- Open a file path for writing, or return io.stdout for "-".
function M.open_output(path, mode)
  mode = mode or "wb"
  if path == "-" then
    return io.stdout
  end
  return io.open(path, mode)
end

--- Detect platform path separator. Returns "\\" on Windows, "/" elsewhere.
function M.path_sep()
  return package.config:sub(1, 1)
end

--- True when running on Windows.
function M.is_windows()
  return M.path_sep() == "\\"
end

--- Extract the basename of a path (last segment after / or \).
function M.basename(path)
  return (path:match("([^/\\]+)$")) or path
end

--- Extract the dirname of a path. Returns "." for bare names.
function M.dirname(path)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir == nil or dir == "" then
    return "."
  end
  return dir
end

--- Join two path components with the platform separator.
function M.path_join(a, b)
  if a == "" or a == "." then
    return b
  end
  if b == "" then
    return a
  end
  local last = a:sub(-1)
  if last == "/" or last == "\\" then
    return a .. b
  end
  return a .. M.path_sep() .. b
end

--- Recursively walk a directory tree, calling `callback(path, attr)` for
--- each entry. `attr` is the lfs.symlinkattributes() result. Yields entries
--- top-down by default; set opts.bottom_up = true for post-order traversal.
--- Returns true on success, or (false, errmsg) if the root cannot be read.
function M.walk(root, callback, opts)
  opts = opts or {}
  local lfs = M.try_lfs()
  if not lfs then
    return false, "luafilesystem not available"
  end
  local function visit(path)
    local attr = lfs.symlinkattributes(path)
    if not attr then
      return
    end
    if not opts.bottom_up then
      callback(path, attr)
    end
    if attr.mode == "directory" and not opts.no_recurse then
      local entries = {}
      -- lfs.dir errors if the path can't be read (perm denied etc.). Wrap
      -- the iteration in pcall so we can skip unreadable subtrees instead
      -- of aborting the whole walk.
      local list_ok = pcall(function()
        for entry in lfs.dir(path) do
          if entry ~= "." and entry ~= ".." then
            entries[#entries + 1] = entry
          end
        end
      end)
      if list_ok then
        table.sort(entries)
        for _, entry in ipairs(entries) do
          visit(M.path_join(path, entry))
        end
      end
    end
    if opts.bottom_up then
      callback(path, attr)
    end
  end
  visit(root)
  return true
end

--- Glob-pattern (fnmatch) matching. Translates `*`, `?`, `[abc]` to a Lua
--- pattern, then matches. Used by `find -name` etc.
function M.fnmatch(pattern, name)
  local lp = { "^" }
  local i = 1
  while i <= #pattern do
    local c = pattern:sub(i, i)
    if c == "*" then
      lp[#lp + 1] = ".*"
    elseif c == "?" then
      lp[#lp + 1] = "."
    elseif c == "[" then
      -- pass through bracket class, escaping nothing inside (Lua's
      -- bracket class syntax is similar enough for ASCII)
      local rb = pattern:find("]", i + 1, true)
      if not rb then
        lp[#lp + 1] = "%["
        i = i + 1
      else
        lp[#lp + 1] = pattern:sub(i, rb)
        i = rb
      end
    elseif c:match("[%(%)%.%%%+%-%^%$]") then
      lp[#lp + 1] = "%" .. c
    else
      lp[#lp + 1] = c
    end
    i = i + 1
  end
  lp[#lp + 1] = "$"
  return name:match(table.concat(lp)) ~= nil
end

--- Strict integer parser. Returns the integer or nil if `s` is not a valid
--- integer (rejects floats, hex, leading whitespace).
function M.parse_int(s)
  if type(s) ~= "string" or s == "" then
    return nil
  end
  if not s:match("^%-?%d+$") then
    return nil
  end
  return tonumber(s)
end

--- Lazily try to load LuaFileSystem. Returns the module or nil.
function M.try_lfs()
  local ok, lfs = pcall(require, "lfs")
  if ok and type(lfs) == "table" then
    return lfs
  end
  return nil
end

--- Read all bytes from a file handle.
function M.read_all(fh)
  return fh:read("*a") or ""
end

--- Streaming line iterator that preserves the trailing newline byte.
--- Reads the file handle in chunks; yields each line as soon as a newline
--- is seen. Equivalent to fh:read("*L") on Lua 5.2+, but works on 5.1 too.
--- Critical for applets like `head` and `nl` that must terminate on a
--- closed pipe before the producer finishes (e.g. `yes | head -5`).
function M.iter_lines_keep_nl(fh)
  local buf = ""
  local eof = false
  local CHUNK = 4096
  return function()
    while true do
      local nl = buf:find("\n", 1, true)
      if nl then
        local line = buf:sub(1, nl)
        buf = buf:sub(nl + 1)
        return line
      end
      if eof then
        if buf == "" then
          return nil
        end
        local line = buf
        buf = ""
        return line
      end
      local chunk = fh:read(CHUNK)
      if chunk == nil or chunk == "" then
        eof = true
      else
        buf = buf .. chunk
      end
    end
  end
end

--- POSIX-style overwrite policy shared by cp / mv. Returns true if the
--- caller should proceed with overwriting the target. Mirrors
--- mainsail.common.should_overwrite.
function M.should_overwrite(applet, target, src, opts)
  opts = opts or {}
  local lfs = M.try_lfs()
  local target_attr = lfs and lfs.symlinkattributes(target) or nil
  if target_attr == nil then
    return true
  end
  if opts.no_clobber then
    return false
  end
  if opts.update and lfs then
    local src_attr = lfs.attributes(src)
    if src_attr and src_attr.modification <= target_attr.modification then
      return false
    end
  end
  if opts.interactive and not opts.force then
    io.stderr:write(string.format("%s: overwrite '%s'? ", applet, target))
    io.stderr:flush()
    local ans = io.stdin:read("*l")
    if not ans or not ans:lower():match("^y") then
      return false
    end
  end
  return true
end

return M
