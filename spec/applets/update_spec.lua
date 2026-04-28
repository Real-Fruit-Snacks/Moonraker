local helpers = require("helpers")

describe("update applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("update", "--bogus")
    assert.equal(2, rc)
  end)

  it("--check on a synthetic asset name reaches network or exits gracefully", function()
    -- The unit test process isn't `moonraker`, so binary detection may
    -- fail. We just want a non-crash and a sane exit code.
    local rc = helpers.invoke_multicall("update", "--asset", "moonraker-linux-x64", "--check")
    -- 0 (already up-to-date), 1 (network down), or 2 (binary not located)
    assert.is_truthy(rc == 0 or rc == 1 or rc == 2)
  end)
end)
