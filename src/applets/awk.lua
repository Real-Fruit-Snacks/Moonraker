-- awk: pattern-scanning and processing language.
--
-- Lua port of mainsail's awk.py. Implements a practical POSIX-awk
-- subset: BEGIN/END, /regex/ patterns, expression patterns, range
-- patterns, print/printf, control flow (if/else, while, do-while,
-- for, for-in, break/continue/next/exit), associative arrays,
-- delete, `k in a`, fields ($0/$1/...), built-in vars (NR/NF/FS/OFS/
-- RS/ORS/FILENAME/FNR), arithmetic + string operators, ~/!~ regex
-- matching, and built-in functions: length/substr/index/split/sub/
-- gsub/match/toupper/tolower/sprintf/int/sqrt/log/exp/sin/cos/atan2/
-- rand/srand/system.
--
-- Not implemented (v1):
--   * user-defined functions (function ... { ... })
--   * getline
--   * full multidimensional arrays via SUBSEP (CONCAT_SUBSEP works
--     internally so a["x","y"] roughly works, but mixing with
--     `(k1, k2) in a` doesn't)

local common = require("common")
local regex = require("regex")

local NAME = "awk"
local SUBSEP = "\28"

-- ---------------------------------------------------------------------
-- Sentinels for control flow (since Lua has no exceptions)
-- ---------------------------------------------------------------------

local NEXT_RECORD = {}
local BREAK_LOOP = {}
local CONTINUE_LOOP = {}
local function EXIT_PROGRAM(code) return { _exit = true, code = code } end

-- ---------------------------------------------------------------------
-- Number / string / boolean coercions
-- ---------------------------------------------------------------------

local function is_numeric_string(s)
  if type(s) ~= "string" or s == "" then return false end
  return s:match("^%s*[+-]?(%d+%.?%d*)([eE][+-]?%d+)?%s*$") ~= nil
    or s:match("^%s*[+-]?(%.%d+)([eE][+-]?%d+)?%s*$") ~= nil
end

local function is_numeric_value(v)
  if type(v) == "number" then return true end
  if type(v) ~= "string" then return false end
  return is_numeric_string(v)
end

local function to_num(v)
  if type(v) == "boolean" then return v and 1 or 0 end
  if type(v) == "number" then return v end
  if v == nil then return 0 end
  -- Match leading numeric prefix (awk-style).
  local m = tostring(v):match("^%s*([+-]?%d+%.?%d*[eE]?[+-]?%d*)")
  if not m or m == "" then
    m = tostring(v):match("^%s*([+-]?%.%d+[eE]?[+-]?%d*)")
  end
  return tonumber(m) or 0
end

local function format_num(n, ofmt)
  if n == math.floor(n) and math.abs(n) < 1e16 then
    return string.format("%d", n)
  end
  return string.format(ofmt or "%.6g", n)
end

local function to_str(v, ofmt)
  if v == nil then return "" end
  if type(v) == "boolean" then return v and "1" or "0" end
  if type(v) == "number" then return format_num(v, ofmt) end
  return tostring(v)
end

local function to_bool(v)
  if v == nil or v == "" then return false end
  if type(v) == "number" then return v ~= 0 end
  if type(v) == "string" then
    if is_numeric_string(v) then return tonumber(v) ~= 0 end
    return v ~= ""
  end
  return v == true
end

-- ---------------------------------------------------------------------
-- Lexer
-- ---------------------------------------------------------------------

local KEYWORDS = {
  BEGIN = true, ["END"] = true,
  ["if"] = true, ["else"] = true,
  ["while"] = true, ["for"] = true, ["do"] = true, ["in"] = true,
  print = true, printf = true,
  next = true, exit = true, ["break"] = true, continue = true,
  delete = true, ["function"] = true, ["return"] = true, getline = true,
}

local MULTI_OPS = {
  ["=="] = true, ["!="] = true, ["<="] = true, [">="] = true,
  ["&&"] = true, ["||"] = true, ["++"] = true, ["--"] = true,
  ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true,
  ["%="] = true, ["^="] = true, ["**"] = true, ["!~"] = true,
}

local SINGLE_OPS = "+-*%^=<>!~,;(){}[]?:$/"

local function regex_context(prev)
  if prev == nil then return true end
  if prev == "NUMBER" or prev == "STRING" or prev == "NAME"
     or prev == "REGEX" or prev == ")" or prev == "]"
     or prev == "++" or prev == "--" then
    return false
  end
  return true
end

local function tokenize(src)
  local tokens = {}
  local i = 1
  local line = 1
  local prev = nil

  local function add(kind, val)
    tokens[#tokens + 1] = { kind = kind, val = val, line = line }
    prev = kind
  end

  local function read_number()
    local start = i
    while i <= #src and (src:sub(i, i):match("%d") or src:sub(i, i) == ".") do
      i = i + 1
    end
    if i <= #src and src:sub(i, i):match("[eE]") then
      i = i + 1
      if i <= #src and src:sub(i, i):match("[+-]") then i = i + 1 end
      while i <= #src and src:sub(i, i):match("%d") do i = i + 1 end
    end
    return tonumber(src:sub(start, i - 1)) or 0
  end

  local function read_string()
    i = i + 1
    local out = {}
    while i <= #src and src:sub(i, i) ~= '"' do
      local c = src:sub(i, i)
      if c == "\\" and i + 1 <= #src then
        local n = src:sub(i + 1, i + 1)
        local esc = ({
          n = "\n", t = "\t", r = "\r", ["\\"] = "\\",
          ['"'] = '"', ["/"] = "/", a = "\a", b = "\b",
          f = "\f", v = "\v",
        })[n]
        out[#out + 1] = esc or n
        i = i + 2
      else
        if c == "\n" then line = line + 1 end
        out[#out + 1] = c
        i = i + 1
      end
    end
    if i > #src then error("awk: unterminated string at line " .. line) end
    i = i + 1
    return table.concat(out)
  end

  local function read_regex()
    i = i + 1
    local out = {}
    while i <= #src and src:sub(i, i) ~= "/" do
      local c = src:sub(i, i)
      if c == "\\" and i + 1 <= #src then
        local n = src:sub(i + 1, i + 1)
        if n == "/" then
          out[#out + 1] = "/"
        else
          out[#out + 1] = c .. n
        end
        i = i + 2
      elseif c == "\n" then
        error("awk: regex may not span lines, line " .. line)
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    if i > #src then error("awk: unterminated regex at line " .. line) end
    i = i + 1
    return table.concat(out)
  end

  local function read_name()
    local start = i
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(start, i - 1)
  end

  while i <= #src do
    local c = src:sub(i, i)
    if c == "#" then
      while i <= #src and src:sub(i, i) ~= "\n" do i = i + 1 end
    elseif c == " " or c == "\t" then
      i = i + 1
    elseif c == "\\" and src:sub(i + 1, i + 1) == "\n" then
      i = i + 2; line = line + 1
    elseif c == "\n" then
      add("NEWLINE", "\n"); i = i + 1; line = line + 1
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      add("NUMBER", read_number())
    elseif c == '"' then
      add("STRING", read_string())
    elseif c:match("[%a_]") then
      local name = read_name()
      if KEYWORDS[name] then add(name, name)
      else add("NAME", name) end
    elseif c == "/" then
      if regex_context(prev) then
        add("REGEX", read_regex())
      elseif src:sub(i + 1, i + 1) == "=" then
        add("/=", "/="); i = i + 2
      else
        add("/", "/"); i = i + 1
      end
    else
      local two = src:sub(i, i + 1)
      if MULTI_OPS[two] then
        add(two, two); i = i + 2
      elseif SINGLE_OPS:find(c, 1, true) then
        add(c, c); i = i + 1
      else
        error("awk: unexpected character '" .. c .. "' at line " .. line)
      end
    end
  end
  tokens[#tokens + 1] = { kind = "EOF", val = nil, line = line }
  return tokens
end

-- ---------------------------------------------------------------------
-- Parser (recursive descent)
-- ---------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function new_parser(tokens)
  return setmetatable({ t = tokens, i = 1 }, Parser)
end

function Parser:peek(off) return self.t[self.i + (off or 0)].kind end
function Parser:peek_val() return self.t[self.i].val end
function Parser:cur_line() return self.t[self.i].line end

function Parser:advance()
  local tok = self.t[self.i]
  self.i = self.i + 1
  return tok
end

function Parser:eat(kind)
  if self:peek() ~= kind then
    error(string.format("awk: expected %s, got %s at line %d",
      kind, self:peek(), self:cur_line()))
  end
  return self:advance()
end

function Parser:accept(...)
  for _, k in ipairs({ ... }) do
    if self:peek() == k then self:advance(); return true end
  end
  return false
end

function Parser:skip_terminators()
  while self:peek() == "NEWLINE" or self:peek() == ";" do self:advance() end
end

local VALUE_START = {
  NUMBER = true, STRING = true, NAME = true, REGEX = true,
  ["$"] = true, ["("] = true, ["!"] = true, ["-"] = true,
  ["+"] = true, ["++"] = true, ["--"] = true,
}

function Parser:parse_program()
  local rules = {}
  self:skip_terminators()
  while self:peek() ~= "EOF" do
    rules[#rules + 1] = self:parse_rule()
    self:skip_terminators()
  end
  return { kind = "program", rules = rules }
end

function Parser:parse_rule()
  if self:peek() == "BEGIN" then
    self:advance()
    return { kind = "BEGIN", action = self:parse_action(true) }
  end
  if self:peek() == "END" then
    self:advance()
    return { kind = "END", action = self:parse_action(true) }
  end
  if self:peek() == "{" then
    return { kind = "main", action = self:parse_action(true) }
  end
  local p1 = self:parse_expr()
  local p2 = nil
  local kind = "main"
  if self:peek() == "," then
    self:advance()
    p2 = self:parse_expr()
    kind = "range"
  end
  local action = self:parse_action(false)
  return { kind = kind, pattern = p1, pattern2 = p2, action = action }
end

function Parser:parse_action(required)
  if self:peek() ~= "{" then
    if required then
      error("awk: expected { at line " .. self:cur_line())
    end
    return nil
  end
  self:eat("{")
  local stmts = self:parse_stmts()
  self:eat("}")
  return stmts
end

function Parser:parse_stmts()
  local stmts = {}
  self:skip_terminators()
  while self:peek() ~= "}" and self:peek() ~= "EOF" do
    stmts[#stmts + 1] = self:parse_stmt()
    if self:peek() == ";" or self:peek() == "NEWLINE" then
      self:skip_terminators()
    end
  end
  return stmts
end

function Parser:parse_stmt()
  local tok = self:peek()
  if tok == "{" then
    self:advance()
    local body = self:parse_stmts()
    self:eat("}")
    return { kind = "block", stmts = body }
  end
  if tok == "if" then return self:parse_if() end
  if tok == "while" then return self:parse_while() end
  if tok == "do" then return self:parse_do() end
  if tok == "for" then return self:parse_for() end
  if tok == "print" then
    self:advance()
    return self:parse_print_args(false)
  end
  if tok == "printf" then
    self:advance()
    return self:parse_print_args(true)
  end
  if tok == "next" then self:advance(); return { kind = "next" } end
  if tok == "exit" then
    self:advance()
    local e = nil
    if self:peek() ~= ";" and self:peek() ~= "NEWLINE"
       and self:peek() ~= "}" and self:peek() ~= "EOF" then
      e = self:parse_expr()
    end
    return { kind = "exit", expr = e }
  end
  if tok == "break" then self:advance(); return { kind = "break" } end
  if tok == "continue" then self:advance(); return { kind = "continue" } end
  if tok == "delete" then
    self:advance()
    local target = self:parse_primary_lhs()
    return { kind = "delete", target = target }
  end
  if tok == "getline" then
    error("awk: getline is not supported in this build")
  end
  local e = self:parse_expr()
  return { kind = "expr", expr = e }
end

function Parser:parse_if()
  self:eat("if")
  self:eat("(")
  local cond = self:parse_expr()
  self:eat(")")
  self:skip_terminators()
  local then_branch = self:parse_stmt()
  local saved = self.i
  while self:peek() == ";" or self:peek() == "NEWLINE" do self:advance() end
  local else_branch = nil
  if self:peek() == "else" then
    self:advance()
    self:skip_terminators()
    else_branch = self:parse_stmt()
  else
    self.i = saved
  end
  return { kind = "if", cond = cond, then_b = then_branch, else_b = else_branch }
end

function Parser:parse_while()
  self:eat("while")
  self:eat("(")
  local cond = self:parse_expr()
  self:eat(")")
  self:skip_terminators()
  local body = self:parse_stmt()
  return { kind = "while", cond = cond, body = body }
end

function Parser:parse_do()
  self:eat("do")
  self:skip_terminators()
  local body = self:parse_stmt()
  while self:peek() == ";" or self:peek() == "NEWLINE" do self:advance() end
  self:eat("while")
  self:eat("(")
  local cond = self:parse_expr()
  self:eat(")")
  return { kind = "dowhile", body = body, cond = cond }
end

function Parser:parse_for()
  self:eat("for")
  self:eat("(")
  local saved = self.i
  -- Try for-in: NAME in NAME )
  if self:peek() == "NAME" and self:peek(1) == "in"
     and self:peek(2) == "NAME" and self:peek(3) == ")" then
    local var = self:advance().val
    self:advance()
    local arrtok = self:advance()
    self:eat(")")
    self:skip_terminators()
    local body = self:parse_stmt()
    return { kind = "forin", var = var, arr = arrtok.val, body = body }
  end
  -- (key in arr)
  if self:peek() == "(" and self:peek(1) == "NAME" and self:peek(2) == "in"
     and self:peek(3) == "NAME" and self:peek(4) == ")" and self:peek(5) == ")" then
    self:advance()
    local var = self:advance().val
    self:advance()
    local arrtok = self:advance()
    self:eat(")"); self:eat(")")
    self:skip_terminators()
    local body = self:parse_stmt()
    return { kind = "forin", var = var, arr = arrtok.val, body = body }
  end
  self.i = saved
  local init = nil
  if self:peek() ~= ";" then init = self:parse_expr() end
  self:eat(";")
  local cond = nil
  if self:peek() ~= ";" then cond = self:parse_expr() end
  self:eat(";")
  local step = nil
  if self:peek() ~= ")" then step = self:parse_expr() end
  self:eat(")")
  self:skip_terminators()
  local body = self:parse_stmt()
  return { kind = "for", init = init, cond = cond, step = step, body = body }
end

function Parser:parse_print_args(is_printf)
  local args = {}
  if self:peek() ~= ";" and self:peek() ~= "NEWLINE"
     and self:peek() ~= "}" and self:peek() ~= "EOF" then
    args[#args + 1] = self:parse_expr()
    while self:peek() == "," do
      self:advance()
      args[#args + 1] = self:parse_expr()
    end
  end
  return { kind = is_printf and "printf" or "print", args = args }
end

-- Expression precedence climbing.

function Parser:parse_expr() return self:parse_assign() end

function Parser:parse_assign()
  local left = self:parse_cond()
  local op = self:peek()
  if op == "=" or op == "+=" or op == "-=" or op == "*="
     or op == "/=" or op == "%=" or op == "^=" then
    self:advance()
    local value = self:parse_assign()
    if left.kind ~= "name" and left.kind ~= "field" and left.kind ~= "index" then
      error("awk: invalid assignment target at line " .. self:cur_line())
    end
    return { kind = "assign", op = op, target = left, value = value }
  end
  return left
end

function Parser:parse_cond()
  local c = self:parse_or()
  if self:peek() == "?" then
    self:advance()
    local t = self:parse_assign()
    self:eat(":")
    local f = self:parse_assign()
    return { kind = "cond", c = c, t = t, f = f }
  end
  return c
end

function Parser:parse_or()
  local left = self:parse_and()
  while self:peek() == "||" do
    self:advance()
    left = { kind = "binary", op = "||", a = left, b = self:parse_and() }
  end
  return left
end

function Parser:parse_and()
  local left = self:parse_in()
  while self:peek() == "&&" do
    self:advance()
    left = { kind = "binary", op = "&&", a = left, b = self:parse_in() }
  end
  return left
end

function Parser:parse_in()
  local left = self:parse_match()
  while self:peek() == "in" do
    self:advance()
    local arrtok = self:eat("NAME")
    left = { kind = "inarr", key = left, arr = arrtok.val }
  end
  return left
end

function Parser:parse_match()
  local left = self:parse_rel()
  while self:peek() == "~" or self:peek() == "!~" do
    local op = self:advance().kind
    local right = self:parse_rel()
    left = { kind = "match", expr = left, regex = right, negate = (op == "!~") }
  end
  return left
end

function Parser:parse_rel()
  local left = self:parse_concat()
  local op = self:peek()
  if op == "<" or op == "<=" or op == ">" or op == ">="
     or op == "==" or op == "!=" then
    self:advance()
    local right = self:parse_concat()
    return { kind = "binary", op = op, a = left, b = right }
  end
  return left
end

function Parser:parse_concat()
  local left = self:parse_add()
  while VALUE_START[self:peek()]
        and self:peek() ~= "-" and self:peek() ~= "+" and self:peek() ~= "!" do
    local right = self:parse_add()
    left = { kind = "concat", a = left, b = right }
  end
  return left
end

function Parser:parse_add()
  local left = self:parse_mul()
  while self:peek() == "+" or self:peek() == "-" do
    local op = self:advance().kind
    local right = self:parse_mul()
    left = { kind = "binary", op = op, a = left, b = right }
  end
  return left
end

function Parser:parse_mul()
  local left = self:parse_unary()
  while self:peek() == "*" or self:peek() == "/" or self:peek() == "%" do
    local op = self:advance().kind
    local right = self:parse_unary()
    left = { kind = "binary", op = op, a = left, b = right }
  end
  return left
end

function Parser:parse_unary()
  if self:peek() == "!" then
    self:advance()
    return { kind = "unary", op = "!", a = self:parse_unary() }
  end
  if self:peek() == "-" then
    self:advance()
    return { kind = "unary", op = "-", a = self:parse_unary() }
  end
  if self:peek() == "+" then
    self:advance()
    return { kind = "unary", op = "+", a = self:parse_unary() }
  end
  if self:peek() == "++" or self:peek() == "--" then
    local op = self:advance().kind
    local target = self:parse_unary()
    return { kind = "inc", op = op, target = target, post = false }
  end
  return self:parse_pow()
end

function Parser:parse_pow()
  local left = self:parse_postfix()
  if self:peek() == "^" or self:peek() == "**" then
    self:advance()
    local right = self:parse_unary()
    return { kind = "binary", op = "^", a = left, b = right }
  end
  return left
end

function Parser:parse_postfix()
  local left = self:parse_field()
  while self:peek() == "++" or self:peek() == "--" do
    local op = self:advance().kind
    left = { kind = "inc", op = op, target = left, post = true }
  end
  return left
end

function Parser:parse_field()
  if self:peek() == "$" then
    self:advance()
    return { kind = "field", expr = self:parse_field() }
  end
  return self:parse_primary()
end

function Parser:parse_primary()
  local t = self:peek()
  if t == "NUMBER" then return { kind = "num", v = self:advance().val } end
  if t == "STRING" then return { kind = "str", v = self:advance().val } end
  if t == "REGEX" then return { kind = "regex", v = self:advance().val } end
  if t == "(" then
    self:advance()
    local e = self:parse_expr()
    self:eat(")")
    return { kind = "group", expr = e }
  end
  if t == "NAME" then
    local name = self:advance().val
    if self:peek() == "(" then
      self:advance()
      local args = {}
      if self:peek() ~= ")" then
        args[#args + 1] = self:parse_expr()
        while self:peek() == "," do
          self:advance()
          args[#args + 1] = self:parse_expr()
        end
      end
      self:eat(")")
      return { kind = "call", name = name, args = args }
    end
    if self:peek() == "[" then
      self:advance()
      local key = self:parse_expr()
      while self:peek() == "," do
        self:advance()
        local more = self:parse_expr()
        key = { kind = "binary", op = "CONCAT_SUBSEP", a = key, b = more }
      end
      self:eat("]")
      return { kind = "index", arr = name, key = key }
    end
    return { kind = "name", name = name }
  end
  error(string.format("awk: unexpected token %s at line %d", t, self:cur_line()))
end

function Parser:parse_primary_lhs()
  local name = self:eat("NAME").val
  if self:peek() == "[" then
    self:advance()
    local key = self:parse_expr()
    while self:peek() == "," do
      self:advance()
      local more = self:parse_expr()
      key = { kind = "binary", op = "CONCAT_SUBSEP", a = key, b = more }
    end
    self:eat("]")
    return { kind = "index", arr = name, key = key }
  end
  return { kind = "name", name = name }
end

-- ---------------------------------------------------------------------
-- printf
-- ---------------------------------------------------------------------

local function awk_printf(fmt, args, ofmt)
  local out = {}
  local i = 1
  local ai = 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c ~= "%" then
      if c == "\\" and i + 1 <= #fmt then
        local n = fmt:sub(i + 1, i + 1)
        local esc = ({ n = "\n", t = "\t", r = "\r", ["\\"] = "\\",
          ["/"] = "/", ['"'] = '"', a = "\a", b = "\b",
          f = "\f", v = "\v" })[n]
        out[#out + 1] = esc or n
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      -- %% literal
      if fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%"
        i = i + 2
      else
        -- Parse %[flags][width][.precision]conv
        local s, e, flags, width, prec, conv = fmt:find(
          "^%%([-+ #0]*)(%d*%*?)%.?(%d*%*?)([diouxXfeEgGsc%%])", i)
        if not s then
          error("awk: bad printf format at position " .. i)
        end
        if width == "*" then
          width = tostring(math.floor(to_num(args[ai] or 0)))
          ai = ai + 1
        end
        if prec == "*" then
          prec = tostring(math.floor(to_num(args[ai] or 0)))
          ai = ai + 1
        end
        local val = args[ai]
        ai = ai + 1
        local prec_part = (prec ~= "" and prec ~= nil) and ("." .. prec) or ""
        local spec = "%" .. flags .. width .. prec_part .. conv
        if conv == "d" or conv == "i" then
          spec = (spec:gsub("i", "d"))
          out[#out + 1] = string.format(spec, math.floor(to_num(val)))
        elseif conv == "o" or conv == "x" or conv == "X" then
          out[#out + 1] = string.format(spec, math.floor(to_num(val)))
        elseif conv == "u" then
          spec = (spec:gsub("u", "d"))
          out[#out + 1] = string.format(spec, math.floor(to_num(val)))
        elseif conv == "f" or conv == "e" or conv == "E"
               or conv == "g" or conv == "G" then
          out[#out + 1] = string.format(spec, to_num(val))
        elseif conv == "s" then
          out[#out + 1] = string.format(spec, to_str(val, ofmt))
        elseif conv == "c" then
          if type(val) == "number" then
            out[#out + 1] = string.char(math.floor(val) % 256)
          else
            out[#out + 1] = to_str(val, ofmt):sub(1, 1)
          end
        end
        i = e + 1
      end
    end
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------
-- Interpreter
-- ---------------------------------------------------------------------

local Interp = {}
Interp.__index = Interp

local function new_interp(program, opts)
  opts = opts or {}
  local self = setmetatable({}, Interp)
  self.program = program
  self.globals = {}
  self.arrays = {}
  self.fields = { [0] = "" }
  self.NR = 0; self.NF = 0; self.FNR = 0
  self.FILENAME = ""
  self.FS = opts.fs or " "
  self.OFS = " "; self.ORS = "\n"; self.RS = "\n"
  self.SUBSEP = SUBSEP
  self.OFMT = "%.6g"; self.CONVFMT = "%.6g"
  self.range_active = {}
  self.exit_code = nil
  self.files = opts.files or {}
  for k, v in pairs(opts.vars or {}) do self.globals[k] = v end
  return self
end

function Interp:get_var(name)
  if name == "NR" then return self.NR end
  if name == "NF" then return self.NF end
  if name == "FNR" then return self.FNR end
  if name == "FILENAME" then return self.FILENAME end
  if name == "FS" then return self.FS end
  if name == "OFS" then return self.OFS end
  if name == "ORS" then return self.ORS end
  if name == "RS" then return self.RS end
  if name == "SUBSEP" then return self.SUBSEP end
  if name == "OFMT" then return self.OFMT end
  if name == "CONVFMT" then return self.CONVFMT end
  return self.globals[name] or ""
end

function Interp:set_var(name, value)
  if name == "NR" then self.NR = math.floor(to_num(value)); return end
  if name == "NF" then
    local n = math.floor(to_num(value))
    if n < 0 then error("awk: NF must be non-negative") end
    if n > self.NF then
      for k = self.NF + 1, n do self.fields[k] = "" end
    elseif n < self.NF then
      for k = n + 1, self.NF do self.fields[k] = nil end
    end
    self.NF = n
    self:rebuild_line()
    return
  end
  if name == "FNR" then self.FNR = math.floor(to_num(value)); return end
  if name == "FILENAME" then self.FILENAME = to_str(value); return end
  if name == "FS" then self.FS = to_str(value); return end
  if name == "OFS" then self.OFS = to_str(value); return end
  if name == "ORS" then self.ORS = to_str(value); return end
  if name == "RS" then self.RS = to_str(value); return end
  if name == "SUBSEP" then self.SUBSEP = to_str(value); return end
  if name == "OFMT" then self.OFMT = to_str(value); return end
  if name == "CONVFMT" then self.CONVFMT = to_str(value); return end
  self.globals[name] = value
end

function Interp:split_fields(line)
  if self.FS == " " then
    -- Default: split on runs of whitespace
    local out = {}
    for tok in line:gmatch("%S+") do out[#out + 1] = tok end
    return out
  end
  if self.FS == "" then
    local out = {}
    for k = 1, #line do out[#out + 1] = line:sub(k, k) end
    return out
  end
  if #self.FS == 1 then
    -- Literal single-char split
    local out = {}
    local start = 1
    for k = 1, #line do
      if line:sub(k, k) == self.FS then
        out[#out + 1] = line:sub(start, k - 1)
        start = k + 1
      end
    end
    out[#out + 1] = line:sub(start)
    return out
  end
  -- multi-char FS: regex
  local ok, compiled = pcall(regex.compile, self.FS)
  if ok then
    local out = {}
    local pos = 1
    while pos <= #line do
      local s, e = compiled:find(line, pos)
      if not s then break end
      out[#out + 1] = line:sub(pos, s - 1)
      pos = e + 1
    end
    out[#out + 1] = line:sub(pos)
    return out
  end
  return { line }
end

function Interp:rebuild_line()
  local parts = {}
  for k = 1, self.NF do parts[#parts + 1] = self.fields[k] or "" end
  self.fields[0] = table.concat(parts, self.OFS)
end

function Interp:set_record(line)
  self.fields = { [0] = line }
  local parts = self:split_fields(line)
  for k, v in ipairs(parts) do self.fields[k] = v end
  self.NF = #parts
end

function Interp:set_field(n, val)
  local s = to_str(val, self.OFMT)
  if n == 0 then self:set_record(s); return end
  if n < 0 then error("awk: negative field index: " .. n) end
  for k = self.NF + 1, n do self.fields[k] = "" end
  self.fields[n] = s
  if n > self.NF then self.NF = n end
  self:rebuild_line()
end

function Interp:get_field(n)
  if n == 0 then return self.fields[0] end
  if n < 0 then error("awk: negative field index: " .. n) end
  return self.fields[n] or ""
end

-- ---- expression evaluation ----

local function num_value(x)
  if x == math.floor(x) and math.abs(x) < 1e16 then
    return math.floor(x)
  end
  return x
end

function Interp:eval_key(node)
  if node.kind == "binary" and node.op == "CONCAT_SUBSEP" then
    return self:eval_key(node.a) .. self.SUBSEP .. self:eval_key(node.b)
  end
  return to_str(self:eval(node), self.OFMT)
end

function Interp:eval(e)
  local k = e.kind
  if k == "num" then return e.v end
  if k == "str" then return e.v end
  if k == "regex" then
    local pat = regex.compile(e.v)
    return pat:find(self.fields[0]) and 1 or 0
  end
  if k == "name" then
    if self.arrays[e.name] then
      error("awk: array '" .. e.name .. "' used in scalar context")
    end
    return self:get_var(e.name)
  end
  if k == "group" then return self:eval(e.expr) end
  if k == "field" then
    local n = math.floor(to_num(self:eval(e.expr)))
    return self:get_field(n)
  end
  if k == "index" then
    self.arrays[e.arr] = self.arrays[e.arr] or {}
    local key = self:eval_key(e.key)
    if self.arrays[e.arr][key] == nil then
      self.arrays[e.arr][key] = ""
    end
    return self.arrays[e.arr][key]
  end
  if k == "binary" then return self:eval_binary(e) end
  if k == "unary" then
    local v = self:eval(e.a)
    if e.op == "!" then return to_bool(v) and 0 or 1 end
    if e.op == "-" then return -to_num(v) end
    if e.op == "+" then return to_num(v) end
  end
  if k == "inc" then
    local cur = to_num(self:eval(e.target))
    local new = e.op == "++" and (cur + 1) or (cur - 1)
    self:assign_lvalue(e.target, num_value(new))
    return num_value(e.post and cur or new)
  end
  if k == "concat" then
    return to_str(self:eval(e.a), self.OFMT)
      .. to_str(self:eval(e.b), self.OFMT)
  end
  if k == "match" then
    local s = to_str(self:eval(e.expr), self.OFMT)
    local pat = self:regex_pattern(e.regex)
    local hit = regex.compile(pat):find(s) ~= nil
    if e.negate then hit = not hit end
    return hit and 1 or 0
  end
  if k == "inarr" then
    self.arrays[e.arr] = self.arrays[e.arr] or {}
    local key = self:eval_key(e.key)
    return (self.arrays[e.arr][key] ~= nil) and 1 or 0
  end
  if k == "cond" then
    if to_bool(self:eval(e.c)) then return self:eval(e.t)
    else return self:eval(e.f) end
  end
  if k == "assign" then return self:eval_assign(e) end
  if k == "call" then return self:call_builtin(e.name, e.args) end
  error("awk: unknown expression node " .. tostring(k))
end

function Interp:regex_pattern(node)
  if node.kind == "regex" then return node.v end
  return to_str(self:eval(node), self.OFMT)
end

function Interp:eval_binary(e)
  local op = e.op
  if op == "&&" then
    if not to_bool(self:eval(e.a)) then return 0 end
    return to_bool(self:eval(e.b)) and 1 or 0
  end
  if op == "||" then
    if to_bool(self:eval(e.a)) then return 1 end
    return to_bool(self:eval(e.b)) and 1 or 0
  end
  local a, b = self:eval(e.a), self:eval(e.b)
  if op == "+" then return to_num(a) + to_num(b) end
  if op == "-" then return to_num(a) - to_num(b) end
  if op == "*" then return to_num(a) * to_num(b) end
  if op == "/" then
    local d = to_num(b)
    if d == 0 then error("awk: division by zero") end
    return to_num(a) / d
  end
  if op == "%" then
    local d = to_num(b)
    if d == 0 then error("awk: division by zero in %") end
    return to_num(a) - d * math.floor(to_num(a) / d)
  end
  if op == "^" then return to_num(a) ^ to_num(b) end
  if op == "==" or op == "!=" or op == "<" or op == "<="
     or op == ">" or op == ">=" then
    local cmp
    if is_numeric_value(a) and is_numeric_value(b) then
      local na, nb = to_num(a), to_num(b)
      cmp = (na > nb and 1) or (na < nb and -1) or 0
    else
      local sa, sb = to_str(a, self.OFMT), to_str(b, self.OFMT)
      cmp = (sa > sb and 1) or (sa < sb and -1) or 0
    end
    if op == "==" then return cmp == 0 and 1 or 0 end
    if op == "!=" then return cmp ~= 0 and 1 or 0 end
    if op == "<"  then return cmp < 0  and 1 or 0 end
    if op == "<=" then return cmp <= 0 and 1 or 0 end
    if op == ">"  then return cmp > 0  and 1 or 0 end
    if op == ">=" then return cmp >= 0 and 1 or 0 end
  end
  if op == "CONCAT_SUBSEP" then
    return to_str(a, self.OFMT) .. self.SUBSEP .. to_str(b, self.OFMT)
  end
  error("awk: bad binary op " .. tostring(op))
end

function Interp:assign_lvalue(node, value)
  if node.kind == "name" then
    if self.arrays[node.name] then
      error("awk: cannot assign scalar to array '" .. node.name .. "'")
    end
    self:set_var(node.name, value)
    return
  end
  if node.kind == "field" then
    local n = math.floor(to_num(self:eval(node.expr)))
    self:set_field(n, value)
    return
  end
  if node.kind == "index" then
    self.arrays[node.arr] = self.arrays[node.arr] or {}
    local key = self:eval_key(node.key)
    self.arrays[node.arr][key] = value
    return
  end
  error("awk: invalid lvalue")
end

function Interp:eval_assign(e)
  local v = self:eval(e.value)
  if e.op == "=" then
    self:assign_lvalue(e.target, v)
    return v
  end
  local cur = self:eval(e.target)
  local nv
  if e.op == "+=" then nv = to_num(cur) + to_num(v)
  elseif e.op == "-=" then nv = to_num(cur) - to_num(v)
  elseif e.op == "*=" then nv = to_num(cur) * to_num(v)
  elseif e.op == "/=" then
    local d = to_num(v)
    if d == 0 then error("awk: division by zero") end
    nv = to_num(cur) / d
  elseif e.op == "%=" then
    local d = to_num(v)
    if d == 0 then error("awk: division by zero") end
    nv = to_num(cur) - d * math.floor(to_num(cur) / d)
  elseif e.op == "^=" then nv = to_num(cur) ^ to_num(v)
  else error("awk: bad assign op " .. tostring(e.op)) end
  local out = num_value(nv)
  self:assign_lvalue(e.target, out)
  return out
end

-- ---- builtins ----

function Interp:call_builtin(name, arg_nodes)
  if name == "length" then
    if #arg_nodes == 0 then return #self.fields[0] end
    if arg_nodes[1].kind == "name" and self.arrays[arg_nodes[1].name] then
      local count = 0
      for _ in pairs(self.arrays[arg_nodes[1].name]) do count = count + 1 end
      return count
    end
    return #to_str(self:eval(arg_nodes[1]), self.OFMT)
  end
  if name == "substr" then
    if #arg_nodes < 2 or #arg_nodes > 3 then error("awk: substr takes 2 or 3 args") end
    local s = to_str(self:eval(arg_nodes[1]), self.OFMT)
    local start = math.floor(to_num(self:eval(arg_nodes[2])))
    if #arg_nodes == 3 then
      local len = math.floor(to_num(self:eval(arg_nodes[3])))
      if len < 0 then return "" end
      local b = math.max(start, 1)
      local en = math.min(start + len - 1, #s)
      if b > en then return "" end
      return s:sub(b, en)
    end
    return s:sub(math.max(start, 1))
  end
  if name == "index" then
    if #arg_nodes ~= 2 then error("awk: index takes 2 args") end
    local s = to_str(self:eval(arg_nodes[1]), self.OFMT)
    local t = to_str(self:eval(arg_nodes[2]), self.OFMT)
    if t == "" then return 0 end
    local pos = s:find(t, 1, true)
    return pos or 0
  end
  if name == "split" then
    if #arg_nodes < 2 or #arg_nodes > 3 then error("awk: split takes 2 or 3 args") end
    local s = to_str(self:eval(arg_nodes[1]), self.OFMT)
    if arg_nodes[2].kind ~= "name" then
      error("awk: split: second arg must be array name")
    end
    local arr_name = arg_nodes[2].name
    self.arrays[arr_name] = {}
    local sep
    if #arg_nodes == 3 then
      sep = self:regex_pattern(arg_nodes[3])
    else
      sep = self.FS
    end
    if s == "" then return 0 end
    local parts
    if sep == " " then
      parts = {}
      for tok in s:gmatch("%S+") do parts[#parts + 1] = tok end
    elseif sep == "" then
      parts = {}
      for k = 1, #s do parts[#parts + 1] = s:sub(k, k) end
    elseif #sep == 1 then
      parts = {}
      local start = 1
      for k = 1, #s do
        if s:sub(k, k) == sep then
          parts[#parts + 1] = s:sub(start, k - 1)
          start = k + 1
        end
      end
      parts[#parts + 1] = s:sub(start)
    else
      parts = {}
      local ok, compiled = pcall(regex.compile, sep)
      if ok then
        local pos = 1
        while pos <= #s do
          local b, e = compiled:find(s, pos)
          if not b then break end
          parts[#parts + 1] = s:sub(pos, b - 1)
          pos = e + 1
        end
        parts[#parts + 1] = s:sub(pos)
      else
        parts = { s }
      end
    end
    for k, p in ipairs(parts) do
      self.arrays[arr_name][tostring(k)] = p
    end
    return #parts
  end
  if name == "sub" or name == "gsub" then
    return self:sub_gsub(arg_nodes, name == "gsub")
  end
  if name == "match" then
    if #arg_nodes ~= 2 then error("awk: match takes 2 args") end
    local s = to_str(self:eval(arg_nodes[1]), self.OFMT)
    local pat = self:regex_pattern(arg_nodes[2])
    local compiled = regex.compile(pat)
    local b, e = compiled:find(s)
    if b then
      self.globals.RSTART = b
      self.globals.RLENGTH = e - b + 1
      return b
    end
    self.globals.RSTART = 0
    self.globals.RLENGTH = -1
    return 0
  end
  if name == "toupper" then
    return to_str(self:eval(arg_nodes[1]), self.OFMT):upper()
  end
  if name == "tolower" then
    return to_str(self:eval(arg_nodes[1]), self.OFMT):lower()
  end
  if name == "sprintf" then
    if #arg_nodes == 0 then error("awk: sprintf: missing format") end
    local fmt = to_str(self:eval(arg_nodes[1]), self.OFMT)
    local args = {}
    for k = 2, #arg_nodes do args[#args + 1] = self:eval(arg_nodes[k]) end
    return awk_printf(fmt, args, self.OFMT)
  end
  if name == "int" then
    local n = to_num(self:eval(arg_nodes[1]))
    return n >= 0 and math.floor(n) or -math.floor(-n)
  end
  if name == "sqrt" then return math.sqrt(to_num(self:eval(arg_nodes[1]))) end
  if name == "log" then return math.log(to_num(self:eval(arg_nodes[1]))) end
  if name == "exp" then return math.exp(to_num(self:eval(arg_nodes[1]))) end
  if name == "sin" then return math.sin(to_num(self:eval(arg_nodes[1]))) end
  if name == "cos" then return math.cos(to_num(self:eval(arg_nodes[1]))) end
  if name == "atan2" then
    -- math.atan2(y, x) was unified into math.atan(y, x) in Lua 5.3.
    -- math.atan with 2 args matches atan2's semantics in 5.3+; in 5.1
    -- math.atan only takes 1 arg, so fall back to a 2-arg atan2 call
    -- if it exists.
    local y = to_num(self:eval(arg_nodes[1]))
    local x = to_num(self:eval(arg_nodes[2]))
    local atan2 = rawget(math, "atan2")
    if atan2 then return atan2(y, x) end
    return math.atan(y, x)
  end
  if name == "rand" then return math.random() end
  if name == "srand" then
    if #arg_nodes > 0 then
      math.randomseed(math.floor(to_num(self:eval(arg_nodes[1]))))
    else
      math.randomseed(os.time())
    end
    return 0
  end
  if name == "system" then
    local cmd = to_str(self:eval(arg_nodes[1]), self.OFMT)
    local ok, _, code = os.execute(cmd)
    if type(ok) == "number" then return ok end
    return ok and 0 or (code or 1)
  end
  error("awk: unknown function '" .. name .. "'")
end

function Interp:sub_gsub(arg_nodes, all_matches)
  if #arg_nodes < 2 or #arg_nodes > 3 then
    error("awk: " .. (all_matches and "gsub" or "sub") .. " takes 2 or 3 args")
  end
  local pat = self:regex_pattern(arg_nodes[1])
  local repl = to_str(self:eval(arg_nodes[2]), self.OFMT)
  local target_node
  if #arg_nodes == 3 then target_node = arg_nodes[3]
  else target_node = { kind = "field", expr = { kind = "num", v = 0 } } end
  local src = to_str(self:eval(target_node), self.OFMT)
  local ok, compiled = pcall(regex.compile, pat)
  if not ok then error("awk: bad regex '" .. pat .. "': " .. tostring(compiled)) end

  -- Custom replacement: & = whole match, \& = literal &, \\ = literal \.
  local function awk_repl(m)
    local out = {}
    local p = 1
    while p <= #repl do
      local c = repl:sub(p, p)
      if c == "\\" and p + 1 <= #repl then
        local n = repl:sub(p + 1, p + 1)
        if n == "&" then out[#out + 1] = "&"; p = p + 2
        elseif n == "\\" then out[#out + 1] = "\\"; p = p + 2
        else out[#out + 1] = n; p = p + 2 end
      elseif c == "&" then
        out[#out + 1] = m
        p = p + 1
      else
        out[#out + 1] = c
        p = p + 1
      end
    end
    return table.concat(out)
  end

  local new, count = compiled:gsub(src, awk_repl, all_matches and math.huge or 1)
  if count > 0 then
    self:assign_lvalue(target_node, new)
  end
  return count
end

-- ---- statement execution ----

function Interp:exec(s)
  local k = s.kind
  if k == "print" then
    if #s.args == 0 then
      io.stdout:write(self.fields[0], self.ORS)
      return
    end
    local parts = {}
    for _, a in ipairs(s.args) do
      parts[#parts + 1] = to_str(self:eval(a), self.OFMT)
    end
    io.stdout:write(table.concat(parts, self.OFS), self.ORS)
    return
  end
  if k == "printf" then
    if #s.args == 0 then error("awk: printf: missing format") end
    local fmt = to_str(self:eval(s.args[1]), self.OFMT)
    local args = {}
    for j = 2, #s.args do args[#args + 1] = self:eval(s.args[j]) end
    io.stdout:write(awk_printf(fmt, args, self.OFMT))
    return
  end
  if k == "expr" then self:eval(s.expr); return end
  if k == "block" then
    for _, st in ipairs(s.stmts) do self:exec(st) end
    return
  end
  if k == "if" then
    if to_bool(self:eval(s.cond)) then
      self:exec(s.then_b)
    elseif s.else_b then
      self:exec(s.else_b)
    end
    return
  end
  if k == "while" then
    while to_bool(self:eval(s.cond)) do
      local ok, err = pcall(self.exec, self, s.body)
      if not ok then
        if err == BREAK_LOOP then return end
        if err ~= CONTINUE_LOOP then error(err) end
      end
    end
    return
  end
  if k == "dowhile" then
    while true do
      local ok, err = pcall(self.exec, self, s.body)
      if not ok then
        if err == BREAK_LOOP then return end
        if err ~= CONTINUE_LOOP then error(err) end
      end
      if not to_bool(self:eval(s.cond)) then return end
    end
  end
  if k == "for" then
    if s.init then self:eval(s.init) end
    while true do
      if s.cond and not to_bool(self:eval(s.cond)) then return end
      local ok, err = pcall(self.exec, self, s.body)
      if not ok then
        if err == BREAK_LOOP then return end
        if err ~= CONTINUE_LOOP then error(err) end
      end
      if s.step then self:eval(s.step) end
    end
  end
  if k == "forin" then
    self.arrays[s.arr] = self.arrays[s.arr] or {}
    local keys = {}
    for kk in pairs(self.arrays[s.arr]) do keys[#keys + 1] = kk end
    for _, kk in ipairs(keys) do
      self.globals[s.var] = kk
      local ok, err = pcall(self.exec, self, s.body)
      if not ok then
        if err == BREAK_LOOP then return end
        if err ~= CONTINUE_LOOP then error(err) end
      end
    end
    return
  end
  if k == "next" then error(NEXT_RECORD) end
  if k == "exit" then
    local code = 0
    if s.expr then code = math.floor(to_num(self:eval(s.expr))) end
    error(EXIT_PROGRAM(code))
  end
  if k == "break" then error(BREAK_LOOP) end
  if k == "continue" then error(CONTINUE_LOOP) end
  if k == "delete" then
    local t = s.target
    if t.kind == "name" then
      self.arrays[t.name] = {}
      return
    end
    if t.kind == "index" then
      self.arrays[t.arr] = self.arrays[t.arr] or {}
      self.arrays[t.arr][self:eval_key(t.key)] = nil
      return
    end
    error("awk: invalid delete target")
  end
  error("awk: unknown statement kind " .. tostring(k))
end

-- ---- top-level run ----

function Interp:exec_stmts(stmts)
  if not stmts then return end
  for _, s in ipairs(stmts) do self:exec(s) end
end

function Interp:process_record(line)
  self.NR = self.NR + 1
  self.FNR = self.FNR + 1
  self:set_record(line)
  for idx, rule in ipairs(self.program.rules) do
    if rule.kind == "main" then
      if not rule.pattern or to_bool(self:eval(rule.pattern)) then
        if not rule.action then
          io.stdout:write(self.fields[0], self.ORS)
        else
          local ok, err = pcall(self.exec_stmts, self, rule.action)
          if not ok then
            if err == NEXT_RECORD then return end
            error(err)
          end
        end
      end
    elseif rule.kind == "range" then
      local active = self.range_active[idx] or false
      if not active and to_bool(self:eval(rule.pattern)) then
        self.range_active[idx] = true
        active = true
      end
      if active then
        if not rule.action then
          io.stdout:write(self.fields[0], self.ORS)
        else
          local ok, err = pcall(self.exec_stmts, self, rule.action)
          if not ok then
            if err == NEXT_RECORD then return end
            error(err)
          end
        end
        if to_bool(self:eval(rule.pattern2)) then
          self.range_active[idx] = false
        end
      end
    end
  end
end

function Interp:process_input()
  local sources = {}
  if #self.files == 0 then
    sources[#sources + 1] = { name = "-", handle = io.stdin }
  else
    for _, f in ipairs(self.files) do
      sources[#sources + 1] = { name = f, handle = nil }
    end
  end
  local function process_one_source(src)
    self.FILENAME = src.name
    self.FNR = 0
    local fh = src.handle
    local close_it = false
    if not fh then
      local err
      fh, err = io.open(src.name, "rb")
      if not fh then
        common.err_path(NAME, src.name, err or "open failed")
        self.exit_code = 2
        return
      end
      close_it = true
    end
    if self.RS == "\n" then
      for line in common.iter_lines_keep_nl(fh) do
        local rec = line
        if rec:sub(-1) == "\n" then rec = rec:sub(1, -2) end
        if rec:sub(-1) == "\r" then rec = rec:sub(1, -2) end
        self:process_record(rec)
      end
    else
      local data = fh:read("*a") or ""
      local records
      if self.RS == "" then
        records = {}
        for r in data:gmatch("([^\n]+)") do records[#records + 1] = r end
      else
        records = {}
        local sep = self.RS
        local start = 1
        local hit = data:find(sep, start, true)
        while hit do
          records[#records + 1] = data:sub(start, hit - 1)
          start = hit + #sep
          hit = data:find(sep, start, true)
        end
        if start <= #data then records[#records + 1] = data:sub(start) end
      end
      for _, rec in ipairs(records) do self:process_record(rec) end
    end
    if close_it then fh:close() end
  end

  for _, src in ipairs(sources) do process_one_source(src) end
end

function Interp:run()
  local has_main = false
  local has_end = false
  for _, r in ipairs(self.program.rules) do
    if r.kind == "main" or r.kind == "range" then has_main = true end
    if r.kind == "END" then has_end = true end
  end

  local function run_phase(phase)
    for _, rule in ipairs(self.program.rules) do
      if rule.kind == phase then self:exec_stmts(rule.action) end
    end
  end

  local ok, err = pcall(function()
    run_phase("BEGIN")
    if has_main or #self.files > 0 or has_end then
      if has_main or #self.files > 0 then
        self:process_input()
      end
    end
    run_phase("END")
  end)

  if not ok then
    if type(err) == "table" and err._exit then
      self.exit_code = err.code
      -- END still runs after exit
      pcall(function() run_phase("END") end)
    else
      common.err(NAME, tostring(err))
      return 2
    end
  end
  return self.exit_code or 0
end

-- ---------------------------------------------------------------------
-- CLI
-- ---------------------------------------------------------------------

local function read_file_text(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a") or ""
  fh:close()
  return data
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local fs = nil
  local preset = {}
  local program_parts = {}
  local files = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do files[#files + 1] = args[j] end
      break
    elseif a == "-F" then
      i = i + 1
      if not args[i] then
        common.err(NAME, "-F requires an argument")
        return 2
      end
      fs = args[i]; i = i + 1
    elseif a:sub(1, 2) == "-F" and #a > 2 then
      fs = a:sub(3); i = i + 1
    elseif a == "-v" then
      i = i + 1
      if not args[i] or not args[i]:find("=", 1, true) then
        common.err(NAME, "-v: expected var=val")
        return 2
      end
      local eq = args[i]:find("=", 1, true)
      preset[args[i]:sub(1, eq - 1)] = args[i]:sub(eq + 1)
      i = i + 1
    elseif a:sub(1, 2) == "-v" and #a > 2 and a:find("=", 3, true) then
      local rest = a:sub(3)
      local eq = rest:find("=", 1, true)
      preset[rest:sub(1, eq - 1)] = rest:sub(eq + 1)
      i = i + 1
    elseif a == "-f" then
      i = i + 1
      if not args[i] then
        common.err(NAME, "-f requires a file")
        return 2
      end
      local data, err = read_file_text(args[i])
      if not data then
        common.err_path(NAME, args[i], err or "open failed")
        return 2
      end
      program_parts[#program_parts + 1] = data
      i = i + 1
    elseif a == "-" then
      files[#files + 1] = "-"; i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if #program_parts == 0 then
        program_parts[#program_parts + 1] = a
      else
        files[#files + 1] = a
      end
      i = i + 1
    end
  end

  if #program_parts == 0 then
    common.err(NAME, "missing program")
    return 2
  end

  local source = table.concat(program_parts, "\n")
  local ok_t, tokens = pcall(tokenize, source)
  if not ok_t then
    common.err(NAME, "parse: " .. tostring(tokens))
    return 2
  end
  local parser = new_parser(tokens)
  local ok_p, program = pcall(parser.parse_program, parser)
  if not ok_p then
    common.err(NAME, "parse: " .. tostring(program))
    return 2
  end

  local interp = new_interp(program, { fs = fs, vars = preset, files = files })
  return interp:run()
end

return {
  name = NAME,
  aliases = {},
  help = "pattern-scanning and processing language",
  main = main,
}
