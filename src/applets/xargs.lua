-- xargs: build and execute command lines from standard input.

local common = require("common")

local NAME = "xargs"

local function shell_quote(s)
  if common.is_windows() then return '"' .. s:gsub('"', '\\"') .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function tokenize_shell_like(data)
  local tokens = {}
  local current = {}
  local in_single, in_double = false, false
  local i = 1
  local function flush()
    if #current > 0 then
      tokens[#tokens + 1] = table.concat(current)
      current = {}
    end
  end
  while i <= #data do
    local c = data:sub(i, i)
    if in_single then
      if c == "'" then
        in_single = false
      else
        current[#current + 1] = c
      end
    elseif in_double then
      if c == '"' then
        in_double = false
      elseif c == "\\" and i + 1 <= #data then
        current[#current + 1] = data:sub(i + 1, i + 1)
        i = i + 1
      else
        current[#current + 1] = c
      end
    else
      if c == " " or c == "\t" or c == "\n" then
        flush()
      elseif c == "'" then
        in_single = true
      elseif c == '"' then
        in_double = true
      elseif c == "\\" and i + 1 <= #data then
        current[#current + 1] = data:sub(i + 1, i + 1)
        i = i + 1
      else
        current[#current + 1] = c
      end
    end
    i = i + 1
  end
  flush()
  return tokens
end

local function split_by_byte(data, b)
  local out = {}
  local start = 1
  while true do
    local idx = data:find(b, start, true)
    if not idx then
      if start <= #data then out[#out + 1] = data:sub(start) end
      break
    end
    if idx > start then out[#out + 1] = data:sub(start, idx - 1) end
    start = idx + 1
  end
  return out
end

local function take_value(flag, args, idx)
  local a = args[idx]
  if #a > #flag then return a:sub(#flag + 1), idx + 1 end
  if idx + 1 > #args then return nil, idx end
  return args[idx + 1], idx + 2
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local n_per_call, lines_per_call, replace_str = nil, nil, nil
  local null_sep, delimiter = false, nil
  local no_run_empty, trace = false, false
  local input_file = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    end
    if a == "-n" or (a:sub(1, 2) == "-n" and a:sub(3):match("^%d+$")) then
      local v, ni = take_value("-n", args, i)
      if not v then return 2 end
      n_per_call = common.parse_int(v)
      i = ni
    elseif a == "-L" or (a:sub(1, 2) == "-L" and a:sub(3):match("^%d+$")) then
      local v, ni = take_value("-L", args, i)
      if not v then return 2 end
      lines_per_call = common.parse_int(v)
      i = ni
    elseif a == "-I" then
      local v, ni = take_value("-I", args, i)
      if not v then return 2 end
      replace_str = v
      i = ni
    elseif a == "-d" or a:sub(1, 2) == "-d" then
      local v, ni = take_value("-d", args, i)
      if not v then return 2 end
      delimiter = v:sub(1, 1)
      i = ni
    elseif a == "-a" then
      local v, ni = take_value("-a", args, i)
      if not v then return 2 end
      input_file = v
      i = ni
    elseif a == "-0" or a == "--null" then
      null_sep = true
      i = i + 1
    elseif a == "-r" or a == "--no-run-if-empty" then
      no_run_empty = true
      i = i + 1
    elseif a == "-t" then
      trace = true
      i = i + 1
    elseif a:sub(1, 1) ~= "-" then
      break
    else
      common.err(NAME, "invalid option: " .. a)
      return 2
    end
  end

  local cmd_template = {}
  for j = i, #args do
    cmd_template[#cmd_template + 1] = args[j]
  end
  if #cmd_template == 0 then cmd_template = { "echo" } end

  local data
  if input_file then
    local fh, ferr = io.open(input_file, "rb")
    if not fh then
      common.err_path(NAME, input_file, ferr)
      return 1
    end
    data = fh:read("*a") or ""
    fh:close()
  else
    data = io.stdin:read("*a") or ""
  end

  local tokens
  if null_sep then
    tokens = split_by_byte(data, "\0")
  elseif delimiter then
    tokens = split_by_byte(data, delimiter)
  elseif lines_per_call then
    tokens = {}
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then tokens[#tokens + 1] = line end
    end
  else
    tokens = tokenize_shell_like(data)
  end

  local nonempty = {}
  for _, t in ipairs(tokens) do
    if t and t ~= "" then nonempty[#nonempty + 1] = t end
  end
  tokens = nonempty

  if #tokens == 0 and no_run_empty then return 0 end

  local function run(cmd_argv)
    if trace then io.stderr:write(table.concat(cmd_argv, " "), "\n") end
    local parts = {}
    for _, p in ipairs(cmd_argv) do
      parts[#parts + 1] = shell_quote(p)
    end
    local _, _, code = os.execute(table.concat(parts, " "))
    return tonumber(code) or 0
  end

  if replace_str then
    local rc = 0
    for _, tok in ipairs(tokens) do
      local cmd_argv = {}
      for _, a in ipairs(cmd_template) do
        cmd_argv[#cmd_argv + 1] = a:gsub(replace_str, tok, 1)
      end
      local r = run(cmd_argv)
      if r ~= 0 then rc = r end
    end
    return rc
  end

  local batch_size = n_per_call or lines_per_call
  local groups = {}
  if batch_size and batch_size > 0 then
    for k = 1, #tokens, batch_size do
      local g = {}
      for j = k, math.min(k + batch_size - 1, #tokens) do
        g[#g + 1] = tokens[j]
      end
      groups[#groups + 1] = g
    end
  else
    if #tokens > 0 then
      groups[1] = tokens
    elseif not no_run_empty then
      groups[1] = {}
    end
  end

  local rc = 0
  for _, g in ipairs(groups) do
    local cmd_argv = {}
    for _, a in ipairs(cmd_template) do
      cmd_argv[#cmd_argv + 1] = a
    end
    for _, t in ipairs(g) do
      cmd_argv[#cmd_argv + 1] = t
    end
    local r = run(cmd_argv)
    if r ~= 0 then rc = r end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "build and execute command lines from standard input",
  main = main,
}
