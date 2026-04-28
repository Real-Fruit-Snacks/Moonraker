local helpers = require("helpers")

describe("seq applet", function()
  before_each(function() helpers.load_applets() end)

  it("default 1..N", function()
    local rc, out = helpers.invoke_multicall("seq", "5")
    assert.equal(0, rc)
    assert.equal("1\n2\n3\n4\n5\n", out)
  end)

  it("FIRST LAST", function()
    local _, out = helpers.invoke_multicall("seq", "3", "5")
    assert.equal("3\n4\n5\n", out)
  end)

  it("FIRST INCR LAST", function()
    local _, out = helpers.invoke_multicall("seq", "1", "2", "9")
    assert.equal("1\n3\n5\n7\n9\n", out)
  end)

  it("descending", function()
    local _, out = helpers.invoke_multicall("seq", "5", "-1", "1")
    assert.equal("5\n4\n3\n2\n1\n", out)
  end)

  it("-s sets separator", function()
    local _, out = helpers.invoke_multicall("seq", "-s", ",", "1", "3")
    assert.equal("1,2,3\n", out)
  end)

  it("-w pads with zeros", function()
    local _, out = helpers.invoke_multicall("seq", "-w", "8", "10")
    assert.equal("08\n09\n10\n", out)
  end)
end)
