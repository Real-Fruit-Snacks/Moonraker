-- hashing: shared logic for the md5sum / sha1sum / sha256sum / sha512sum
-- applets. Mirrors mainsail.applets.md5sum.hashsum_main.
--
-- Backed by the pure-Lua sha2 module vendored under src/vendor/sha2.lua
-- (Egor Skriptunoff's library; supports MD5, SHA-1, SHA-2 family).

local common = require("common")

local M = {}

local sha = require("vendor.sha2")

local ALGOS = {
  md5 = sha.md5,
  sha1 = sha.sha1,
  sha256 = sha.sha256,
  sha512 = sha.sha512,
}

--- Compute the digest of an entire file or stdin (when path is "-").
local function compute(path, algo)
  local hash_fn = ALGOS[algo]
  if not hash_fn then return nil, "unknown algorithm: " .. tostring(algo) end
  local fh, err = common.open_input(path, "rb")
  if not fh then return nil, err end
  local data = common.read_all(fh)
  if path ~= "-" then fh:close() end
  return hash_fn(data)
end

--- Parse one line of a -c (check) file. Returns (expected, target) or nil.
local function parse_check_line(line, label)
  -- BSD-tag form: "LABEL (FILE) = HEX"
  local prefix = label .. " ("
  if line:sub(1, #prefix) == prefix then
    local rest = line:sub(#prefix + 1)
    local close = rest:find(") = ", 1, true)
    if not close then return nil end
    return rest:sub(close + 4), rest:sub(1, close - 1)
  end
  -- Standard form: "HEX[ ][* or ' ']FILE"
  local hex, sep, target = line:match("^([0-9a-fA-F]+)[ \t]+([ *]?)(.+)$")
  if hex then
    local _ = sep
    return hex, target
  end
  return nil
end

local function do_check(applet, algo, label, files, opts)
  local ok_count, bad, unreadable, malformed = 0, 0, 0, 0
  for _, f in ipairs(files) do
    local fh, ferr = common.open_input(f, "rb")
    if not fh then
      common.err_path(applet, f, ferr)
      return 1
    end
    local lineno = 0
    for raw in common.iter_lines_keep_nl(fh) do
      lineno = lineno + 1
      local line = raw:gsub("[\r\n]+$", "")
      if line ~= "" and line:sub(1, 1) ~= "#" then
        local expected, target = parse_check_line(line, label)
        if not expected then
          malformed = malformed + 1
          if opts.warn then
            common.err(applet, string.format("%s:%d: improperly formatted %s checksum line", f, lineno, label))
          end
        else
          local actual, cerr = compute(target, algo)
          if not actual then
            unreadable = unreadable + 1
            if not opts.status then io.stdout:write(target, ": FAILED open or read\n") end
            local _ = cerr
          elseif actual:lower() == expected:lower() then
            ok_count = ok_count + 1
            if not opts.status and not opts.quiet then io.stdout:write(target, ": OK\n") end
          else
            bad = bad + 1
            if not opts.status then io.stdout:write(target, ": FAILED\n") end
          end
        end
      end
    end
    if f ~= "-" then fh:close() end
  end
  if opts.strict and malformed > 0 then return 1 end
  if bad > 0 or unreadable > 0 then
    if not opts.status then
      if bad > 0 then
        io.stderr:write(string.format("%s: WARNING: %d computed checksum did NOT match\n", applet, bad))
      end
      if unreadable > 0 then
        io.stderr:write(string.format("%s: WARNING: %d listed file could not be read\n", applet, unreadable))
      end
    end
    return 1
  end
  local _ = ok_count
  return 0
end

--- Top-level entry shared by all four hashsum applets.
function M.run(applet, algo, label, argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local opts = {
    check = false,
    binary = false,
    tag = false,
    quiet = false,
    status = false,
    warn = false,
    strict = false,
    zero = false,
  }
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
    if a == "-c" or a == "--check" then
      opts.check = true
    elseif a == "-b" or a == "--binary" then
      opts.binary = true
    elseif a == "-t" or a == "--text" then
      opts.binary = false
    elseif a == "--tag" then
      opts.tag = true
    elseif a == "--quiet" then
      opts.quiet = true
    elseif a == "--status" then
      opts.status = true
    elseif a == "-w" or a == "--warn" then
      opts.warn = true
    elseif a == "--strict" then
      opts.strict = true
    elseif a == "-z" or a == "--zero" then
      opts.zero = true
    elseif a:sub(1, 1) == "-" and a ~= "-" then
      common.err(applet, "invalid option: " .. a)
      return 2
    else
      files[#files + 1] = a
    end
    i = i + 1
  end

  if #files == 0 then files = { "-" } end

  if opts.check then return do_check(applet, algo, label, files, opts) end

  local rc = 0
  local endch = opts.zero and "\0" or "\n"
  for _, f in ipairs(files) do
    local digest, derr = compute(f, algo)
    if not digest then
      common.err_path(applet, f, derr)
      rc = 1
    elseif opts.tag then
      io.stdout:write(string.format("%s (%s) = %s%s", label, f, digest, endch))
    else
      local sep = opts.binary and "*" or " "
      io.stdout:write(digest, " ", sep, f, endch)
    end
  end
  return rc
end

return M
