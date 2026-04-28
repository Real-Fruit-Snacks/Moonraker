local helpers = require("helpers")

describe("stat applet", function()
  local cleanup = {}
  before_each(function()
    helpers.load_applets()
    cleanup = {}
  end)
  after_each(function()
    for _, p in ipairs(cleanup) do pcall(os.remove, p) end
  end)

  local function tmp(content)
    local p = helpers.tmp_file(content)
    cleanup[#cleanup + 1] = p
    return p
  end

  it("default output for a regular file", function()
    local p = tmp("hello world")
    local rc, out = helpers.invoke_multicall("stat", p)
    assert.equal(0, rc)
    assert.is_truthy(out:find("regular file", 1, true))
    assert.is_truthy(out:find("Size: 11", 1, true))
  end)

  it("-c custom format", function()
    local p = tmp("xx")
    local _, out = helpers.invoke_multicall("stat", "-c", "%n %s", p)
    assert.is_truthy(out:find(p, 1, true))
    assert.is_truthy(out:find(" 2", 1, true))
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("stat")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)

  it("nonexistent path → exit 1", function()
    local rc, _, err = helpers.invoke_multicall("stat", "/no/such/path")
    assert.equal(1, rc)
    assert.is_truthy(err:match("No such"))
  end)
end)
