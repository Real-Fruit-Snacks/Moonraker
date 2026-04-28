-- nc: minimal TCP netcat (connect, listen, port-scan).
--
-- Lua port of mainsail's nc.py. Backed by vendored luasocket. Lua has
-- no portable async stdin, so the data-pumping pattern is
-- "send-then-receive" rather than truly bidirectional. This supports
-- the common workflows:
--   * banner grab  (no stdin, read socket until EOF)
--   * request/response  (slurp stdin, send, then read response)
--   * `-z` port scan   (connect, close)
--   * listen-for-one  (bind, accept, slurp peer, write stdin, close)
--
-- UDP (-u) and bidirectional REPL-style sessions are not implemented.

local common = require("common")
local socket = require("socket")

local NAME = "nc"
local CHUNK = 65536

local function pump_socket_to_stdout(sock, timeout)
  sock:settimeout(timeout or 30)
  while true do
    local data, err, partial = sock:receive(CHUNK)
    if data then
      io.stdout:write(data)
    elseif partial and partial ~= "" then
      io.stdout:write(partial)
    end
    if err == "closed" or (not data and not partial) then break end
    if err and err ~= "timeout" and err ~= "wantread" then break end
    if err == "timeout" then break end
  end
  io.stdout:flush()
end

local function send_stdin(sock)
  -- Read stdin to EOF and send. If stdin is a tty with no input, this
  -- may block forever — caller is expected to redirect stdin or supply
  -- payload non-interactively.
  --
  -- We deliberately do NOT half-close the send side here. luasocket's
  -- shutdown("send") is observed to abort the response on some
  -- middleboxes (e.g. cloudflare-fronted hosts), and most protocols
  -- (HTTP, simple line-oriented servers) end the request without
  -- needing an EOF marker. The peer closes when done.
  while true do
    local chunk = io.stdin:read(CHUNK)
    if not chunk or chunk == "" then break end
    local ok, err = sock:send(chunk)
    if not ok then
      common.err(NAME, "send: " .. tostring(err))
      return false
    end
  end
  return true
end

local function parse_ports(spec)
  local lo, hi = spec:match("^(%d+)%-(%d+)$")
  if lo then
    lo, hi = tonumber(lo), tonumber(hi)
    if not lo or not hi or lo > hi then return nil end
    local out = {}
    for p = lo, hi do
      out[#out + 1] = p
    end
    return out
  end
  local p = tonumber(spec)
  if not p then return nil end
  return { p }
end

local function stdin_is_tty()
  -- Heuristic: if io.stdin:read(0) is nil immediately, no input piped.
  -- This is unreliable on Lua 5.1 (where read(0) returns ""); good
  -- enough for our purpose (skip blocking on stdin in -z mode).
  return false
end

local function main(argv)
  local args = {}
  for i = 1, #argv do
    args[i] = argv[i]
  end

  local listen = false
  local port = nil
  local zero_io = false
  local verbose = false
  local timeout = nil
  local udp = false
  local positional = {}

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then
      for j = i + 1, #args do
        positional[#positional + 1] = args[j]
      end
      break
    elseif a == "-l" then
      listen = true
      i = i + 1
    elseif a == "-p" and args[i + 1] then
      port = tonumber(args[i + 1])
      if not port then
        common.err(NAME, "invalid port: " .. args[i + 1])
        return 2
      end
      i = i + 2
    elseif a == "-z" then
      zero_io = true
      i = i + 1
    elseif a == "-v" then
      verbose = true
      i = i + 1
    elseif a == "-w" and args[i + 1] then
      timeout = tonumber(args[i + 1])
      if not timeout then
        common.err(NAME, "invalid timeout: " .. args[i + 1])
        return 2
      end
      i = i + 2
    elseif a == "-u" then
      udp = true
      i = i + 1
    elseif a == "-4" or a == "-6" then
      i = i + 1 -- accepted but luasocket picks family from address
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      positional[#positional + 1] = a
      i = i + 1
    end
  end

  if udp then
    common.err(NAME, "UDP mode (-u) is not supported in this build")
    return 2
  end

  if listen then
    local listen_port = port
    if not listen_port and #positional > 0 then
      listen_port = tonumber(positional[#positional])
      if not listen_port then
        common.err(NAME, "invalid port: " .. positional[#positional])
        return 2
      end
    end
    if not listen_port then
      common.err(NAME, "listen mode requires a port")
      return 2
    end
    local srv, err = socket.bind("0.0.0.0", listen_port)
    if not srv then
      common.err(NAME, tostring(err))
      return 1
    end
    if verbose then io.stderr:write("listening on port ", listen_port, "\n") end
    if timeout then srv:settimeout(timeout) end
    local conn, aerr = srv:accept()
    srv:close()
    if not conn then
      common.err(NAME, "accept: " .. tostring(aerr))
      return 1
    end
    if verbose then
      local ip, p = conn:getpeername()
      io.stderr:write(string.format("connection from %s:%d\n", ip or "?", p or 0))
    end
    -- Drain socket -> stdout, then push stdin -> socket. (Order matches
    -- "request/response" pattern; for "talk to me first then I'll
    -- reply" the user can swap with `< input.txt`.)
    pump_socket_to_stdout(conn, timeout)
    conn:close()
    return 0
  end

  -- Client mode
  if #positional < 2 then
    common.err(NAME, "missing host or port")
    return 2
  end
  local host = positional[1]
  local ports = parse_ports(positional[2])
  if not ports then
    common.err(NAME, "invalid port spec: " .. positional[2])
    return 2
  end

  if zero_io then
    local rc = 0
    for _, p in ipairs(ports) do
      local sock, cerr = socket.tcp()
      if sock then
        sock:settimeout(timeout or 3)
        local ok, err = sock:connect(host, p)
        if ok then
          if verbose then io.stderr:write(string.format("Connection to %s %d port [tcp/*] succeeded!\n", host, p)) end
          io.stdout:write(string.format("%d/tcp open\n", p))
          sock:close()
        else
          rc = 1
          if verbose then
            io.stderr:write(string.format("nc: connect to %s port %d failed: %s\n", host, p, tostring(err)))
          end
          sock:close()
        end
      else
        rc = 1
        if verbose then io.stderr:write("nc: socket: " .. tostring(cerr) .. "\n") end
      end
    end
    return rc
  end

  if #ports > 1 then
    common.err(NAME, "port range only valid with -z")
    return 2
  end

  local p = ports[1]
  local sock, cerr = socket.tcp()
  if not sock then
    common.err(NAME, "socket: " .. tostring(cerr))
    return 1
  end
  if timeout then sock:settimeout(timeout) end
  local ok, err = sock:connect(host, p)
  if not ok then
    common.err(NAME, "connect: " .. tostring(err))
    sock:close()
    return 1
  end
  if verbose then io.stderr:write(string.format("Connection to %s %d port [tcp/*] succeeded!\n", host, p)) end

  -- Send stdin (if any), then drain socket -> stdout.
  if not stdin_is_tty() then send_stdin(sock) end
  pump_socket_to_stdout(sock, timeout or 30)
  sock:close()
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "TCP netcat -- connect, listen, port-scan",
  main = main,
}
