local helpers = require("helpers")

describe("mkdir applet", function()
  local lfs
  local cleanup = {}

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
    cleanup = {}
  end)

  after_each(function()
    -- Remove created dirs in reverse order (deepest first).
    for i = #cleanup, 1, -1 do
      lfs.rmdir(cleanup[i])
    end
  end)

  local function tmp_dir_path()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
    return string.format("%s%smr-mkdir-%d-%d", base, sep, os.time(), math.random(1, 1000000))
  end

  it("creates a single directory", function()
    local d = tmp_dir_path()
    cleanup[#cleanup + 1] = d
    local rc = helpers.invoke_multicall("mkdir", d)
    assert.equal(0, rc)
    assert.equal("directory", lfs.attributes(d, "mode"))
  end)

  it("-p creates parents", function()
    local d = tmp_dir_path()
    local sub = d .. "/a/b/c"
    cleanup[#cleanup + 1] = sub
    cleanup[#cleanup + 1] = d .. "/a/b"
    cleanup[#cleanup + 1] = d .. "/a"
    cleanup[#cleanup + 1] = d
    local rc = helpers.invoke_multicall("mkdir", "-p", sub)
    assert.equal(0, rc)
    assert.equal("directory", lfs.attributes(sub, "mode"))
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("mkdir")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)

  it("-v emits a created message", function()
    local d = tmp_dir_path()
    cleanup[#cleanup + 1] = d
    local _, out = helpers.invoke_multicall("mkdir", "-v", d)
    assert.is_truthy(out:find("created directory", 1, true))
  end)
end)
