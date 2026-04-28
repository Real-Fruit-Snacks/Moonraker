local helpers = require("helpers")

describe("gunzip applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("decompresses stdin -> stdout (delegates to gzip -d)", function()
    -- Compress first
    local _, encoded = helpers.invoke_with_stdin("gzip", "round trip", "-c")
    -- Decompress via gunzip
    local rc, decoded = helpers.invoke_with_stdin("gunzip", encoded, "-c")
    assert.equal(0, rc)
    assert.equal("round trip", decoded)
  end)
end)
