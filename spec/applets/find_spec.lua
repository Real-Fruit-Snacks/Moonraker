local helpers = require("helpers")

describe("find applet", function()
  local lfs
  local cleanup_dirs = {}
  local cleanup_files = {}
  local root

  before_each(function()
    helpers.load_applets()
    lfs = require("lfs")
    cleanup_dirs = {}
    cleanup_files = {}
    local sep = package.config:sub(1, 1)
    local base = os.getenv("TMPDIR") or "/tmp"
    root = string.format("%s%smr-find-%d-%d", base, sep, os.time(), math.random(1, 1000000))
    lfs.mkdir(root)
    cleanup_dirs[#cleanup_dirs + 1] = root
  end)

  after_each(function()
    for _, f in ipairs(cleanup_files) do pcall(os.remove, f) end
    for i = #cleanup_dirs, 1, -1 do pcall(lfs.rmdir, cleanup_dirs[i]) end
  end)

  local function add_file(rel, content)
    local path = root .. "/" .. rel
    local fh = assert(io.open(path, "wb"))
    fh:write(content or "")
    fh:close()
    cleanup_files[#cleanup_files + 1] = path
    return path
  end

  local function add_dir(rel)
    local path = root .. "/" .. rel
    lfs.mkdir(path)
    cleanup_dirs[#cleanup_dirs + 1] = path
    return path
  end

  it("default lists all files in tree", function()
    add_file("a.txt", "")
    add_file("b.log", "")
    local rc, out = helpers.invoke_multicall("find", root)
    assert.equal(0, rc)
    assert.is_truthy(out:find("a.txt", 1, true))
    assert.is_truthy(out:find("b.log", 1, true))
  end)

  it("-name filters by glob", function()
    add_file("a.txt", "")
    add_file("b.log", "")
    local _, out = helpers.invoke_multicall("find", root, "-name", "*.log")
    assert.is_truthy(out:find("b.log", 1, true))
    assert.is_falsy(out:find("a.txt", 1, true))
  end)

  it("-type d lists directories", function()
    add_dir("subdir")
    local _, out = helpers.invoke_multicall("find", root, "-type", "d")
    assert.is_truthy(out:find("subdir", 1, true))
  end)

  it("-type f lists regular files", function()
    add_dir("subdir")
    add_file("a", "")
    local _, out = helpers.invoke_multicall("find", root, "-type", "f")
    assert.is_truthy(out:find("/a", 1, true))
    assert.is_falsy(out:find("/subdir\n", 1, true))
  end)

  it("-maxdepth 1 limits recursion", function()
    add_dir("sub")
    add_file("sub/inner.txt", "")
    local _, out = helpers.invoke_multicall("find", root, "-maxdepth", "1")
    assert.is_falsy(out:find("inner.txt", 1, true))
  end)

  it("nonexistent path → rc 1", function()
    local rc = helpers.invoke_multicall("find", "/no/such/path")
    assert.equal(1, rc)
  end)
end)
