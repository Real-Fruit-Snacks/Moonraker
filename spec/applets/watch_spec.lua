local helpers = require("helpers")

describe("watch applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("requires a command", function()
    local rc = helpers.invoke_multicall("watch")
    assert.equal(2, rc)
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("watch", "--bogus", "true")
    assert.equal(2, rc)
  end)

  it("rejects an invalid interval", function()
    local rc = helpers.invoke_multicall("watch", "-n", "abc", "true")
    assert.equal(2, rc)
  end)

  it("--max-cycles bounds the loop", function()
    -- One cycle, no title, with the trivial `true` command that exits
    -- immediately. The applet should return 0 after a single iteration.
    local rc, out = helpers.invoke_multicall("watch", "-t", "--max-cycles", "1", "-n", "0.1", "true")
    assert.equal(0, rc)
    -- ANSI clear sequence is always emitted
    assert.is_truthy(out:find("\27%[2J"))
  end)
end)
