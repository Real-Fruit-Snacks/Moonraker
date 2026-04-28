-- uniq: report or omit repeated adjacent lines.

local common = require("common")

local NAME = "uniq"

local function compute_key(line, skip_fields, skip_chars, width, ignore_case)
  local s = line
  if skip_fields > 0 then
    local i = 1
    local skipped = 0
    while skipped < skip_fields and i <= #s do
      while i <= #s and (s:sub(i, i) == " " or s:sub(i, i) == "\t") do
        i = i + 1
      end
      while i <= #s and s:sub(i, i) ~= " " and s:sub(i, i) ~= "\t" do
        i = i + 1
      end
      skipped = skipped + 1
    end
    s = s:sub(i)
  end
  if skip_chars > 0 then
    s = s:sub(skip_chars + 1)
  end
  if width then
    s = s:sub(1, width)
  end
  if ignore_case then
    s = s:lower()
  end
  return s
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

  local count = false
  local only_dup = false
  local only_unique = false
  local ignore_case = false
  local skip_fields = 0
  local skip_chars = 0
  local width = nil

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-c" then
      count = true
      i = i + 1
    elseif a == "-d" then
      only_dup = true
      i = i + 1
    elseif a == "-u" then
      only_unique = true
      i = i + 1
    elseif a == "-i" then
      ignore_case = true
      i = i + 1
    elseif a:sub(1, 2) == "-f" then
      local v, ni = take_value("-f", args, i)
      if not v then
        common.err(NAME, "-f: missing argument")
        return 2
      end
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "-f: invalid value '" .. v .. "'")
        return 2
      end
      skip_fields = n
      i = ni
    elseif a:sub(1, 2) == "-s" then
      local v, ni = take_value("-s", args, i)
      if not v then
        common.err(NAME, "-s: missing argument")
        return 2
      end
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "-s: invalid value '" .. v .. "'")
        return 2
      end
      skip_chars = n
      i = ni
    elseif a:sub(1, 2) == "-w" then
      local v, ni = take_value("-w", args, i)
      if not v then
        common.err(NAME, "-w: missing argument")
        return 2
      end
      local n = common.parse_int(v)
      if not n then
        common.err(NAME, "-w: invalid value '" .. v .. "'")
        return 2
      end
      width = n
      i = ni
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 and a:sub(2):match("^%d+$") then
      skip_fields = tonumber(a:sub(2))
      i = i + 1
    else
      break
    end
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  local input_path = positional[1] or "-"
  local output_path = positional[2] or "-"

  local in_fh, ierr = common.open_input(input_path, "rb")
  if not in_fh then
    common.err_path(NAME, input_path, ierr)
    return 1
  end
  local out_fh = io.stdout
  local close_out = false
  if output_path ~= "-" then
    local oh, oerr = io.open(output_path, "wb")
    if not oh then
      common.err_path(NAME, output_path, oerr)
      if input_path ~= "-" then
        in_fh:close()
      end
      return 1
    end
    out_fh = oh
    close_out = true
  end

  local function emit(line, cnt)
    if only_dup and cnt < 2 then return end
    if only_unique and cnt ~= 1 then return end
    if count then
      out_fh:write(string.format("%7d %s\n", cnt, line))
    else
      out_fh:write(line, "\n")
    end
  end

  local prev_line, prev_key = nil, nil
  local cnt = 0
  for line in common.iter_lines_keep_nl(in_fh) do
    line = line:gsub("\n$", "")
    local k = compute_key(line, skip_fields, skip_chars, width, ignore_case)
    if prev_key == nil then
      prev_line, prev_key, cnt = line, k, 1
    elseif k == prev_key then
      cnt = cnt + 1
    else
      emit(prev_line, cnt)
      prev_line, prev_key, cnt = line, k, 1
    end
  end
  if prev_line ~= nil then
    emit(prev_line, cnt)
  end

  if input_path ~= "-" then
    in_fh:close()
  end
  if close_out then
    out_fh:close()
  end
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "report or omit repeated adjacent lines",
  main = main,
}
