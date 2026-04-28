local helpers = require("helpers")

describe("uniq applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("removes adjacent duplicates", function()
    local rc, out = helpers.invoke_with_stdin("uniq", "a\na\nb\nb\nc\n")
    assert.equal(0, rc)
    assert.equal("a\nb\nc\n", out)
  end)

  it("-c counts occurrences", function()
    local _, out = helpers.invoke_with_stdin("uniq", "a\na\nb\n", "-c")
    assert.is_truthy(out:match("%s+2 a"))
    assert.is_truthy(out:match("%s+1 b"))
  end)

  it("-d only shows duplicates", function()
    local _, out = helpers.invoke_with_stdin("uniq", "a\na\nb\n", "-d")
    assert.equal("a\n", out)
  end)

  it("-u only shows unique lines", function()
    local _, out = helpers.invoke_with_stdin("uniq", "a\na\nb\n", "-u")
    assert.equal("b\n", out)
  end)

  it("-i case insensitive", function()
    local _, out = helpers.invoke_with_stdin("uniq", "Hello\nhello\nWorld\n", "-i")
    assert.equal("Hello\nWorld\n", out)
  end)
end)
