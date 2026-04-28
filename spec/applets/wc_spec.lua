local helpers = require("helpers")

describe("wc applet", function()
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

  it("default: lines, words, bytes", function()
    local p = tmp("hello world\nfoo bar baz\n")
    local rc, out = helpers.invoke_multicall("wc", p)
    assert.equal(0, rc)
    -- 2 lines, 5 words, 24 bytes
    assert.is_truthy(out:match("%s+2%s+5%s+24"))
  end)

  it("-l counts only lines", function()
    local p = tmp("a\nb\nc\n")
    local _, out = helpers.invoke_multicall("wc", "-l", p)
    assert.is_truthy(out:match("%s+3"))
    assert.is_falsy(out:match("%s+%d+%s+%d+%s+%d+%s+"))
  end)

  it("-c counts bytes", function()
    local p = tmp("hello")
    local _, out = helpers.invoke_multicall("wc", "-c", p)
    assert.is_truthy(out:match("%s+5"))
  end)

  it("-w counts words", function()
    local p = tmp("a b c d e")
    local _, out = helpers.invoke_multicall("wc", "-w", p)
    assert.is_truthy(out:match("%s+5"))
  end)

  it("multi-file emits totals", function()
    local a = tmp("a\n")
    local b = tmp("b\n")
    local _, out = helpers.invoke_multicall("wc", "-l", a, b)
    assert.is_truthy(out:match("total"))
  end)

  it("reads stdin", function()
    local rc, out = helpers.invoke_with_stdin("wc", "x\ny\n", "-l")
    assert.equal(0, rc)
    assert.is_truthy(out:match("%s+2"))
  end)
end)
