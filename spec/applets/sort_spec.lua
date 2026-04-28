local helpers = require("helpers")

describe("sort applet", function()
  before_each(function() helpers.load_applets() end)

  it("default ascending sort", function()
    local rc, out = helpers.invoke_with_stdin("sort", "banana\napple\ncherry\n")
    assert.equal(0, rc)
    assert.equal("apple\nbanana\ncherry\n", out)
  end)

  it("-r reverses", function()
    local _, out = helpers.invoke_with_stdin("sort", "a\nb\nc\n", "-r")
    assert.equal("c\nb\na\n", out)
  end)

  it("-n numeric sort", function()
    local _, out = helpers.invoke_with_stdin("sort", "10\n2\n1\n", "-n")
    assert.equal("1\n2\n10\n", out)
  end)

  it("-u removes duplicates", function()
    local _, out = helpers.invoke_with_stdin("sort", "b\na\na\nb\nc\n", "-u")
    assert.equal("a\nb\nc\n", out)
  end)

  it("-f case-insensitive", function()
    local _, out = helpers.invoke_with_stdin("sort", "Banana\napple\nCherry\n", "-f")
    assert.equal("apple\nBanana\nCherry\n", out)
  end)
end)
