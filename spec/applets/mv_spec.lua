local helpers = require("helpers")

describe("mv applet", function()
  local lfs
  local cleanup = {}

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
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

  local function tmp_path()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local p = string.format("%s%smr-mv-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    cleanup[#cleanup + 1] = p
    return p
  end

  it("renames a file", function()
    local src = tmp("data")
    local dst = tmp_path()
    local rc = helpers.invoke_multicall("mv", src, dst)
    assert.equal(0, rc)
    assert.is_nil(lfs.attributes(src))
    assert.is_truthy(lfs.attributes(dst))
    assert.equal("data", helpers.read_file(dst))
  end)

  it("missing source → rc 1", function()
    local dst = tmp_path()
    local rc, _, err = helpers.invoke_multicall("mv", "/no/such/file", dst)
    assert.equal(1, rc)
    assert.is_truthy(err:match("No such"))
  end)

  it("missing operand → rc 2", function()
    local rc, _, err = helpers.invoke_multicall("mv", "only-one")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing"))
  end)

  it("-v prints rename log", function()
    local src = tmp("x")
    local dst = tmp_path()
    local _, out = helpers.invoke_multicall("mv", "-v", src, dst)
    assert.is_truthy(out:find("->", 1, true))
  end)

  it("-n refuses to overwrite existing target", function()
    local src = tmp("new")
    local dst = tmp("existing")
    local rc = helpers.invoke_multicall("mv", "-n", src, dst)
    assert.equal(0, rc)
    assert.equal("existing", helpers.read_file(dst))
    -- src should remain
    assert.is_truthy(lfs.attributes(src))
  end)
end)
