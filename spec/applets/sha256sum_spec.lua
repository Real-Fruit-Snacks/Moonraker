local helpers = require("helpers")

describe("sha256sum applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("computes sha256 of 'abc'", function()
    local rc, out = helpers.invoke_with_stdin("sha256sum", "abc")
    assert.equal(0, rc)
    assert.is_truthy(out:find("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 1, true))
  end)
end)
