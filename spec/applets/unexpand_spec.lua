local helpers = require("helpers")

describe("unexpand applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("converts leading spaces to tabs", function()
    local _, out = helpers.invoke_with_stdin("unexpand", "        foo\n")
    assert.equal("\tfoo\n", out)
  end)

  it("-a converts all aligned space runs", function()
    local _, out = helpers.invoke_with_stdin("unexpand", "abc       defxxxxx\n", "-a")
    assert.is_truthy(out:find("\t", 1, true))
  end)

  it("preserves non-aligned space runs", function()
    local _, out = helpers.invoke_with_stdin("unexpand", "abc def\n")
    assert.equal("abc def\n", out)
  end)
end)
