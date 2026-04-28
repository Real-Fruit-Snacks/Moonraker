local helpers = require("helpers")

describe("timeout applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("missing operand → exit 125", function()
    local rc = helpers.invoke_multicall("timeout", "5")
    assert.equal(125, rc)
  end)

  it("invalid duration → exit 125", function()
    local rc = helpers.invoke_multicall("timeout", "abc", "true")
    assert.equal(125, rc)
  end)

  it("command that finishes in time returns its exit code", function()
    -- The applet shells out to the system `timeout` binary (GNU
    -- coreutils). Skip on Windows (no timeout) and on macOS without
    -- coreutils installed.
    if package.config:sub(1, 1) == "\\" then
      pending("system `timeout` not available on Windows")
      return
    end
    local probe = io.popen("command -v timeout 2>/dev/null")
    local found = probe and probe:read("*l") or nil
    if probe then probe:close() end
    if not found or found == "" then
      pending("system `timeout` binary not on PATH (install coreutils)")
      return
    end
    local rc = helpers.invoke_multicall("timeout", "5", "true")
    assert.equal(0, rc)
  end)
end)
