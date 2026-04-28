-- tail: output the last part of files.

local common = require("common")

local NAME = "tail"

local function ring_push(ring, max, item)
  ring[#ring + 1] = item
  if #ring > max then
    table.remove(ring, 1)
  end
end

local function emit_initial_tail(fh, bytes_mode, byte_count, lines)
  if bytes_mode then
    local data = common.read_all(fh)
    if byte_count > 0 then
      io.stdout:write(data:sub(-byte_count))
    end
    return
  end
  local ring = {}
  for line in common.iter_lines_keep_nl(fh) do
    ring_push(ring, lines, line)
  end
  for _, line in ipairs(ring) do
    io.stdout:write(line)
  end
end

--- Sleep for `secs` seconds. Used by -f follow. Crude but cross-platform.
local function sleep(secs)
  if common.is_windows() then
    os.execute(string.format("timeout /t %d /nobreak >nul 2>&1", math.max(1, math.ceil(secs))))
  else
    os.execute(string.format("sleep %s", tostring(secs)))
  end
end

--- Follow appended data on each path. Polls every `interval` seconds.
--- Detects truncation by tracking position; rotation detection requires
--- LFS attributes (best-effort — falls back to size-based detection).
local function follow(paths, multi, interval)
  local lfs = common.try_lfs()
  local entries = {}
  for _, f in ipairs(paths) do
    local fh, errmsg = io.open(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
    else
      fh:seek("end")
      local ino = nil
      if lfs then
        local attr = lfs.attributes(f)
        ino = attr and attr.ino or nil
      end
      entries[#entries + 1] = { path = f, fh = fh, ino = ino }
    end
  end
  if #entries == 0 then
    return 0
  end

  local last_path = entries[#entries].path

  while true do
    local got_any = false
    for _, e in ipairs(entries) do
      -- Detect truncation / rotation
      if lfs then
        local attr = lfs.attributes(e.path)
        if attr then
          local pos = e.fh:seek()
          if attr.size and attr.size < pos then
            e.fh:seek("set", 0)
          end
          if e.ino and attr.ino and attr.ino ~= e.ino then
            e.fh:close()
            local newfh = io.open(e.path, "rb")
            if newfh then
              e.fh = newfh
              e.ino = attr.ino
            end
          end
        end
      end
      local data = e.fh:read("*a")
      if data and data ~= "" then
        if multi and last_path ~= e.path then
          io.stdout:write("\n==> ", e.path, " <==\n")
          last_path = e.path
        end
        io.stdout:write(data)
        io.stdout:flush()
        got_any = true
      end
    end
    if not got_any then
      sleep(interval)
    end
  end
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local lines = 10
  local bytes_mode = false
  local byte_count = 0
  local follow_mode = false
  local interval = 1

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-n" and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if n == nil then
        common.err(NAME, "invalid line count: " .. args[i + 1])
        return 2
      end
      lines = n
      i = i + 2
    elseif a == "-c" and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if n == nil then
        common.err(NAME, "invalid byte count: " .. args[i + 1])
        return 2
      end
      bytes_mode = true
      byte_count = n
      i = i + 2
    elseif a == "-s" and i + 1 <= #args then
      local n = tonumber(args[i + 1])
      if n == nil then
        common.err(NAME, "invalid sleep interval: " .. args[i + 1])
        return 2
      end
      interval = n
      i = i + 2
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      lines = tonumber(a:sub(2))
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 then
      for ch in a:sub(2):gmatch(".") do
        if ch == "f" or ch == "F" then
          follow_mode = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    else
      break
    end
  end

  local files = {}
  for j = i, #args do
    files[#files + 1] = args[j]
  end
  if #files == 0 then
    files = { "-" }
  end
  local multi = #files > 1
  local rc = 0

  for idx, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      if multi then
        if idx > 1 then
          io.stdout:write("\n")
        end
        io.stdout:write("==> ", f, " <==\n")
      end
      emit_initial_tail(fh, bytes_mode, byte_count, lines)
      if f ~= "-" then
        fh:close()
      end
    end
  end
  io.stdout:flush()

  if not follow_mode then
    return rc
  end

  -- Follow only real files; "-" can't be re-opened.
  local follow_paths = {}
  for _, f in ipairs(files) do
    if f ~= "-" then
      follow_paths[#follow_paths + 1] = f
    end
  end
  if #follow_paths == 0 then
    return rc
  end
  local f_rc = follow(follow_paths, multi, interval)
  return rc ~= 0 and rc or f_rc
end

return {
  name = NAME,
  aliases = {},
  help = "output the last part of files",
  main = main,
}
