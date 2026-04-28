local helpers = require("helpers")

describe("http applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("requires a URL", function()
    local rc = helpers.invoke_multicall("http")
    assert.equal(2, rc)
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("http", "--bogus", "https://example.com")
    assert.equal(2, rc)
  end)

  it("invalid timeout is rejected", function()
    local rc = helpers.invoke_multicall("http", "--timeout", "fast", "https://example.com")
    assert.equal(2, rc)
  end)

  it("@-prefixed body file with missing path errors", function()
    local rc = helpers.invoke_multicall("http", "-d", "@/nonexistent-moonraker-test-file", "https://example.com")
    assert.equal(1, rc)
  end)
end)
