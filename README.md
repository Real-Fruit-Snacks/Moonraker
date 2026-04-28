<div align="center">

# Moonraker

A BusyBox-style multi-call binary in Lua — Unix utilities in a single executable, native on Linux, Windows, and macOS.

![Language](https://img.shields.io/badge/language-Lua%205.4-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Status](https://img.shields.io/badge/status-early%20development-orange.svg)

</div>

---

## Status

**Early development.** Phase 0 scaffolding only. Currently shipping: `true`, `false`, `echo`, `pwd`.

Moonraker is a Lua 5.4 port of [Mainsail](https://github.com/Real-Fruit-Snacks/Mainsail), tracking its applet inventory and test behavior. The full port targets 84 applets; see milestones below.

## Quick start

### From source

Requires Lua 5.4, [LuaRocks](https://luarocks.org/), and a C toolchain (gcc/clang/MSVC).

```bash
luarocks install --local luastatic busted luacheck
make build           # build the moonraker binary
make test            # run the test suite
./dist/moonraker --list
./dist/moonraker echo "hello, world"
```

### Multi-call dispatch

Symlink or hardlink the binary to an applet name and call it directly:

```bash
ln -s ./dist/moonraker /usr/local/bin/echo
echo "hello"
```

Or invoke through the wrapper:

```bash
moonraker echo "hello"
moonraker pwd
moonraker --list
moonraker --help
```

## Project layout

```
moonraker/
├── src/
│   ├── main.lua          entry point
│   ├── cli.lua           dispatcher (multi-call + wrapper modes)
│   ├── registry.lua      applet table
│   ├── common.lua        shared helpers (err, err_path, IO)
│   ├── version.lua       version constant
│   ├── usage.lua         help text
│   ├── applets/          one file per applet
│   ├── vendor/           pure-Lua dependencies
│   └── cdeps/            vendored C source (zlib, OpenSSL, sockets, LPeg)
├── spec/                 busted tests, mirrors src/ layout
├── docs/                 architecture and contributor docs
├── build.lua             luastatic-based build orchestration
├── Makefile              developer entry points
└── .github/workflows/    CI (Linux, Windows, macOS)
```

See [docs/architecture.md](docs/architecture.md) for design notes.

## Development

```bash
make test                # run busted suite
make lint                # luacheck
make fmt                 # stylua
make build               # full binary via luastatic
make clean               # remove build artifacts
```

Each applet is a self-contained module exporting `name`, `help`, `aliases`, and `main(argv) -> integer`. See [docs/architecture.md](docs/architecture.md#adding-an-applet) for the recipe.

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Scaffolding + dispatcher + 4 applets (`true`, `false`, `echo`, `pwd`) | In progress |
| 1 | Trivial applets (22 total) | Pending |
| 2 | Text utilities, regex via LPeg | Pending |
| 3 | `sed` | Pending |
| 4 | Filesystem (`ls`, `find`, `stat`, …) | Pending |
| 5 | Encoding & hashing | Pending |
| 6 | Archives (`gzip`, `tar`, `zip`) | Pending |
| 7 | Network (`http`, `dig`, `nc`) | Pending |
| 8 | `awk` and `jq` | Pending |
| 9 | Misc (`date`, `env`, `xargs`, …) | Pending |
| 10 | Test parity, build presets, polish | Pending |

## License

[MIT](LICENSE). Behavior and applet semantics derive from [Mainsail](https://github.com/Real-Fruit-Snacks/Mainsail) (also MIT) — see [NOTICE](NOTICE).
