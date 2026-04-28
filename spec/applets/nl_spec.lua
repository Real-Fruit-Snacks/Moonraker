local helpers = require("helpers")

describe("nl applet", function()
  local tmp_files = {}

  before_each(function()
    helpers.load_applets()
    tmp_files = {}
  end)

  after_each(function()
    for _, p in ipairs(tmp_files) do
      os.remove(p)
    end
  end)

  local function tmp(content)
    local p = helpers.tmp_file(content)
    tmp_files[#tmp_files + 1] = p
    return p
  end

  it("numbers non-empty lines by default", function()
    local p = tmp("a\n\nb\n")
    local rc, out = helpers.invoke_multicall("nl", p)
    assert.equal(0, rc)
    assert.is_truthy(out:find("     1\ta\n", 1, true))
    assert.is_truthy(out:find("     2\tb\n", 1, true))
    -- Empty line in middle should not be numbered
    assert.is_falsy(out:find("     2\t\n", 1, true))
  end)

  it("-ba numbers all lines including blank", function()
    local p = tmp("a\n\nb\n")
    local _, out = helpers.invoke_multicall("nl", "-ba", p)
    assert.is_truthy(out:find("     1\ta\n", 1, true))
    assert.is_truthy(out:find("     2\t\n", 1, true))
    assert.is_truthy(out:find("     3\tb\n", 1, true))
  end)

  it("-w sets number width", function()
    local p = tmp("a\n")
    local _, out = helpers.invoke_multicall("nl", "-w", "3", p)
    assert.is_truthy(out:find("  1\ta\n", 1, true))
  end)

  it("-s sets separator", function()
    local p = tmp("a\n")
    local _, out = helpers.invoke_multicall("nl", "-s", ": ", p)
    assert.is_truthy(out:find(": a\n", 1, true))
  end)

  it("-v sets starting number", function()
    local p = tmp("a\n")
    local _, out = helpers.invoke_multicall("nl", "-v", "100", p)
    assert.is_truthy(out:find("   100\ta\n", 1, true))
  end)
end)
