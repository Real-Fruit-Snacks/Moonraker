local helpers = require("helpers")

describe("tac applet", function()
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

  it("reverses lines (default newline separator)", function()
    local p = tmp("a\nb\nc\n")
    local rc, out = helpers.invoke_multicall("tac", p)
    assert.equal(0, rc)
    assert.equal("c\nb\na\n", out)
  end)

  it("preserves trailing newline state", function()
    local p = tmp("a\nb\nc")
    local _, out = helpers.invoke_multicall("tac", p)
    assert.equal("c\nb\na", out)
  end)

  it("reads stdin", function()
    local rc, out = helpers.invoke_with_stdin("tac", "1\n2\n3\n")
    assert.equal(0, rc)
    assert.equal("3\n2\n1\n", out)
  end)

  it("-s custom separator", function()
    local p = tmp("a:b:c")
    local _, out = helpers.invoke_multicall("tac", "-s", ":", p)
    assert.equal("c:b:a", out)
  end)
end)
