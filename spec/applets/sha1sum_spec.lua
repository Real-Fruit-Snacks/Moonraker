local helpers = require("helpers")

describe("sha1sum applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("computes sha1 of 'abc'", function()
    local rc, out = helpers.invoke_with_stdin("sha1sum", "abc")
    assert.equal(0, rc)
    assert.is_truthy(out:find("a9993e364706816aba3e25717850c26c9cd0d89d", 1, true))
  end)
end)
