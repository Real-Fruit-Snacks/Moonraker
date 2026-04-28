local helpers = require("helpers")

-- xargs spawns subprocesses whose stdout writes directly to the parent's
-- real terminal, not to our in-memory io.stdout buffer. That means we
-- can't easily assert on the subprocess output via the unit-test helper.
-- Smoke tests via the built binary cover the real behaviour. Here we
-- verify exit codes and parsing only.

describe("xargs applet", function()
  before_each(function()
    helpers.load_applets()
  end)

  it("returns 0 on simple input", function()
    local rc = helpers.invoke_with_stdin("xargs", "a b c\n")
    assert.equal(0, rc)
  end)

  it("-r skips empty input", function()
    local rc = helpers.invoke_with_stdin("xargs", "", "-r", "echo")
    assert.equal(0, rc)
  end)

  it("invalid option → exit 2", function()
    local rc = helpers.invoke_with_stdin("xargs", "x", "-Z")
    assert.equal(2, rc)
  end)
end)
