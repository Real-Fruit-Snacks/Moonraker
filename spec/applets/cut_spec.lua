local helpers = require("helpers")

describe("cut applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("-c selects characters", function()
    local rc, out = helpers.invoke_with_stdin("cut", "hello\nworld\n", "-c", "1-3")
    assert.equal(0, rc)
    assert.equal("hel\nwor\n", out)
  end)

  it("-f with -d selects fields", function()
    local _, out = helpers.invoke_with_stdin("cut", "a:b:c\nd:e:f\n", "-d", ":", "-f", "2")
    assert.equal("b\ne\n", out)
  end)

  it("-f range", function()
    local _, out = helpers.invoke_with_stdin("cut", "a:b:c:d\n", "-d", ":", "-f", "2-3")
    assert.equal("b:c\n", out)
  end)

  it("missing -f or -c → exit 2", function()
    local rc, _, err = helpers.invoke_with_stdin("cut", "x\n")
    assert.equal(2, rc)
    assert.is_truthy(err:match("must specify"))
  end)
end)
