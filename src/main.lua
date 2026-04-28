-- Moonraker entry point.
--
-- Loads all applets into the registry, then hands control to the dispatcher.
-- The luastatic-built binary embeds this as its top-level Lua module.

local applets = require("applets.init")
local cli = require("cli")

-- Capture the program path before any applet sees a rewritten argv[0].
-- The `update` applet uses this to figure out which file to replace.
_G._MOONRAKER_BINARY = (arg and arg[0]) or "moonraker"

applets.load_all()

local rc = cli.main(arg)
os.exit(rc)
