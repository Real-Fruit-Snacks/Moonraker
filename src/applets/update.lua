-- update: replace the running binary with the latest GitHub release.
--
-- Lua port of mainsail's update.py. We can't ship a TLS stack in this
-- build, so the network calls shell out to curl or wget — both
-- effectively universal on POSIX and shipped with Windows 10+.
--
-- Strategy:
--   1. GET https://api.github.com/repos/Real-Fruit-Snacks/Moonraker/releases/latest
--   2. Parse out tag_name and the matching asset (by name).
--   3. Download asset to a temp file, mark it executable.
--   4. Smoke-test: run `<tmp> --version` and confirm it prints `moonraker `.
--   5. Atomically swap (move running binary to .old, move new into slot).
--
--   --check     prints what would change but doesn't download
--   --force     re-download even when on the latest tag
--   --asset N   override asset autodetection

local common = require("common")
local version = require("version")

local NAME = "update"
local API = "https://api.github.com/repos/Real-Fruit-Snacks/Moonraker/releases/latest"
local USER_AGENT = "moonraker-update/" .. version.version

local function shell_exists(cmd)
  local probe
  if common.is_windows() then
    probe = "where " .. cmd .. " >nul 2>&1"
  else
    probe = "command -v " .. cmd .. " >/dev/null 2>&1"
  end
  local ok, _, code = os.execute(probe)
  if type(ok) == "number" then
    return ok == 0
  end
  if ok == true and (code == nil or code == 0) then
    return true
  end
  return false
end

local function downloader()
  if shell_exists("curl") then return "curl" end
  if shell_exists("wget") then return "wget" end
  return nil
end

local function http_get(url, dest)
  -- dest is nil to capture the body (returns body, err); otherwise download to file.
  local tool = downloader()
  if not tool then
    return nil, "neither curl nor wget is available on PATH"
  end
  local cmd
  if tool == "curl" then
    if dest then
      cmd = string.format(
        'curl -fSL --connect-timeout 30 -A "%s" -o "%s" "%s"',
        USER_AGENT, dest, url)
    else
      cmd = string.format(
        'curl -fsSL --connect-timeout 30 -A "%s" "%s"',
        USER_AGENT, url)
    end
  else  -- wget
    if dest then
      cmd = string.format(
        'wget -q --user-agent="%s" -O "%s" "%s"',
        USER_AGENT, dest, url)
    else
      cmd = string.format(
        'wget -q --user-agent="%s" -O- "%s"',
        USER_AGENT, url)
    end
  end
  if dest then
    local ok, _, code = os.execute(cmd)
    if type(ok) == "number" then ok = (ok == 0) end
    if not ok then
      return nil, tool .. " exit " .. tostring(code or "?")
    end
    return true
  end
  local p = io.popen(cmd, "r")
  if not p then
    return nil, "popen failed"
  end
  local body = p:read("*a") or ""
  local ok = p:close()
  if not ok then
    return nil, tool .. " failed (HTTP error or network down)"
  end
  return body
end

-- Tiny JSON-ish extractor for just the keys we need from the API
-- response. We don't need a general parser — just tag_name and the
-- asset entries (name, size, browser_download_url).
local function decode_json_string(s)
  -- Replace common escapes; not exhaustive but the GitHub API doesn't
  -- emit anything more elaborate in our target fields.
  s = s:gsub('\\"', '"')
  s = s:gsub("\\\\", "\\")
  s = s:gsub("\\n", "\n")
  s = s:gsub("\\t", "\t")
  s = s:gsub("\\r", "\r")
  return s
end

-- Find a JSON string value starting at or after `from`. Returns
-- (value, position_after_closing_quote) or nil.
local function find_string_at(body, key, from)
  from = from or 1
  local idx = body:find('"' .. key .. '"', from, true)
  if not idx then return nil end
  local colon = body:find(":", idx + #key + 2, true)
  if not colon then return nil end
  local p = colon + 1
  while p <= #body and body:sub(p, p):match("%s") do p = p + 1 end
  if body:sub(p, p) ~= '"' then return nil end
  p = p + 1
  local out = {}
  while p <= #body do
    local c = body:sub(p, p)
    if c == "\\" then
      out[#out + 1] = body:sub(p, p + 1)
      p = p + 2
    elseif c == '"' then
      return decode_json_string(table.concat(out)), p + 1
    else
      out[#out + 1] = c
      p = p + 1
    end
  end
  return nil
end

local function find_string(body, key)
  local v = find_string_at(body, key, 1)
  return v
end

local function find_number_at(body, key, from)
  local idx = body:find('"' .. key .. '"', from or 1, true)
  if not idx then return nil end
  local colon = body:find(":", idx + #key + 2, true)
  if not colon then return nil end
  local rest = body:sub(colon + 1):match("^%s*(%-?[%d%.]+)")
  return tonumber(rest), idx
end

-- Walk the assets array, returning a list of {name, size, url} entries.
local function parse_assets(body)
  local assets = {}
  local arr_start = body:find('"assets"%s*:%s*%[')
  if not arr_start then return assets end
  local p = arr_start
  while true do
    local name_val, name_end = find_string_at(body, "name", p)
    if not name_val then break end
    local size = find_number_at(body, "size", name_end) or 0
    local url, url_end = find_string_at(body, "browser_download_url", name_end)
    if not url then break end
    assets[#assets + 1] = { name = name_val, size = size, url = url }
    p = url_end
  end
  return assets
end

local function detect_arch()
  local p = io.popen("uname -m 2>/dev/null")
  if p then
    local m = p:read("*l") or ""
    p:close()
    m = m:lower()
    if m == "x86_64" or m == "amd64" then return "x64" end
    if m == "aarch64" or m == "arm64" then return "arm64" end
  end
  if common.is_windows() then
    local arch = (os.getenv("PROCESSOR_ARCHITECTURE") or ""):lower()
    if arch:find("64") then
      if arch:find("arm") then return "arm64" end
      return "x64"
    end
  end
  return nil
end

local function default_asset_name(self_path)
  local base = common.basename(self_path)
  local stem = base:lower():gsub("%.exe$", "")
  if stem:sub(1, 10) == "moonraker-" then return base end
  local arch = detect_arch()
  if not arch then return nil end
  if common.is_windows() then return string.format("moonraker-windows-%s.exe", arch) end
  -- Detect macOS vs Linux via uname -s
  local p = io.popen("uname -s 2>/dev/null")
  local sys = ""
  if p then sys = (p:read("*l") or ""):lower(); p:close() end
  if sys:find("darwin") then return string.format("moonraker-macos-%s", arch) end
  return string.format("moonraker-linux-%s", arch)
end

local function resolve_path(p)
  -- Turn a possibly-relative argv[0] into an absolute, symlink-resolved
  -- path. Falls back to the input on systems without realpath.
  local cmd
  if common.is_windows() then
    -- PowerShell -Command "& { (Resolve-Path -LiteralPath '...').Path }"
    cmd = string.format(
      'powershell -NoProfile -Command "(Resolve-Path -LiteralPath \'%s\').Path" 2>nul',
      p:gsub("'", "''"))
  else
    cmd = string.format("readlink -f %q 2>/dev/null", p)
  end
  local pipe = io.popen(cmd, "r")
  if pipe then
    local line = pipe:read("*l")
    pipe:close()
    if line and line ~= "" then return line end
  end
  return p
end

local function running_binary_path()
  -- main.lua stashes argv[0] in _MOONRAKER_BINARY before any applet
  -- gets a chance to rewrite it. Resolve through realpath so symlinks
  -- (i.e. install-aliases output) point back at the underlying file.
  local raw = _G._MOONRAKER_BINARY
  if raw and raw ~= "" then
    local resolved = resolve_path(raw)
    -- Sanity check: it must exist and not be a directory.
    local fh = io.open(resolved, "rb")
    if fh then
      fh:close()
      return resolved
    end
  end
  -- Final fallback: which/where moonraker.
  local cmd
  if common.is_windows() then cmd = "where moonraker 2>nul"
  else cmd = "command -v moonraker 2>/dev/null" end
  local pipe = io.popen(cmd, "r")
  if pipe then
    local line = pipe:read("*l")
    pipe:close()
    if line and line ~= "" then return line end
  end
  return nil
end

local function make_executable(path)
  if common.is_windows() then return end
  os.execute(string.format("chmod +x %q", path))
end

local function smoke_test(path)
  local cmd = string.format("%q --version 2>&1", path)
  local p = io.popen(cmd, "r")
  if not p then return false, "popen failed" end
  local line = p:read("*l") or ""
  p:close()
  if not line:match("^moonraker%s+") then
    return false, line ~= "" and line or "no version output"
  end
  return true, (line:match("^moonraker%s+(.+)$") or line)
end

local function replace_binary(current, new_file)
  local backup = current .. ".old"
  os.remove(backup)  -- best-effort cleanup of stale .old
  local ok, err = os.rename(current, backup)
  if not ok then return nil, err or "rename failed" end
  ok, err = os.rename(new_file, current)
  if not ok then
    -- Try to roll back
    pcall(os.rename, backup, current)
    return nil, err or "rename failed"
  end
  make_executable(current)
  return backup
end

local function tmp_path(suffix)
  local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
  local sep = common.path_sep()
  return string.format("%s%smoonraker-update-%d-%d.%s",
    base, sep, os.time(), math.random(100000, 999999), suffix or "tmp")
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local check_only, force = false, false
  local asset_override = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--check" then check_only = true; i = i + 1
    elseif a == "--force" then force = true; i = i + 1
    elseif a == "--asset" and args[i + 1] then
      asset_override = args[i + 1]; i = i + 2
    elseif a:sub(1, 8) == "--asset=" then
      asset_override = a:sub(9); i = i + 1
    else
      common.err(NAME, "unknown option: " .. a)
      return 2
    end
  end

  local self_path = running_binary_path()
  if not self_path then
    common.err(NAME, "could not locate the running moonraker binary")
    return 2
  end

  local asset_name = asset_override or default_asset_name(self_path)
  if not asset_name then
    common.err(NAME, "could not figure out which release asset matches this "
      .. "binary (" .. common.basename(self_path) .. "). Try --asset NAME.")
    return 2
  end

  if not downloader() then
    common.err(NAME, "self-update needs `curl` or `wget` on PATH")
    return 2
  end

  io.stdout:write(string.format("current: moonraker %s at %s\n", version.version, self_path))
  io.stdout:write("target asset: ", asset_name, "\n")
  io.stdout:flush()

  local body, err = http_get(API)
  if not body then
    common.err(NAME, "GitHub API: " .. (err or "request failed"))
    return 1
  end

  local tag = find_string(body, "tag_name")
  if not tag or tag == "" then
    common.err(NAME, "release has no tag_name")
    return 1
  end
  local latest_version = (tag:gsub("^v", ""))
  io.stdout:write("latest release: ", tag, "\n")

  if latest_version == version.version and not force then
    io.stdout:write("already on latest. (use --force to redownload)\n")
    return 0
  end

  local assets = parse_assets(body)
  local match
  for _, a in ipairs(assets) do
    if a.name == asset_name then match = a; break end
  end
  if not match then
    local names = {}
    for _, a in ipairs(assets) do names[#names + 1] = a.name end
    common.err(NAME, string.format("asset %q not in release %s. available: %s",
      asset_name, tag, table.concat(names, ", ")))
    return 1
  end
  if not match.url then
    common.err(NAME, "asset has no browser_download_url")
    return 1
  end

  io.stdout:write(string.format("downloading %s (%d bytes)... ", asset_name, match.size))
  io.stdout:flush()

  if check_only then
    io.stdout:write("[check-only, skipped]\n")
    return 0
  end

  local new_file = tmp_path(asset_name)
  local ok2
  ok2, err = http_get(match.url, new_file)
  if not ok2 then
    pcall(os.remove, new_file)
    common.err(NAME, "download failed: " .. (err or "unknown"))
    return 1
  end
  io.stdout:write("done.\n")

  make_executable(new_file)

  io.stdout:write("verifying... ")
  io.stdout:flush()
  local sok, sinfo = smoke_test(new_file)
  if not sok then
    pcall(os.remove, new_file)
    common.err(NAME, "new binary failed --version smoke test: " .. (sinfo or ""))
    return 1
  end
  io.stdout:write("ok (", sinfo, ").\n")

  local backup, rerr = replace_binary(self_path, new_file)
  if not backup then
    pcall(os.remove, new_file)
    common.err(NAME, "replace failed: " .. (rerr or "unknown"))
    return 1
  end
  io.stdout:write("updated. previous binary kept at ", backup, "\n")
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "self-update from the latest GitHub release",
  main = main,
}
