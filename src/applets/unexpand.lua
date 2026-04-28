-- unexpand: convert spaces to tabs.

local common = require("common")

local NAME = "unexpand"

local function parse_tabs(spec)
  local clean = spec:gsub(" ", ",")
  local out = {}
  for p in clean:gmatch("[^,]+") do
    local n = common.parse_int(p)
    if not n then
      return nil
    end
    out[#out + 1] = n
  end
  return out
end

local function compact_spaces(start_col, count, tabs, step)
  local out = {}
  local col = start_col
  local remaining = count
  while remaining > 0 do
    local next_stop
    if step > 0 then
      next_stop = (math.floor(col / step) + 1) * step
    else
      for _, t in ipairs(tabs) do
        if t > col then
          next_stop = t
          break
        end
      end
      if not next_stop then
        next_stop = col + remaining
      end
    end
    local gap = next_stop - col
    if gap <= remaining then
      out[#out + 1] = "\t"
      remaining = remaining - gap
      col = next_stop
    else
      out[#out + 1] = string.rep(" ", remaining)
      col = col + remaining
      remaining = 0
    end
  end
  return out
end

local function convert_line(line, tabs, step, all_blanks)
  local out = {}
  local col = 0
  local pending_spaces = 0
  local seen_non_blank = false
  for k = 1, #line do
    local ch = line:sub(k, k)
    if ch == " " then
      pending_spaces = pending_spaces + 1
    else
      if pending_spaces > 0 then
        if not seen_non_blank or all_blanks then
          for _, piece in ipairs(compact_spaces(col, pending_spaces, tabs, step)) do
            out[#out + 1] = piece
          end
        else
          out[#out + 1] = string.rep(" ", pending_spaces)
        end
        col = col + pending_spaces
        pending_spaces = 0
      end
      out[#out + 1] = ch
      col = col + 1
      if ch ~= "\t" then
        seen_non_blank = true
      end
      if ch == "\t" then
        if step > 0 then
          col = col - 1
          col = (math.floor(col / step) + 1) * step
        else
          local stop
          for _, t in ipairs(tabs) do
            if t > col then
              stop = t
              break
            end
          end
          col = stop or (col + 1)
        end
      end
    end
  end
  if pending_spaces > 0 then
    if not seen_non_blank or all_blanks then
      for _, piece in ipairs(compact_spaces(col, pending_spaces, tabs, step)) do
        out[#out + 1] = piece
      end
    else
      out[#out + 1] = string.rep(" ", pending_spaces)
    end
  end
  return table.concat(out)
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local tabs = { 8 }
  local all_blanks = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-a" or a == "--all" then
      all_blanks = true
      i = i + 1
    elseif a == "--first-only" then
      all_blanks = false
      i = i + 1
    elseif (a == "-t" or a == "--tabs") and i + 1 <= #args then
      local t = parse_tabs(args[i + 1])
      if not t then
        common.err(NAME, "invalid tabs: " .. args[i + 1])
        return 2
      end
      tabs = t
      all_blanks = true
      i = i + 2
    elseif a:sub(1, 2) == "-t" and #a > 2 then
      local t = parse_tabs(a:sub(3))
      if not t then
        common.err(NAME, "invalid tabs: " .. a:sub(3))
        return 2
      end
      tabs = t
      all_blanks = true
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
  local rc = 0
  local step = #tabs == 1 and tabs[1] or 0

  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      for line in common.iter_lines_keep_nl(fh) do
        local body, trailing
        if line:sub(-2) == "\r\n" then
          body, trailing = line:sub(1, -3), "\r\n"
        elseif line:sub(-1) == "\n" then
          body, trailing = line:sub(1, -2), "\n"
        else
          body, trailing = line, ""
        end
        io.stdout:write(convert_line(body, tabs, step, all_blanks), trailing)
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
  help = "convert spaces to tabs",
  main = main,
}
