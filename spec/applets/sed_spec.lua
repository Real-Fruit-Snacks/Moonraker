local helpers = require("helpers")

describe("sed applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("substitutes once per line by default", function()
    local rc, out = helpers.invoke_with_stdin("sed", "foo bar foo\n", "s/foo/X/")
    assert.equal(0, rc)
    assert.equal("X bar foo\n", out)
  end)

  it("g flag substitutes globally", function()
    local _, out = helpers.invoke_with_stdin("sed", "foo bar foo\n", "s/foo/X/g")
    assert.equal("X bar X\n", out)
  end)

  it("supports -E (ERE)", function()
    local _, out = helpers.invoke_with_stdin("sed", "alpha\nbravo\n", "-E", "s/(alpha|bravo)/<\\1>/")
    assert.equal("<alpha>\n<bravo>\n", out)
  end)

  it("BRE escapes work without -E", function()
    local _, out = helpers.invoke_with_stdin("sed", "alpha bravo\n", "s/\\(alpha\\) \\(bravo\\)/\\2 \\1/")
    assert.equal("bravo alpha\n", out)
  end)

  it("backreferences in replacement", function()
    local _, out = helpers.invoke_with_stdin("sed", "hello world\n", "-E", "s/(\\w+) (\\w+)/\\2 \\1/")
    assert.equal("world hello\n", out)
  end)

  it("& expands to whole match", function()
    local _, out = helpers.invoke_with_stdin("sed", "hi\n", "s/h.*/[&]/")
    assert.equal("[hi]\n", out)
  end)

  it("d deletes lines", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\nc\n", "/b/d")
    assert.equal("a\nc\n", out)
  end)

  it("-n + p prints only matching lines", function()
    local _, out = helpers.invoke_with_stdin("sed", "x\nfoo\ny\nfoo\n", "-n", "/foo/p")
    assert.equal("foo\nfoo\n", out)
  end)

  it("address by line number", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\nc\nd\n", "-n", "2p")
    assert.equal("b\n", out)
  end)

  it("address $ matches last line", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\nc\n", "-n", "$p")
    assert.equal("c\n", out)
  end)

  it("address range", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\nc\nd\ne\n", "-n", "2,4p")
    assert.equal("b\nc\nd\n", out)
  end)

  it("! negates address", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\nc\n", "2!d")
    assert.equal("b\n", out)
  end)

  it("y transliterates characters", function()
    local _, out = helpers.invoke_with_stdin("sed", "Hello\n", "y/lo/LO/")
    assert.equal("HeLLO\n", out)
  end)

  it("= prints line numbers", function()
    local _, out = helpers.invoke_with_stdin("sed", "a\nb\n", "=")
    -- = prints line number then the line
    assert.equal("1\na\n2\nb\n", out)
  end)

  it("multiple -e scripts compose", function()
    local _, out = helpers.invoke_with_stdin("sed", "x\n", "-e", "s/x/y/", "-e", "s/y/z/")
    assert.equal("z\n", out)
  end)

  it("rejects unsupported commands cleanly", function()
    local rc = helpers.invoke_with_stdin("sed", "x\n", "Z")
    assert.equal(2, rc)
  end)
end)
