local helpers = require("helpers")

describe("hexdump applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("default 16-byte hex words", function()
    local rc, out = helpers.invoke_with_stdin("hexdump", "abcd")
    assert.equal(0, rc)
    -- "ab" little-endian → 6261; "cd" → 6463
    assert.is_truthy(out:find("6261", 1, true))
    assert.is_truthy(out:find("6463", 1, true))
  end)

  it("-C canonical format", function()
    local _, out = helpers.invoke_with_stdin("hexdump", "abc", "-C")
    assert.is_truthy(out:find("|abc|", 1, true))
    assert.is_truthy(out:find("61 62 63", 1, true))
  end)

  it("-b octal byte format", function()
    local _, out = helpers.invoke_with_stdin("hexdump", "ab", "-b")
    assert.is_truthy(out:find("141", 1, true))
    assert.is_truthy(out:find("142", 1, true))
  end)
end)
