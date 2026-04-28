local helpers = require("helpers")

describe("expand applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("converts tabs to spaces (default 8)", function()
    local _, out = helpers.invoke_with_stdin("expand", "a\tb\n")
    -- "a" is at col 0; tab stops at 8; after "a" col=1; need 7 spaces to reach 8
    assert.equal("a       b\n", out)
  end)

  it("-t N sets tab width", function()
    local _, out = helpers.invoke_with_stdin("expand", "a\tb\n", "-t", "4")
    assert.equal("a   b\n", out)
  end)

  it("-i only converts leading tabs", function()
    local _, out = helpers.invoke_with_stdin("expand", "\tfoo\tbar\n", "-i")
    assert.is_truthy(out:find("        foo\tbar", 1, true))
  end)
end)
