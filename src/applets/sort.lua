-- sort: sort lines of text files.

local common = require("common")

local NAME = "sort"

local function parse_key_spec(s)
  local field_part, opts = s:match("^([%d,]+)(.*)$")
  if not field_part or field_part == "" then
    return nil
  end
  local start, stop
  if field_part:find(",", 1, true) then
    local a, b = field_part:match("^(%d*),(%d*)$")
    start = (a == "" or a == nil) and 1 or tonumber(a)
    stop = (b == "" or b == nil) and nil or tonumber(b)
  else
    start = tonumber(field_part)
    stop = nil
  end
  return { start = start, stop = stop, numeric = opts:find("n", 1, true) ~= nil }
end

local function split_fields(line, sep)
  local out = {}
  if sep == nil then
    for word in line:gmatch("%S+") do
      out[#out + 1] = word
    end
  else
    local start = 1
    while true do
      local from = line:find(sep, start, true)
      if not from then
        out[#out + 1] = line:sub(start)
        break
      end
      out[#out + 1] = line:sub(start, from - 1)
      start = from + #sep
    end
  end
  return out
end

local function extract_field(line, spec, sep)
  local fields = split_fields(line, sep)
  local joiner = sep == nil and " " or sep
  local from = math.max(1, spec.start)
  local to = spec.stop or #fields
  if to > #fields then to = #fields end
  if from > to then return "" end
  local picked = {}
  for k = from, to do
    picked[#picked + 1] = fields[k]
  end
  return table.concat(picked, joiner)
end

local function numeric_key(s)
  local stripped = s:gsub("^%s+", "")
  local sign_idx = 1
  if stripped:sub(1, 1) == "+" or stripped:sub(1, 1) == "-" then
    sign_idx = 2
  end
  local body = stripped:sub(sign_idx)
  local num_str = body:match("^(%d+%.?%d*)") or body:match("^(%.?%d+)")
  if not num_str or num_str == "" or num_str == "." then
    return { 1, 0, s }
  end
  local sign = stripped:sub(1, 1) == "-" and -1 or 1
  local val = tonumber(num_str)
  if not val then
    return { 1, 0, s }
  end
  return { 0, sign * val, s }
end

--- Compare two numeric_key tuples.
local function num_lt(a, b)
  if a[1] ~= b[1] then return a[1] < b[1] end
  if a[2] ~= b[2] then return a[2] < b[2] end
  return a[3] < b[3]
end

local function take_value(flag, args, idx)
  local a = args[idx]
  if #a > #flag then
    return a:sub(#flag + 1), idx + 1
  end
  if idx + 1 > #args then
    return nil, idx
  end
  return args[idx + 1], idx + 2
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local reverse = false
  local numeric = false
  local unique = false
  local ignore_case = false
  local ignore_leading_blanks = false
  local separator = nil
  local output_path = nil
  local key_specs = {}
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
    if a == "-" or a:sub(1, 1) ~= "-" or #a < 2 then
      files[#files + 1] = a
      i = i + 1
    elseif a == "-k" or a:sub(1, 2) == "-k" then
      local v, ni = take_value("-k", args, i)
      if not v then
        common.err(NAME, "-k: missing argument")
        return 2
      end
      local spec = parse_key_spec(v)
      if not spec then
        common.err(NAME, "invalid -k spec: '" .. v .. "'")
        return 2
      end
      key_specs[#key_specs + 1] = spec
      i = ni
    elseif a == "-t" or a:sub(1, 2) == "-t" then
      local v, ni = take_value("-t", args, i)
      if not v then
        common.err(NAME, "-t: missing argument")
        return 2
      end
      if #v ~= 1 then
        common.err(NAME, "separator must be a single character: '" .. v .. "'")
        return 2
      end
      separator = v
      i = ni
    elseif a == "-o" or a:sub(1, 2) == "-o" then
      local v, ni = take_value("-o", args, i)
      if not v then
        common.err(NAME, "-o: missing argument")
        return 2
      end
      output_path = v
      i = ni
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "r" then reverse = true
        elseif ch == "n" then numeric = true
        elseif ch == "u" then unique = true
        elseif ch == "f" then ignore_case = true
        elseif ch == "b" then ignore_leading_blanks = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    end
  end

  if #files == 0 then
    files = { "-" }
  end

  local lines = {}
  local rc = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        lines[#lines + 1] = (line:gsub("\n$", ""))
      end
      if f ~= "-" then
        fh:close()
      end
    end
  end

  local function base_transform(s)
    if ignore_leading_blanks then
      s = s:gsub("^%s+", "")
    end
    if ignore_case then
      s = s:lower()
    end
    return s
  end

  local function key_fn(s)
    if #key_specs > 0 then
      local parts = {}
      for _, spec in ipairs(key_specs) do
        local v = base_transform(extract_field(s, spec, separator))
        parts[#parts + 1] = spec.numeric and numeric_key(v) or v
      end
      return parts
    end
    local v = base_transform(s)
    return numeric and numeric_key(v) or v
  end

  local function compare(a, b)
    local ka, kb = key_fn(a), key_fn(b)
    if type(ka) == "table" and ka[1] ~= nil and type(ka[1]) == "number" then
      -- numeric_key tuple
      return num_lt(ka, kb)
    end
    if type(ka) == "table" then
      -- list of keys (multiple -k specs)
      for k = 1, math.max(#ka, #kb) do
        local pa, pb = ka[k], kb[k]
        if pa == nil and pb ~= nil then return true end
        if pb == nil and pa ~= nil then return false end
        if type(pa) == "table" then
          if num_lt(pa, pb) then return true end
          if num_lt(pb, pa) then return false end
        else
          if pa ~= pb then return pa < pb end
        end
      end
      return false
    end
    return ka < kb
  end

  if reverse then
    local cmp = compare
    table.sort(lines, function(a, b)
      return cmp(b, a)
    end)
  else
    table.sort(lines, compare)
  end

  if unique then
    local seen = {}
    local deduped = {}
    for _, line in ipairs(lines) do
      local k = key_fn(line)
      local sk = type(k) == "table" and table.concat(
        (function()
          local strs = {}
          for _, p in ipairs(k) do
            if type(p) == "table" then
              strs[#strs + 1] = tostring(p[2]) .. "\0" .. p[3]
            else
              strs[#strs + 1] = tostring(p)
            end
          end
          return strs
        end)(),
        "\1"
      ) or tostring(k)
      if not seen[sk] then
        seen[sk] = true
        deduped[#deduped + 1] = line
      end
    end
    lines = deduped
  end

  local out_fh = io.stdout
  local close_out = false
  if output_path then
    local oh, oerr = io.open(output_path, "wb")
    if not oh then
      common.err_path(NAME, output_path, oerr)
      return 1
    end
    out_fh = oh
    close_out = true
  end

  for _, line in ipairs(lines) do
    out_fh:write(line, "\n")
  end
  if close_out then
    out_fh:close()
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "sort lines of text files",
  main = main,
}
