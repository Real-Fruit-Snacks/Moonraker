local helpers = require("helpers")

describe("du applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("reports usage for current dir", function()
    local rc, out = helpers.invoke_multicall("du", "-s", ".")
    assert.equal(0, rc)
    assert.is_truthy(out:match("%d+%s+%."))
  end)

  it("-h human-readable", function()
    local _, out = helpers.invoke_multicall("du", "-sh", ".")
    assert.is_truthy(out:find("\t.", 1, true))
  end)

  it("nonexistent path → exit 1", function()
    local rc = helpers.invoke_multicall("du", "/no/such/path")
    assert.equal(1, rc)
  end)
end)
