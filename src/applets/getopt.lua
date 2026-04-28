-- getopt: parse command-line options for shell scripts.
--
-- Mirrors GNU enhanced getopt. Output is shell-quoted via single quotes
-- so it can be `eval`-ed safely.

local common = require("common")

local NAME = "getopt"

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function parse_short(spec)
  local out = {}
  local i = 1
  while i <= #spec do
    local ch = spec:sub(i, i)
    if ch == ":" then
      i = i + 1
    else
      local kind = "none"
      if i + 1 <= #spec and spec:sub(i + 1, i + 1) == ":" then
        if i + 2 <= #spec and spec:sub(i + 2, i + 2) == ":" then
          kind = "optional"
          i = i + 3
        else
          kind = "required"
          i = i + 2
        end
      else
        i = i + 1
      end
      out[ch] = kind
    end
  end
  return out
end

local function parse_long(opts)
  local out = {}
  for _, o in ipairs(opts) do
    if o:sub(-2) == "::" then
      out[o:sub(1, -3)] = "optional"
    elseif o:sub(-1) == ":" then
      out[o:sub(1, -2)] = "required"
    else
      out[o] = "none"
    end
  end
  return out
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local short_opts = ""
  local long_opts = {}
  local options_first = false
  local quoted_style = "shell"

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      i = i + 1
      break
    end
    if (a == "-o" or a == "--options") and i + 1 <= #args then
      short_opts = args[i + 1]; i = i + 2
    elseif a:sub(1, 2) == "-o" and #a > 2 then
      short_opts = a:sub(3); i = i + 1
    elseif (a == "-l" or a == "--longoptions" or a == "--long") and i + 1 <= #args then
      for p in (args[i + 1] .. ","):gmatch("([^,]+)") do
        if p ~= "" then long_opts[#long_opts + 1] = p end
      end
      i = i + 2
    elseif a:sub(1, 14) == "--longoptions=" or a:sub(1, 7) == "--long=" then
      local v = a:find("=", 1, true)
      for p in (a:sub(v + 1) .. ","):gmatch("([^,]+)") do
        if p ~= "" then long_opts[#long_opts + 1] = p end
      end
      i = i + 1
    elseif a == "-q" or a == "--quiet" then
      i = i + 1
    elseif a == "-T" or a == "--test" then
      return 4
    elseif a == "-a" or a == "--alternative" then
      i = i + 1
    elseif a == "-u" or a == "--unquoted" then
      quoted_style = "raw"; i = i + 1
    elseif a == "-s" or a == "--shell" then
      i = i + (i + 1 <= #args and 2 or 1)
    elseif a == "+" then
      options_first = true; i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  local inputs = {}
  for j = i, #args do inputs[#inputs + 1] = args[j] end

  local short_map = parse_short(short_opts)
  local long_map = parse_long(long_opts)
  local parsed_opts = {} -- list of {name, value-or-nil}
  local operands = {}

  local j = 1
  while j <= #inputs do
    local arg = inputs[j]
    if arg == "--" then
      for k = j + 1, #inputs do operands[#operands + 1] = inputs[k] end
      break
    end
    if arg:sub(1, 2) == "--" and #arg > 2 then
      local name = arg:sub(3)
      local value = nil
      local eq = name:find("=", 1, true)
      if eq then
        value = name:sub(eq + 1)
        name = name:sub(1, eq - 1)
      end
      local kind = long_map[name]
      if kind == nil then
        local matches = {}
        for k in pairs(long_map) do
          if k:sub(1, #name) == name then matches[#matches + 1] = k end
        end
        if #matches == 1 then
          name = matches[1]
          kind = long_map[name]
        else
          common.err(NAME, "unrecognized option '--" .. name .. "'")
          return 1
        end
      end
      if kind == "required" then
        if value == nil then
          if j + 1 > #inputs then
            common.err(NAME, "option '--" .. name .. "' requires an argument")
            return 1
          end
          j = j + 1
          value = inputs[j]
        end
        parsed_opts[#parsed_opts + 1] = { "--" .. name, value }
      elseif kind == "optional" then
        parsed_opts[#parsed_opts + 1] = { "--" .. name, value }
      else
        if value ~= nil then
          common.err(NAME, "option '--" .. name .. "' doesn't allow an argument")
          return 1
        end
        parsed_opts[#parsed_opts + 1] = { "--" .. name, nil }
      end
      j = j + 1
    elseif arg:sub(1, 1) == "-" and #arg > 1 and arg ~= "-" then
      local k = 2
      while k <= #arg do
        local ch = arg:sub(k, k)
        local kind = short_map[ch]
        if kind == nil then
          common.err(NAME, "invalid option -- '" .. ch .. "'")
          return 1
        end
        if kind == "required" then
          if k + 1 <= #arg then
            parsed_opts[#parsed_opts + 1] = { "-" .. ch, arg:sub(k + 1) }
            k = #arg + 1
          else
            if j + 1 > #inputs then
              common.err(NAME, "option requires an argument -- '" .. ch .. "'")
              return 1
            end
            j = j + 1
            parsed_opts[#parsed_opts + 1] = { "-" .. ch, inputs[j] }
            k = #arg + 1
          end
        elseif kind == "optional" then
          if k + 1 <= #arg then
            parsed_opts[#parsed_opts + 1] = { "-" .. ch, arg:sub(k + 1) }
            k = #arg + 1
          else
            parsed_opts[#parsed_opts + 1] = { "-" .. ch, nil }
            k = k + 1
          end
        else
          parsed_opts[#parsed_opts + 1] = { "-" .. ch, nil }
          k = k + 1
        end
      end
      j = j + 1
    else
      if options_first then
        for k = j, #inputs do operands[#operands + 1] = inputs[k] end
        break
      end
      operands[#operands + 1] = arg
      j = j + 1
    end
  end

  local parts = {}
  for _, p in ipairs(parsed_opts) do
    parts[#parts + 1] = p[1]
    if p[2] ~= nil then parts[#parts + 1] = p[2] end
  end
  parts[#parts + 1] = "--"
  for _, op in ipairs(operands) do parts[#parts + 1] = op end

  if quoted_style == "shell" then
    local quoted = {}
    for _, p in ipairs(parts) do quoted[#quoted + 1] = shell_quote(p) end
    io.stdout:write(table.concat(quoted, " "), "\n")
  else
    io.stdout:write(table.concat(parts, " "), "\n")
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "parse command-line options for shell scripts",
  main = main,
}
