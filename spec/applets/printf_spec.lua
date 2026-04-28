local helpers = require("helpers")

describe("printf applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("simple string", function()
    local rc, out = helpers.invoke_multicall("printf", "hello\\n")
    assert.equal(0, rc)
    assert.equal("hello\n", out)
  end)

  it("%s substitution", function()
    local _, out = helpers.invoke_multicall("printf", "%s\\n", "world")
    assert.equal("world\n", out)
  end)

  it("%d integer", function()
    local _, out = helpers.invoke_multicall("printf", "%d\\n", "42")
    assert.equal("42\n", out)
  end)

  it("repeats format for extra args", function()
    local _, out = helpers.invoke_multicall("printf", "%s\\n", "a", "b", "c")
    assert.equal("a\nb\nc\n", out)
  end)

  it("missing format → exit 2", function()
    local rc = helpers.invoke_multicall("printf")
    assert.equal(2, rc)
  end)
end)
