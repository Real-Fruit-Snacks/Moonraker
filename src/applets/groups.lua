-- groups: print groups a user is in.

local common = require("common")

local NAME = "groups"

local function main(argv)
  if common.is_windows() then
    local user = argv[1] or os.getenv("USERNAME") or os.getenv("USER") or "?"
    io.stdout:write(string.format("%s : (groups not available on this platform)\n", user))
    return 0
  end

  local users = {}
  for i = 1, #argv do users[i] = argv[i] end

  local cmd = "groups"
  if #users > 0 then
    local quoted = {}
    for _, u in ipairs(users) do
      quoted[#quoted + 1] = "'" .. u:gsub("'", "'\\''") .. "'"
    end
    cmd = cmd .. " " .. table.concat(quoted, " ")
  end

  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then
    common.err(NAME, "could not invoke groups")
    return 1
  end
  local out = p:read("*a") or ""
  p:close()
  if out == "" then
    common.err(NAME, "no such user")
    return 1
  end
  io.stdout:write(out)
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "print groups a user is in",
  main = main,
}
