local helpers = require("helpers")

describe("dirname applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("strips last component", function()
    local rc, out = helpers.invoke_multicall("dirname", "/path/to/file.txt")
    assert.equal(0, rc)
    assert.equal("/path/to\n", out)
  end)

  it("returns . for bare filename", function()
    local _, out = helpers.invoke_multicall("dirname", "file.txt")
    assert.equal(".\n", out)
  end)

  it("returns / for /file", function()
    local _, out = helpers.invoke_multicall("dirname", "/file")
    assert.equal("/\n", out)
  end)

  it("handles trailing slashes", function()
    local _, out = helpers.invoke_multicall("dirname", "/a/b/")
    assert.equal("/a\n", out)
  end)

  it("multiple paths", function()
    local _, out = helpers.invoke_multicall("dirname", "/a/x", "/b/y", "z")
    assert.equal("/a\n/b\n.\n", out)
  end)

  it("-z uses NUL terminator", function()
    local _, out = helpers.invoke_multicall("dirname", "-z", "/a/x")
    assert.equal("/a\0", out)
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("dirname")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)
end)
