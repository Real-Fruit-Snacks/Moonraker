<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/Moonraker/main/docs/assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/Moonraker/main/docs/assets/logo-light.svg">
  <img alt="Moonraker" src="https://raw.githubusercontent.com/Real-Fruit-Snacks/Moonraker/main/docs/assets/logo-dark.svg" width="100%">
</picture>

> [!IMPORTANT]
> **A BusyBox-style multi-call binary in Lua** — 81 Unix utilities, one ~1.2 MB statically-linked executable, Lua 5.1 / 5.4 portable. Linux + macOS binaries published with each release.

> *The Lua sibling in the sail-themed family — interpreter, scripts, and every C dependency embedded into a single binary via luastatic.*

---

## §1 / Premise

Lua is the obvious language for a multi-call shell toolkit: small, fast, embeddable, and the standard library composes well with `io.read`/`io.write` pipelines. The historic blocker was distribution — Lua scripts need an interpreter, and "install Lua first" defeats the point of a single-binary tool.

[`luastatic`](https://github.com/ers35/luastatic) solves that by linking the Lua interpreter, every required C extension, and your scripts into one self-contained executable. Moonraker ships **81 applets**, **6 vendored C dependencies**, and the full Lua VM in **~1.2 MB** — no Lua install required, no shared libs, just one binary that runs anywhere with a kernel.

---

## §2 / Specs

| KEY      | VALUE                                                                       |
|----------|-----------------------------------------------------------------------------|
| BINARY   | One **~1.2 MB statically-linked executable** — interpreter + scripts + cdeps |
| APPLETS  | **81 POSIX utilities** — text · files · hashing · archives · network        |
| RUNTIME  | **Embedded Lua VM** via luastatic · Lua 5.1 + 5.4 portable                  |
| VENDORED | LPeg · zlib · bzip2 · LuaSocket · pure_lua_SHA · re.lua — all hermetic     |
| TESTS    | **401 busted specs** + 1 pending bz2 · luacheck-clean                       |
| STACK    | Lua 5.1 / 5.4 · LuaRocks · luastatic · CI on Ubuntu 22.04 + macOS           |

Architecture write-up in [`docs/architecture.md`](docs/architecture.md). Adding an applet covered in [`docs/developing-applets.md`](docs/developing-applets.md).

---

## §3 / Quickstart

```bash
# From a release — no Lua install required
curl -LO https://github.com/Real-Fruit-Snacks/Moonraker/releases/latest/download/moonraker-linux-x64
chmod +x moonraker-linux-x64
./moonraker-linux-x64 --list

# macOS Apple Silicon
curl -LO https://github.com/Real-Fruit-Snacks/Moonraker/releases/latest/download/moonraker-macos-arm64
chmod +x moonraker-macos-arm64

# From source — Lua 5.4 (or 5.1), LuaRocks, C toolchain
luarocks install --local luastatic busted luacheck luafilesystem lua-zlib lpeg luasocket
make build
./dist/moonraker --list
```

```bash
# Wire up multi-call dispatch so each applet runs by its own name
ln -s ./dist/moonraker /usr/local/bin/echo
echo "hello"

# Or use the wrapper
moonraker echo "hello"
moonraker awk --help                       # per-applet help

# Install every applet at once + tab-completion
moonraker install-aliases ~/.local/bin
moonraker completions bash | sudo tee /etc/bash_completion.d/moonraker
```

```bash
# Pick exactly the applets you need
lua build.lua --preset minimal             # 4 applets (true, false, echo, pwd)
lua build.lua --applets ls,cat,grep,sed,awk # hand-picked
lua build.lua                              # full (81 applets)
lua build.lua --regen-only                 # refresh src/applets/init.lua only
```

---

## §4 / Reference

```
APPLET CATEGORIES                                       # 81 total

  FILE OPS      ls cp mv rm mkdir touch find chmod ln stat truncate mktemp dd
  TEXT          cat tac rev grep head tail wc nl sort uniq cut paste tr
                sed awk tee xargs printf echo expand unexpand split cmp comm
                fmt fold column od hexdump base64
  NETWORK       http (curl-style) · dig (UDP DNS) · nc (TCP)
  HASHING       md5sum · sha1sum · sha256sum · sha512sum
  ARCHIVES      tar (gzip + bzip2) · gzip · gunzip · zip · unzip
  FILESYSTEM    du · df
  PATHS         basename · dirname · realpath · pwd · which
  PROCESS       watch · timeout
  SYSTEM        uname hostname whoami id groups date env sleep getopt uuidgen
  CONTROL       true · false · yes · seq
  LIFECYCLE     install-aliases · completions · update

DISPATCH

  moonraker <applet> [args]                # subcommand form
  ln -s moonraker <applet>                 # multi-call: argv[0] basename
                                           # both dispatch identically

VENDORED C/LUA DEPS                                     # all linked statically
  LPeg 1.1.0                               Roberto Ierusalimschy · MIT
  zlib 1.3.1                               Gailly + Adler · with lua-zlib 1.4-0
  bzip2 1.0.8                              Julian Seward · ~150-line Lua binding
  LuaSocket 3.1.0                          Diego Nehab · POSIX TCP/UDP/select
  pure_lua_SHA v12                         Egor Skriptunoff · backs *sum applets
  re.lua + src/regex.lua                   POSIX ERE-on-LPeg for sed/awk

NOTABLE FLAG SUPPORT
  find          expression tree · -exec · -prune · -and/-or · parens
                size/time predicates · -delete
  sed           s/// d p q = y/// addresses ranges negation -i in-place BRE+ERE
  awk           BEGIN/END · /regex/ · expressions · range patterns · printf
                full control flow · associative arrays · 16+ builtins
  tar           create / extract / list · gzip (-z) and bzip2 (-j) filters
  http          GET/POST/PUT/DELETE/HEAD · -H · -d · @file · --json · --fail
                redirect-following · TLS via LuaSocket
  zip / unzip   PKZip 2.0 · stored + deflated entries · path-traversal-safe
  gzip          streaming compress/decompress · level 1–9

BUILD TARGETS                                           # Makefile
  make test                                busted suite (401 specs)
  make lint                                luacheck
  make fmt                                 stylua
  make build                               full binary via luastatic
  make clean                               remove build artifacts
```

**Not yet shipped:** `jq` (planned), `tar -J` (xz; deferred — autoconf-heavy build for low ROI), `awk` user-defined functions and `getline`.

---

## §5 / Authorization

Moonraker is a userland Unix utility binary — no privileged operations, no exploitation surface. Same applet contract as `mainsail`, `topsail`, `jib`, `staysail`, `rill`. Pick `moonraker` when you want a Lua-extensible toolkit you can drop a new module into in 50 lines.

Vendored third-party libraries keep their original licenses; full attribution stack in [`NOTICE`](NOTICE) — LPeg, zlib, bzip2, LuaSocket, pure_lua_SHA, luastatic. Vulnerabilities go through [private security advisories](https://github.com/Real-Fruit-Snacks/Moonraker/security/advisories/new), never public issues.

---

[License: MIT](LICENSE) · [Security policy](SECURITY.md) · [Changelog](CHANGELOG.md) · Part of [Real-Fruit-Snacks](https://github.com/Real-Fruit-Snacks) — building offensive security tools, one wave at a time. Sibling: [mainsail](https://github.com/Real-Fruit-Snacks/mainsail) (Python) · [topsail](https://github.com/Real-Fruit-Snacks/topsail) (Go) · [jib](https://github.com/Real-Fruit-Snacks/jib) (Rust) · [staysail](https://github.com/Real-Fruit-Snacks/Staysail) (Zig) · [rill](https://github.com/Real-Fruit-Snacks/rill) (NASM).
