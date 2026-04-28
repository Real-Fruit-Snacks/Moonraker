local helpers = require("helpers")

describe("gzip applet", function()
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

  it("compresses + decompresses stdin → stdout", function()
    local input = "hello world hello world hello world"
    local rc1, encoded = helpers.invoke_with_stdin("gzip", input, "-c")
    assert.equal(0, rc1)
    -- gzip magic: 1f 8b
    assert.equal(0x1f, encoded:byte(1))
    assert.equal(0x8b, encoded:byte(2))

    local rc2, decoded = helpers.invoke_with_stdin("gzip", encoded, "-d", "-c")
    assert.equal(0, rc2)
    assert.equal(input, decoded)
  end)

  it("compresses then decompresses a file (replacing original by default)", function()
    local p = tmp("the quick brown fox jumps over the lazy dog")
    local rc = helpers.invoke_multicall("gzip", p)
    assert.equal(0, rc)
    cleanup[#cleanup + 1] = p .. ".gz"
    -- p should be gone; p.gz should exist
    assert.is_nil(io.open(p, "rb"))
    local fh = io.open(p .. ".gz", "rb")
    assert.is_not_nil(fh)
    fh:close()
    -- Decompress back
    local rc2 = helpers.invoke_multicall("gunzip", p .. ".gz")
    assert.equal(0, rc2)
    assert.equal("the quick brown fox jumps over the lazy dog", helpers.read_file(p))
  end)

  it("-k keeps the original", function()
    local p = tmp("data")
    local rc = helpers.invoke_multicall("gzip", "-k", p)
    assert.equal(0, rc)
    cleanup[#cleanup + 1] = p .. ".gz"
    assert.is_truthy(io.open(p, "rb"))
    assert.is_truthy(io.open(p .. ".gz", "rb"))
  end)

  it("-t tests integrity", function()
    -- Compress something first
    local p = tmp("data")
    helpers.invoke_multicall("gzip", "-k", p)
    cleanup[#cleanup + 1] = p .. ".gz"
    local rc = helpers.invoke_multicall("gzip", "-t", p .. ".gz")
    assert.equal(0, rc)
  end)
end)
