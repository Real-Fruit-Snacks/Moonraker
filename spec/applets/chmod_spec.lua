local helpers = require("helpers")

describe("chmod applet", function()
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

  it("octal mode", function()
    if package.config:sub(1, 1) == "\\" then return end
    local p = tmp()
    local rc = helpers.invoke_multicall("chmod", "644", p)
    assert.equal(0, rc)
    local lfs = require("lfs")
    local attr = lfs.attributes(p)
    assert.equal("rw-r--r--", attr.permissions)
  end)

  it("symbolic +x", function()
    if package.config:sub(1, 1) == "\\" then return end
    local p = tmp()
    helpers.invoke_multicall("chmod", "644", p)
    local rc = helpers.invoke_multicall("chmod", "u+x", p)
    assert.equal(0, rc)
    local lfs = require("lfs")
    assert.equal("rwxr--r--", lfs.attributes(p).permissions)
  end)

  it("missing operand → exit 2", function()
    local rc, _, err = helpers.invoke_multicall("chmod")
    assert.equal(2, rc)
    assert.is_truthy(err:match("missing operand"))
  end)
end)
