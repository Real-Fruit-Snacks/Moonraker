local helpers = require("helpers")

describe("cmp applet", function()
  local tmp_files = {}

  before_each(function()
    helpers.load_applets()
    tmp_files = {}
  end)

  after_each(function()
    for _, p in ipairs(tmp_files) do os.remove(p) end
  end)

  local function tmp(content)
    local p = helpers.tmp_file(content)
    tmp_files[#tmp_files + 1] = p
    return p
  end

  it("returns 0 for identical files", function()
    local a = tmp("hello\nworld\n")
    local b = tmp("hello\nworld\n")
    local rc = helpers.invoke_multicall("cmp", a, b)
    assert.equal(0, rc)
  end)

  it("returns 1 for differing files", function()
    local a = tmp("hello\n")
    local b = tmp("world\n")
    local rc, out = helpers.invoke_multicall("cmp", a, b)
    assert.equal(1, rc)
    assert.is_truthy(out:find("differ"))
  end)

  it("-s silent mode emits nothing", function()
    local a = tmp("hello")
    local b = tmp("world")
    local rc, out = helpers.invoke_multicall("cmp", "-s", a, b)
    assert.equal(1, rc)
    assert.equal("", out)
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("cmp", tmp("a"))
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)
end)
