-- expand: convert tabs to spaces.

local common = require("common")

local NAME = "expand"

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

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local tabs = { 8 }
  local initial_only = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a == "-i" or a == "--initial" then
      initial_only = true
      i = i + 1
    elseif (a == "-t" or a == "--tabs") and i + 1 <= #args then
      local t = parse_tabs(args[i + 1])
      if not t then
        common.err(NAME, "invalid tabs: " .. args[i + 1])
        return 2
      end
      tabs = t
      i = i + 2
    elseif a:sub(1, 2) == "-t" and #a > 2 then
      local t = parse_tabs(a:sub(3))
      if not t then
        common.err(NAME, "invalid tabs: " .. a:sub(3))
        return 2
      end
      tabs = t
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a:sub(2):match("^%d+$") then
      tabs = { tonumber(a:sub(2)) }
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
        local col = 0
        local seen_non_blank = false
        local out = {}
        for k = 1, #body do
          local ch = body:sub(k, k)
          if ch == "\t" then
            if initial_only and seen_non_blank then
              out[#out + 1] = "\t"
              col = col + 1
            else
              local n
              if #tabs == 1 then
                local step = tabs[1]
                n = step - (col % step)
              else
                local stop
                for _, t in ipairs(tabs) do
                  if t > col then
                    stop = t
                    break
                  end
                end
                n = stop and (stop - col) or 1
              end
              out[#out + 1] = string.rep(" ", n)
              col = col + n
            end
          else
            out[#out + 1] = ch
            col = col + 1
            if ch ~= " " then
              seen_non_blank = true
            end
          end
        end
        io.stdout:write(table.concat(out), trailing)
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
  help = "convert tabs to spaces",
  main = main,
}
