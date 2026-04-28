local helpers = require("helpers")

describe("pwd applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("prints a non-empty cwd ending with newline", function()
    local rc, out = helpers.invoke_multicall("pwd")
    assert.equal(0, rc)
    assert.is_truthy(out:match(".+\n$"))
  end)

  it("-P returns a non-empty path", function()
    local rc, out = helpers.invoke_multicall("pwd", "-P")
    assert.equal(0, rc)
    assert.is_truthy(out:match(".+\n$"))
  end)

  it("-L returns a non-empty path", function()
    local rc, out = helpers.invoke_multicall("pwd", "-L")
    assert.equal(0, rc)
    assert.is_truthy(out:match(".+\n$"))
  end)

  it("rejects unknown options with exit 2", function()
    local rc, _, err = helpers.invoke_multicall("pwd", "--bogus")
    assert.equal(2, rc)
    assert.is_truthy(err:match("invalid option"))
  end)

  it("--help is intercepted by dispatcher", function()
    -- In multi-call mode the dispatcher prints applet help before applet
    -- code runs. The leading line is "<name> - <summary>".
    local rc, out = helpers.invoke_multicall("pwd", "--help")
    assert.equal(0, rc)
    assert.is_truthy(out:match("^pwd"))
  end)
end)
