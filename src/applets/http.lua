-- http: minimal curl-style HTTP client.
--
-- Lua port of mainsail's http.py. Shells out to curl (or wget) so we
-- get HTTPS support without vendoring a TLS stack. The applet just
-- assembles the right command-line and forwards stdio.

local common = require("common")

local NAME = "http"

local function shell_exists(cmd)
  local probe
  if common.is_windows() then
    probe = "where " .. cmd .. " >nul 2>&1"
  else
    probe = "command -v " .. cmd .. " >/dev/null 2>&1"
  end
  local ok, _, code = os.execute(probe)
  if type(ok) == "number" then return ok == 0 end
  if ok == true and (code == nil or code == 0) then return true end
  return false
end

local function shell_quote(s)
  if common.is_windows() then
    return '"' .. s:gsub('"', '\\"') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a")
  fh:close()
  return data
end

local function write_temp_body(data)
  local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
  local sep = common.path_sep()
  local path = string.format("%s%smoonraker-http-%d-%d.body",
    base, sep, os.time(), math.random(100000, 999999))
  local fh = io.open(path, "wb")
  if not fh then return nil end
  fh:write(data)
  fh:close()
  return path
end

local function build_curl(url, opts)
  local parts = { "curl", "-sS" }
  if opts.fail then parts[#parts + 1] = "-f" end
  if opts.include_headers then parts[#parts + 1] = "-i" end
  if opts.head_only then parts[#parts + 1] = "-I" end
  if opts.follow_redirects ~= false then parts[#parts + 1] = "-L" end
  if opts.silent then parts[1] = "curl"; parts[2] = "-s" end
  if opts.timeout then
    parts[#parts + 1] = "--max-time"
    parts[#parts + 1] = tostring(opts.timeout)
  end
  parts[#parts + 1] = "-A"
  parts[#parts + 1] = shell_quote(opts.user_agent or "moonraker-http/1.0")
  if opts.method then
    parts[#parts + 1] = "-X"
    parts[#parts + 1] = opts.method
  end
  for _, h in ipairs(opts.headers or {}) do
    parts[#parts + 1] = "-H"
    parts[#parts + 1] = shell_quote(h)
  end
  if opts.body_file then
    parts[#parts + 1] = "--data-binary"
    parts[#parts + 1] = "@" .. shell_quote(opts.body_file)
  end
  if opts.output then
    parts[#parts + 1] = "-o"
    parts[#parts + 1] = shell_quote(opts.output)
  end
  parts[#parts + 1] = shell_quote(url)
  return table.concat(parts, " ")
end

local function build_wget(url, opts)
  local parts = { "wget", "-q", "-O" }
  if opts.output then
    parts[#parts + 1] = shell_quote(opts.output)
  else
    parts[#parts + 1] = "-"  -- write body to stdout
  end
  parts[#parts + 1] = "--user-agent=" .. shell_quote(opts.user_agent or "moonraker-http/1.0")
  if opts.timeout then
    parts[#parts + 1] = "--timeout=" .. tostring(opts.timeout)
  end
  if opts.head_only then parts[#parts + 1] = "--method=HEAD" end
  if opts.method and opts.method ~= "GET" then
    parts[#parts + 1] = "--method=" .. opts.method
  end
  for _, h in ipairs(opts.headers or {}) do
    parts[#parts + 1] = "--header=" .. shell_quote(h)
  end
  if opts.body_file then
    parts[#parts + 1] = "--body-file=" .. shell_quote(opts.body_file)
  end
  if opts.include_headers then parts[#parts + 1] = "-S" end
  parts[#parts + 1] = shell_quote(url)
  return table.concat(parts, " ")
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local opts = {
    headers = {},
    follow_redirects = true,
    user_agent = "moonraker-http/1.0",
    timeout = 30,
  }
  local url = nil
  local body = nil
  local json_body = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      if args[i] and not url then url = args[i] end
      break
    elseif (a == "-X" or a == "--request") and args[i + 1] then
      opts.method = args[i + 1]:upper(); i = i + 2
    elseif (a == "-H" or a == "--header") and args[i + 1] then
      opts.headers[#opts.headers + 1] = args[i + 1]; i = i + 2
    elseif (a == "-d" or a == "--data") and args[i + 1] then
      local v = args[i + 1]
      if v:sub(1, 1) == "@" then
        local data, err = read_file(v:sub(2))
        if not data then
          common.err(NAME, v:sub(2) .. ": " .. tostring(err))
          return 1
        end
        body = data
      else
        body = v
      end
      i = i + 2
    elseif a == "--json" and args[i + 1] then
      local v = args[i + 1]
      if v:sub(1, 1) == "@" then
        local data, err = read_file(v:sub(2))
        if not data then
          common.err(NAME, v:sub(2) .. ": " .. tostring(err))
          return 1
        end
        json_body = data
      else
        json_body = v
      end
      i = i + 2
    elseif (a == "-o" or a == "--output") and args[i + 1] then
      opts.output = args[i + 1]; i = i + 2
    elseif a == "-i" or a == "--include" then
      opts.include_headers = true; i = i + 1
    elseif a == "-I" or a == "--head" then
      opts.head_only = true; i = i + 1
    elseif a == "-L" or a == "--location" then
      opts.follow_redirects = true; i = i + 1
    elseif a == "--no-location" then
      opts.follow_redirects = false; i = i + 1
    elseif a == "-s" or a == "--silent" then
      opts.silent = true; i = i + 1
    elseif a == "-f" or a == "--fail" then
      opts.fail = true; i = i + 1
    elseif (a == "-A" or a == "--user-agent") and args[i + 1] then
      opts.user_agent = args[i + 1]; i = i + 2
    elseif a == "--timeout" and args[i + 1] then
      local t = tonumber(args[i + 1])
      if not t then
        common.err(NAME, "invalid timeout: " .. args[i + 1])
        return 2
      end
      opts.timeout = t; i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if not url then url = a else
        common.err(NAME, "unexpected argument: " .. a)
        return 2
      end
      i = i + 1
    end
  end

  if not url then
    common.err(NAME, "missing URL")
    return 2
  end

  if json_body and not body then
    body = json_body
    local has_ct = false
    for _, h in ipairs(opts.headers) do
      if h:lower():match("^%s*content%-type%s*:") then has_ct = true; break end
    end
    if not has_ct then
      opts.headers[#opts.headers + 1] = "Content-Type: application/json"
    end
  end

  if opts.head_only then opts.method = "HEAD" end
  if not opts.method then opts.method = body and "POST" or "GET" end

  if body then
    local p = write_temp_body(body)
    if not p then
      common.err(NAME, "could not stage request body")
      return 1
    end
    opts.body_file = p
  end

  local cmd
  if shell_exists("curl") then
    cmd = build_curl(url, opts)
  elseif shell_exists("wget") then
    cmd = build_wget(url, opts)
  else
    if opts.body_file then pcall(os.remove, opts.body_file) end
    common.err(NAME, "neither curl nor wget is available on PATH")
    return 1
  end

  local ok, _, code = os.execute(cmd)
  if opts.body_file then pcall(os.remove, opts.body_file) end

  -- Normalize the exit code across Lua versions.
  if type(ok) == "number" then code = ok; ok = (ok == 0) end
  if ok then return 0 end
  if opts.fail then return 22 end
  return code or 1
end

return {
  name = NAME,
  aliases = {},
  help = "minimal HTTP client (curl-equivalent)",
  main = main,
}
