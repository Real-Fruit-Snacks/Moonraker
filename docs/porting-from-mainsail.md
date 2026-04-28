# Porting an applet from Mainsail to Moonraker

Moonraker tracks [Mainsail](https://github.com/Real-Fruit-Snacks/Mainsail) for applet inventory and behavior. Each port should be a faithful translation: same flags, same exit codes, same edge cases. This guide walks through the mechanical and judgment-call parts of doing so.

## Before you start

1. Pick an applet from the [roadmap](../README.md#roadmap). Confirm the phase it lives in — earlier phases may unblock it.
2. Read the upstream Python under `reference/mainsail/applets/<name>.py`.
3. Read the upstream tests under `reference/tests/test_applets.py` (search for the applet name; tests are grouped by applet).
4. Note any `common.py` helpers it depends on — those may need a Lua counterpart in [`src/common.lua`](../src/common.lua).

## Translation rules

| Python idiom | Lua equivalent |
|---|---|
| `sys.argv` | `argv` parameter (Lua-style: `argv[0]` = applet name, `argv[1..n]` = args) |
| `sys.stdout.write(s)` | `io.stdout:write(s)` |
| `sys.stdout.buffer.write(b)` | `io.stdout:write(b)` (bytes — set binary mode if needed) |
| `sys.stderr.write(s)` | `io.stderr:write(s)` |
| `print(...)` | `io.stdout:write(..., "\n")` (use `io.stdout:write`, not `print`, to avoid the auto-tab-separator) |
| `sys.exit(rc)` | `return rc` from `main` |
| `os.path.basename(p)` | `common.basename(p)` |
| `os.getcwd()` | `lfs.currentdir()` (require `lfs` via pcall, fall back per `pwd.lua`) |
| `re.match`, `re.sub` | LPeg-based regex (Phase 2+) — for now, Lua patterns where the spec is forgiving |
| `pathlib.Path.read_bytes()` | `io.open(p, "rb"):read("*a")` |
| `enumerate(xs)` | `for i, v in ipairs(xs)` |
| `for x in xs` | `for _, x in ipairs(xs)` |
| `dict[k] = v`, `dict.get(k)` | `t[k] = v`, `t[k]` (returns nil if absent) |
| `''.join(parts)` | `table.concat(parts)` |
| `s.startswith("-")` | `s:sub(1, 1) == "-"` |
| `s.endswith(".lua")` | `s:sub(-4) == ".lua"` |
| `len(s)` (string) | `#s` |
| `len(t)` (list) | `#t` (note: only valid for arrays, not maps) |

## Exit codes & errors

- `0` — success.
- `1` — applet-specific failure (a file couldn't be read, a check failed).
- `2` — usage error (invalid flag, missing argument).

For error messages, use `common.err(applet, msg)` and `common.err_path(applet, path, errmsg)` — they format identically to Mainsail's `err()` and `err_path()`.

## Argument parsing

Mainsail applets parse argv by hand. Moonraker does the same, deliberately — there's no shared argparse helper. This keeps each applet's flag handling explicit and matches POSIX corner cases that argparse libraries tend to mishandle.

If you find yourself wanting a helper, check whether [`src/common.lua`](../src/common.lua) already has it. If not, and the helper is broadly useful (used by 3+ applets), add it there with the same name and signature as Mainsail's `common.py` helper.

## Tests

Mirror the structure of upstream tests. For applet `<name>`:

- Find the `class Test<Name>` (or named test functions) in [`reference/tests/test_applets.py`](../reference/tests/test_applets.py).
- Translate each case to a `it("<description>", function() ... end)` in [`spec/applets/<name>_spec.lua`](../spec/applets/).
- Use the `invoke_multicall` helper for symlink-mode tests and `invoke_wrapper` when the test specifically exercises the wrapper.

Aim for *behavioral* equivalence: same `(rc, stdout, stderr)` for the same input. If Mainsail uses a fixture file, recreate the fixture in the spec via `io.open(...):write(...)` and a `tmp_path` (which busted provides via `setup`/`teardown`).

## When to diverge

Diverge from Mainsail only when:

1. **Mainsail has a documented bug.** Note it in the applet header comment and link the upstream issue.
2. **Lua's stdlib forces a different approach.** For example, Python's `re` is full PCRE; Lua patterns are weaker. Document the gap and either pull in LPeg (Phase 2+) or restrict the supported flag set.
3. **Cross-platform behavior is genuinely better.** If Mainsail does something brittle on Windows that we can do cleanly with `package.config`, document it in the applet and the changelog.

In all three cases, add a comment at the top of the applet module explaining the divergence and link to the relevant Mainsail file/test for future reference.

## Cross-platform gotchas

- **Path separators.** Use `common.path_sep()`, not a hardcoded `/`.
- **Newlines.** Lua's `io.stdout` is text-mode by default on Windows. Binary applets need `io.stdout:setvbuf("no")` plus a binary-mode shim (Phase 6).
- **Environment variables.** `os.getenv` returns `nil` when missing; never assume a string.
- **`os.execute` exit codes.** On Lua 5.4, returns `(true|nil, "exit"|"signal", code)`. Earlier code may pattern-match differently.
