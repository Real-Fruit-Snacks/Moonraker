local helpers = require("helpers")

describe("fmt applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("reflows a paragraph to default 75 cols", function()
    local input = "foo bar baz\nqux quux\n"
    local _, out = helpers.invoke_with_stdin("fmt", input)
    assert.equal("foo bar baz qux quux\n", out)
  end)

  it("-w sets width", function()
    local input = "one two three four\n"
    local _, out = helpers.invoke_with_stdin("fmt", input, "-w", "10")
    -- Should wrap at ~10 chars
    assert.is_truthy(#out:match("[^\n]+") <= 11)
  end)

  it("preserves paragraph separation", function()
    local _, out = helpers.invoke_with_stdin("fmt", "foo\nbar\n\nbaz\n")
    assert.is_truthy(out:find("\n\n", 1, true))
  end)
end)
