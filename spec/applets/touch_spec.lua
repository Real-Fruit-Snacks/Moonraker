local helpers = require("helpers")

describe("touch applet", function()
  local lfs
  local tmp_files = {}

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
    tmp_files = {}
  end)

  after_each(function()
    for _, p in ipairs(tmp_files) do
      pcall(os.remove, p)
    end
  end)

  local function tmp_path()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local p = string.format("%s%smr-touch-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    tmp_files[#tmp_files + 1] = p
    return p
  end

  it("creates a missing file", function()
    local p = tmp_path()
    local rc = helpers.invoke_multicall("touch", p)
    assert.equal(0, rc)
    assert.is_truthy(lfs.attributes(p))
  end)

  it("-c does not create a missing file", function()
    local p = tmp_path()
    local rc = helpers.invoke_multicall("touch", "-c", p)
    assert.equal(0, rc)
    assert.is_nil(lfs.attributes(p))
  end)

  it("missing operand → rc 2", function()
    local rc, _, err = helpers.invoke_multicall("touch")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing"))
  end)

  it("invalid -t value → rc 2", function()
    local rc, _, err = helpers.invoke_multicall("touch", "-t", "notadate", tmp_path())
    assert.equal(2, rc)
    assert.is_truthy(err:match("invalid %-t"))
  end)

  it("updates timestamp on existing file (no error)", function()
    local p = tmp_path()
    local f = assert(io.open(p, "wb"))
    f:write("hi")
    f:close()
    local rc = helpers.invoke_multicall("touch", p)
    assert.equal(0, rc)
    assert.is_truthy(lfs.attributes(p))
  end)
end)
