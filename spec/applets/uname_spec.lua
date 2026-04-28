local helpers = require("helpers")

describe("uname applet", function()
  before_each(function() helpers.load_applets() end)

  it("default prints kernel name", function()
    local rc, out = helpers.invoke_multicall("uname")
    assert.equal(0, rc)
    assert.is_truthy(out:match("^[^\n]+\n$"))
  end)

  it("-a prints all fields", function()
    local rc, out = helpers.invoke_multicall("uname", "-a")
    assert.equal(0, rc)
    -- Multiple space-separated fields
    assert.is_truthy(out:match("[^\n]+%s+[^\n]+%s+"))
  end)

  it("invalid option → exit 2", function()
    local rc = helpers.invoke_multicall("uname", "-Z")
    assert.equal(2, rc)
  end)
end)
