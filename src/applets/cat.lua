-- cat: concatenate files and print on the standard output.

local common = require("common")

local NAME = "cat"

local CHUNK = 64 * 1024

local function emit_numbered(files, number_all, number_nonblank)
  local rc = 0
  local counter = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local ends_nl = line:sub(-1) == "\n"
        local body = ends_nl and line:sub(1, -2) or line
        local blank = body == ""
        if number_all or (number_nonblank and not blank) then
          counter = counter + 1
          io.stdout:write(string.format("%6d\t%s", counter, body))
        else
          io.stdout:write(body)
        end
        if ends_nl then io.stdout:write("\n") end
      end
      if f ~= "-" then fh:close() end
    end
  end
  return rc
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local number_all, number_nonblank = false, false
  local files = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do
        files[#files + 1] = args[j]
      end
      break
    elseif a == "-" or a:sub(1, 1) ~= "-" or #a < 2 then
      files[#files + 1] = a
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "n" then
          number_all = true
          number_nonblank = false
        elseif ch == "b" then
          number_nonblank = true
          number_all = false
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
    end
    i = i + 1
  end

  if #files == 0 then files = { "-" } end

  if number_all or number_nonblank then return emit_numbered(files, number_all, number_nonblank) end

  local rc = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      while true do
        local chunk = fh:read(CHUNK)
        if not chunk or chunk == "" then break end
        io.stdout:write(chunk)
      end
      if f ~= "-" then fh:close() end
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "concatenate files and print on the standard output",
  main = main,
}
