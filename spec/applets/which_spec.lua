local helpers = require("helpers")

describe("which applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("locates a common command", function()
    local rc, out = helpers.invoke_multicall("which", "sh")
    -- On POSIX, /bin/sh exists. Skip on Windows.
    if package.config:sub(1, 1) == "\\" then return end
    assert.equal(0, rc)
    assert.is_truthy(out:find("sh", 1, true))
  end)

  it("returns 1 for missing command", function()
    local rc = helpers.invoke_multicall("which", "definitelynotacommand123")
    assert.equal(1, rc)
  end)

  it("missing operand → exit 2", function()
    local rc = helpers.invoke_multicall("which")
    assert.equal(2, rc)
  end)
end)
