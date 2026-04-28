-- head: output the first part of files.

local common = require("common")

local NAME = "head"

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local lines = 10
  local bytes_mode = false
  local byte_count = 0

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
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      lines = tonumber(a:sub(2))
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
      if bytes_mode then
        local data = byte_count > 0 and (fh:read(byte_count) or "") or ""
        io.stdout:write(data)
      else
        local count = 0
        for line in common.iter_lines_keep_nl(fh) do
          if count >= lines then
            break
          end
          io.stdout:write(line)
          count = count + 1
        end
      end
      if f ~= "-" then
        fh:close()
      end
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "output the first part of files",
  main = main,
}
