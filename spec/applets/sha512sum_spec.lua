local helpers = require("helpers")

describe("sha512sum applet", function()
  before_each(function() helpers.load_applets() end)

  it("computes sha512 of 'abc'", function()
    local rc, out = helpers.invoke_with_stdin("sha512sum", "abc")
    assert.equal(0, rc)
    assert.is_truthy(out:find(
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
      .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      1, true))
  end)
end)
