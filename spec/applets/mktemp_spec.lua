local helpers = require("helpers")

describe("mktemp applet", function()
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

  it("creates a file with default template", function()
    local rc, out = helpers.invoke_multicall("mktemp")
    assert.equal(0, rc)
    local path = out:gsub("\n$", "")
    cleanup[#cleanup + 1] = path
    local fh = io.open(path, "rb")
    assert.is_not_nil(fh)
    if fh then fh:close() end
  end)

  it("-d creates a directory", function()
    local rc, out = helpers.invoke_multicall("mktemp", "-d")
    assert.equal(0, rc)
    local path = out:gsub("\n$", "")
    cleanup[#cleanup + 1] = path
    local lfs = require("lfs")
    assert.equal("directory", lfs.attributes(path, "mode"))
    pcall(lfs.rmdir, path)
  end)

  it("-u dry-run does not leave a file", function()
    local rc, out = helpers.invoke_multicall("mktemp", "-u")
    assert.equal(0, rc)
    local path = out:gsub("\n$", "")
    local fh = io.open(path, "rb")
    assert.is_nil(fh)
  end)

  it("too few X's → exit 1", function()
    local rc = helpers.invoke_multicall("mktemp", "shortXX")
    assert.equal(1, rc)
  end)
end)
