local helpers = require("helpers")

describe("tr applet", function()
  before_each(function() helpers.load_applets() end)

  it("translates characters", function()
    local rc, out = helpers.invoke_with_stdin("tr", "hello", "a-z", "A-Z")
    assert.equal(0, rc)
    assert.equal("HELLO", out)
  end)

  it("-d deletes characters in SET1", function()
    local _, out = helpers.invoke_with_stdin("tr", "hello world", "-d", "lo")
    assert.equal("he wrd", out)
  end)

  it("-s squeezes adjacent duplicates", function()
    local _, out = helpers.invoke_with_stdin("tr", "aabbcc", "-s", "abc")
    assert.equal("abc", out)
  end)

  it("[:upper:] character class", function()
    local _, out = helpers.invoke_with_stdin("tr", "Hello", "[:upper:]", "[:lower:]")
    assert.equal("hello", out)
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("tr")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)
end)
