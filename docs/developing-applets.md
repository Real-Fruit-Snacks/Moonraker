# Developing applets

How to add or modify a Moonraker applet. Read [`docs/architecture.md`](architecture.md) first if you haven't.

## The applet contract

An applet is a single Lua module under `src/applets/<name>.lua` that returns a table:

```lua
return {
  name = "<applet-name>",        -- canonical name; matches the file basename
  aliases = { "alt1", "alt2" },  -- optional alternative invocation names
  help = "<one-line summary>",   -- shown by `moonraker --list`
  main = function(argv)          -- entry point; returns an integer exit code
    -- ...
    return 0
  end,
}
```

The dispatcher passes a Lua table for `argv` where `argv[0]` is the canonical applet name (after symlink resolution and `.exe`/`.lua` stripping) and `argv[1..n]` are the user's positional arguments. `main` returns an integer exit code: `0` for success, `1` for runtime error, `2` for usage error.

## Boilerplate

Most applets follow this skeleton:

```lua
-- foo: one-line summary of what foo does.

local common = require("common")

local NAME = "foo"

local function main(argv)
  local args = {}
  for i = 1, #argv do args[i] = argv[i] end

  -- Parse flags.
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--" then i = i + 1; break end
    if a == "-h" or a == "--help" then
      -- Long-form help is registered in src/usage.lua and rendered by
      -- the dispatcher. Per-applet -h handling is rare; only set it
      -- when -h means something else (e.g. df -h).
      return 0
    elseif a == "-v" or a == "--verbose" then
      verbose = true; i = i + 1
    elseif a:sub(1, 1) == "-" and a ~= "-" and #a > 1 then
      common.err(NAME, "unknown option: " .. a)
      return 2
    else
      break
    end
  end

  -- Positional args.
  local files = {}
  for j = i, #args do files[#files + 1] = args[j] end

  -- Do the work. Use io.stdout / io.stderr for output. Return 0 on
  -- success, 1 for runtime errors, 2 for usage errors.
  return 0
end

return {
  name = NAME,
  aliases = {},
  help = "one-line summary of what foo does",
  main = main,
}
```

## Shared helpers

Reach for [`src/common.lua`](../src/common.lua) before adding ad-hoc utilities to your applet:

| Helper | Purpose |
|--------|---------|
| `common.err(applet, msg)` | Write `applet: msg\n` to stderr. |
| `common.err_path(applet, path, errmsg)` | Write `applet: path: errmsg\n` to stderr. |
| `common.open_input(path)` | Open a file for reading; `"-"` returns `io.stdin`. |
| `common.open_output(path)` | Same, for writing. |
| `common.iter_lines_keep_nl(fh)` | Streaming line iterator that preserves trailing newlines. Critical for `head`-style applets that must terminate on a closed downstream pipe. |
| `common.path_sep()` / `is_windows()` | Platform detection. |
| `common.basename(path)` / `dirname(path)` / `path_join(a, b)` | Path manipulation. |
| `common.walk(root, callback, opts)` | Recursive directory walk. Set `opts.bottom_up = true` for post-order. |
| `common.fnmatch(pattern, name)` | Glob (`*`, `?`, `[abc]`) → boolean match. |
| `common.try_lfs()` | Lazily load LuaFileSystem; returns `nil` if unavailable. |
| `common.parse_int(s)` | Strict integer parse — rejects floats, hex, and leading whitespace. |

## Argument parsing

Applets parse `argv` by hand. There is no shared argparse helper. This keeps each applet's flag handling explicit and avoids subtle POSIX-vs-GNU corner cases that argparse libraries tend to mishandle.

A couple of conventions:

- `--` ends option processing; everything after it is positional.
- `-` (a single dash) is a positional argument meaning "stdin" or "stdout".
- Long options use `--name` or `--name=value`; the latter is split on `=`.
- Short options can be bundled (`-la` ≡ `-l -a`) when they don't take values. Bundles that include a value-taking flag (e.g. `-fdir/path`) work the same way as POSIX `tar`/`grep`/etc.

## I/O

Write to `io.stdout` and `io.stderr` directly. The test helper ([`spec/helpers.lua`](../spec/helpers.lua)) replaces them with in-memory buffers during specs, so you don't need to plumb handles through your code.

For binary data that has to round-trip cleanly through pipes (e.g. `gzip`, `dd`), open files with `"rb"` / `"wb"` modes. On Windows, `io.stdin` / `io.stdout` are in text mode by default, which mangles `\n` → `\r\n`. Applets that must be byte-exact through stdio are responsible for switching modes themselves; the rest of the codebase assumes text mode is fine.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success. |
| `1` | Runtime error (file not found, network failure, decompression error, etc.). |
| `2` | Usage error (unknown flag, missing required argument, etc.). |
| Other | Reserved for applet-specific semantics (e.g. `cmp` returns 1 for "differ", 2 for "trouble"; `grep` returns 1 for "no match"). Document any non-standard codes in the applet's usage block. |

## Testing

Every applet ships a spec under `spec/applets/<name>_spec.lua`. Use the helper:

```lua
local helpers = require("helpers")

describe("foo applet", function()
  before_each(function() helpers.load_applets() end)

  it("does the basic thing", function()
    local rc, out, err = helpers.invoke_multicall("foo", "arg1", "arg2")
    assert.equal(0, rc)
    assert.equal("expected output\n", out)
  end)

  it("rejects unknown options", function()
    local rc = helpers.invoke_multicall("foo", "--bogus")
    assert.equal(2, rc)
  end)

  it("reads stdin when given no files", function()
    local _, out = helpers.invoke_with_stdin("foo", "input data\n", "-")
    assert.equal("expected\n", out)
  end)
end)
```

The helper exposes:

- `invoke_multicall(name, ...args)` — runs as if invoked via a symlink named `<name>`.
- `invoke_wrapper(...args)` — runs as `moonraker <args...>`.
- `invoke_with_stdin(name, stdin_text, ...args)` — same as `invoke_multicall` but pre-fills stdin.
- `tmp_file(content)` — creates a temp file; caller cleans up.
- `read_file(path)` — reads a whole file into a string.
- `load_applets()` — re-loads applets into a fresh registry. Call from `before_each` to isolate specs.

## Long-form help

Add a usage block to [`src/usage.lua`](../src/usage.lua), keyed by your applet's name:

```lua
foo = [[usage: foo [OPTIONS] [FILE ...]

One-paragraph summary of what foo does.
  -v, --verbose    explain what is being done
  -n, --dry-run    print actions without performing them
]],
```

The dispatcher prints the one-line summary from your applet's `help` field, then the usage block, when the user passes `--help`.

If your usage block contains literal `]]` (e.g. inside a regex example), use leveled brackets: `[==[...]==]`.

## Registering the applet

After you create `src/applets/<name>.lua`, run:

```bash
make regen
# or: lua build.lua --regen-only
```

This rewrites `src/applets/init.lua` with an alphabetized `require` list of every `.lua` file in `src/applets/` (skipping `init.lua` itself).

## Verifying

```bash
make lint           # luacheck
make fmt-check      # stylua
make test           # busted (your new spec runs alongside the rest)
make build          # full binary
./dist/moonraker foo --help                  # check usage rendering
./dist/moonraker foo arg1 arg2               # smoke test
```

## Style

- 2-space indent, no tabs (enforced by stylua).
- Local variables only at the top of a function unless you need a tighter scope.
- One applet per file. Shared logic between two or more applets goes into `src/common.lua` (general) or its own top-level module under `src/` (large enough — see `src/regex.lua` and `src/hashing.lua`).
- Avoid wide try/catch via `pcall` unless you're catching a specific failure; let unexpected errors propagate to the dispatcher.
- Comments answer "why," not "what." Identifier names answer "what."

## Lua 5.1 / 5.4 portability

The codebase compiles and runs on both Lua 5.1 and 5.4. Avoid 5.2+-only features:

- No `goto` / labels (5.2+). Use early-return helper functions instead.
- No `//` integer division (5.3+). Use `math.floor(a / b)`.
- No `*L` read format (5.2+). Use `common.iter_lines_keep_nl()` for line-by-line reads that preserve newlines.
- No `<close>` / `<const>` attributes (5.4).
- No `string.pack` / `string.unpack` (5.3+). Hand-roll byte packing for binary formats (see `src/regex.lua`'s `u16le` for an example).
- `math.atan2(y, x)` was unified into `math.atan(y, x)` in 5.3. If you need 2-arg atan, do `(rawget(math, "atan2") or math.atan)(y, x)`.
- `unpack` is a global in 5.1 and `table.unpack` in 5.2+. Locally alias: `local _unpack = table.unpack or unpack`.
