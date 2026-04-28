local helpers = require("helpers")

describe("env applet", function()
  before_each(function() helpers.load_applets() end)

  it("prints environment when no command given", function()
    local rc, out = helpers.invoke_multicall("env")
    assert.equal(0, rc)
    -- Should produce KEY=VAL lines (we'll see at least PATH or HOME on POSIX)
    assert.is_truthy(out:match("^[^=\n]+=") or out == "")
  end)

  it("invalid -X option → exit 2", function()
    local rc = helpers.invoke_multicall("env", "-X")
    assert.equal(2, rc)
  end)
end)
