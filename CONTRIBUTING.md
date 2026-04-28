# Contributing to Moonraker

Thanks for your interest. Moonraker is a Lua 5.4 port of [Mainsail](https://github.com/Real-Fruit-Snacks/Mainsail) — every contribution should keep parity with Mainsail's behavior unless there is a documented reason to diverge.

## Prerequisites

- Lua 5.4 (preferred; 5.1 also works for development — see [Local development on Windows](#local-development-on-windows))
- LuaRocks 3.x
- A C toolchain (gcc, clang, or MSVC) — required by `luastatic` at build time
- `busted`, `luacheck`, `luastatic`, `luafilesystem` rocks
- `stylua` (separate Rust binary; install via `cargo install stylua` or a [release download](https://github.com/JohnnyMorganz/StyLua/releases))

## Local development on Windows

Native Windows is supported by CI but the local build path runs into Ubuntu-style POSIX assumptions in `luastatic` (and quirks in how `cmd.exe` resolves PATH from spawned subshells). The smoothest local workflow on Windows is **WSL** (Ubuntu 22.04 or similar):

```bash
sudo apt install -y lua5.4 liblua5.4-dev luarocks build-essential
sudo luarocks install busted luacheck luastatic luafilesystem
```

If `luarocks-5.4` fails with an SSL error (a [known Ubuntu bug](https://bugs.launchpad.net/ubuntu/+source/lua-sec/+bug/1953448) involving lua-sec for Lua 5.4), fall back to plain `sudo luarocks install ...` which targets the system Lua (5.1 on Ubuntu 22.04 by default). The Moonraker codebase is compatible with both Lua 5.1 and 5.4 — CI runs the canonical Lua 5.4 build on every push.

## Workflow

1. Fork and branch from `main`.
2. Add or modify code under `src/`.
3. Add or update tests under `spec/`.
4. Run the local checks:

   ```bash
   make lint
   make fmt-check
   make test
   make build
   ```

5. Open a pull request. CI runs the same checks across Linux, Windows, and macOS.

## Adding a new applet

1. Create `src/applets/<name>.lua`. The module must return a table with these fields:

   ```lua
   return {
     name = "<name>",
     aliases = {},                       -- optional
     help = "<one-line summary>",
     main = function(argv) ... return rc end,
   }
   ```

2. Register it in `src/applets/init.lua` (alphabetical order).
3. Add `spec/applets/<name>_spec.lua` covering the POSIX flags and edge cases. When porting from Mainsail, mirror the cases in `reference/tests/test_applets.py` for that applet.
4. Update [`README.md`](README.md) and [`CHANGELOG.md`](CHANGELOG.md).

## Style

- `stylua` enforces formatting. Run `make fmt` before committing.
- `luacheck` enforces lint rules. Run `make lint`.
- Indent with 2 spaces; no tabs.
- Keep applet modules self-contained — shared helpers belong in `src/common.lua`.

## Tests

- All applets must have a spec.
- Tests use the helper in [`spec/helpers.lua`](spec/helpers.lua) to invoke applets through the dispatcher with captured stdio.
- Aim for behavioral parity with Mainsail: same input, same output, same exit code.

## Reporting bugs

Open an issue using the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). Include the applet, exact arguments, expected vs actual output, and platform details.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
