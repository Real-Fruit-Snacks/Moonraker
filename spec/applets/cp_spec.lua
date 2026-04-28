local helpers = require("helpers")

describe("cp applet", function()
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

  local function tmp_path()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local p = string.format("%s%smr-cp-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    cleanup[#cleanup + 1] = p
    return p
  end

  it("copies a file", function()
    local src = tmp("hello")
    local dst = tmp_path()
    local rc = helpers.invoke_multicall("cp", src, dst)
    assert.equal(0, rc)
    assert.equal("hello", helpers.read_file(dst))
  end)

  it("missing source → exit 1", function()
    local dst = tmp_path()
    local rc, _, err = helpers.invoke_multicall("cp", "/no/such/file", dst)
    assert.equal(1, rc)
    assert.is_truthy(err:match("No such"))
  end)

  it("refuses directory without -r", function()
    local lfs = require("lfs")
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local d = string.format("%s%smr-cp-d-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    lfs.mkdir(d)
    cleanup[#cleanup + 1] = d
    local dst = tmp_path()
    local rc, _, err = helpers.invoke_multicall("cp", d, dst)
    assert.equal(1, rc)
    assert.is_truthy(err:match("omitting directory"))
    pcall(lfs.rmdir, d)
  end)

  it("missing operand → exit 2", function()
    local rc = helpers.invoke_multicall("cp", "only-one")
    assert.equal(2, rc)
  end)
end)
