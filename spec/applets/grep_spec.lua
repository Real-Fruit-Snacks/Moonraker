local helpers = require("helpers")

describe("grep applet", function()
  before_each(function() helpers.load_applets() end)

  it("matches a literal pattern", function()
    local rc, out = helpers.invoke_with_stdin("grep", "foo\nbar\nfoobar\n", "foo")
    assert.equal(0, rc)
    assert.equal("foo\nfoobar\n", out)
  end)

  it("-v inverts match", function()
    local _, out = helpers.invoke_with_stdin("grep", "foo\nbar\nfoobar\n", "-v", "foo")
    assert.equal("bar\n", out)
  end)

  it("-i ignores case", function()
    local _, out = helpers.invoke_with_stdin("grep", "FOO\nbar\n", "-i", "foo")
    assert.equal("FOO\n", out)
  end)

  it("-n shows line numbers", function()
    local _, out = helpers.invoke_with_stdin("grep", "a\nfoo\nb\n", "-n", "foo")
    assert.equal("2:foo\n", out)
  end)

  it("-c counts matches", function()
    local _, out = helpers.invoke_with_stdin("grep", "foo\nfoo\nbar\n", "-c", "foo")
    assert.equal("2\n", out)
  end)

  it("-F treats pattern as fixed string", function()
    local _, out = helpers.invoke_with_stdin("grep", "a.b\naxb\n", "-F", "a.b")
    assert.equal("a.b\n", out)
  end)

  it("returns 1 when no matches", function()
    local rc = helpers.invoke_with_stdin("grep", "foo\n", "nosuchpattern")
    assert.equal(1, rc)
  end)

  it("-q is silent and returns match status", function()
    local rc, out = helpers.invoke_with_stdin("grep", "foo\n", "-q", "foo")
    assert.equal(0, rc)
    assert.equal("", out)
  end)
end)
