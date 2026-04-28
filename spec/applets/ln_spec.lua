local helpers = require("helpers")

describe("ln applet", function()
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

  local function tmp_path()
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    return string.format("%s%smr-ln-%d-%d", base, sep, os.time(), math.random(1, 1000000))
  end

  local function tmp_file()
    local p = helpers.tmp_file("data")
    cleanup[#cleanup + 1] = p
    return p
  end

  it("-s creates a symlink", function()
    local target = tmp_file()
    local link = tmp_path()
    cleanup[#cleanup + 1] = link
    local rc = helpers.invoke_multicall("ln", "-s", target, link)
    assert.equal(0, rc)
    local lfs = require("lfs")
    assert.equal("link", lfs.symlinkattributes(link, "mode"))
  end)

  it("missing operand → exit 2", function()
    local rc = helpers.invoke_multicall("ln")
    assert.equal(2, rc)
  end)
end)
