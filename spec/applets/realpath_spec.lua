local helpers = require("helpers")

describe("realpath applet", function()
  before_each(function() helpers.load_applets() end)

  it("resolves a relative path to absolute", function()
    local rc, out = helpers.invoke_multicall("realpath", ".")
    assert.equal(0, rc)
    -- Should produce an absolute path
    assert.is_truthy(out:match("^/") or out:match("^[A-Z]:"))
  end)

  it("missing operand → exit 2", function()
    local rc = helpers.invoke_multicall("realpath")
    assert.equal(2, rc)
  end)
end)
