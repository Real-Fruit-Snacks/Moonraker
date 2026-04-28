std = "lua54"

include_files = {
  "src/**/*.lua",
  "spec/**/*.lua",
  "build.lua",
}

exclude_files = {
  "reference/",
  "src/vendor/",
}

max_line_length = 100

-- Test files use busted's globals.
files["spec/**/*.lua"] = {
  std = "+busted",
}

-- The test helper deliberately swaps io.stdout / io.stderr to capture
-- output. Allow that single pattern without warnings.
files["spec/helpers.lua"] = {
  std = "+busted",
  ignore = { "122/io" },
}

-- Applets receive argv via the dispatcher; they don't need to declare it as
-- a global, but they sometimes ignore unused parameters intentionally.
unused_args = false

-- Allow shadowing the upvalue `arg` in main.lua specifically.
files["src/main.lua"] = {
  globals = { "arg" },
}
