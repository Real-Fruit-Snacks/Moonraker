local helpers = require("helpers")

describe("getopt applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("-T returns 4 (enhanced getopt available)", function()
    local rc = helpers.invoke_multicall("getopt", "-T")
    assert.equal(4, rc)
  end)

  it("parses short opts", function()
    local _, out = helpers.invoke_multicall("getopt", "-o", "ab", "--", "-a", "-b", "x")
    -- Output should contain quoted -a -b -- 'x'
    assert.is_truthy(out:find("-a", 1, true))
    assert.is_truthy(out:find("-b", 1, true))
    assert.is_truthy(out:find("--", 1, true))
  end)

  it("parses required-arg short opt", function()
    local _, out = helpers.invoke_multicall("getopt", "-o", "f:", "--", "-f", "value")
    assert.is_truthy(out:find("-f", 1, true))
    assert.is_truthy(out:find("'value'", 1, true))
  end)

  it("parses long opts", function()
    local _, out = helpers.invoke_multicall("getopt", "-o", "", "-l", "verbose", "--", "--verbose")
    assert.is_truthy(out:find("--verbose", 1, true))
  end)
end)
