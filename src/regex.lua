-- POSIX ERE-on-LPeg regex compiler.
--
-- Compiles a POSIX Extended Regular Expression (ERE) into an LPeg
-- pattern, then exposes find / match / gsub primitives that mimic the
-- familiar `string` library calls. Used by `sed`, `awk` (eventually),
-- and `grep -P`.
--
-- Supports:
--   * Anchors:  ^  $
--   * Char classes: [abc] [^abc] [a-z]  [[:alpha:]] [[:digit:]] [[:space:]] etc.
--   * Quantifiers: ? * + {n} {n,} {n,m}
--   * Alternation: |
--   * Grouping/captures: (...)  (?:...) for non-capturing
--   * Escapes: \d \D \s \S \w \W \b (word boundary) \n \r \t \\
--   * Dot:  matches any char except newline
--   * Replacement-side backreferences: \1 .. \9 in the replacement
--     string (passed to gsub).
--
-- Not supported (yet):
--   * In-pattern backreferences (\1)
--   * Lookahead / lookbehind
--   * Unicode-aware classes (we treat strings as bytes)

local lpeg = require("lpeg")

local M = {}

-- LPeg primitives we use a lot.
local P, S, R, C, Cp, V = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Cp, lpeg.V

-- Lua 5.1 has unpack(); 5.2+ has table.unpack.
local _unpack = table.unpack or _G.unpack

local any_byte = P(1)
local any_no_newline = P(1) - P("\n")

-- POSIX character class names → LPeg pattern.
local POSIX_CLASS = {
  alpha = R("AZ", "az"),
  alnum = R("AZ", "az", "09"),
  digit = R("09"),
  xdigit = R("09", "AF", "af"),
  lower = R("az"),
  upper = R("AZ"),
  space = S(" \t\n\r\f\v"),
  blank = S(" \t"),
  punct = S("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"),
  cntrl = R("\0\31") + P("\127"),
  print = R(" ~"),
  graph = R("!~"),
}

-- ---------------------------------------------------------------------
-- Tokenizer + parser (recursive descent)
-- ---------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function new_parser(src, opts)
  return setmetatable({
    src = src,
    pos = 1,
    n_groups = 0,
    opts = opts or {},
  }, Parser)
end

function Parser:peek(o) return self.src:sub(self.pos + (o or 0), self.pos + (o or 0)) end
function Parser:eof() return self.pos > #self.src end
function Parser:adv(n) self.pos = self.pos + (n or 1) end

function Parser:expect(ch)
  if self:peek() ~= ch then
    error("expected '" .. ch .. "' at position " .. self.pos)
  end
  self:adv()
end

-- Parse a backslash-escape; returns an AST node.
function Parser:parse_escape()
  self:adv()  -- consume backslash
  if self:eof() then error("trailing backslash") end
  local c = self:peek(); self:adv()
  if c == "n" then return { kind = "literal", ch = "\n" } end
  if c == "r" then return { kind = "literal", ch = "\r" } end
  if c == "t" then return { kind = "literal", ch = "\t" } end
  if c == "f" then return { kind = "literal", ch = "\f" } end
  if c == "v" then return { kind = "literal", ch = "\v" } end
  if c == "0" then return { kind = "literal", ch = "\0" } end
  if c == "d" then return { kind = "class", set = R("09") } end
  if c == "D" then return { kind = "class", set = any_byte - R("09") } end
  if c == "s" then return { kind = "class", set = S(" \t\n\r\f\v") } end
  if c == "S" then return { kind = "class", set = any_byte - S(" \t\n\r\f\v") } end
  if c == "w" then return { kind = "class", set = R("AZ", "az", "09") + P("_") } end
  if c == "W" then return { kind = "class", set = any_byte - (R("AZ", "az", "09") + P("_")) } end
  if c == "b" then return { kind = "wordboundary" } end
  if c == "B" then return { kind = "notwordboundary" } end
  -- backslash followed by anything else is a literal of that char
  return { kind = "literal", ch = c }
end

-- Parse contents of [...]. Caller has already consumed the leading '['.
function Parser:parse_charclass()
  local negated = false
  if self:peek() == "^" then
    negated = true
    self:adv()
  end
  local pat = nil
  local function add(p)
    pat = pat and (pat + p) or p
  end
  -- Special-case: ']' as first char is literal.
  if self:peek() == "]" then
    add(P("]"))
    self:adv()
  end
  while not self:eof() and self:peek() ~= "]" do
    if self:peek() == "[" and self:peek(1) == ":" then
      -- [:class:]
      local close = self.src:find(":]", self.pos, true)
      if not close then error("unterminated POSIX class") end
      local name = self.src:sub(self.pos + 2, close - 1)
      local cls = POSIX_CLASS[name]
      if not cls then error("unknown POSIX class: " .. name) end
      add(cls)
      self.pos = close + 2
    elseif self:peek() == "\\" then
      local node = self:parse_escape()
      if node.kind == "literal" then add(P(node.ch))
      elseif node.kind == "class" then add(node.set)
      else error("non-class escape inside [...]") end
    else
      local c = self:peek(); self:adv()
      if self:peek() == "-" and self:peek(1) ~= "]" and not self:eof() then
        self:adv()  -- consume -
        local d = self:peek(); self:adv()
        add(R(c .. d))
      else
        add(P(c))
      end
    end
  end
  self:expect("]")
  if not pat then error("empty character class") end
  if negated then pat = any_byte - pat end
  return { kind = "class", set = pat }
end

-- Parse a single atom (no quantifier yet).
function Parser:parse_atom()
  local c = self:peek()
  if c == "." then
    self:adv()
    return { kind = "dot" }
  end
  if c == "^" then
    self:adv()
    return { kind = "anchor", which = "^" }
  end
  if c == "$" then
    self:adv()
    return { kind = "anchor", which = "$" }
  end
  if c == "[" then
    self:adv()
    return self:parse_charclass()
  end
  if c == "(" then
    self:adv()
    local non_capturing = false
    if self:peek() == "?" and self:peek(1) == ":" then
      non_capturing = true
      self:adv(); self:adv()
    end
    local inner = self:parse_alt()
    self:expect(")")
    if non_capturing then return inner end
    self.n_groups = self.n_groups + 1
    return { kind = "group", inner = inner, index = self.n_groups }
  end
  if c == "\\" then
    return self:parse_escape()
  end
  -- Plain literal byte
  self:adv()
  return { kind = "literal", ch = c }
end

-- Parse {n}, {n,}, or {n,m}. Caller has consumed the '{'.
function Parser:parse_brace_quant()
  local s = self.pos
  local close = self.src:find("}", s, true)
  if not close then error("unterminated quantifier") end
  local body = self.src:sub(s, close - 1)
  self.pos = close + 1
  local lo, hi = body:match("^(%d+),(%d+)$")
  if lo then return tonumber(lo), tonumber(hi) end
  lo = body:match("^(%d+),$")
  if lo then return tonumber(lo), -1 end
  lo = body:match("^(%d+)$")
  if lo then local n = tonumber(lo); return n, n end
  error("bad quantifier: {" .. body .. "}")
end

-- Apply optional quantifier.
function Parser:parse_piece()
  local atom = self:parse_atom()
  -- Anchors and word boundaries don't take quantifiers, but ERE allows
  -- '*' after '^' as a literal interpretation; we follow GNU extended
  -- behaviour which is: anchors with a quantifier are an error. To
  -- stay forgiving we just pass through.
  local q = self:peek()
  if q == "?" then
    self:adv()
    return { kind = "quant", inner = atom, min = 0, max = 1 }
  elseif q == "*" then
    self:adv()
    return { kind = "quant", inner = atom, min = 0, max = -1 }
  elseif q == "+" then
    self:adv()
    return { kind = "quant", inner = atom, min = 1, max = -1 }
  elseif q == "{" then
    self:adv()
    local lo, hi = self:parse_brace_quant()
    return { kind = "quant", inner = atom, min = lo, max = hi }
  end
  return atom
end

function Parser:parse_concat()
  local parts = {}
  while not self:eof() and self:peek() ~= ")" and self:peek() ~= "|" do
    parts[#parts + 1] = self:parse_piece()
  end
  if #parts == 1 then return parts[1] end
  return { kind = "concat", parts = parts }
end

function Parser:parse_alt()
  local first = self:parse_concat()
  if self:peek() ~= "|" then return first end
  local branches = { first }
  while self:peek() == "|" do
    self:adv()
    branches[#branches + 1] = self:parse_concat()
  end
  return { kind = "alt", branches = branches }
end

-- ---------------------------------------------------------------------
-- AST → LPeg
-- ---------------------------------------------------------------------

-- Word-character predicate (used by \b).
local word_char = R("AZ", "az", "09") + P("_")
local end_of_string = -P(1)
-- \b matches at a position where one side is a word char and the
-- other isn't. Built from four cases:
--   start-of-string + word        (entering word at offset 0)
--   word            + end-of-str
--   non-word        + word
--   word            + non-word
local at_word_boundary
do
  local at_start_word = (-lpeg.B(1)) * #word_char
  local at_word_end_eos = lpeg.B(word_char) * end_of_string
  local nonword_to_word = lpeg.B(P(1) - word_char) * #word_char
  local word_to_nonword = lpeg.B(word_char) * #(P(1) - word_char)
  at_word_boundary = at_start_word + at_word_end_eos + nonword_to_word + word_to_nonword
end
-- \B is the complement: both sides agree (both word, or both non-word
-- including string boundaries).
local at_not_word_boundary
do
  local both_word = lpeg.B(word_char) * #word_char
  local both_nonword_mid = lpeg.B(P(1) - word_char) * #(P(1) - word_char)
  local nonword_eos = lpeg.B(P(1) - word_char) * end_of_string
  local sos_nonword = (-lpeg.B(1)) * #(P(1) - word_char)
  local empty_string = (-lpeg.B(1)) * end_of_string
  at_not_word_boundary = both_word + both_nonword_mid +
    nonword_eos + sos_nonword + empty_string
end

local function compile_node(node, ignore_case)
  -- Build a literal string pattern, optionally case-insensitive.
  local function lit(ch)
    if ignore_case and ch:match("%a") then
      return S(ch:lower() .. ch:upper())
    end
    return P(ch)
  end

  if node.kind == "literal" then
    return lit(node.ch)
  end
  if node.kind == "dot" then
    return any_no_newline
  end
  if node.kind == "class" then
    return node.set
  end
  if node.kind == "anchor" then
    if node.which == "^" then
      -- Match start of string or after newline (multiline mode).
      return -lpeg.B(any_byte) + lpeg.B(P("\n"))
    end
    -- $: end of string or before newline
    return -any_byte + #P("\n")
  end
  if node.kind == "wordboundary" then
    return at_word_boundary
  end
  if node.kind == "notwordboundary" then
    return at_not_word_boundary
  end
  if node.kind == "group" then
    local inner = compile_node(node.inner, ignore_case)
    -- Capture the matched text. Use Cg with name = numeric index so
    -- replacement-side \N can find it via lpeg.match returning an
    -- ordered table.
    return C(inner)
  end
  if node.kind == "concat" then
    local pat = compile_node(node.parts[1], ignore_case)
    for j = 2, #node.parts do
      pat = pat * compile_node(node.parts[j], ignore_case)
    end
    return pat
  end
  if node.kind == "alt" then
    local pat = compile_node(node.branches[1], ignore_case)
    for j = 2, #node.branches do
      pat = pat + compile_node(node.branches[j], ignore_case)
    end
    return pat
  end
  if node.kind == "quant" then
    local inner = compile_node(node.inner, ignore_case)
    local lo, hi = node.min, node.max
    if lo == 0 and hi == -1 then return inner ^ 0 end
    if lo == 1 and hi == -1 then return inner ^ 1 end
    if lo == 0 and hi == 1 then return inner ^ -1 end
    if hi == -1 then return inner ^ lo end
    -- Bounded {n,m}: build P^n * (P^-1)^(m-n)
    local pat = inner ^ lo
    if hi > lo then
      local optional = inner ^ -1
      for _ = 1, hi - lo do pat = pat * optional end
    end
    return pat
  end
  error("unknown node kind: " .. tostring(node.kind))
end

-- ---------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------

local Matcher = {}
Matcher.__index = Matcher

-- Returns (start, end, captures...) or nil.
function Matcher:find(s, init)
  init = init or 1
  if init < 1 then init = #s + init + 1 end
  if init < 1 then init = 1 end
  if init > #s + 1 then return nil end
  -- The search pattern is `Cp() * body * Cp() + (any_byte * V(1))`.
  -- lpeg.match returns multiple values in left-to-right capture order:
  --   start, body-capture-1, body-capture-2, ..., end_plus_1
  local results = { lpeg.match(self._search, s, init) }
  if #results == 0 then return nil end
  local start = results[1]
  local stop = results[#results] - 1
  local caps = {}
  for i = 2, #results - 1 do caps[#caps + 1] = results[i] end
  return start, stop, caps
end

function Matcher:match(s, init)
  local _, _, caps = self:find(s, init)
  if not caps then return nil end
  if #caps > 0 then return _unpack(caps) end
  return nil  -- whole match returned via find; .match returns captures only
end

function Matcher:gsub(s, repl, max_n)
  local result = {}
  local out_idx = 1
  local pos = 1
  local count = 0
  max_n = max_n or math.huge
  while pos <= #s + 1 and count < max_n do
    local start, stop, caps = self:find(s, pos)
    if not start then break end
    -- Append text before the match.
    result[out_idx] = s:sub(pos, start - 1); out_idx = out_idx + 1
    -- Append replacement.
    if type(repl) == "string" then
      -- Expand replacement: \0 / & = whole match; \1..\9 = captures;
      -- \\ = literal backslash; \& = literal &. We do a single linear
      -- pass since trying to use Lua's gsub for the substitutions runs
      -- into the well-known "\0 terminates pattern" trap.
      local matched = s:sub(start, stop)
      local out = {}
      local rp = 1
      while rp <= #repl do
        local ch = repl:sub(rp, rp)
        if ch == "\\" and rp + 1 <= #repl then
          local nx = repl:sub(rp + 1, rp + 1)
          if nx:match("%d") then
            local idx = tonumber(nx)
            out[#out + 1] = (idx == 0) and matched or (caps[idx] or "")
          elseif nx == "n" then out[#out + 1] = "\n"
          elseif nx == "t" then out[#out + 1] = "\t"
          else out[#out + 1] = nx end
          rp = rp + 2
        elseif ch == "&" then
          out[#out + 1] = matched
          rp = rp + 1
        else
          out[#out + 1] = ch
          rp = rp + 1
        end
      end
      result[out_idx] = table.concat(out); out_idx = out_idx + 1
    elseif type(repl) == "function" then
      local r
      if #caps > 0 then
        r = repl(_unpack(caps))
      else
        r = repl(s:sub(start, stop))
      end
      result[out_idx] = tostring(r or s:sub(start, stop)); out_idx = out_idx + 1
    elseif type(repl) == "table" then
      local key = caps[1] or s:sub(start, stop)
      result[out_idx] = tostring(repl[key] or s:sub(start, stop))
      out_idx = out_idx + 1
    end
    count = count + 1
    if stop < start then
      -- Zero-width match: advance one char to avoid infinite loop.
      result[out_idx] = s:sub(pos, pos); out_idx = out_idx + 1
      pos = pos + 1
    else
      pos = stop + 1
    end
  end
  -- Append remainder.
  result[out_idx] = s:sub(pos)
  return table.concat(result), count
end

--- Compile a regex pattern.
-- @param pattern string  POSIX ERE source
-- @param opts    table   { ignore_case = bool }
-- @return Matcher
function M.compile(pattern, opts)
  opts = opts or {}
  local p = new_parser(pattern, opts)
  local ast = p:parse_alt()
  if not p:eof() then
    error("unexpected character at position " .. p.pos)
  end
  local body = compile_node(ast, opts.ignore_case)
  -- Build a "search anywhere" pattern. Captures emit varargs:
  --   start, body-caps..., end+1
  local search = P{
    Cp() * body * Cp() + (any_byte * V(1)),
  }
  return setmetatable({ _search = search, _body = body }, Matcher)
end

--- Quick one-shot find. Returns start, end, caps or nil.
function M.find(pattern, s, init, opts)
  return M.compile(pattern, opts):find(s, init)
end

--- Quick one-shot gsub.
function M.gsub(s, pattern, repl, max_n, opts)
  return M.compile(pattern, opts):gsub(s, repl, max_n)
end

return M
