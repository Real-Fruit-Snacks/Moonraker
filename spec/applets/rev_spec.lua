local helpers = require("helpers")

describe("rev applet", function()
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

  it("reverses each line", function()
    local p = tmp("hello\nworld\n")
    local rc, out = helpers.invoke_multicall("rev", p)
    assert.equal(0, rc)
    assert.equal("olleh\ndlrow\n", out)
  end)

  it("preserves CRLF line endings", function()
    local p = tmp("ab\r\ncd\r\n")
    local _, out = helpers.invoke_multicall("rev", p)
    assert.equal("ba\r\ndc\r\n", out)
  end)

  it("handles missing trailing newline", function()
    local p = tmp("abc")
    local _, out = helpers.invoke_multicall("rev", p)
    assert.equal("cba", out)
  end)

  it("reads stdin", function()
    local rc, out = helpers.invoke_with_stdin("rev", "abc\n")
    assert.equal(0, rc)
    assert.equal("cba\n", out)
  end)
end)
