-- grep: print lines matching a pattern.
--
-- Phase 2 implementation: pattern matching is backed by Lua's built-in
-- string patterns rather than POSIX BRE/ERE. The two engines have
-- significant differences:
--
--   * Character classes use `%a`, `%d`, `%s`, `%w`, `%p` instead of
--     `[a-z]`, `[0-9]`, etc. Bracket expressions like `[abc]` still work.
--   * Quantifiers `*`, `+`, `?`, `-` (non-greedy *) are supported.
--   * **No alternation (`|`)** — `foo|bar` won't match.
--   * **No backreferences** in patterns (`\1` etc.).
--   * **No lookahead / lookbehind**.
--   * `.` matches any byte; `%.` matches a literal dot.
--
-- `-F` (fixed string) and `-E` (treat as Lua pattern; alternation still
-- unsupported) flags are accepted. `-i` lowercases both the pattern and
-- the line for matching.
--
-- TODO(phase2.5): vendor LPeg via cdeps/ and build a thin POSIX BRE/ERE
-- layer on top so grep can match Mainsail's regex behavior 1:1.

local common = require("common")

local NAME = "grep"

--- Escape Lua-pattern magic characters so the input becomes a literal match.
local function escape_pattern(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function lower_string(s)
  return s:lower()
end

local function parse_count(flag, value)
  local n = common.parse_int(value)
  if n == nil or n < 0 then
    common.err(NAME, flag .. ": invalid number '" .. value .. "'")
    return nil
  end
  return n
end

local function rstrip_nl(s)
  return (s:gsub("[\r\n]+$", ""))
end

local function read_lines(fh)
  local lines = {}
  for raw in common.iter_lines_keep_nl(fh) do
    lines[#lines + 1] = rstrip_nl(raw)
  end
  return lines
end

local function find_all(text, pattern)
  local matches = {}
  local start = 1
  while start <= #text do
    local s, e = text:find(pattern, start)
    if not s then break end
    if e < s then
      -- zero-width match — advance to avoid infinite loop
      matches[#matches + 1] = { s = s, e = e }
      start = e + 2
    else
      matches[#matches + 1] = { s = s, e = e }
      start = e + 1
    end
  end
  return matches
end

local function walk_dir(path, out, lfs)
  local attr = lfs.attributes(path)
  if not attr then return end
  if attr.mode == "directory" then
    local entries = {}
    for entry in lfs.dir(path) do
      if entry ~= "." and entry ~= ".." then entries[#entries + 1] = entry end
    end
    table.sort(entries)
    for _, entry in ipairs(entries) do
      walk_dir(path .. "/" .. entry, out, lfs)
    end
  else
    out[#out + 1] = path
  end
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local ignore_case, invert = false, false
  local show_line_num = false
  local recursive = false
  local fixed_string = false
  local list_files = false
  local count_only = false
  local word_match = false
  local only_matching = false
  local quiet = false
  local before_n, after_n = 0, 0

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end

    if a == "-A" or a == "-B" or a == "-C" then
      if i + 1 > #args then
        common.err(NAME, a .. ": missing argument")
        return 2
      end
      local n = parse_count(a, args[i + 1])
      if n == nil then return 2 end
      if a == "-A" then
        after_n = math.max(after_n, n)
      elseif a == "-B" then
        before_n = math.max(before_n, n)
      else
        before_n = math.max(before_n, n)
        after_n = math.max(after_n, n)
      end
      i = i + 2
    elseif
      #a > 2
      and (a:sub(1, 2) == "-A" or a:sub(1, 2) == "-B" or a:sub(1, 2) == "-C")
      and a:sub(3):match("^%d+$")
    then
      local flag = a:sub(1, 2)
      local n = parse_count(flag, a:sub(3))
      if n == nil then return 2 end
      if flag == "-A" then
        after_n = math.max(after_n, n)
      elseif flag == "-B" then
        before_n = math.max(before_n, n)
      else
        before_n = math.max(before_n, n)
        after_n = math.max(after_n, n)
      end
      i = i + 1
    elseif a:sub(1, 1) ~= "-" or #a < 2 or a == "-" then
      break
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "i" then
          ignore_case = true
        elseif ch == "v" then
          invert = true
        elseif ch == "n" then
          show_line_num = true
        elseif ch == "r" or ch == "R" then
          recursive = true
        elseif ch == "F" then
          fixed_string = true
        elseif ch == "l" then
          list_files = true
        elseif ch == "c" then
          count_only = true
        elseif ch == "w" then
          word_match = true
        elseif ch == "o" then
          only_matching = true
        elseif ch == "q" then
          quiet = true
        elseif ch == "E" then -- luacheck: ignore
          -- accepted for compat; we don't change patterns since Lua
          -- patterns are the only engine we have right now
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
      i = i + 1
    end
  end

  local remaining = {}
  for j = i, #args do
    remaining[#remaining + 1] = args[j]
  end
  if #remaining == 0 then
    common.err(NAME, "missing pattern")
    return 2
  end

  local pattern = remaining[1]
  local targets = {}
  for j = 2, #remaining do
    targets[#targets + 1] = remaining[j]
  end

  if fixed_string then pattern = escape_pattern(pattern) end
  if word_match then
    -- Lua patterns: %f[%w_] is a frontier pattern, similar to \b at start.
    pattern = "%f[%w_]" .. pattern .. "%f[^%w_]"
  end
  if ignore_case then pattern = pattern:lower() end

  -- Validate the pattern by attempting a no-op match.
  local ok = pcall(string.find, "", pattern)
  if not ok then
    common.err(NAME, "bad pattern: " .. pattern)
    return 2
  end

  if #targets == 0 then targets = { "-" } end

  if recursive then
    local lfs = common.try_lfs()
    if lfs then
      local expanded = {}
      for _, t in ipairs(targets) do
        walk_dir(t, expanded, lfs)
      end
      targets = expanded
    end
  end

  local show_filename = #targets > 1 or recursive
  local matched_any = false

  local function write_line(path, lineno, text, match_sep)
    local parts = {}
    if show_filename then parts[#parts + 1] = path end
    if show_line_num then parts[#parts + 1] = tostring(lineno) end
    parts[#parts + 1] = text
    local sep = match_sep and ":" or "-"
    io.stdout:write(table.concat(parts, sep), "\n")
  end

  for _, t in ipairs(targets) do
    local fh, errmsg = common.open_input(t, "rb")
    if not fh then
      common.err_path(NAME, t, errmsg)
    else
      local lines = read_lines(fh)
      if t ~= "-" then fh:close() end

      local match_map = {}
      for n, text in ipairs(lines) do
        local needle = ignore_case and lower_string(text) or text
        local found = find_all(needle, pattern)
        local has = #found > 0
        local is_match = has ~= invert
        if is_match then match_map[n] = invert and {} or found end
      end

      local function any_matches()
        return next(match_map) ~= nil
      end

      if quiet then
        if any_matches() then return 0 end
      elseif list_files then
        if any_matches() then
          matched_any = true
          io.stdout:write(t, "\n")
        end
      elseif count_only then
        local cnt = 0
        for _ in pairs(match_map) do
          cnt = cnt + 1
        end
        if show_filename then
          io.stdout:write(t, ":", tostring(cnt), "\n")
        else
          io.stdout:write(tostring(cnt), "\n")
        end
        if cnt > 0 then matched_any = true end
      elseif only_matching then
        for n, text in ipairs(lines) do
          if match_map[n] then
            for _, m in ipairs(match_map[n]) do
              write_line(t, n, text:sub(m.s, m.e), true)
            end
          end
        end
        if any_matches() then matched_any = true end
      else
        if any_matches() then
          matched_any = true
          local to_print = {}
          for n in pairs(match_map) do
            to_print[n] = true
          end
          if before_n > 0 or after_n > 0 then
            local total = #lines
            for n in pairs(match_map) do
              for k = math.max(1, n - before_n), math.min(total, n + after_n) do
                if to_print[k] == nil then to_print[k] = false end
              end
            end
          end
          local has_context = before_n > 0 or after_n > 0
          local prev_printed = nil
          for n, text in ipairs(lines) do
            if to_print[n] ~= nil then
              if has_context and prev_printed and n - prev_printed > 1 then io.stdout:write("--\n") end
              write_line(t, n, text, to_print[n])
              prev_printed = n
            end
          end
        end
      end
    end
  end

  return matched_any and 0 or 1
end

return {
  name = NAME,
  aliases = {},
  help = "print lines matching a pattern",
  main = main,
}
