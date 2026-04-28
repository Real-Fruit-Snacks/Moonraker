local helpers = require("helpers")

describe("date applet", function()
  before_each(function() helpers.load_applets() end)

  it("default prints a date string", function()
    local rc, out = helpers.invoke_multicall("date")
    assert.equal(0, rc)
    assert.is_truthy(out:match("[A-Z][a-z][a-z]"))
  end)

  it("+%Y outputs year", function()
    local _, out = helpers.invoke_multicall("date", "+%Y")
    assert.is_truthy(out:match("^%d%d%d%d\n$"))
  end)

  it("-d ISO date parses", function()
    local rc, out = helpers.invoke_multicall("date", "-d", "2024-06-15", "+%Y-%m-%d")
    assert.equal(0, rc)
    assert.equal("2024-06-15\n", out)
  end)

  it("invalid date → exit 1", function()
    local rc = helpers.invoke_multicall("date", "-d", "notadate")
    assert.equal(1, rc)
  end)
end)
