local helpers = require("helpers")

describe("timeout applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("missing operand → exit 125", function()
    local rc = helpers.invoke_multicall("timeout", "5")
    assert.equal(125, rc)
  end)

  it("invalid duration → exit 125", function()
    local rc = helpers.invoke_multicall("timeout", "abc", "true")
    assert.equal(125, rc)
  end)

  it("command that finishes in time returns its exit code", function()
    if package.config:sub(1, 1) == "\\" then return end
    local rc = helpers.invoke_multicall("timeout", "5", "true")
    assert.equal(0, rc)
  end)
end)
