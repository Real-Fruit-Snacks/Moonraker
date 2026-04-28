local helpers = require("helpers")

describe("md5sum applet", function()
  local cleanup = {}
  before_each(function() helpers.load_applets(); cleanup = {} end)
  after_each(function()
    for _, p in ipairs(cleanup) do pcall(os.remove, p) end
  end)

  local function tmp(content)
    local p = helpers.tmp_file(content)
    cleanup[#cleanup + 1] = p
    return p
  end

  it("computes md5 of stdin", function()
    local rc, out = helpers.invoke_with_stdin("md5sum", "abc")
    assert.equal(0, rc)
    assert.is_truthy(out:find("900150983cd24fb0d6963f7d28e17f72", 1, true))
  end)

  it("computes md5 of file", function()
    local p = tmp("abc")
    local _, out = helpers.invoke_multicall("md5sum", p)
    assert.is_truthy(out:find("900150983cd24fb0d6963f7d28e17f72", 1, true))
    assert.is_truthy(out:find(p, 1, true))
  end)

  it("--tag uses BSD format", function()
    local p = tmp("abc")
    local _, out = helpers.invoke_multicall("md5sum", "--tag", p)
    assert.is_truthy(out:find("MD5 (", 1, true))
  end)
end)
