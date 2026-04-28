local helpers = require("helpers")

describe("comm applet", function()
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

  it("emits 3 columns by default", function()
    local a = tmp("apple\nbanana\ncherry\n")
    local b = tmp("banana\ncherry\ndate\n")
    local rc, out = helpers.invoke_multicall("comm", a, b)
    assert.equal(0, rc)
    assert.is_truthy(out:find("apple", 1, true))
    assert.is_truthy(out:find("date", 1, true))
    assert.is_truthy(out:find("banana", 1, true))
  end)

  it("-12 shows only column 3 (common lines)", function()
    local a = tmp("a\nb\nc\n")
    local b = tmp("b\nc\nd\n")
    local _, out = helpers.invoke_multicall("comm", "-12", a, b)
    assert.equal("b\nc\n", out)
  end)

  it("requires two file operands", function()
    local rc, _, err = helpers.invoke_multicall("comm", "onlyone")
    assert.equal(2, rc)
    assert.is_truthy(err:match("two file operands"))
  end)
end)
