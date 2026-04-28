local helpers = require("helpers")

describe("truncate applet", function()
  local cleanup = {}
  before_each(function()
    helpers.load_applets()
    cleanup = {}
  end)
  after_each(function()
    for _, p in ipairs(cleanup) do
      pcall(os.remove, p)
    end
  end)

  local function tmp(content)
    local p = helpers.tmp_file(content or "")
    cleanup[#cleanup + 1] = p
    return p
  end

  it("-s shrinks a file", function()
    local p = tmp("hello world")
    local rc = helpers.invoke_multicall("truncate", "-s", "5", p)
    assert.equal(0, rc)
    assert.equal(5, require("lfs").attributes(p).size)
  end)

  it("-s grows a file (zero-fill)", function()
    local p = tmp("hi")
    helpers.invoke_multicall("truncate", "-s", "100", p)
    assert.equal(100, require("lfs").attributes(p).size)
  end)

  it("missing operand → exit 2", function()
    local rc = helpers.invoke_multicall("truncate", "-s", "10")
    assert.equal(2, rc)
  end)

  it("missing -s/-r → exit 2", function()
    local rc = helpers.invoke_multicall("truncate", tmp("x"))
    assert.equal(2, rc)
  end)
end)
