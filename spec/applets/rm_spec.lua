local helpers = require("helpers")

describe("rm applet", function()
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

  local function tmp(content)
    local p = helpers.tmp_file(content or "")
    tmp_files[#tmp_files + 1] = p
    return p
  end

  it("removes a file", function()
    local p = tmp("hi")
    local rc = helpers.invoke_multicall("rm", p)
    assert.equal(0, rc)
    assert.is_nil(lfs.attributes(p))
  end)

  it("missing file without -f → rc 1", function()
    local rc, _, err = helpers.invoke_multicall("rm", "/no/such/file")
    assert.equal(1, rc)
    assert.is_truthy(err:match("No such"))
  end)

  it("-f silences missing-file errors", function()
    local rc, _, err = helpers.invoke_multicall("rm", "-f", "/no/such/file")
    assert.equal(0, rc)
    assert.equal("", err)
  end)

  it("refuses directory without -r", function()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local d = string.format("%s%smr-rmdir-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    assert(lfs.mkdir(d))
    local rc, _, err = helpers.invoke_multicall("rm", d)
    assert.equal(1, rc)
    assert.is_truthy(err:match("Is a directory"))
    lfs.rmdir(d) -- cleanup
  end)

  it("-r removes directory tree", function()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    local d = string.format("%s%smr-rmtree-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    assert(lfs.mkdir(d))
    local f = d .. sep .. "child.txt"
    local fh = assert(io.open(f, "wb"))
    fh:write("x")
    fh:close()
    local rc = helpers.invoke_multicall("rm", "-r", d)
    assert.equal(0, rc)
    assert.is_nil(lfs.attributes(d))
  end)

  it("-v prints removed paths", function()
    local p = tmp("x")
    local _, out = helpers.invoke_multicall("rm", "-v", p)
    assert.is_truthy(out:find("removed", 1, true))
  end)
end)
