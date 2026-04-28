# Changelog

All notable changes to Moonraker are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial scaffolding: dispatcher, registry, shared helpers.
- **Phase 0 applets** (4): `true`, `false`, `echo`, `pwd`.
- **Phase 1 applets** (18): `yes`, `whoami`, `basename`, `dirname`, `sleep`, `hostname`, `cat`, `tac`, `rev`, `head`, `tail`, `wc`, `nl`, `tee`, `mkdir`, `rm`, `mv`, `touch`.
- Aliases: `mkdir → md`, `rm → del, erase`, `mv → move, ren, rename`, `echo → type` (already shipped).
- Build pipeline via vendored `luastatic` (Windows-portability patch).
- CI matrix: Linux, Windows, macOS on Lua 5.4.
- Test suite using `busted` with stdio-capture helper, in-memory stdin, temp-file helpers.
- Static analysis via `luacheck`; formatting via `stylua`.
- Auto-detection of Lua include / static library paths via `luarocks config`.
- Documentation: architecture guide, Mainsail-porting guide, contributing guide.

### Phase 2 additions
- **Phase 2 applets** (14): `grep`, `tr`, `cut`, `paste`, `sort`, `uniq`, `comm`, `cmp`, `fmt`, `fold`, `column`, `expand`, `unexpand`, `split`.
- Total: **36 applets in the binary, ~347 KB on Linux x86_64.**
- 181/181 tests pass.

### Phase 2.5 additions — LPeg + regex infrastructure
- **Vendored LPeg 1.1.0** (`src/cdeps/lpeg/`, MIT) — Roberto Ierusalimschy's PEG-based pattern engine. 6 `.c` files (lpcap, lpcode, lpcset, lpprint, lptree, lpvm) compiled and linked into the binary; `luaopen_lpeg` is exported as a `T` symbol. `require("lpeg")` works at runtime.
- **Vendored `re.lua`** (`src/vendor/re.lua`) — LPeg's regex-style frontend, unmodified. `require("vendor.re")` returns the compiler.
- **Build pipeline extended**: `build.lua` now auto-discovers any subdirectory of `src/cdeps/` and compiles every `.c` file inside via `gcc -c -O2 -I<lua-include> -I<lib-dir>`, then passes `.o` files to luastatic. Pure-Lua deps in `src/vendor/*.lua` are bundled into the binary alongside the applets.
- Binary size: 401 KB (up from 347 KB; ~54 KB for LPeg).
- 186/186 tests pass (5 new LPeg tests).
- No applet refactors yet — `grep` still uses Lua patterns. LPeg integration into `sed` (Phase 3) and `awk` (Phase 8) lands when those phases ship.

### Phase 4 additions — Filesystem
- **Phase 4 applets** (11): `ls`, `find`, `stat`, `chmod`, `ln`, `du`, `df`, `mktemp`, `truncate`, `dd`, `cp`.
- Total: **47 applets in the binary, ~470 KB on Linux x86_64.**
- 228/228 tests pass (42 new + 186 from earlier phases).
- New `common.lua` helpers: `dirname`, `path_join`, `walk` (recursive tree traversal), `fnmatch` (glob).
- `find` ships with a full expression-tree evaluator: `-name`, `-iname`, `-path`, `-ipath`, `-type`, `-size`, `-mtime/-mmin/-atime/-amin/-ctime/-cmin`, `-newer`, `-empty`, `-true`, `-print`, `-print0`, `-delete`, `-prune`, `-exec` (both `;` and `+`), boolean `-a`/`-o`/`-not` and parens, plus global `-mindepth`/`-maxdepth`.
- `dd` supports POSIX `key=value` operands: `if`, `of`, `bs`, `ibs`, `obs`, `count`, `skip`, `seek`, `conv` (notrunc/noerror/sync/lcase/ucase/swab/excl/nocreat/fsync/fdatasync), `status`.
- `df` shells out to system `df -P -k` (Lua/lfs have no native disk-usage API). Re-formats output for consistent presentation.
- `chmod` shells out to system `chmod` (lfs lacks chmod). On Windows, mode bits are silently ignored — documented limitation.
- `truncate` uses system `truncate -s` on POSIX; Windows fallback rewrites the file with zero-fill.
- `cp -p` (preserve metadata) is a no-op since lfs doesn't expose chmod/utime; documented.
- `ln -r` (relative target) is parsed but doesn't currently rewrite the target (needs absolute path resolution that lfs alone doesn't expose). TODO(phase4+).

### Phase 5 additions — Encoding & hashing
- **Phase 5 applets** (7): `base64`, `od`, `hexdump`, `md5sum`, `sha1sum`, `sha256sum`, `sha512sum`.
- Total: **54 applets in the binary, ~766 KB on Linux x86_64** (up from 470 KB; +296 KB mostly for the vendored hash library).
- 253/253 tests pass (25 new + 228 from earlier phases).
- **Vendored `pure_lua_SHA` v12** (`src/vendor/sha2.lua`, MIT) — Egor Skriptunoff's pure-Lua hash library. Provides MD5, SHA-1, SHA-2 family, plus SHA-3, HMAC, BLAKE2/3 (unused by us). Adapts internally to Lua 5.1/5.2/5.3/5.4/LuaJIT.
- All four `*sum` applets share `src/hashing.lua` (parallels Mainsail's `hashsum_main`): both compute mode and `-c` (check) mode work, plus `--tag` (BSD format), `-z` (NUL terminator), `--quiet`/`--status`/`--warn`/`--strict`.
- Test vectors verified against the hash specs: MD5/SHA-1/SHA-256/SHA-512 of `"abc"` all produce the expected RFC values.
- `base64`, `od`, `hexdump` are pure Lua — no external deps.

### Build pipeline change
- `build.lua` now auto-discovers top-level Lua modules (anything in `src/*.lua` except `main.lua`, which must come first). Previously the list was hardcoded; adding `hashing.lua` to it would have required a build edit. Now any new shared module under `src/` is bundled automatically.

### Phase 9 additions — Misc utilities
- **Phase 9 applets** (14): `env`, `id`, `groups`, `uname`, `uuidgen`, `realpath`, `which`, `seq`, `date`, `printf`, `xargs`, `getopt`, `timeout`, `install-aliases`.
- Total: **68 applets in the binary, ~823 KB on Linux x86_64** (up from 766 KB; +57 KB).
- 290/290 tests pass (37 new + 253 from earlier phases).
- Aliases: `which → where`.
- **Skipped from Phase 9** (deferred):
  - `watch` — terminal control + ANSI redraw loop is non-trivial; user can use `while true; do clear; cmd; sleep 2; done` until we revisit
  - `completions` — shell completion script generation; no high demand yet
  - `update` — self-update from GitHub releases; we don't ship releases yet
- **`uuidgen`**: only random (v4) UUIDs supported in this build. Time/MD5/SHA1 namespace variants would need careful HMAC + clock-sequence handling — deferred until needed.
- **`env`, `id`, `groups`, `uname`, `which`, `realpath`, `timeout`**: shell out to system equivalents where Lua's stdlib lacks the primitive (no execve, no pwd/grp, no readlink, no SIGTERM). Cross-platform: POSIX uses native binaries, Windows is best-effort or surfaces a "not supported" message.
- **`xargs`** unit tests: subprocesses spawned by `xargs` write to the parent's real terminal, not to our in-memory `io.stdout` buffer. Spec covers exit codes only; full output behaviour is verified via binary smoke tests.
- **`install-aliases`** locates the running binary via `/proc/self/exe` (Linux) or `which moonraker` (fallback). Creates symlinks per applet via `lfs.link`, falls back to copying.

### Phase 9 leftovers — `watch`, `completions`, `update`
- **3 applets** previously deferred from Phase 9: `watch`, `completions`, `update`.
- Total: **74 applets in the binary, ~978 KB on Linux x86_64** (no new C deps).
- 313/313 tests pass (13 new + 300 from earlier phases).
- `watch` runs a command on a fixed interval, redrawing with ANSI clear (`\x1b[2J\x1b[H`). Lua's stdlib has no monotonic clock or sub-second sleep, so the inter-cycle pause shells out to `sleep` (POSIX) or `Start-Sleep` (Windows). `--max-cycles N` test hook bounds the otherwise-infinite loop.
- `completions` emits ready-to-use shell completion scripts for **bash**, **zsh**, **fish**, and **powershell**. Each script calls back into the running `moonraker --list` at completion time, so it stays accurate as new applets ship.
- `update` self-updates from the latest GitHub release. Shells out to `curl` or `wget` (HTTPS without bundling a TLS stack). Smoke-tests the new binary with `--version`, then atomic-swaps; the previous binary stays alongside as `<binary>.old` for one-step revert.
- **`main.lua` enhancement**: stashes `arg[0]` as `_G._MOONRAKER_BINARY` before the dispatcher rewrites argv, so `update` can locate the running binary regardless of whether it was invoked as a symlink or by name.

### Phase 8a — `awk`
- **1 new applet**: `awk` — full lexer + recursive-descent parser + tree-walking interpreter (~1170 lines).
- Total: **81 applets in the binary, ~1.3 MB on Linux x86_64** (no new C deps).
- 401/401 tests pass + 1 pending. 32 new awk specs covering each major feature.
- **Supported subset**: BEGIN/END, /regex/ patterns, expression patterns, range patterns; print, printf with all standard conversions (%d/%i/%o/%x/%X/%f/%e/%E/%g/%G/%s/%c); control flow (if/else, while, do/while, for(;;), for (k in a), break/continue/next/exit); associative arrays + `delete` + `k in a`; field access ($0..$NF, $(expr)); built-in vars (NR/NF/FNR/FILENAME/FS/OFS/RS/ORS/SUBSEP/OFMT); arithmetic + string concat (juxtaposition) + comparison + `~`/`!~` matching + `&&`/`||`/`!` + ternary + all compound assignments; built-ins (length, substr, index, split, sub, gsub, match, toupper, tolower, sprintf, int, sqrt, log, exp, sin, cos, atan2, rand, srand, system).
- **Not implemented (v1)**: user-defined functions, `getline`, full multidimensional arrays via SUBSEP (the parser handles `a[k1, k2]` via internal CONCAT_SUBSEP, but `(k1, k2) in a` doesn't fully round-trip).
- **Smoke verified**: accumulator pipelines (`{ s += $2 } END { print s }`), printf formatting, BEGIN-only programs, custom field separators (`-F:`), field iteration via NF, range patterns, regex matching, array iteration, and exit codes.
- **Lua 5.1 portability gotcha**: my first version used `goto continue_files`/`::continue_files::` for early-exit in the input loop. `goto` is 5.2+. Replaced with an inner function early-return.

### Phase 7.7 — Regex layer + `sed`
- **1 new applet**: `sed`. **1 new shared module**: `src/regex.lua` (POSIX ERE-on-LPeg compiler).
- Total: **80 applets in the binary, ~1.2 MB on Linux x86_64** (no new C deps; ~14 KB of Lua).
- 369/369 tests pass + 1 pending (the bz2 one). 16 new regex specs + 16 new sed specs.
- **`src/regex.lua`** — recursive-descent ERE compiler. Emits LPeg patterns. Supports anchors (`^`, `$`), char classes (`[abc]`, `[^abc]`, `[a-z]`, `[[:alpha:]]`, `[[:digit:]]`, etc.), quantifiers (`?`, `*`, `+`, `{n}`, `{n,}`, `{n,m}`), alternation (`|`), grouping (`(...)`, `(?:...)` for non-capturing), escapes (`\d`, `\D`, `\s`, `\S`, `\w`, `\W`, `\b`, `\B`, plus `\n`, `\t`, `\r`, `\\`), and dot. Public API: `compile(pattern, opts) → matcher`, plus one-shot `find`/`gsub`. Matcher exposes `find` / `match` / `gsub` mirroring the `string` library shape. Replacement strings handle `\0`/`&` (whole match), `\1..\9` (captures), `\n`/`\t` escapes, and `\\` / `\&` as literals.
- **`sed`** — direct port of mainsail's sed.py. Workhorse subset: addresses (line number, `$`, `/regex/`, ranges, `!` negation); commands `s///` (with flags `g`, `i`, `p`, `N`), `d`, `p`, `q`, `=`, `y/src/dst/`; options `-n` (quiet), `-E` (ERE), `-i` (in-place), `-e SCRIPT` (repeatable), `-f FILE`. BRE is the default per POSIX; an internal BRE→ERE translator swaps `\(`/`(`, `\?`/`?`, etc. so the regex layer always sees ERE.
- Verified end-to-end: substitution with backrefs, ERE alternation, BRE escape swapping, `&` whole-match expansion, address ranges, `!` negation, `y` transliteration, `=` line-number printing, multi-`-e` script composition.
- **xz / `tar -J` deferred** — xz-utils is a 1.7 MB autoconf-heavy build (~84 .c files needing platform feature detection); ROI doesn't justify the vendoring effort. Most users with `.tar.xz` archives have system `tar` available. Will revisit if there's user demand.
- **Bug caught**: my first replacement-string handling round used `\0AMP\0` as a placeholder during `gsub` chaining. Lua patterns C-string-terminate at `\0`, so the placeholder gsub silently turned into a "match at every position" gsub, injecting `&` between every character. Replaced the gsub-cascade with a single linear pass.

### Phase 7.5 — `zip` / `unzip` + `tar -j` (bzip2)
- **2 new applets**: `zip`, `unzip`. Plus `tar -j` is now functional (was previously rejected).
- Total: **79 applets in the binary, ~1.2 MB on Linux x86_64** (up from 1.1 MB; +90 KB for vendored bzip2).
- 337/337 tests pass + 1 pending (the pending one needs the `bzip2` luarock outside the binary; the binary itself works).
- **`zip`** — pure-Lua PKZip 2.0 writer on top of the existing `zlib` C dep (raw DEFLATE via `windowBits = -MAX_WBITS`). Supports `-r` (recursive walk), `-j` (junk paths), `-g` (append/grow an existing archive), `-d` (delete entries by name), and `-0..-9` (compression level). When deflate doesn't actually shrink the payload, we silently fall back to `STORE` so the archive isn't bloated by tiny files.
- **`unzip`** — reads the central directory, decompresses each entry (`STORE` or `DEFLATE`), writes to disk. Supports `-l` (list), `-p` (pipe to stdout), `-d DIR` (extract destination), `-o`/`-n` (overwrite policy), `-q`/`-qq` (quiet). Refuses path-escape entries (`../...`, absolute, drive-letter) before extraction.
- Cross-tool verified: moonraker zip → system unzip works; system zip → moonraker unzip works; moonraker round-trip works for both `STORE` and `DEFLATE` payloads.
- **`tar -j` / `--bzip2`**: now creates and reads `.tar.bz2` / `.tbz2` / `.tbz` archives. Auto-detects compression from extension when reading. Cross-tool verified against system `tar -tjf`.
- **Vendored libbzip2 1.0.8** (`src/cdeps/bzip2/`, BSD-style, Julian Seward) — only the library sources (blocksort, bzlib, compress, crctable, decompress, huffman, randtable). The CLI tools (`bzip2`, `bunzip2`, `bzip2recover`) are intentionally not vendored.
- **`src/cdeps/bzip2/lua_bzip2.c`** — moonraker's own minimal Lua binding (~150 lines, MIT). One-shot `bzip2.compress(data, level)` / `bzip2.decompress(data)` API. tar buffers content in memory before compressing — typical archives are well under available RAM, and going one-shot keeps the binding small.
- **EOCD scan bug fixed**: my first attempt at `unzip` looped from `#tail - 22` instead of `#tail - 3`, missing the EOCD signature when the archive had no zip-comment trailer. Off-by-one; tests caught it immediately.
- **Tar refactor**: replaced the `gzipped` boolean with a `compression = nil | "gz" | "bz2"` enum threading through `op_create` / `op_extract` / `op_list`. The bzip2 binding is loaded lazily so the unit-test environment (where lua-bzip2 isn't installed as a luarock) can still require the `tar` applet.

### Phase 7 additions — Network (`http`, `nc`, `dig`)
- **3 applets**: `http`, `nc`, `dig`.
- Total: **77 applets in the binary, ~1.1 MB on Linux x86_64** (up from 978 KB; +143 KB for vendored luasocket).
- 329/329 tests pass (16 new + 313 from earlier phases).
- **Vendored LuaSocket 3.1.0** (`src/cdeps/luasocket/`, MIT, Diego Nehab) — POSIX TCP/UDP/select C sources only (auxiliar, buffer, compat, except, inet, io, luasocket, options, select, tcp, timeout, udp, usocket). The mime, ftp, http, smtp, and unix-socket modules are intentionally not vendored. The top-level `socket.lua` helper sits at `src/socket.lua` so `require("socket")` resolves cleanly under luastatic's path-based module-name scheme.
- `dig` is a pure Lua DNS resolver over UDP — A, AAAA, MX, CNAME, TXT, NS, SOA, PTR, ANY records. `+short`, `-x ADDR` (reverse lookup), `@server` overrides, `--timeout`. Reads `/etc/resolv.conf` for default servers; falls back to 1.1.1.1 / 8.8.8.8.
- `nc` is a TCP-only minimal netcat: client (connect-and-pump), listener (accept one connection), and `-z` port scanner (single port or range). UDP (`-u`) is parsed but rejected with "not supported". The pump is "send-stdin then drain socket" — Lua has no portable async stdin, so truly bidirectional REPL-style sessions are not supported (documented). Half-close (`shutdown("send")`) was tried and removed: some middleboxes (e.g. cloudflare) treat it as an abort.
- `http` is a curl-style client that shells out to `curl` (preferred) or `wget`. HTTPS just works because the system tool handles TLS. Supports `-X METHOD`, `-H HEADER`, `-d BODY` (with `@file`), `--json`, `-i`/`-I`/`-L`/`--no-location`, `-o FILE`, `-s`, `-f`, `-A USER-AGENT`, `--timeout`.
- Verified end-to-end: `dig +short example.com` returns A records; `dig MX example.com` decodes the null-MX correctly; `nc -z -w 1 127.0.0.1 22` reports closed ports with rc=1; `nc -l -p PORT` round-trips data; `printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 5 example.com 80` reads the response; `http -I -s https://example.com` returns 200 headers; `http --json '{"x":1}' https://httpbin.org/post` echoes the body back.
- **Windows note**: luasocket needs `-lws2_32` and `wsocket.c` instead of `usocket.c`. The current build pipeline targets POSIX; Windows-native build lands alongside the Phase 10 CI matrix work.

### Phase 6 additions — Archives (gzip family)
- **Phase 6 applets** (3): `gzip`, `gunzip`, `tar` (uncompressed and gzip-compressed).
- Total: **71 applets in the binary, ~954 KB on Linux x86_64** (up from 823 KB; +131 KB for zlib + lua_zlib).
- 300/300 tests pass (10 new + 290 from earlier phases).
- **Vendored zlib 1.3.1** (`src/cdeps/zlib/`, zlib license) — compiled unmodified.
- **Vendored lua-zlib 1.4-0** (`src/cdeps/zlib/lua_zlib.c`, MIT, Brian Maher) — Lua bindings to zlib.
- Build pipeline gained per-cdep `cflags` files (`src/cdeps/<lib>/cflags`) for compile-time defines. zlib's binding needs `-DLZLIB_COMPAT` to expose `MAXIMUM_WINDOWBITS` / `GZIP_WINDOWBITS` constants, which sit behind `#ifdef LZLIB_COMPAT` in lua_zlib.c.
- `gzip`/`gunzip` use streaming deflate/inflate with `windowBits = MAXIMUM_WINDOWBITS + GZIP_WINDOWBITS` (= 31) for the gzip framing.
- `tar` implements POSIX ustar reading/writing in pure Lua. Auto-detects gzip from `.tar.gz` / `.tgz` extensions on read; pipes through zlib when `-z` is given.
- **Skipped from Phase 6** (deferred to a follow-up):
  - `tar -j` (bz2), `tar -J` (xz) — accepted at the parser level but rejected with "not supported in this build". Adding them needs additional vendored libs.
  - `zip`, `unzip` — separate ZIP archive format. Not used by the gzip workhorse pipeline that covers most real distribution use; will land alongside any larger archive overhaul.
  - Symlinks inside tars are skipped (lfs has no `readlink`; revisit when we have it).

### Notes
- `tail -f` follows appended data via a polling loop; rotation detection is best-effort and depends on LuaFileSystem inode info (unreliable on Windows).
- `touch` precise timestamp setting depends on `lfs.touch`; on systems where it's unavailable the timestamp falls back to "now".
- `yes` exposes a private `_module.max_iter` test hook to bound the otherwise-infinite write loop in unit tests.
- **`grep` regex engine**: Phase 2 uses Lua's built-in string patterns rather than POSIX BRE/ERE. Differences: no alternation (`|`), no backreferences, character classes use `%a`/`%d`/`%s` instead of `[a-z]` etc. (bracket expressions still work). `-F` (fixed string) and `-E` flags are accepted. **TODO(phase 2.5)**: vendor LPeg via `cdeps/` for full POSIX regex parity.
- `grep` group separator (`--`) is gated on `-A`/`-B`/`-C` use, matching GNU grep rather than Mainsail (which emits `--` between any non-adjacent matches).
- `paste` reads each input file fully into memory (Lua 5.1 stdio doesn't expose a uniform readline-or-nil idiom across pipes and files). Acceptable for typical inputs.

[Unreleased]: https://github.com/Real-Fruit-Snacks/Moonraker/commits/main
