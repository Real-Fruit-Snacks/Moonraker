-- which: locate a command on PATH.

local common = require("common")

local NAME = "which"

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local all_matches = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 then break end
    for ch in a:sub(2):gmatch(".") do
      if ch == "a" then
        all_matches = true
      else
        common.err(NAME, "invalid option: -" .. ch)
        return 2
      end
    end
    i = i + 1
  end

  local names = {}
  for j = i, #args do
    names[#names + 1] = args[j]
  end
  if #names == 0 then
    common.err(NAME, "missing command name")
    return 2
  end

  local sep = common.is_windows() and ";" or ":"
  local path_env = os.getenv("PATH") or ""
  local path_dirs = {}
  for d in (path_env .. sep):gmatch("([^" .. sep .. "]+)") do
    if d ~= "" then path_dirs[#path_dirs + 1] = d end
  end

  local pathexts = { "" }
  if common.is_windows() then
    local pe = os.getenv("PATHEXT") or ".EXE;.BAT;.CMD;.COM"
    for ext in (pe .. ";"):gmatch("([^;]+)") do
      if ext ~= "" then pathexts[#pathexts + 1] = ext:lower() end
    end
  end

  local lfs = common.try_lfs()
  local function is_file(p)
    if not lfs then
      local fh = io.open(p, "rb")
      if fh then
        fh:close()
        return true
      end
      return false
    end
    local attr = lfs.attributes(p)
    return attr and attr.mode == "file"
  end

  local rc = 0
  for _, name in ipairs(names) do
    local found = {}
    if name:find("[/\\]") then
      if is_file(name) then found[#found + 1] = name end
    else
      for _, d in ipairs(path_dirs) do
        for _, ext in ipairs(pathexts) do
          local cand = common.path_join(d, name .. ext)
          if is_file(cand) then
            found[#found + 1] = cand
            if not all_matches then break end
          end
        end
        if #found > 0 and not all_matches then break end
      end
    end
    if #found == 0 then
      rc = 1
    else
      for _, m in ipairs(found) do
        io.stdout:write(m, "\n")
        if not all_matches then break end
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = { "where" },
  help = "locate a command on PATH",
  main = main,
}
