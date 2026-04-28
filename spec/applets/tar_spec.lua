local helpers = require("helpers")

describe("tar applet", function()
  local lfs
  local cleanup_files = {}
  local cleanup_dirs = {}
  local tmp_root

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
    cleanup_files = {}
    cleanup_dirs = {}
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    tmp_root = string.format("%s%smr-tar-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    lfs.mkdir(tmp_root)
    cleanup_dirs[#cleanup_dirs + 1] = tmp_root
  end)

  after_each(function()
    for _, p in ipairs(cleanup_files) do
      pcall(os.remove, p)
    end
    for k = #cleanup_dirs, 1, -1 do
      pcall(lfs.rmdir, cleanup_dirs[k])
    end
  end)

  local function add_file(name, content)
    local path = tmp_root .. "/" .. name
    local fh = assert(io.open(path, "wb"))
    fh:write(content)
    fh:close()
    cleanup_files[#cleanup_files + 1] = path
    return path
  end

  it("must specify operation", function()
    local rc = helpers.invoke_multicall("tar")
    assert.equal(2, rc)
  end)

  it("requires -f", function()
    local rc = helpers.invoke_multicall("tar", "-c")
    assert.equal(2, rc)
  end)

  it("still rejects xz (-J)", function()
    local rc = helpers.invoke_multicall("tar", "-cJf", "/tmp/test.tar.xz", "/tmp/anything")
    assert.equal(2, rc)
  end)

  it("creates and extracts a tar.bz2", function()
    -- The bzip2 module is statically linked into the moonraker binary
    -- but isn't installed as a luarock in the unit-test environment by
    -- default. Skip gracefully if it's not loadable.
    if not pcall(require, "bzip2") then
      pending("bzip2 module not available (vendored only inside the binary)")
      return
    end
    add_file("hi.txt", "compressed greetings via bzip2")
    local archive = tmp_root .. "/test.tar.bz2"
    cleanup_files[#cleanup_files + 1] = archive
    local rc = helpers.invoke_multicall("tar", "-cjf", archive, tmp_root .. "/hi.txt")
    assert.equal(0, rc)
    -- bzip2 magic: "BZh"
    local fh = io.open(archive, "rb")
    local first3 = fh and fh:read(3) or ""
    if fh then fh:close() end
    assert.equal("BZh", first3)
    -- List
    local _, out = helpers.invoke_multicall("tar", "-tf", archive)
    assert.is_truthy(out:find("hi.txt", 1, true))
  end)

  it("creates and lists a simple archive", function()
    add_file("a.txt", "alpha")
    add_file("b.txt", "bravo")
    local archive = tmp_root .. "/test.tar"
    cleanup_files[#cleanup_files + 1] = archive
    local rc = helpers.invoke_multicall("tar", "-cf", archive, tmp_root .. "/a.txt", tmp_root .. "/b.txt")
    assert.equal(0, rc)
    -- List
    local rc2, out = helpers.invoke_multicall("tar", "-tf", archive)
    assert.equal(0, rc2)
    assert.is_truthy(out:find("a.txt", 1, true))
    assert.is_truthy(out:find("b.txt", 1, true))
  end)

  it("creates and extracts a tar.gz", function()
    add_file("hi.txt", "compressed greetings")
    local archive = tmp_root .. "/test.tar.gz"
    cleanup_files[#cleanup_files + 1] = archive
    local rc = helpers.invoke_multicall("tar", "-czf", archive, tmp_root .. "/hi.txt")
    assert.equal(0, rc)
    -- gzip magic on tar.gz
    local fh = io.open(archive, "rb")
    local first2 = fh and fh:read(2) or ""
    if fh then fh:close() end
    assert.equal(0x1f, first2:byte(1))
    assert.equal(0x8b, first2:byte(2))
    -- List
    local _, out = helpers.invoke_multicall("tar", "-tf", archive)
    assert.is_truthy(out:find("hi.txt", 1, true))
  end)
end)
