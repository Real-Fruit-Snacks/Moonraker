local helpers = require("helpers")

describe("tail applet", function()
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

  it("prints last 10 lines by default", function()
    local content = ""
    for i = 1, 15 do
      content = content .. "line" .. i .. "\n"
    end
    local p = tmp(content)
    local rc, out = helpers.invoke_multicall("tail", p)
    assert.equal(0, rc)
    assert.equal(10, select(2, out:gsub("\n", "\n")))
    assert.is_truthy(out:find("line6\n", 1, true))
    assert.is_truthy(out:find("line15\n", 1, true))
    assert.is_falsy(out:find("line5\n", 1, true))
  end)

  it("-n N prints last N lines", function()
    local p = tmp("a\nb\nc\nd\n")
    local _, out = helpers.invoke_multicall("tail", "-n", "2", p)
    assert.equal("c\nd\n", out)
  end)

  it("-c N prints last N bytes", function()
    local p = tmp("abcdefgh")
    local _, out = helpers.invoke_multicall("tail", "-c", "3", p)
    assert.equal("fgh", out)
  end)

  it("-NUM shorthand", function()
    local p = tmp("a\nb\nc\n")
    local _, out = helpers.invoke_multicall("tail", "-2", p)
    assert.equal("b\nc\n", out)
  end)

  it("reads stdin", function()
    local rc, out = helpers.invoke_with_stdin("tail", "a\nb\nc\nd\n", "-n", "2")
    assert.equal(0, rc)
    assert.equal("c\nd\n", out)
  end)
end)
