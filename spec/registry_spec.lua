describe("registry", function()
  local registry

  before_each(function()
    package.loaded["registry"] = nil
    registry = require("registry")
  end)

  it("registers and retrieves by name", function()
    local applet = {
      name = "demo",
      main = function()
        return 0
      end,
    }
    registry.register(applet)
    assert.equal(applet, registry.get("demo"))
  end)

  it("registers aliases pointing to the same applet", function()
    local applet = {
      name = "demo",
      aliases = { "d", "dem" },
      main = function()
        return 0
      end,
    }
    registry.register(applet)
    assert.equal(applet, registry.get("d"))
    assert.equal(applet, registry.get("dem"))
  end)

  it("returns nil for unknown names", function()
    assert.is_nil(registry.get("nope"))
  end)

  it("requires name and main", function()
    assert.has_error(function()
      registry.register({ main = function() end })
    end)
    assert.has_error(function()
      registry.register({ name = "x" })
    end)
  end)

  it("iterates in alphabetical order", function()
    registry.register({ name = "z", main = function() return 0 end })
    registry.register({ name = "a", main = function() return 0 end })
    registry.register({ name = "m", main = function() return 0 end })
    local names = {}
    for _, a in registry.iter_sorted() do
      names[#names + 1] = a.name
    end
    assert.same({ "a", "m", "z" }, names)
  end)

  it("counts unique applets only (aliases don't inflate)", function()
    registry.register({
      name = "x",
      aliases = { "y", "z" },
      main = function() return 0 end,
    })
    assert.equal(1, registry.count())
  end)
end)
