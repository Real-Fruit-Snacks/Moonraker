-- tee: read from stdin, write to stdout and files.

local common = require("common")

local NAME = "tee"

local CHUNK = 64 * 1024

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local append = false
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
    if a == "--append" then
      append = true
      i = i + 1
    elseif a == "-" or a:sub(1, 1) ~= "-" or #a < 2 then
      files[#files + 1] = a
      i = i + 1
    else
      local body = a:sub(2)
      local valid = body:match("^[ai]+$")
      if not valid then
        common.err(NAME, "invalid option: " .. a)
        return 2
      end
      for ch in body:gmatch(".") do
        if ch == "a" then
          append = true
        end
        -- 'i' (ignore SIGINT) is accepted for compat; Lua doesn't expose
        -- signal masking from the stdlib.
      end
      i = i + 1
    end
  end

  local mode = append and "ab" or "wb"
  local handles = {}
  local rc = 0
  for _, f in ipairs(files) do
    local h, errmsg = io.open(f, mode)
    if not h then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      handles[#handles + 1] = { path = f, fh = h }
    end
  end

  while true do
    local chunk = io.stdin:read(CHUNK)
    if not chunk or chunk == "" then
      break
    end
    io.stdout:write(chunk)
    io.stdout:flush()
    for _, h in ipairs(handles) do
      h.fh:write(chunk)
      h.fh:flush()
    end
  end

  for _, h in ipairs(handles) do
    h.fh:close()
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "read from stdin and write to stdout and files",
  main = main,
}
