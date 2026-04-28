-- Spec helper: invoke the dispatcher with captured stdio.
--
-- The dispatcher and applets write to io.stdout / io.stderr directly. To
-- test them we swap those globals for in-memory buffers, then restore.
-- The buffers expose the same `write`/`flush`/`close` shape that file
-- handles do, so applet code is unchanged in tests.

local M = {}

local function make_buffer()
  local buf = { chunks = {} }
  function buf:write(...)
    for _, v in ipairs({ ... }) do
      self.chunks[#self.chunks + 1] = tostring(v)
    end
    return self
  end
  function buf:flush() end
  function buf:close() end
  function buf:value()
    return table.concat(self.chunks)
  end
  return buf
end

--- Build a read-only handle backed by an in-memory string. Supports the
--- read-format strings applets use: "*a", "*l", "*L", a number, and the
--- :lines() iterator.
local function make_input(text)
  local pos = 1
  local h = {}
  function h:read(fmt)
    fmt = fmt or "*l"
    if fmt == "*a" or fmt == "a" then
      local rest = text:sub(pos)
      pos = #text + 1
      return rest
    end
    if fmt == "*l" or fmt == "l" or fmt == "*L" or fmt == "L" then
      if pos > #text then
        return nil
      end
      local nl = text:find("\n", pos, true)
      local line
      if nl then
        line = text:sub(pos, fmt:sub(-1) == "L" and nl or nl - 1)
        pos = nl + 1
      else
        line = text:sub(pos)
        pos = #text + 1
      end
      return line
    end
    if type(fmt) == "number" then
      if pos > #text then
        return nil
      end
      local chunk = text:sub(pos, pos + fmt - 1)
      pos = pos + #chunk
      return chunk
    end
    error("unsupported read format: " .. tostring(fmt))
  end
  -- Lua 5.1 has unpack(); Lua 5.2+ has table.unpack.
  local _unpack = table.unpack or unpack -- luacheck: globals unpack
  function h:lines(...)
    local fmts = { ... }
    if #fmts == 0 then
      fmts = { "*l" }
    end
    return function()
      return self:read(_unpack(fmts))
    end
  end
  function h:close() end
  return h
end

--- Invoke cli.main with the given argv table. Returns rc, stdout, stderr.
--- Optional `stdin_text` swaps io.stdin for an in-memory handle.
function M.invoke(argv, stdin_text)
  local cli = require("cli")
  local out = make_buffer()
  local err = make_buffer()

  local orig_out, orig_err, orig_in = io.stdout, io.stderr, io.stdin
  io.stdout = out
  io.stderr = err
  if stdin_text ~= nil then
    io.stdin = make_input(stdin_text)
  end
  local ok, rc_or_err = pcall(cli.main, argv)
  io.stdout = orig_out
  io.stderr = orig_err
  io.stdin = orig_in

  if not ok then
    error(rc_or_err)
  end
  return rc_or_err, out:value(), err:value()
end

--- Invoke as if from `moonraker <args...>` (wrapper mode).
function M.invoke_wrapper(...)
  local argv = { [0] = "moonraker" }
  local args = { ... }
  for i = 1, #args do
    argv[i] = args[i]
  end
  return M.invoke(argv)
end

--- Invoke as if from a symlink/hardlink to `<applet>` (multi-call mode).
function M.invoke_multicall(applet_name, ...)
  local argv = { [0] = applet_name }
  local args = { ... }
  for i = 1, #args do
    argv[i] = args[i]
  end
  return M.invoke(argv)
end

--- Invoke an applet (multi-call) with stdin pre-filled with `stdin_text`.
function M.invoke_with_stdin(applet_name, stdin_text, ...)
  local argv = { [0] = applet_name }
  local args = { ... }
  for i = 1, #args do
    argv[i] = args[i]
  end
  return M.invoke(argv, stdin_text)
end

--- Create a temporary file containing `content`. Returns the path. The
--- caller is responsible for cleanup (or use spec teardown).
function M.tmp_file(content)
  local lfs = require("lfs")
  local dir = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
  local sep = package.config:sub(1, 1)
  local name = string.format(
    "%s%smr-spec-%d-%d.tmp",
    dir,
    sep,
    os.time(),
    math.random(1, 1000000)
  )
  local f = assert(io.open(name, "wb"))
  if content then
    f:write(content)
  end
  f:close()
  -- Touch lfs to prove it's available (and to satisfy luacheck about unused).
  local _ = lfs.attributes(name)
  return name
end

--- Read a file's full contents. Returns the string, or "" if missing.
function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return ""
  end
  local data = f:read("*a") or ""
  f:close()
  return data
end

--- Reload all applets into a fresh registry. Call from before_each() to
--- isolate specs that mutate the registry.
function M.load_applets()
  package.loaded["registry"] = nil
  for k in pairs(package.loaded) do
    if k:match("^applets") then
      package.loaded[k] = nil
    end
  end
  package.loaded["cli"] = nil
  package.loaded["usage"] = nil
  package.loaded["common"] = nil
  package.loaded["version"] = nil
  require("applets.init").load_all()
end

return M
