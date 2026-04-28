-- find: search for files in a directory hierarchy.
--
-- Expression-tree evaluator with the most useful POSIX find features:
-- -name, -iname, -path, -ipath, -type, -size, -mtime/-mmin/-atime/-amin/
-- -ctime/-cmin, -newer, -empty, -true, -print, -print0, -delete,
-- -prune, -exec ... ; / +, plus -a / -o / -not / parens.

local common = require("common")

local NAME = "find"

-- ====== Evaluation context ============================================

local function new_ctx()
  return { now = os.time(), pruned = false }
end

-- ====== AST nodes =====================================================
-- Each node is a table with `eval(self, path, attr, ctx)` returning bool
-- and an optional `finalize(self, ctx)` for batched-exec flushing.

local function and_node(a, b)
  return setmetatable({ left = a, right = b, type = "and" }, {
    __index = {
      eval = function(self, p, attr, ctx)
        return self.left:eval(p, attr, ctx) and self.right:eval(p, attr, ctx)
      end,
      finalize = function(self, ctx)
        self.left:finalize(ctx); self.right:finalize(ctx)
      end,
    },
  })
end

local function or_node(a, b)
  return setmetatable({ left = a, right = b, type = "or" }, {
    __index = {
      eval = function(self, p, attr, ctx)
        return self.left:eval(p, attr, ctx) or self.right:eval(p, attr, ctx)
      end,
      finalize = function(self, ctx)
        self.left:finalize(ctx); self.right:finalize(ctx)
      end,
    },
  })
end

local function not_node(inner)
  return setmetatable({ inner = inner, type = "not" }, {
    __index = {
      eval = function(self, p, attr, ctx) return not self.inner:eval(p, attr, ctx) end,
      finalize = function(self, ctx) self.inner:finalize(ctx) end,
    },
  })
end

local function true_node()
  return setmetatable({ type = "true" }, {
    __index = { eval = function() return true end, finalize = function() end },
  })
end

-- ====== Predicate nodes ===============================================

local function name_test(pat, ci)
  return setmetatable({}, {
    __index = {
      eval = function(_, p, _attr, _ctx)
        local n = common.basename(p)
        if ci then
          return common.fnmatch(pat:lower(), n:lower())
        end
        return common.fnmatch(pat, n)
      end,
      finalize = function() end,
    },
  })
end

local function path_test(pat, ci)
  return setmetatable({}, {
    __index = {
      eval = function(_, p)
        if ci then
          return common.fnmatch(pat:lower(), p:lower())
        end
        return common.fnmatch(pat, p)
      end,
      finalize = function() end,
    },
  })
end

local function type_test(t)
  return setmetatable({}, {
    __index = {
      eval = function(_, _p, attr)
        if not attr then return false end
        if t == "f" then return attr.mode == "file" end
        if t == "d" then return attr.mode == "directory" end
        if t == "l" then return attr.mode == "link" end
        return false
      end,
      finalize = function() end,
    },
  })
end

local function size_test(cmp_, n, unit)
  return setmetatable({}, {
    __index = {
      eval = function(_, _p, attr)
        if not attr then return false end
        local size_units = math.ceil((attr.size or 0) / unit)
        if cmp_ == "+" then return size_units > n end
        if cmp_ == "-" then return size_units < n end
        return size_units == n
      end,
      finalize = function() end,
    },
  })
end

local function time_test(which, unit, cmp_, n)
  return setmetatable({}, {
    __index = {
      eval = function(_, _p, attr, ctx)
        if not attr then return false end
        local t = attr.modification
        if which == "a" then t = attr.access
        elseif which == "c" then t = attr.change
        end
        local diff = ctx.now - (t or 0)
        local divisor = unit == "day" and 86400 or 60
        local units = math.floor(diff / divisor)
        if cmp_ == "+" then return units > n end
        if cmp_ == "-" then return units < n end
        return units == n
      end,
      finalize = function() end,
    },
  })
end

local function newer_test(ref_mtime)
  return setmetatable({}, {
    __index = {
      eval = function(_, _p, attr)
        return attr and (attr.modification or 0) > ref_mtime
      end,
      finalize = function() end,
    },
  })
end

local function empty_test()
  return setmetatable({}, {
    __index = {
      eval = function(_, p, attr)
        if not attr then return false end
        if attr.mode == "file" then return (attr.size or 0) == 0 end
        if attr.mode == "directory" then
          local lfs = common.try_lfs()
          if not lfs then return false end
          for entry in lfs.dir(p) do
            if entry ~= "." and entry ~= ".." then return false end
          end
          return true
        end
        return false
      end,
      finalize = function() end,
    },
  })
end

-- ====== Action nodes ==================================================

local function print_action(null_sep)
  return setmetatable({}, {
    __index = {
      eval = function(_, p)
        io.stdout:write(p, null_sep and "\0" or "\n")
        return true
      end,
      finalize = function() end,
    },
  })
end

local function delete_action()
  return setmetatable({}, {
    __index = {
      eval = function(_, p, attr)
        local lfs = common.try_lfs()
        if attr and attr.mode == "directory" then
          if lfs then return lfs.rmdir(p) ~= nil end
        end
        return os.remove(p) ~= nil
      end,
      finalize = function() end,
    },
  })
end

local function prune_action()
  return setmetatable({}, {
    __index = {
      eval = function(_, _p, _attr, ctx) ctx.pruned = true; return true end,
      finalize = function() end,
    },
  })
end

local function exec_action(cmd, mode)
  local self = { cmd = cmd, mode = mode, batch = {} }
  local function flush()
    if #self.batch == 0 then return end
    local argv = {}
    local placeholder = false
    for _, tok in ipairs(self.cmd) do
      if tok == "{}" then
        for _, x in ipairs(self.batch) do argv[#argv + 1] = x end
        placeholder = true
      else
        argv[#argv + 1] = tok
      end
    end
    if not placeholder then
      for _, x in ipairs(self.batch) do argv[#argv + 1] = x end
    end
    -- shell-quote each arg
    local parts = {}
    for _, a in ipairs(argv) do
      parts[#parts + 1] = '"' .. a:gsub('"', '\\"') .. '"'
    end
    os.execute(table.concat(parts, " "))
    self.batch = {}
  end
  return setmetatable(self, {
    __index = {
      eval = function(s, p)
        if s.mode == ";" then
          local argv = {}
          for _, tok in ipairs(s.cmd) do
            argv[#argv + 1] = (tok == "{}") and p or tok
          end
          local parts = {}
          for _, a in ipairs(argv) do
            parts[#parts + 1] = '"' .. a:gsub('"', '\\"') .. '"'
          end
          local ok = os.execute(table.concat(parts, " "))
          return ok == true or ok == 0
        end
        s.batch[#s.batch + 1] = p
        if #s.batch >= 1000 then flush() end
        return true
      end,
      finalize = function(s) if s.mode == "+" then flush() end end,
    },
  })
end

-- ====== Parser ========================================================

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
  return setmetatable({ toks = tokens, i = 1, has_action = false }, Parser)
end

function Parser:peek() return self.toks[self.i] end
function Parser:consume()
  local t = self.toks[self.i]
  self.i = self.i + 1
  return t
end
function Parser:expect(tok)
  if self:peek() ~= tok then
    error("expected '" .. tok .. "', got '" .. tostring(self:peek()) .. "'")
  end
  self:consume()
end

function Parser:parse_expr() return self:parse_or() end

function Parser:parse_or()
  local left = self:parse_and()
  while self:peek() == "-o" or self:peek() == "-or" do
    self:consume()
    left = or_node(left, self:parse_and())
  end
  return left
end

function Parser:parse_and()
  local left = self:parse_not()
  while true do
    local nxt = self:peek()
    if nxt == "-a" or nxt == "-and" then
      self:consume()
      left = and_node(left, self:parse_not())
    elseif nxt == nil or nxt == "-o" or nxt == "-or" or nxt == ")" then
      break
    else
      left = and_node(left, self:parse_not())
    end
  end
  return left
end

function Parser:parse_not()
  if self:peek() == "-not" or self:peek() == "!" then
    self:consume()
    return not_node(self:parse_not())
  end
  return self:parse_primary()
end

function Parser:need_arg(flag)
  if self:peek() == nil then
    error(flag .. ": missing argument")
  end
  return self:consume()
end

function Parser:parse_size_value()
  local v = self:need_arg("-size")
  local cmp_ = "="
  local first = v:sub(1, 1)
  if first == "+" or first == "-" then
    cmp_ = first
    v = v:sub(2)
  end
  local digits = v:match("^(%d+)")
  if not digits then error("-size: invalid value") end
  local n = tonumber(digits)
  local suffix = v:sub(#digits + 1)
  local units = { [""] = 512, b = 512, c = 1, w = 2, k = 1024,
    M = 1024 * 1024, G = 1024 * 1024 * 1024 }
  local unit = units[suffix]
  if not unit then error("-size: unknown unit '" .. suffix .. "'") end
  return size_test(cmp_, n, unit)
end

function Parser:parse_time_value(tok)
  local v = self:need_arg(tok)
  local cmp_ = "="
  local first = v:sub(1, 1)
  if first == "+" or first == "-" then
    cmp_ = first
    v = v:sub(2)
  end
  local n = common.parse_int(v)
  if n == nil then error(tok .. ": invalid value '" .. v .. "'") end
  local which = tok:sub(2, 2)
  local unit = tok:match("min$") and "min" or "day"
  return time_test(which, unit, cmp_, n)
end

function Parser:parse_exec()
  local cmd = {}
  while true do
    if self:peek() == nil then
      error("-exec: unterminated (expected ';' or '+')")
    end
    local t = self:consume()
    if t == ";" or t == "+" then
      return exec_action(cmd, t)
    end
    cmd[#cmd + 1] = t
  end
end

function Parser:parse_primary()
  if self:peek() == "(" then
    self:consume()
    local inner = self:parse_expr()
    self:expect(")")
    return inner
  end
  local tok = self:consume()
  if tok == "-name" then return name_test(self:need_arg(tok)) end
  if tok == "-iname" then return name_test(self:need_arg(tok), true) end
  if tok == "-path" then return path_test(self:need_arg(tok)) end
  if tok == "-ipath" then return path_test(self:need_arg(tok), true) end
  if tok == "-type" then
    local v = self:need_arg(tok)
    if v ~= "f" and v ~= "d" and v ~= "l" then
      error("-type: unsupported type '" .. v .. "'")
    end
    return type_test(v)
  end
  if tok == "-size" then return self:parse_size_value() end
  if tok == "-mtime" or tok == "-mmin" or tok == "-atime"
     or tok == "-amin" or tok == "-ctime" or tok == "-cmin" then
    return self:parse_time_value(tok)
  end
  if tok == "-newer" then
    local ref = self:need_arg(tok)
    local lfs = common.try_lfs()
    local attr = lfs and lfs.attributes(ref)
    if not attr then
      error("-newer: " .. ref .. ": No such file or directory")
    end
    return newer_test(attr.modification or 0)
  end
  if tok == "-empty" then return empty_test() end
  if tok == "-true" then return true_node() end
  if tok == "-print" then self.has_action = true; return print_action(false) end
  if tok == "-print0" then self.has_action = true; return print_action(true) end
  if tok == "-delete" then self.has_action = true; return delete_action() end
  if tok == "-prune" then return prune_action() end
  if tok == "-exec" then self.has_action = true; return self:parse_exec() end
  error("unknown predicate: '" .. tostring(tok) .. "'")
end

-- ====== Driver ========================================================

local function extract_globals(tokens)
  local mindepth, maxdepth = 0, -1
  local out = {}
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t == "-maxdepth" and i + 1 <= #tokens then
      local n = common.parse_int(tokens[i + 1])
      if not n then
        common.err(NAME, "-maxdepth: invalid value '" .. tokens[i + 1] .. "'")
        return nil
      end
      maxdepth = n
      i = i + 2
    elseif t == "-mindepth" and i + 1 <= #tokens then
      local n = common.parse_int(tokens[i + 1])
      if not n then
        common.err(NAME, "-mindepth: invalid value '" .. tokens[i + 1] .. "'")
        return nil
      end
      mindepth = n
      i = i + 2
    else
      out[#out + 1] = t
      i = i + 1
    end
  end
  return out, mindepth, maxdepth
end

local function walk_tree(root, expr, mindepth, maxdepth, ctx)
  local lfs = common.try_lfs()
  if not lfs then return 1 end
  local rc = 0

  local function visit(p, depth)
    local attr = lfs.symlinkattributes(p)
    if not attr then
      common.err_path(NAME, p, "No such file or directory")
      rc = 1
      return
    end
    ctx.pruned = false
    if depth >= mindepth and (maxdepth < 0 or depth <= maxdepth) then
      local ok, err = pcall(function() expr:eval(p, attr, ctx) end)
      if not ok then
        common.err(NAME, tostring(err))
        rc = 1
      end
    end
    if ctx.pruned then return end
    if maxdepth >= 0 and depth >= maxdepth then return end
    if attr.mode ~= "directory" or attr.mode == "link" then return end
    local entries = {}
    local ok = pcall(function()
      for entry in lfs.dir(p) do
        if entry ~= "." and entry ~= ".." then
          entries[#entries + 1] = entry
        end
      end
    end)
    if not ok then
      common.err_path(NAME, p, "could not read directory")
      rc = 1
      return
    end
    table.sort(entries)
    for _, entry in ipairs(entries) do
      visit(common.path_join(p, entry), depth + 1)
    end
  end

  visit(root, 0)
  return rc
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local paths = {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a:sub(1, 1) == "-" or a == "(" or a == ")" or a == "!" then
      break
    end
    paths[#paths + 1] = a
    i = i + 1
  end
  local expr_tokens = {}
  for j = i, #args do
    expr_tokens[#expr_tokens + 1] = args[j]
  end
  if #paths == 0 then
    paths = { "." }
  end

  local tokens, mindepth, maxdepth = extract_globals(expr_tokens)
  if not tokens then return 2 end

  local parser = Parser.new(tokens)
  local expr
  if #tokens == 0 then
    expr = true_node()
  else
    local ok, result = pcall(function() return parser:parse_expr() end)
    if not ok then
      common.err(NAME, tostring(result))
      return 2
    end
    expr = result
  end
  if parser.i <= #tokens then
    common.err(NAME, "unexpected token: '" .. tostring(tokens[parser.i]) .. "'")
    return 2
  end
  if not parser.has_action then
    expr = and_node(expr, print_action(false))
  end

  local ctx = new_ctx()
  local rc = 0
  local lfs = common.try_lfs()
  for _, p in ipairs(paths) do
    if not lfs or not lfs.symlinkattributes(p) then
      common.err_path(NAME, p, "No such file or directory")
      rc = 1
    else
      local r = walk_tree(p, expr, mindepth, maxdepth, ctx)
      if r ~= 0 then rc = r end
    end
  end
  expr:finalize(ctx)
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "search for files in a directory hierarchy",
  main = main,
}
