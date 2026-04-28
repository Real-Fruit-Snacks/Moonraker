local helpers = require("helpers")

describe("tee applet", function()
  local tmp_files = {}

  before_each(function()
    helpers.load_applets()
    tmp_files = {}
  end)

  after_each(function()
    for _, p in ipairs(tmp_files) do
      os.remove(p)
    end
  end)

  local function tmp_path()
    local p = helpers.tmp_file("")
    tmp_files[#tmp_files + 1] = p
    return p
  end

  it("writes stdin to stdout and a file", function()
    local p = tmp_path()
    local rc, out = helpers.invoke_with_stdin("tee", "hello\n", p)
    assert.equal(0, rc)
    assert.equal("hello\n", out)
    assert.equal("hello\n", helpers.read_file(p))
  end)

  it("writes to multiple files", function()
    local a, b = tmp_path(), tmp_path()
    local rc, out = helpers.invoke_with_stdin("tee", "x\n", a, b)
    assert.equal(0, rc)
    assert.equal("x\n", out)
    assert.equal("x\n", helpers.read_file(a))
    assert.equal("x\n", helpers.read_file(b))
  end)

  it("-a appends to existing file", function()
    local p = tmp_path()
    local f = assert(io.open(p, "wb"))
    f:write("existing\n")
    f:close()
    local _, out = helpers.invoke_with_stdin("tee", "new\n", "-a", p)
    assert.equal("new\n", out)
    assert.equal("existing\nnew\n", helpers.read_file(p))
  end)

  it("with no files just copies stdin to stdout", function()
    local rc, out = helpers.invoke_with_stdin("tee", "passthrough\n")
    assert.equal(0, rc)
    assert.equal("passthrough\n", out)
  end)
end)
