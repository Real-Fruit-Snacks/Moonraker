-- echo: display a line of text (POSIX, with -n / -e / -E flags).

local NAME = "echo"

local ESCAPES = {
  ["\\"] = "\\",
  a = "\a",
  b = "\b",
  f = "\f",
  n = "\n",
  r = "\r",
  t = "\t",
  v = "\v",
  ["0"] = "\0",
}

local function interpret(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i + 1 <= #s then
      local mapped = ESCAPES[s:sub(i + 1, i + 1)]
      if mapped ~= nil then
        out[#out + 1] = mapped
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function flag_chars_valid(body)
  for ch in body:gmatch(".") do
    if ch ~= "n" and ch ~= "e" and ch ~= "E" then
      return false
    end
  end
  return true
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local newline = true
  local interp = false

  while #args > 0 do
    local first = args[1]
    if first:sub(1, 1) ~= "-" or #first <= 1 or first == "--" then
      break
    end
    local body = first:sub(2)
    if not flag_chars_valid(body) then
      break
    end
    for ch in body:gmatch(".") do
      if ch == "n" then
        newline = false
      elseif ch == "e" then
        interp = true
      elseif ch == "E" then
        interp = false
      end
    end
    table.remove(args, 1)
  end

  local text = table.concat(args, " ")
  if interp then
    text = interpret(text)
  end

  io.stdout:write(text)
  if newline then
    io.stdout:write("\n")
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "display a line of text",
  main = main,
}
