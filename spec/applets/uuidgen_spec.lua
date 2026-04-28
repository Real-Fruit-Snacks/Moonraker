local helpers = require("helpers")

describe("uuidgen applet", function()
  before_each(function() helpers.load_applets() end)

  it("prints a UUID v4", function()
    local rc, out = helpers.invoke_multicall("uuidgen")
    assert.equal(0, rc)
    -- xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx where y is 8/9/a/b
    local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]"
      .. "%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x\n$"
    assert.is_truthy(out:match(pattern))
  end)

  it("--upper produces uppercase", function()
    local _, out = helpers.invoke_multicall("uuidgen", "--upper")
    assert.is_truthy(out:match("^[%u%d%-]+\n$"))
    assert.is_falsy(out:find("[a-z]"))
  end)

  it("--hex strips dashes", function()
    local _, out = helpers.invoke_multicall("uuidgen", "--hex")
    assert.is_falsy(out:find("-", 1, true))
    assert.is_truthy(out:match("^%x+\n$"))
  end)

  it("-c emits multiple", function()
    local _, out = helpers.invoke_multicall("uuidgen", "-c", "3")
    -- 3 lines
    assert.equal(3, select(2, out:gsub("\n", "\n")))
  end)
end)
