-- column: format input into multiple columns.

local common = require("common")

local NAME = "column"

local function ljust(s, width)
  if #s >= width then return s end
  return s .. string.rep(" ", width - #s)
end

local function rstrip(s)
  return (s:gsub("%s+$", ""))
end

local function split_row(line, sep)
  if sep == nil then
    local out = {}
    for w in line:gmatch("%S+") do
      out[#out + 1] = w
    end
    return out
  end
  if #sep == 1 then
    local out = {}
    local start = 1
    while true do
      local from = line:find(sep, start, true)
      if not from then
        out[#out + 1] = line:sub(start)
        break
      end
      out[#out + 1] = line:sub(start, from - 1)
      start = from + 1
    end
    return out
  end
  -- Multi-char: split on any of the chars
  local out = { "" }
  for k = 1, #line do
    local ch = line:sub(k, k)
    if sep:find(ch, 1, true) then
      out[#out + 1] = ""
    else
      out[#out] = out[#out] .. ch
    end
  end
  return out
end

local function read_lines(fh)
  local data = common.read_all(fh)
  local lines = {}
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local table_mode = false
  local in_sep = nil
  local out_sep = "  "
  local fill_rows = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-t" or a == "--table" then
      table_mode = true
      i = i + 1
    elseif (a == "-s" or a == "--separator") and i + 1 <= #args then
      in_sep = args[i + 1]
      i = i + 2
    elseif (a == "-o" or a == "--output-separator") and i + 1 <= #args then
      out_sep = args[i + 1]
      i = i + 2
    elseif a == "-x" or a == "--fillrows" then
      fill_rows = true
      i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
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

  local lines = {}
  local rc = 0
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for _, ln in ipairs(read_lines(fh)) do
        lines[#lines + 1] = ln
      end
      if f ~= "-" then fh:close() end
    end
  end

  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  if #lines == 0 then return rc end

  if table_mode then
    local rows = {}
    local maxcols = 0
    for _, line in ipairs(lines) do
      local r = split_row(line, in_sep)
      rows[#rows + 1] = r
      if #r > maxcols then maxcols = #r end
    end
    local widths = {}
    for k = 1, maxcols do widths[k] = 0 end
    for _, row in ipairs(rows) do
      for k, cell in ipairs(row) do
        if #cell > widths[k] then widths[k] = #cell end
      end
    end
    for _, row in ipairs(rows) do
      local cells = {}
      for k, cell in ipairs(row) do
        if k < #row then
          cells[#cells + 1] = ljust(cell, widths[k])
        else
          cells[#cells + 1] = cell
        end
      end
      io.stdout:write(rstrip(table.concat(cells, out_sep)), "\n")
    end
  else
    -- Columnar (non-table) layout
    local term_w = tonumber(os.getenv("COLUMNS") or "") or 80
    local max_w = 0
    for _, s in ipairs(lines) do
      if #s > max_w then max_w = #s end
    end
    local col_w = max_w + 2
    local cols = math.max(1, math.floor(term_w / col_w))
    local rows = math.ceil(#lines / cols)
    if fill_rows then
      for r = 1, rows do
        local cells = {}
        for c = 1, cols do
          local idx = (r - 1) * cols + c
          if idx <= #lines then
            cells[#cells + 1] = ljust(lines[idx], col_w)
          end
        end
        io.stdout:write(rstrip(table.concat(cells)), "\n")
      end
    else
      for r = 1, rows do
        local cells = {}
        for c = 1, cols do
          local idx = (c - 1) * rows + r
          if idx <= #lines then
            cells[#cells + 1] = ljust(lines[idx], col_w)
          end
        end
        io.stdout:write(rstrip(table.concat(cells)), "\n")
      end
    end
  end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "format input into multiple columns",
  main = main,
}
