local helpers = require("helpers")

describe("split applet", function()
  local lfs
  local tmp_dir
  local cleanup_files = {}

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
    cleanup_files = {}
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    tmp_dir = string.format("%s%smr-split-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    lfs.mkdir(tmp_dir)
  end)

  after_each(function()
    for _, p in ipairs(cleanup_files) do
      pcall(os.remove, p)
    end
    pcall(lfs.rmdir, tmp_dir)
  end)

  local function track(path)
    cleanup_files[#cleanup_files + 1] = path
    return path
  end

  it("splits by lines", function()
    local prefix = tmp_dir .. "/x"
    local rc = helpers.invoke_with_stdin("split", "1\n2\n3\n4\n5\n", "-l", "2", "-", prefix)
    assert.equal(0, rc)
    assert.is_truthy(lfs.attributes(track(prefix .. "aa")))
    assert.is_truthy(lfs.attributes(track(prefix .. "ab")))
    assert.is_truthy(lfs.attributes(track(prefix .. "ac")))
  end)

  it("custom prefix", function()
    local prefix = tmp_dir .. "/out_"
    helpers.invoke_with_stdin("split", "a\nb\n", "-l", "1", "-", prefix)
    assert.is_truthy(lfs.attributes(track(prefix .. "aa")))
    track(prefix .. "ab")
  end)

  it("-d numeric suffixes", function()
    local prefix = tmp_dir .. "/x"
    helpers.invoke_with_stdin("split", "a\nb\n", "-l", "1", "-d", "-", prefix)
    assert.is_truthy(lfs.attributes(track(prefix .. "00")))
    assert.is_truthy(lfs.attributes(track(prefix .. "01")))
  end)
end)
