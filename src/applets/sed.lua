-- sed: stream editor.
--
-- Lua port of mainsail's sed.py. Supports the workhorse subset:
--   * Addresses: line number, $, /regex/, range, ! (negation)
--   * Commands: s/// (with flags g, i, p, N), d, p, q, =, y/src/dst/
--   * Options:  -n, -E (ERE), -i (in-place), -e SCRIPT, -f FILE
--
-- BRE is the default per POSIX; -E switches to ERE. Internally we
-- compile patterns through src/regex.lua (ERE-on-LPeg). The BRE
-- translator below swaps escaped metas (\(, \), \?, \+, \{...\}, \|)
-- so the regex engine always sees ERE.

local common = require("common")
local regex = require("regex")

local NAME = "sed"

-- ---------------------------------------------------------------------
-- BRE → ERE translator
-- ---------------------------------------------------------------------

local BRE_SWAP = {
  ["("] = true,
  [")"] = true,
  ["{"] = true,
  ["}"] = true,
  ["+"] = true,
  ["?"] = true,
  ["|"] = true,
}

local function bre_to_ere(pattern)
  local out = {}
  local i = 1
  while i <= #pattern do
    local c = pattern:sub(i, i)
    if c == "\\" and i + 1 <= #pattern then
      local nxt = pattern:sub(i + 1, i + 1)
      if BRE_SWAP[nxt] then
        out[#out + 1] = nxt -- BRE \( becomes ERE (
      else
        out[#out + 1] = c .. nxt
      end
      i = i + 2
    elseif BRE_SWAP[c] then
      out[#out + 1] = "\\" .. c -- BRE bare ( is literal
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------
-- Script parser
-- ---------------------------------------------------------------------

local function skip_ws(s, i)
  while i <= #s and s:sub(i, i):match("[ \t\n;]") do
    i = i + 1
  end
  return i
end

local function read_delim_part(s, i, delim)
  local start = i
  while i <= #s and s:sub(i, i) ~= delim do
    if s:sub(i, i) == "\\" and i + 1 <= #s then
      i = i + 2
    else
      i = i + 1
    end
  end
  return s:sub(start, i - 1), i
end

local function parse_address(s, i)
  if i > #s then return nil, i end
  local c = s:sub(i, i)
  if c:match("%d") then
    local start = i
    while i <= #s and s:sub(i, i):match("%d") do
      i = i + 1
    end
    return s:sub(start, i - 1), i
  end
  if c == "$" then return "$", i + 1 end
  if c == "/" then
    i = i + 1
    local pat
    pat, i = read_delim_part(s, i, "/")
    if i <= #s then i = i + 1 end
    return "/" .. pat .. "/", i
  end
  return nil, i
end

local function parse_script(script, extended)
  local cmds = {}
  local i = 1
  while i <= #script do
    i = skip_ws(script, i)
    if i > #script then break end

    local addr1, addr2
    addr1, i = parse_address(script, i)
    if i <= #script and script:sub(i, i) == "," then
      i = i + 1
      addr2, i = parse_address(script, i)
    end

    while i <= #script and script:sub(i, i):match("[ \t]") do
      i = i + 1
    end
    local negate = false
    if i <= #script and script:sub(i, i) == "!" then
      negate = true
      i = i + 1
      while i <= #script and script:sub(i, i):match("[ \t]") do
        i = i + 1
      end
    end

    if i > #script then break end
    local op = script:sub(i, i)
    i = i + 1
    local cmd = { op = op, addr1 = addr1, addr2 = addr2, negate = negate }

    if op == "s" then
      if i > #script then return nil, "s: missing delimiter" end
      local delim = script:sub(i, i)
      i = i + 1
      cmd.pattern, i = read_delim_part(script, i, delim)
      if i <= #script then i = i + 1 end
      cmd.replacement, i = read_delim_part(script, i, delim)
      if i <= #script then i = i + 1 end
      local fstart = i
      while i <= #script and not script:sub(i, i):match("[ \t\n;]") do
        i = i + 1
      end
      cmd.flags = script:sub(fstart, i - 1)
      local pat = extended and cmd.pattern or bre_to_ere(cmd.pattern)
      local case_insensitive = cmd.flags:find("[iI]") ~= nil
      local ok, compiled = pcall(regex.compile, pat, { ignore_case = case_insensitive })
      if not ok then return nil, "bad regex '" .. cmd.pattern .. "': " .. tostring(compiled) end
      cmd._compiled = compiled
    elseif op == "y" then
      if i > #script then return nil, "y: missing delimiter" end
      local delim = script:sub(i, i)
      i = i + 1
      cmd.src, i = read_delim_part(script, i, delim)
      if i <= #script then i = i + 1 end
      cmd.dst, i = read_delim_part(script, i, delim)
      if i <= #script then i = i + 1 end
    elseif not (op == "d" or op == "p" or op == "q" or op == "=") then
      return nil, "unsupported command: '" .. op .. "'"
    end

    cmds[#cmds + 1] = cmd
  end
  return cmds
end

-- ---------------------------------------------------------------------
-- Address evaluation
-- ---------------------------------------------------------------------

local function match_addr(addr, lineno, line, last_lineno)
  if addr == "$" then return last_lineno ~= nil and lineno == last_lineno end
  if addr:match("^%d+$") then return lineno == tonumber(addr) end
  if addr:sub(1, 1) == "/" and addr:sub(-1) == "/" and #addr >= 2 then
    local pat = addr:sub(2, -2)
    local ok, compiled = pcall(regex.compile, pat)
    if not ok then return false end
    return compiled:find(line) ~= nil
  end
  return false
end

local function active_for(cmd, lineno, line, last, state)
  local base
  if cmd.addr1 == nil then
    base = true
  elseif cmd.addr2 == nil then
    base = match_addr(cmd.addr1, lineno, line, last)
  else
    local key = cmd
    local in_range = state[key] or false
    if not in_range and match_addr(cmd.addr1, lineno, line, last) then
      in_range = true
      state[key] = true
    end
    base = in_range
    if in_range and match_addr(cmd.addr2, lineno, line, last) then state[key] = false end
  end
  if cmd.negate then return not base end
  return base
end

-- ---------------------------------------------------------------------
-- Execution
-- ---------------------------------------------------------------------

local function run(cmds, lines, quiet)
  local output = {}
  local state = {}
  local total = #lines
  local quitting = false

  for lineno = 1, total do
    if quitting then break end
    local raw = lines[lineno]
    local pattern_space, had_nl
    if raw:sub(-1) == "\n" then
      pattern_space = raw:sub(1, -2)
      had_nl = true
    else
      pattern_space = raw
      had_nl = false
    end
    local deleted = false

    for _, cmd in ipairs(cmds) do
      if deleted or quitting then break end
      if active_for(cmd, lineno, pattern_space, total, state) then
        if cmd.op == "s" then
          local n_replace = cmd.flags:find("g", 1, true) and math.huge or 1
          local new_space, nsubs = cmd._compiled:gsub(pattern_space, cmd.replacement, n_replace)
          pattern_space = new_space
          if cmd.flags:find("p", 1, true) and nsubs > 0 then output[#output + 1] = pattern_space .. "\n" end
        elseif cmd.op == "d" then
          deleted = true
        elseif cmd.op == "p" then
          output[#output + 1] = pattern_space .. "\n"
        elseif cmd.op == "q" then
          if not quiet then output[#output + 1] = pattern_space .. (had_nl and "\n" or "") end
          quitting = true
        elseif cmd.op == "=" then
          output[#output + 1] = tostring(lineno) .. "\n"
        elseif cmd.op == "y" then
          if #cmd.src ~= #cmd.dst then return nil, "y: source and destination differ in length" end
          local table_map = {}
          for k = 1, #cmd.src do
            table_map[cmd.src:sub(k, k)] = cmd.dst:sub(k, k)
          end
          local out = {}
          for k = 1, #pattern_space do
            local ch = pattern_space:sub(k, k)
            out[#out + 1] = table_map[ch] or ch
          end
          pattern_space = table.concat(out)
        end
      end
    end

    if not deleted and not quitting and not quiet then
      output[#output + 1] = pattern_space .. (had_nl and "\n" or "")
    end
  end

  return output
end

-- ---------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------

local function read_lines(path)
  local fh
  if path == "-" then
    fh = io.stdin
  else
    local err
    fh, err = io.open(path, "rb")
    if not fh then return nil, err end
  end
  local lines = {}
  for line in common.iter_lines_keep_nl(fh) do
    lines[#lines + 1] = line
  end
  if path ~= "-" then fh:close() end
  return lines
end

local function main(argv)
  local args = {}
  for k = 1, #argv do
    args[k] = argv[k]
  end

  local quiet, in_place, extended = false, false, false
  local scripts = {}
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
    if a == "-n" or a == "--quiet" or a == "--silent" then
      quiet = true
      i = i + 1
    elseif a == "-E" or a == "-r" or a == "--regexp-extended" then
      extended = true
      i = i + 1
    elseif a == "-i" or a == "--in-place" then
      in_place = true
      i = i + 1
    elseif a == "-e" then
      if not args[i + 1] then
        common.err(NAME, "-e: missing argument")
        return 2
      end
      scripts[#scripts + 1] = args[i + 1]
      i = i + 2
    elseif a:sub(1, 2) == "-e" then
      scripts[#scripts + 1] = a:sub(3)
      i = i + 1
    elseif a == "-f" then
      if not args[i + 1] then
        common.err(NAME, "-f: missing argument")
        return 2
      end
      local fh, err = io.open(args[i + 1], "rb")
      if not fh then
        common.err_path(NAME, args[i + 1], err or "open failed")
        return 1
      end
      scripts[#scripts + 1] = fh:read("*a") or ""
      fh:close()
      i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "invalid option: " .. a)
      return 2
    else
      break
    end
  end

  local positional = {}
  for j = i, #args do
    positional[#positional + 1] = args[j]
  end
  if #scripts == 0 then
    if #positional == 0 then
      common.err(NAME, "missing script")
      return 2
    end
    scripts[#scripts + 1] = positional[1]
    table.remove(positional, 1)
  end
  for _, f in ipairs(positional) do
    files[#files + 1] = f
  end

  local script = table.concat(scripts, "\n")
  local cmds, perr = parse_script(script, extended)
  if not cmds then
    common.err(NAME, perr or "parse failed")
    return 2
  end

  if #files == 0 then files = { "-" } end

  if in_place then
    for _, f in ipairs(files) do
      if f == "-" then
        common.err(NAME, "-i cannot be used with stdin")
        return 2
      end
    end
  end

  local rc = 0
  for _, f in ipairs(files) do
    local lines, lerr = read_lines(f)
    if not lines then
      common.err_path(NAME, f, lerr or "read failed")
      rc = 1
    else
      local out_lines, rerr = run(cmds, lines, quiet)
      if not out_lines then
        common.err(NAME, rerr or "run failed")
        return 2
      end
      if in_place then
        local tmp = f .. ".moonraker_tmp"
        local fh, oerr = io.open(tmp, "wb")
        if not fh then
          common.err_path(NAME, f, oerr or "open failed")
          rc = 1
        else
          for _, l in ipairs(out_lines) do
            fh:write(l)
          end
          fh:close()
          local ok, rrerr = os.rename(tmp, f)
          if not ok then
            pcall(os.remove, tmp)
            common.err_path(NAME, f, rrerr or "rename failed")
            rc = 1
          end
        end
      else
        for _, l in ipairs(out_lines) do
          io.stdout:write(l)
        end
      end
    end
  end

  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "stream editor: basic s///, d, p, q, =, y and addresses",
  main = main,
}
