-- wc: print newline, word, and byte counts for each file.

local common = require("common")

local NAME = "wc"

local function count_buffer(data)
  local lines, words, bytes_, chars = 0, 0, #data, 0
  -- Count chars (UTF-8 codepoints, falling back to byte count for invalid).
  local i = 1
  while i <= #data do
    local b = data:byte(i)
    local size
    if b < 0x80 then
      size = 1
    elseif b < 0xC0 then
      size = 1 -- invalid continuation; count as one char
    elseif b < 0xE0 then
      size = 2
    elseif b < 0xF0 then
      size = 3
    else
      size = 4
    end
    chars = chars + 1
    i = i + size
  end

  -- Count lines (byte '\n' occurrences).
  for _ in data:gmatch("\n") do
    lines = lines + 1
  end

  -- Count words (whitespace-delimited runs, matching Python str.split()).
  for _ in data:gmatch("%S+") do
    words = words + 1
  end

  return lines, words, bytes_, chars
end

local function format_row(counts, label, want_lines, want_words, want_bytes, want_chars)
  local parts = {}
  if want_lines then parts[#parts + 1] = string.format("%7d", counts[1]) end
  if want_words then parts[#parts + 1] = string.format("%7d", counts[2]) end
  if want_bytes then parts[#parts + 1] = string.format("%7d", counts[3]) end
  if want_chars then parts[#parts + 1] = string.format("%7d", counts[4]) end
  if label and label ~= "" and label ~= "-" then parts[#parts + 1] = label end
  return table.concat(parts, " ")
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local want_lines, want_words, want_bytes, want_chars = false, false, false, false
  local files = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do
        files[#files + 1] = args[j]
      end
      break
    elseif a == "-" or a:sub(1, 1) ~= "-" or #a < 2 then
      files[#files + 1] = a
    else
      for ch in a:sub(2):gmatch(".") do
        if ch == "l" then
          want_lines = true
        elseif ch == "w" then
          want_words = true
        elseif ch == "c" then
          want_bytes = true
        elseif ch == "m" then
          want_chars = true
        else
          common.err(NAME, "invalid option: -" .. ch)
          return 2
        end
      end
    end
    i = i + 1
  end

  if not (want_lines or want_words or want_bytes or want_chars) then
    want_lines, want_words, want_bytes = true, true, true
  end

  if #files == 0 then files = { "-" } end

  local totals = { 0, 0, 0, 0 }
  local results = {}
  local rc = 0

  for _, f in ipairs(files) do
    local fh, errmsg = common.open_input(f, "rb")
    if not fh then
      common.err_path(NAME, f, errmsg)
      rc = 1
    else
      local data = common.read_all(fh)
      if f ~= "-" then fh:close() end
      local l, w, b, c = count_buffer(data)
      results[#results + 1] = { counts = { l, w, b, c }, label = f }
      totals[1] = totals[1] + l
      totals[2] = totals[2] + w
      totals[3] = totals[3] + b
      totals[4] = totals[4] + c
    end
  end

  for _, r in ipairs(results) do
    io.stdout:write(format_row(r.counts, r.label, want_lines, want_words, want_bytes, want_chars), "\n")
  end
  if #results > 1 then
    io.stdout:write(format_row(totals, "total", want_lines, want_words, want_bytes, want_chars), "\n")
  end
  return rc
end

return {
  name = NAME,
  aliases = {},
  help = "print newline, word, and byte counts for each file",
  main = main,
}
