local helpers = require("helpers")

describe("cat applet", function()
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

  it("emits file contents", function()
    local p = tmp("hello\nworld\n")
    local rc, out = helpers.invoke_multicall("cat", p)
    assert.equal(0, rc)
    assert.equal("hello\nworld\n", out)
  end)

  it("concatenates multiple files", function()
    local a = tmp("A\n")
    local b = tmp("B\n")
    local _, out = helpers.invoke_multicall("cat", a, b)
    assert.equal("A\nB\n", out)
  end)

  it("reads stdin when no files given", function()
    local rc, out = helpers.invoke_with_stdin("cat", "via stdin\n")
    assert.equal(0, rc)
    assert.equal("via stdin\n", out)
  end)

  it("reads stdin via '-' sentinel", function()
    local rc, out = helpers.invoke_with_stdin("cat", "x\n", "-")
    assert.equal(0, rc)
    assert.equal("x\n", out)
  end)

  it("-n numbers all lines", function()
    local p = tmp("a\nb\n")
    local _, out = helpers.invoke_multicall("cat", "-n", p)
    assert.equal("     1\ta\n     2\tb\n", out)
  end)

  it("-b numbers non-blank lines only", function()
    local p = tmp("a\n\nb\n")
    local _, out = helpers.invoke_multicall("cat", "-b", p)
    assert.equal("     1\ta\n\n     2\tb\n", out)
  end)

  it("missing file → rc 1 with error", function()
    local rc, _, err = helpers.invoke_multicall("cat", "/nope/nope/nope")
    assert.equal(1, rc)
    assert.is_truthy(err:match("nope"))
  end)
end)
