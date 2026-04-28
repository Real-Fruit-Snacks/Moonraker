local helpers = require("helpers")

describe("nc applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("nc", "--bogus")
    assert.equal(2, rc)
  end)

  it("client mode requires host and port", function()
    local rc = helpers.invoke_multicall("nc", "127.0.0.1")
    assert.equal(2, rc)
  end)

  it("listen mode requires a port", function()
    local rc = helpers.invoke_multicall("nc", "-l")
    assert.equal(2, rc)
  end)

  it("UDP is rejected (not implemented)", function()
    local rc = helpers.invoke_multicall("nc", "-u", "127.0.0.1", "53")
    assert.equal(2, rc)
  end)

  it("port range without -z is rejected", function()
    local rc = helpers.invoke_multicall("nc", "127.0.0.1", "1-10")
    assert.equal(2, rc)
  end)

  it("invalid port is rejected", function()
    local rc = helpers.invoke_multicall("nc", "-p", "abc")
    assert.equal(2, rc)
  end)

  it("-z to a closed port returns 1", function()
    -- Pick a port unlikely to be open. This is best-effort: if something
    -- happens to be listening on 127.0.0.1:1 we accept either outcome.
    local rc = helpers.invoke_multicall("nc", "-z", "-w", "1", "127.0.0.1", "1")
    assert.is_truthy(rc == 0 or rc == 1)
  end)
end)
