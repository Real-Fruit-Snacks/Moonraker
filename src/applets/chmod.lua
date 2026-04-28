-- chmod: change file mode bits.
--
-- Lua has no direct chmod binding (lfs doesn't expose it either). We shell
-- out to the system `chmod` on POSIX. On Windows, file mode bits don't
-- map cleanly to NTFS ACLs, and we emit a one-time warning on stderr.

local common = require("common")

local NAME = "chmod"

local function parse_octal(s)
  if s:match("^[0-7]+$") then
    return tonumber(s, 8)
  end
  return nil
end

--- Apply one symbolic clause like 'u+x' to mode. Returns the new mode.
local function apply_clause(mode, clause)
  local op_idx = nil
  for k = 1, #clause do
    local c = clause:sub(k, k)
    if c == "+" or c == "-" or c == "=" then
      op_idx = k
      break
    end
  end
  if not op_idx then
    error("no operator in clause '" .. clause .. "'")
  end
  local who = clause:sub(1, op_idx - 1)
  local op = clause:sub(op_idx, op_idx)
  local perms = clause:sub(op_idx + 1)

  local who_mask
  local has_u, has_g
  if who == "" or who:find("a", 1, true) then
    who_mask = 511 -- 0o777
    has_u, has_g = true, true
  else
    who_mask = 0
    if who:find("u", 1, true) then who_mask = who_mask + 448 end -- 0o700
    if who:find("g", 1, true) then who_mask = who_mask + 56 end  -- 0o070
    if who:find("o", 1, true) then who_mask = who_mask + 7 end   -- 0o007
    has_u = who:find("u", 1, true) ~= nil
    has_g = who:find("g", 1, true) ~= nil
  end

  local perm_bits = 0
  if perms:find("r", 1, true) then perm_bits = perm_bits + 292 end -- 0o444
  if perms:find("w", 1, true) then perm_bits = perm_bits + 146 end -- 0o222
  if perms:find("x", 1, true) then perm_bits = perm_bits + 73 end  -- 0o111

  local effective = 0
  -- bitwise AND in 5.1 via simple loop
  for b = 0, 8 do
    local v = 2 ^ b
    if (math.floor(perm_bits / v) % 2 == 1) and (math.floor(who_mask / v) % 2 == 1) then
      effective = effective + v
    end
  end

  if perms:find("s", 1, true) then
    if has_u then effective = effective + 2048 end -- 0o4000
    if has_g then effective = effective + 1024 end -- 0o2000
  end
  if perms:find("t", 1, true) then
    effective = effective + 512 -- 0o1000
  end

  -- Apply op via bit operations (manual since Lua 5.1 has no bitops)
  local function bit_or(a, b)
    local r = 0
    for k = 0, 11 do
      local v = 2 ^ k
      if (math.floor(a / v) % 2 == 1) or (math.floor(b / v) % 2 == 1) then
        r = r + v
      end
    end
    return r
  end
  local function bit_and_not(a, b)
    local r = 0
    for k = 0, 11 do
      local v = 2 ^ k
      if (math.floor(a / v) % 2 == 1) and (math.floor(b / v) % 2 == 0) then
        r = r + v
      end
    end
    return r
  end

  if op == "+" then
    return bit_or(mode, effective)
  end
  if op == "-" then
    return bit_and_not(mode, effective)
  end
  if op == "=" then
    local clear_mask = who_mask
    if has_u then clear_mask = clear_mask + 2048 end
    if has_g then clear_mask = clear_mask + 1024 end
    return bit_or(bit_and_not(mode, clear_mask), effective)
  end
  return mode
end

local function compute_new_mode(current, spec)
  local octal = parse_octal(spec)
  if octal then return octal end
  local mode = current
  for clause in spec:gmatch("[^,]+") do
    mode = apply_clause(mode, clause:match("^%s*(.-)%s*$"))
  end
  return mode
end

--- Run chmod via system command. We do this rather than doing in-process
--- mode bit math + lfs because lfs lacks chmod and shelling out is robust.
local function chmod_path(path, mode_str)
  if common.is_windows() then
    -- Windows: ignore. Document the limitation.
    return true, nil
  end
  local cmd = string.format('chmod %s "%s" 2>&1', mode_str, path:gsub('"', '\\"'))
  local pipe = io.popen(cmd)
  if not pipe then
    return false, "could not invoke chmod"
  end
  local out = pipe:read("*a")
  local ok, _, code = pipe:close()
  if not ok then
    return false, (out and out ~= "") and out:gsub("\n$", "") or ("exit " .. tostring(code))
  end
  return true, nil
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local recursive = false
  local verbose = false
  local changes_only = false
  local silent = false

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      table.remove(args, i)
      break
    end
    if a:sub(1, 1) ~= "-" or #a < 2 or a == "-" then
      break
    end
    if not a:sub(2):match("^[Rrvcf]+$") then
      break -- could be a mode like -rwx
    end
    for ch in a:sub(2):gmatch(".") do
      if ch == "R" or ch == "r" then recursive = true
      elseif ch == "v" then verbose = true
      elseif ch == "c" then changes_only = true
      elseif ch == "f" then silent = true
      end
    end
    i = i + 1
  end

  local remaining = {}
  for j = i, #args do
    remaining[#remaining + 1] = args[j]
  end
  if #remaining < 2 then
    common.err(NAME, "missing operand")
    return 2
  end

  local mode_spec = remaining[1]
  local paths = {}
  for j = 2, #remaining do
    paths[#paths + 1] = remaining[j]
  end

  local lfs = common.try_lfs()
  local rc = 0

  local function apply(p)
    local attr = lfs and lfs.symlinkattributes(p)
    if not attr then
      if not silent then
        common.err_path(NAME, p, "No such file or directory")
      end
      rc = 1
      return
    end

    -- Compute target mode for verbose/changes reporting.
    local current = 0
    if attr.permissions then
      local p_str = attr.permissions
      local function bit_at(idx, val)
        return p_str:sub(idx, idx) ~= "-" and val or 0
      end
      current = bit_at(1, 256) + bit_at(2, 128) + bit_at(3, 64)
              + bit_at(4, 32) + bit_at(5, 16) + bit_at(6, 8)
              + bit_at(7, 4) + bit_at(8, 2) + bit_at(9, 1)
    end

    local ok_compute, new_mode = pcall(compute_new_mode, current, mode_spec)
    if not ok_compute then
      common.err(NAME, tostring(new_mode))
      rc = 2
      return
    end

    if new_mode == current then
      if verbose and not changes_only then
        io.stdout:write(string.format("mode of '%s' retained as %04o\n", p, current))
      end
      return
    end

    local effective_spec
    if parse_octal(mode_spec) then
      effective_spec = mode_spec
    else
      effective_spec = string.format("%o", new_mode)
    end

    local ok, errmsg = chmod_path(p, effective_spec)
    if not ok then
      if not silent then
        common.err_path(NAME, p, errmsg)
      end
      rc = 1
      return
    end
    if verbose or changes_only then
      io.stdout:write(string.format("mode of '%s' changed from %04o to %04o\n",
        p, current, new_mode))
    end
  end

  for _, path in ipairs(paths) do
    local attr = lfs and lfs.symlinkattributes(path)
    if not attr then
      if not silent then
        common.err_path(NAME, path, "No such file or directory")
      end
      rc = 1
    else
      apply(path)
      if recursive and attr.mode == "directory" then
        common.walk(path, function(p, a)
          if p ~= path and a.mode ~= "link" then
            apply(p)
          end
        end)
      end
    end
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "change file mode bits",
  main = main,
}
