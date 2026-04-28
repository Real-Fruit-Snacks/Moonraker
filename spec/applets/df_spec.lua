local helpers = require("helpers")

describe("df applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("emits a header and a row for current dir", function()
    local rc, out = helpers.invoke_multicall("df", ".")
    assert.equal(0, rc)
    assert.is_truthy(out:find("Filesystem", 1, true))
    assert.is_truthy(out:find("Use%%", 1, true) or out:find("Use%", 1, true))
  end)

  it("invalid option → exit 2", function()
    local rc = helpers.invoke_multicall("df", "-z")
    assert.equal(2, rc)
  end)
end)
