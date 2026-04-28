local helpers = require("helpers")

describe("od applet", function()
  before_each(function() helpers.load_applets() end)

  it("default: octal byte format", function()
    local rc, out = helpers.invoke_with_stdin("od", "abc")
    assert.equal(0, rc)
    assert.is_truthy(out:find("141", 1, true))  -- 'a' = 0o141
    assert.is_truthy(out:find("142", 1, true))  -- 'b' = 0o142
    assert.is_truthy(out:find("143", 1, true))  -- 'c' = 0o143
  end)

  it("-x hex format", function()
    local _, out = helpers.invoke_with_stdin("od", "abc", "-x")
    assert.is_truthy(out:find("61", 1, true))  -- 'a' = 0x61
  end)

  it("-c char format", function()
    local _, out = helpers.invoke_with_stdin("od", "abc", "-c")
    assert.is_truthy(out:find("a", 1, true))
  end)

  it("-A n suppresses address column", function()
    local _, out = helpers.invoke_with_stdin("od", "x", "-A", "n")
    assert.is_falsy(out:match("^%d+%s"))
  end)
end)
