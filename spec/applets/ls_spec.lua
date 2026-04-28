local helpers = require("helpers")

describe("ls applet", function()
  local cleanup = {}
  before_each(function()
    helpers.load_applets()
    cleanup = {}
  end)
  after_each(function()
    for _, p in ipairs(cleanup) do pcall(os.remove, p) end
  end)

  local function tmp()
    local p = helpers.tmp_file("x")
    cleanup[#cleanup + 1] = p
    return p
  end

  it("lists a directory", function()
    local rc, out = helpers.invoke_multicall("ls", ".")
    assert.equal(0, rc)
    assert.is_truthy(#out > 0)
  end)

  it("lists a single file", function()
    local p = tmp()
    local _, out = helpers.invoke_multicall("ls", p)
    assert.is_truthy(out:find(require("common").basename(p), 1, true))
  end)

  it("-l long format", function()
    local _, out = helpers.invoke_multicall("ls", "-l", ".")
    -- long format starts with mode chars
    assert.is_truthy(out:find("\n[%-d]", 1, false) or out:match("^[%-d]"))
  end)

  it("nonexistent path → exit 1", function()
    local rc = helpers.invoke_multicall("ls", "/no/such/path")
    assert.equal(1, rc)
  end)

  it("invalid option → exit 2", function()
    local rc = helpers.invoke_multicall("ls", "-Z")
    assert.equal(2, rc)
  end)
end)
