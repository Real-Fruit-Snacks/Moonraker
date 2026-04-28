local helpers = require("helpers")

describe("whoami applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("prints a non-empty user name", function()
    local rc, out = helpers.invoke_multicall("whoami")
    assert.equal(0, rc)
    assert.is_truthy(out:match("^[^\n]+\n$"))
  end)
end)
