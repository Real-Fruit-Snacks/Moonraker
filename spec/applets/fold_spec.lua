local helpers = require("helpers")

describe("fold applet", function()
  before_each(function() helpers.load_applets() end)

  it("wraps at default width 80", function()
    local _, out = helpers.invoke_with_stdin("fold", string.rep("a", 100) .. "\n")
    assert.equal(string.rep("a", 80) .. "\n" .. string.rep("a", 20) .. "\n", out)
  end)

  it("-w sets width", function()
    local _, out = helpers.invoke_with_stdin("fold", "abcdefghij\n", "-w", "3")
    assert.equal("abc\ndef\nghi\nj\n", out)
  end)

  it("-s breaks at spaces", function()
    local _, out = helpers.invoke_with_stdin("fold", "hello world foo\n", "-w", "8", "-s")
    assert.equal("hello \nworld \nfoo\n", out)
  end)

  it("invalid width → exit 2", function()
    local rc, _, err = helpers.invoke_with_stdin("fold", "x\n", "-w", "abc")
    assert.equal(2, rc)
    assert.is_truthy(err:match("invalid width"))
  end)
end)
