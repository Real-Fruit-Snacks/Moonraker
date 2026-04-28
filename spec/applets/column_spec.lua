local helpers = require("helpers")

describe("column applet", function()
  before_each(function() helpers.load_applets() end)

  it("-t aligns columns by whitespace", function()
    local input = "a bb ccc\nxxx y zz\n"
    local _, out = helpers.invoke_with_stdin("column", input, "-t")
    -- The output should be column-aligned; second row 'xxx y zz' should
    -- end up with consistent column widths.
    assert.is_truthy(out:match("a%s+bb%s+ccc"))
    assert.is_truthy(out:match("xxx%s+y%s+zz"))
  end)

  it("-s sets separator for table mode", function()
    local input = "a:b:c\nd:e:f\n"
    local _, out = helpers.invoke_with_stdin("column", input, "-t", "-s", ":")
    assert.is_truthy(out:match("a%s+b%s+c"))
  end)

  it("default columnar mode produces output", function()
    local input = "alpha\nbeta\ngamma\n"
    local _, out = helpers.invoke_with_stdin("column", input)
    assert.is_truthy(#out > 0)
  end)
end)
