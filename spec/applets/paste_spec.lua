local helpers = require("helpers")

describe("paste applet", function()
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

  it("merges lines with TAB", function()
    local a = tmp("1\n2\n3\n")
    local b = tmp("a\nb\nc\n")
    local rc, out = helpers.invoke_multicall("paste", a, b)
    assert.equal(0, rc)
    assert.equal("1\ta\n2\tb\n3\tc\n", out)
  end)

  it("-d sets delimiter", function()
    local a = tmp("1\n2\n")
    local b = tmp("a\nb\n")
    local _, out = helpers.invoke_multicall("paste", "-d", ",", a, b)
    assert.equal("1,a\n2,b\n", out)
  end)

  it("-s concatenates each file's lines", function()
    local a = tmp("1\n2\n3\n")
    local _, out = helpers.invoke_multicall("paste", "-s", a)
    assert.equal("1\t2\t3\n", out)
  end)
end)
