-- dig: minimal DNS resolver over UDP.
--
-- Lua port of mainsail's dig.py. Constructs raw DNS query packets and
-- decodes responses. UDP transport via vendored luasocket.
--
-- Lua 5.1 doesn't have string.pack/unpack (added in 5.3), so we build
-- the wire format with string.byte/char and bit math.

local common = require("common")
local socket = require("socket")

local NAME = "dig"

local TYPE_NUM = {
  A = 1, NS = 2, CNAME = 5, SOA = 6, PTR = 12,
  MX = 15, TXT = 16, AAAA = 28, ANY = 255,
}

local NUM_TYPE = {}
for k, v in pairs(TYPE_NUM) do NUM_TYPE[v] = k end

local RCODE_NAMES = {
  [0] = "NOERROR", [1] = "FORMERR", [2] = "SERVFAIL",
  [3] = "NXDOMAIN", [4] = "NOTIMP", [5] = "REFUSED",
}

local function u16_be(n)
  return string.char(math.floor(n / 256) % 256, n % 256)
end

local function read_u16(data, pos)
  local b1, b2 = data:byte(pos, pos + 1)
  return b1 * 256 + b2, pos + 2
end

local function read_u32(data, pos)
  local b1, b2, b3, b4 = data:byte(pos, pos + 3)
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4, pos + 4
end

local function encode_name(name)
  local out = {}
  for label in (name:gsub("%.+$", "")):gmatch("[^.]+") do
    if #label > 63 then
      return nil, "label too long: " .. label
    end
    out[#out + 1] = string.char(#label) .. label
  end
  out[#out + 1] = "\0"
  return table.concat(out)
end

local function build_query(qid, name, qtype)
  local qname, err = encode_name(name)
  if not qname then return nil, err end
  -- Header: id, flags(RD=1=0x0100), qdcount=1, ancount=0, nscount=0, arcount=0
  local header = u16_be(qid) .. u16_be(0x0100) ..
    u16_be(1) .. u16_be(0) .. u16_be(0) .. u16_be(0)
  local question = qname .. u16_be(qtype) .. u16_be(1)  -- class IN
  return header .. question
end

local function read_name(data, offset)
  local labels = {}
  local seen = {}
  local pos = offset
  local first_end = nil
  while true do
    if seen[pos] then
      return nil, "compression loop"
    end
    seen[pos] = true
    local ln = data:byte(pos)
    if not ln then
      return nil, "truncated"
    end
    if ln == 0 then
      pos = pos + 1
      first_end = first_end or pos
      return table.concat(labels, "."), first_end
    end
    if ln >= 0xC0 then  -- pointer
      local b2 = data:byte(pos + 1)
      if not b2 then return nil, "truncated pointer" end
      local ptr = (ln - 0xC0) * 256 + b2
      first_end = first_end or (pos + 2)
      pos = ptr + 1  -- offsets in DNS are 0-based; Lua strings are 1-based
    else
      labels[#labels + 1] = data:sub(pos + 1, pos + ln)
      pos = pos + 1 + ln
    end
  end
end

local function format_ipv4(rdata)
  local b1, b2, b3, b4 = rdata:byte(1, 4)
  return string.format("%d.%d.%d.%d", b1, b2, b3, b4)
end

local function format_ipv6(rdata)
  -- 8 groups of 16 bits, hex.
  local groups = {}
  for i = 1, 16, 2 do
    local hi, lo = rdata:byte(i, i + 1)
    groups[#groups + 1] = string.format("%x", hi * 256 + lo)
  end
  return table.concat(groups, ":")
end

local function format_rdata(rtype, rdata, full, offset)
  if rtype == 1 and #rdata == 4 then return format_ipv4(rdata) end
  if rtype == 28 and #rdata == 16 then return format_ipv6(rdata) end
  if rtype == 2 or rtype == 5 or rtype == 12 then  -- NS, CNAME, PTR
    local name = read_name(full, offset)
    return (name or "") .. "."
  end
  if rtype == 15 then  -- MX: pref(2) + exchange
    if #rdata < 3 then return "" end
    local pref = read_u16(rdata, 1)
    local exch = read_name(full, offset + 2) or ""
    return string.format("%d %s.", pref, exch)
  end
  if rtype == 16 then  -- TXT: length-prefixed strings
    local out = {}
    local i = 1
    while i <= #rdata do
      local ln = rdata:byte(i)
      i = i + 1
      out[#out + 1] = rdata:sub(i, i + ln - 1)
      i = i + ln
    end
    return '"' .. table.concat(out, '" "') .. '"'
  end
  if rtype == 6 then  -- SOA
    local mname, p2 = read_name(full, offset)
    if not mname then return "" end
    local rname, p3 = read_name(full, p2)
    if not rname then return mname .. "." end
    if #full >= p3 + 19 then
      local serial; serial, p3 = read_u32(full, p3)
      local refresh; refresh, p3 = read_u32(full, p3)
      local retry; retry, p3 = read_u32(full, p3)
      local expire; expire, p3 = read_u32(full, p3)
      local minimum = read_u32(full, p3)
      return string.format("%s. %s. %d %d %d %d %d",
        mname, rname, serial, refresh, retry, expire, minimum)
    end
    return string.format("%s. %s.", mname, rname)
  end
  -- Unknown: hex dump
  local out = {}
  for i = 1, #rdata do
    out[i] = string.format("%02x", rdata:byte(i))
  end
  return table.concat(out)
end

local function parse_response(data)
  if #data < 12 then return nil, "response too short" end
  -- Header: id(2), flags(2), qd(2), an(2), ns(2), ar(2). We only need
  -- flags/qd/an; skip the rest with arithmetic.
  local flags = read_u16(data, 3)
  local qd = read_u16(data, 5)
  local an = read_u16(data, 7)
  local rcode = flags % 16
  local pos = 13  -- past 12-byte header

  for _ = 1, qd do
    local _, np = read_name(data, pos)
    if not np then return nil, "bad question section" end
    pos = np + 4  -- skip qtype + qclass
  end

  local answers = {}
  for _ = 1, an do
    local name, np = read_name(data, pos)
    if not name then return nil, "bad answer name" end
    pos = np
    if pos + 9 > #data then return nil, "answer truncated" end
    local rtype; rtype, pos = read_u16(data, pos)
    pos = pos + 2  -- skip rclass
    local ttl; ttl, pos = read_u32(data, pos)
    local rdlen; rdlen, pos = read_u16(data, pos)
    local rdata = data:sub(pos, pos + rdlen - 1)
    local value = format_rdata(rtype, rdata, data, pos)
    pos = pos + rdlen
    answers[#answers + 1] = {
      name = name,
      type = NUM_TYPE[rtype] or tostring(rtype),
      ttl = ttl,
      value = value,
    }
  end
  return rcode, answers
end

local function do_query(server, name, qtype, timeout)
  local qid = math.random(0, 0xFFFF)
  local query, err = build_query(qid, name, qtype)
  if not query then return nil, err end
  local sock = socket.udp()
  if not sock then return nil, "udp open failed" end
  sock:settimeout(timeout)
  local ok, serr = sock:setpeername(server, 53)
  if not ok then sock:close(); return nil, serr end
  ok, serr = sock:send(query)
  if not ok then sock:close(); return nil, serr end
  local data, recv_err = sock:receive(4096)
  sock:close()
  if not data then return nil, recv_err end
  return data
end

local function arpa_for_ip(ip)
  if ip:find(":", 1, true) then
    -- IPv6: convert hex digits, reverse, append ip6.arpa
    local hex = {}
    for chunk in ip:gmatch("[^:]+") do
      hex[#hex + 1] = string.format("%04s", chunk):gsub(" ", "0")
    end
    local raw = table.concat(hex)
    if #raw ~= 32 then return nil end
    local nibbles = {}
    for i = #raw, 1, -1 do nibbles[#nibbles + 1] = raw:sub(i, i) end
    return table.concat(nibbles, ".") .. ".ip6.arpa"
  end
  -- IPv4: a.b.c.d -> d.c.b.a.in-addr.arpa
  local parts = {}
  for p in ip:gmatch("[^.]+") do parts[#parts + 1] = p end
  if #parts ~= 4 then return nil end
  return parts[4] .. "." .. parts[3] .. "." .. parts[2] .. "." .. parts[1] .. ".in-addr.arpa"
end

local function resolvers_from_etc()
  local out = {}
  local fh = io.open("/etc/resolv.conf", "r")
  if not fh then return out end
  for line in fh:lines() do
    local ns = line:match("^%s*nameserver%s+(%S+)")
    if ns then out[#out + 1] = ns end
  end
  fh:close()
  return out
end

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  local server = nil
  local name = nil
  local qtype = "A"
  local short = false
  local timeout = 5

  local i = 1
  while i <= #args do
    local a = args[i]
    if a:sub(1, 1) == "@" then
      server = a:sub(2); i = i + 1
    elseif a == "+short" then
      short = true; i = i + 1
    elseif a == "-x" and args[i + 1] then
      local arpa = arpa_for_ip(args[i + 1])
      if not arpa then
        common.err(NAME, "invalid address: " .. args[i + 1])
        return 2
      end
      name = arpa
      qtype = "PTR"
      i = i + 2
    elseif (a == "-t" or a == "--type") and args[i + 1] then
      qtype = args[i + 1]:upper()
      i = i + 2
    elseif a == "--timeout" and args[i + 1] then
      timeout = tonumber(args[i + 1])
      if not timeout then
        common.err(NAME, "invalid timeout: " .. args[i + 1])
        return 2
      end
      i = i + 2
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 and a:sub(1, 1) ~= "@" then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      if TYPE_NUM[a:upper()] then
        qtype = a:upper()
      elseif name == nil then
        name = a
      else
        common.err(NAME, "unexpected argument: " .. a)
        return 2
      end
      i = i + 1
    end
  end

  if not name then
    common.err(NAME, "missing query name")
    return 2
  end

  local qtype_num = TYPE_NUM[qtype:upper()]
  if not qtype_num then
    common.err(NAME, "unknown query type: " .. qtype)
    return 2
  end

  local servers
  if server then
    servers = { server }
  else
    servers = resolvers_from_etc()
    if #servers == 0 then servers = { "1.1.1.1", "8.8.8.8" } end
  end

  local response, used_server, last_err
  for _, s in ipairs(servers) do
    local data, err = do_query(s, name, qtype_num, timeout)
    if data then
      response = data
      used_server = s
      break
    end
    last_err = err
  end

  if not response then
    common.err(NAME, "no response from any server: " .. (last_err or "unknown"))
    return 9
  end

  local rcode, answers = parse_response(response)
  if not rcode then
    common.err(NAME, "malformed response: " .. (answers or "?"))
    return 1
  end

  if short then
    for _, ans in ipairs(answers) do
      io.stdout:write(ans.value, "\n")
    end
  else
    io.stdout:write(string.format(";; SERVER: %s\n", used_server))
    io.stdout:write(string.format(";; status: %s\n", RCODE_NAMES[rcode] or tostring(rcode)))
    io.stdout:write(string.format(";; QUESTION: %s. IN %s\n", name, qtype))
    if #answers > 0 then
      io.stdout:write(";; ANSWER SECTION:\n")
      for _, ans in ipairs(answers) do
        io.stdout:write(string.format("%s.\t%d\tIN\t%s\t%s\n",
          ans.name, ans.ttl, ans.type, ans.value))
      end
    else
      io.stdout:write(";; (no answer)\n")
    end
  end

  return rcode == 0 and 0 or 1
end

return {
  name = NAME,
  aliases = {},
  help = "DNS resolver",
  main = main,
}
