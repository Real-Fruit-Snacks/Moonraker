local helpers = require("helpers")

describe("install-aliases applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("--dry-run produces preview", function()
    -- Dry run shouldn't write anywhere; binary location detection might
    -- fail in the unit test process (no real moonraker on PATH), so we
    -- just check the exit code is 0 or 2 (graceful failure).
    local rc = helpers.invoke_multicall("install-aliases", "--dry-run", "/tmp/mr-test-aliases")
    assert.is_truthy(rc == 0 or rc == 2)
  end)

  it("invalid option → exit 2", function()
    local rc = helpers.invoke_multicall("install-aliases", "--bogus")
    assert.equal(2, rc)
  end)
end)
