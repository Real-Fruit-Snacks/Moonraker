local helpers = require("helpers")

describe("base64 applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("encodes ASCII", function()
    local rc, out = helpers.invoke_with_stdin("base64", "Man")
    assert.equal(0, rc)
    assert.is_truthy(out:find("TWFu", 1, true))
  end)

  it("decodes back to ASCII", function()
    local rc, out = helpers.invoke_with_stdin("base64", "TWFu", "-d")
    assert.equal(0, rc)
    assert.equal("Man", out)
  end)

  it("round-trips arbitrary bytes", function()
    local input = "hello, world\n\t\x00binary"
    local _, encoded = helpers.invoke_with_stdin("base64", input, "-w", "0")
    local _, decoded = helpers.invoke_with_stdin("base64", encoded, "-d")
    assert.equal(input, decoded)
  end)

  it("-w 0 produces no line breaks", function()
    local _, out = helpers.invoke_with_stdin("base64", string.rep("A", 100), "-w", "0")
    assert.is_falsy(out:find("\n", 1, true))
  end)

  it("-w 76 wraps (default)", function()
    local _, out = helpers.invoke_with_stdin("base64", string.rep("A", 100))
    assert.is_truthy(out:find("\n", 1, true))
  end)
end)
