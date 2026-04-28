-- rev: reverse lines characterwise.

local common = require("common")

local NAME = "rev"

local function reverse_string(s)
  -- string.reverse reverses bytes. For ASCII this is what we want; for
  -- multibyte UTF-8 it would corrupt characters. Mainsail's Python uses
  -- s[::-1] which is also byte-wise on non-ASCII unless the input is text-
  -- decoded. We match Mainsail's behaviour.
  return s:reverse()
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end
  local files = #args > 0 and args or { "-" }
  local rc = 0

  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local body, nl
        if line:sub(-2) == "\r\n" then
          body, nl = line:sub(1, -3), "\r\n"
        elseif line:sub(-1) == "\n" then
          body, nl = line:sub(1, -2), "\n"
        else
          body, nl = line, ""
        end
        io.stdout:write(reverse_string(body), nl)
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
  help = "reverse lines characterwise",
  main = main,
}
