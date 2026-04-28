local helpers = require("helpers")

describe("groups applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("prints group membership", function()
    local rc, out = helpers.invoke_multicall("groups")
    assert.equal(0, rc)
    assert.is_truthy(out:match("[^\n]+\n$"))
  end)
end)
