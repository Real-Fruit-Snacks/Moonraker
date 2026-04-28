local helpers = require("helpers")

describe("yes applet", function()
  before_each(function()
    helpers.load_applets()
    require("applets.yes")._module.max_iter = 2
  end)

  after_each(function()
    require("applets.yes")._module.max_iter = nil
  end)

  it("prints 'y\\n' repeatedly when no args", function()
    local rc, out = helpers.invoke_multicall("yes")
    assert.equal(0, rc)
    -- Each chunk is "y\n" * 64; max_iter=2 → 128 lines.
    assert.equal(128, select(2, out:gsub("\n", "\n")))
    assert.is_truthy(out:find("y\ny\ny\n", 1, true))
  end)

  it("uses joined args as the line text", function()
    local rc, out = helpers.invoke_multicall("yes", "hello", "world")
    assert.equal(0, rc)
    assert.is_truthy(out:find("hello world\nhello world\n", 1, true))
  end)
end)
