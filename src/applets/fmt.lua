-- fmt: simple optimal text formatter.

local common = require("common")

local NAME = "fmt"

local function split_words(line)
  local out = {}
  for w in line:gmatch("%S+") do
    out[#out + 1] = w
  end
  return out
end

local function reflow(paragraph, width)
  local words = {}
  for _, line in ipairs(paragraph) do
    for _, w in ipairs(split_words(line)) do
      words[#words + 1] = w
    end
  end
  if #words == 0 then return {} end
  local out = {}
  local cur = {}
  local cur_len = 0
  for _, w in ipairs(words) do
    local new_len = cur_len + #w + (#cur > 0 and 1 or 0)
    if #cur > 0 and new_len > width then
      out[#out + 1] = table.concat(cur, " ")
      cur = { w }
      cur_len = #w
    else
      cur[#cur + 1] = w
      cur_len = new_len
    end
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur, " ") end
  return out
end

local function split_long(line, width)
  if #line <= width then return { line } end
  local out = {}
  local cur = ""
  for _, w in ipairs(split_words(line)) do
    if cur ~= "" and #cur + 1 + #w > width then
      out[#out + 1] = cur
      cur = w
    elseif cur ~= "" then
      cur = cur .. " " .. w
    else
      cur = w
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end

local function read_lines(fh)
  local data = common.read_all(fh)
  local lines = {}
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  -- Trim a trailing empty entry that gmatch produces if input ends with \n.
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local width = 75
  local split_only = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if (a == "-w" or a == "--width") and i + 1 <= #args then
      local n = common.parse_int(args[i + 1])
      if not n then
        common.err(NAME, "invalid width: " .. args[i + 1])
        return 2
      end
      width = n
      i = i + 2
    elseif a:sub(1, 2) == "-w" and #a > 2 and a:sub(3):match("^%d+$") then
      width = tonumber(a:sub(3))
      i = i + 1
    elseif a == "-u" or a == "--uniform-spacing" then
      i = i + 1
    elseif a == "-c" or a == "--crown-margin" then
      i = i + 1
    elseif a == "-t" or a == "--tagged-paragraph" then
      i = i + 1
    elseif a == "-s" or a == "--split-only" then
      split_only = true
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      width = tonumber(a:sub(2))
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
  if #files == 0 then files = { "-" } end

  local rc = 0
  local out_lines = {}
  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      local lines = read_lines(fh)
      if f ~= "-" then fh:close() end
      local paragraph = {}
      local function flush()
        if #paragraph > 0 then
          if split_only then
            for _, p_line in ipairs(paragraph) do
              for _, sub in ipairs(split_long(p_line, width)) do
                out_lines[#out_lines + 1] = sub
              end
            end
          else
            for _, ln in ipairs(reflow(paragraph, width)) do
              out_lines[#out_lines + 1] = ln
            end
          end
          paragraph = {}
        end
      end
      for _, line in ipairs(lines) do
        if line:match("^%s*$") then
          flush()
          out_lines[#out_lines + 1] = ""
        else
          paragraph[#paragraph + 1] = line
        end
      end
      flush()
    end
  end

  if #out_lines > 0 then io.stdout:write(table.concat(out_lines, "\n"), "\n") end
  io.stdout:flush()
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "simple optimal text formatter",
  main = main,
}
