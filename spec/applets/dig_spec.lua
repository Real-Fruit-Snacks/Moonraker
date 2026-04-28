local helpers = require("helpers")

describe("dig applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("requires a query name", function()
    local rc = helpers.invoke_multicall("dig")
    assert.equal(2, rc)
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("dig", "--bogus", "example.com")
    assert.equal(2, rc)
  end)

  it("rejects bad query type", function()
    local rc = helpers.invoke_multicall("dig", "-t", "BOGUS", "example.com")
    assert.equal(2, rc)
  end)

  it("-x with a malformed address fails fast", function()
    local rc = helpers.invoke_multicall("dig", "-x", "999.999.0.0")
    -- Either rejected as invalid (2) or attempted and fails with rcode 1
    assert.is_truthy(rc == 2 or rc == 1 or rc == 9)
  end)

  it("loads luasocket without crashing", function()
    -- Sanity check that require("socket") works when an applet uses it.
    -- We don't actually reach the network here — just ensure the applet
    -- module loads, which means socket.lua + socket.core both linked.
    local applet = require("applets.dig")
    assert.is_function(applet.main)
  end)
end)
