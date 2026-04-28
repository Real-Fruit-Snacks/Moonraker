local helpers = require("helpers")

describe("id applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("prints uid/gid/groups by default", function()
    local rc, out = helpers.invoke_multicall("id")
    assert.equal(0, rc)
    -- POSIX: "uid=N(name) gid=N(group) ..."; Windows fallback also has uid=
    assert.is_truthy(out:find("uid=", 1, true))
  end)

  it("-u prints just the uid (or username with -un)", function()
    local _, out = helpers.invoke_multicall("id", "-u")
    -- Either a number or a fallback. Should be non-empty.
    assert.is_truthy(out:match("[^\n]+\n$"))
  end)
end)
