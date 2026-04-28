local helpers = require("helpers")

describe("dd applet", function()
  local cleanup = {}
  before_each(function()
    helpers.load_applets()
    cleanup = {}
  end)
  after_each(function()
    for _, p in ipairs(cleanup) do pcall(os.remove, p) end
  end)

  local function tmp()
    local p = helpers.tmp_file("")
    cleanup[#cleanup + 1] = p
    return p
  end

  it("copies stdin to stdout", function()
    local rc, out = helpers.invoke_with_stdin("dd", "hello world", "bs=512")
    assert.equal(0, rc)
    assert.equal("hello world", out)
  end)

  it("of= writes to a file", function()
    local p = tmp()
    helpers.invoke_with_stdin("dd", "data", "of=" .. p)
    assert.equal("data", helpers.read_file(p))
  end)

  it("conv=ucase uppercases", function()
    local _, out = helpers.invoke_with_stdin("dd", "hello", "conv=ucase", "bs=1")
    assert.equal("HELLO", out)
  end)

  it("bad operand → exit 2", function()
    local rc = helpers.invoke_with_stdin("dd", "x", "noequals")
    assert.equal(2, rc)
  end)

  it("invalid bs → exit 2", function()
    local rc = helpers.invoke_with_stdin("dd", "x", "bs=abc")
    assert.equal(2, rc)
  end)
end)
