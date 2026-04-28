-- Long-form usage text per applet, keyed by applet name. Mirrors
-- mainsail/usage.py. Entries are optional; the dispatcher falls back to the
-- one-line summary when no usage block is registered.

return {
  basename = [[usage: basename NAME [SUFFIX]
       basename -a [-s SUFFIX] NAME...

Strip directory components and an optional SUFFIX from NAME(s).
  -a, --multiple        process every NAME
  -s, --suffix=SUFFIX   trim SUFFIX from each NAME (implies -a)
  -z, --zero            terminate output with NUL instead of newline
]],
  cat = [[usage: cat [-nb] [FILE ...]

Concatenate FILE(s) to standard output. With no FILE, or when FILE is `-`,
read from standard input.
  -n     number all output lines
  -b     number non-empty output lines
]],
  dirname = [[usage: dirname [-z] PATH...

Print PATH with the last component removed.
  -z, --zero    terminate output with NUL instead of newline
]],
  echo = [[usage: echo [-neE] [STRING ...]

Display STRING(s) on standard output. Options:
  -n     do not append a trailing newline
  -e     interpret backslash escapes (\n, \t, \\, \a, \b, \f, \r, \v, \0)
  -E     do not interpret backslash escapes (default)
]],
  head = [[usage: head [-n LINES] [-c BYTES] [-NUM] [FILE ...]

Print the first 10 lines of each FILE. With no FILE, read stdin.
  -n NUM    print the first NUM lines (negative skips last NUM)
  -c NUM    print the first NUM bytes
  -NUM      shorthand for `-n NUM`
]],
  hostname = [[usage: hostname [-s | -f]

Print the system hostname.
  -s, --short    short host (everything before the first dot)
  -f, --fqdn     fully-qualified domain name (best effort)
]],
  mkdir = [[usage: mkdir [-pv] [-m MODE] DIR...

Create the DIR(s).
  -p, --parents      no error if existing, create parent directories
  -v, --verbose      print a message for each created directory
  -m, --mode=MODE    set file mode (octal) on created directories
]],
  mv = [[usage: mv [-finuv] SOURCE... DEST

Rename or move SOURCE(s) to DEST.
  -f, --force          do not prompt before overwriting
  -i, --interactive    prompt before overwrite
  -n, --no-clobber     do not overwrite an existing file
  -u, --update         move only when SOURCE is newer than DEST
  -v, --verbose        explain what is being done
]],
  nl = [[usage: nl [OPTIONS] [FILE ...]

Number lines of FILE(s).
  -b, --body-numbering=STYLE   a (all), t (non-empty, default), n (none)
  -w, --number-width=N         use N columns for line numbers (default 6)
  -s, --number-separator=STR   string between number and text (default \t)
  -v, --starting-line-number=N first line number (default 1)
  -i, --line-increment=N       increment between lines (default 1)
]],
  pwd = [[usage: pwd [-LP]

Print the absolute path of the current working directory. Options:
  -L     prefer logical path from PWD environment variable (default)
  -P     resolve symlinks (physical path)
]],
  rev = [[usage: rev [FILE ...]

Reverse each line of FILE(s) characterwise. With no FILE, read stdin.
]],
  rm = [[usage: rm [-rRfvd] FILE...

Remove each FILE.
  -r, -R    remove directories and their contents recursively
  -f        ignore nonexistent files; never prompt
  -v        explain what is being done
  -d        remove empty directories
]],
  sleep = [[usage: sleep DURATION...

Pause for DURATION (default seconds; suffixes: s, m, h, d). Sums multiple
arguments together.
]],
  tac = [[usage: tac [-bsr] [FILE ...]

Concatenate FILE(s) and print in reverse, line-by-line.
  -b, --before          attach the separator before each record
  -s, --separator=SEP   use SEP as the record separator (default newline)
]],
  tail = [[usage: tail [-fF] [-n LINES] [-c BYTES] [-NUM] [FILE ...]

Print the last 10 lines of each FILE.
  -n NUM    last NUM lines
  -c NUM    last NUM bytes
  -f, -F    follow appended data
  -s SECS   poll interval for -f (default 1)
  -NUM      shorthand for `-n NUM`
]],
  tee = [[usage: tee [-ai] [FILE ...]

Copy stdin to stdout and to each FILE.
  -a, --append    append to the given FILEs, do not overwrite
  -i              ignore SIGINT (best-effort; not supported on Windows)
]],
  touch = [==[usage: touch [-acm] [-r REF | -d DATE | -t TIME] FILE...

Update access and modification timestamps. Creates FILE if it doesn't exist.
  -c          do not create files
  -a          change only the access time
  -m          change only the modification time
  -r REF      use timestamps from REF
  -d DATE     parse a date string (ISO 8601)
  -t TIME     POSIX [[CC]YY]MMDDhhmm[.ss]
]==],
  wc = [[usage: wc [-lwcm] [FILE ...]

Print newline, word, and byte counts for each FILE. With no FILE, read stdin.
  -l    print newline counts
  -w    print word counts
  -c    print byte counts
  -m    print character counts
]],
  whoami = [[usage: whoami

Print the effective user name.
]],
  yes = [[usage: yes [STRING...]

Repeatedly output a line with all of STRING(s) (or 'y' if none given).
]],

  -- Phase 4 entries

  chmod = [[usage: chmod [-Rrvcf] MODE FILE...

Change file mode bits. MODE is octal (e.g. 0644) or symbolic (e.g. u+x,go-w).
  -R, -r    apply recursively
  -v        report all changes (verbose)
  -c        report only files whose mode actually changed
  -f        suppress most error messages
On Windows, mode bits are silently ignored (NTFS ACLs differ).
]],

  cp = [[usage: cp [-rRfivnpau] SOURCE... DEST

Copy files and directories.
  -r, -R    copy directories recursively
  -f        force; remove existing target without prompting
  -i        prompt before overwriting an existing target
  -n        no-clobber: never overwrite
  -u        update: copy only if SOURCE is newer
  -v        verbose
  -p        preserve metadata (no-op in Phase 4 — see notes)
  -a        archive mode (recursive)
]],

  dd = [[usage: dd [if=FILE] [of=FILE] [bs=N] [count=N] [skip=N] [seek=N] [conv=...] [status=...]

Convert and copy a file with block-mode I/O. Operands are key=value.
  if=FILE    input file (default stdin)
  of=FILE    output file (default stdout)
  bs=N       block size for both input and output (default 512)
  ibs=N      input block size (overrides bs)
  obs=N      output block size (overrides bs)
  count=N    copy at most N blocks
  skip=N     skip N input blocks
  seek=N     seek N output blocks before writing
  conv=LIST  comma-separated: notrunc, noerror, sync, lcase, ucase, swab,
             excl, nocreat, fsync, fdatasync
  status=    none | noxfer | progress | default
Sizes accept K, M, G, T, P (×1024), k, m, g (×1000), b (×512), w (×2).
]],

  df = [[usage: df [-hkm] [PATH ...]

Report filesystem disk space usage. Defaults to current directory.
  -h    human-readable sizes (K, M, G, ...)
  -k    block size 1K (default)
  -m    block size 1M
]],

  du = [[usage: du [-sahbckm] [--max-depth N] [PATH ...]

Estimate file space usage.
  -s        display only the total for each argument
  -a        show counts for files as well as directories
  -h        human-readable sizes
  -b        report exact bytes (overrides block size)
  -c        produce a grand total at the end
  -k, -m    block size 1K (default) or 1M
  --max-depth N    descend at most N levels (0 = summary)
]],

  find = [[usage: find [PATH ...] [EXPRESSION]

Search for files in a directory hierarchy. Default PATH is `.`.

Predicates: -name GLOB, -iname GLOB, -path GLOB, -ipath GLOB,
            -type {f,d,l}, -size [+-]N[bckwMG],
            -mtime/-mmin/-atime/-amin/-ctime/-cmin [+-]N,
            -newer FILE, -empty, -true
Actions:    -print, -print0, -delete, -prune,
            -exec CMD ... ; (per-file) or -exec CMD ... + (batched)
Operators:  -a / -and (default), -o / -or, -not / !, ( ... )
Globals:    -mindepth N, -maxdepth N (place anywhere; processed first)
]],

  ln = [[usage: ln [-sfvrT] TARGET... LINK_NAME | DIR

Create hard or symbolic links.
  -s    create symbolic links (default: hard)
  -f    force; remove existing destination
  -v    verbose
  -r    create relative symbolic link (parsed; doesn't rewrite target — see notes)
  -T    treat the second arg as a regular file, not a directory
]],

  ls = [[usage: ls [-laA1RFStr] [PATH ...]

List directory contents.
  -l    long listing format
  -a    show entries starting with '.'
  -A    like -a but exclude . and ..
  -1    one entry per line
  -R    list subdirectories recursively
  -F    append type indicator (/, @, *, |, =)
  -S    sort by file size, largest first
  -t    sort by modification time, newest first
  -r    reverse order
  -d    (alias) — invoked as `dir`
]],

  mktemp = [[usage: mktemp [-duqt] [-p DIR] [TEMPLATE]

Create a unique temporary file or directory.
  -d, --directory   create a directory instead of a file
  -u, --dry-run     print the name but don't create it
  -q, --quiet       suppress diagnostic messages
  -t                interpret TEMPLATE relative to $TMPDIR
  -p DIR            create the file/dir in DIR
TEMPLATE must contain at least 3 trailing X's; default is tmp.XXXXXXXXXX.
]],

  stat = [[usage: stat [-c FMT | -t] [-L] FILE...

Display file or filesystem status.
  -c, --format=FMT   custom format (e.g. '%n %s' for name and size)
  -t, --terse        single-line POSIX-ish output
  -L, --dereference  follow symbolic links
Format specifiers: %n (name), %s (size), %a (mode octal), %A (mode str),
%u (uid), %g (gid), %F (type), %y/%x/%z (time), %Y/%X/%Z (epoch).
]],

  truncate = [[usage: truncate [-co] {-s SIZE | -r REF} FILE...

Shrink or extend each FILE to SIZE.
  -s SIZE     target size; prefix with +-<>/% for relative ops
              (suffixes K, M, G, T, P scale by 1024)
  -r REF      use the size of REF
  -c          do not create files that don't exist
  -o          treat SIZE as IO-block multiples (accepted, currently no-op)
On Windows we approximate by rewriting the file (system `truncate` doesn't
exist there).
]],

  -- Phase 5 entries

  base64 = [[usage: base64 [-d] [-w COLS] [-i] [FILE]

Encode/decode base64. With no FILE, or when FILE is `-`, reads stdin.
  -d, --decode          decode base64
  -w, --wrap=COLS       wrap encoded output at COLS columns (default 76; 0 = no wrap)
  -i, --ignore-garbage  when decoding, accept any input characters
]],

  hexdump = [[usage: hexdump [-Cbcdov] [-s OFFSET] [-n LENGTH] [FILE ...]

Display file contents in various formats. Default: 2-byte hex words.
  -C, --canonical    canonical hex+ASCII (16 bytes per line, like xxd)
  -b                 one-byte octal display
  -c                 one-byte character display (with C escapes)
  -d                 two-byte decimal display
  -o                 two-byte octal display
  -x                 two-byte hex (default)
  -v                 do not collapse repeated rows (we never collapse anyway)
  -s OFFSET          skip OFFSET bytes
  -n LENGTH          dump at most LENGTH bytes
]],

  md5sum = [[usage: md5sum [OPTIONS] [FILE ...]

Compute or check MD5 message digests.
  -c, --check       read sums from FILE and verify them
  -b, --binary      read in binary mode (no-op on POSIX)
  -t, --text        read in text mode
  --tag             use BSD-style "MD5 (FILE) = HEX" output
  --quiet           don't print OK for each successfully verified file
  --status          don't output anything; status code only (with -c)
  -w, --warn        warn about improperly formatted check lines
  --strict          exit non-zero on any malformed check line
  -z, --zero        end each output line with NUL instead of newline
]],

  od = [[usage: od [-A RADIX] [-bcdox] [-w WIDTH] [-j SKIP] [-N COUNT] [FILE ...]

Dump files in octal and other formats.
  -o, -b      octal byte dump (default)
  -d          unsigned decimal byte dump
  -x          hexadecimal byte dump
  -c          ASCII character dump (with C escapes)
  -A RADIX    address radix: d (decimal), o (octal), x (hex), n (none)
  -w WIDTH    bytes per output line (default 16)
  -j SKIP     skip SKIP bytes from start
  -N COUNT    dump at most COUNT bytes
  -v          show all lines (we never collapse)
]],

  sha1sum = [[usage: sha1sum [OPTIONS] [FILE ...]

Compute or check SHA-1 message digests. Same options as md5sum.
]],

  sha256sum = [[usage: sha256sum [OPTIONS] [FILE ...]

Compute or check SHA-256 message digests. Same options as md5sum.
]],

  sha512sum = [[usage: sha512sum [OPTIONS] [FILE ...]

Compute or check SHA-512 message digests. Same options as md5sum.
]],

  -- Phase 9 entries

  date = [==[usage: date [-u] [-d STR | -r REF | +FORMAT] [-R] [-I[=SPEC]]

Print the current date/time, or format a given timestamp.
  -u, --utc         use UTC instead of local time
  -d, --date=STR    parse STR as an ISO-8601 date (subset)
  -r REF            use the modification time of REF
  -R, --rfc-2822    output RFC 2822 format
  -I[SPEC]          ISO 8601 (date | hours | minutes | seconds | ns)
  +FORMAT           strftime-style format (e.g. "+%Y-%m-%d %H:%M:%S")
]==],

  env = [==[usage: env [-i] [-u NAME] [KEY=VALUE ...] [COMMAND [ARG ...]]

Run a program in a modified environment, or print the environment.
  -i, --ignore-environment    start with empty environment
  -u, --unset NAME            remove NAME from the environment
With no COMMAND, prints the (possibly modified) environment.
]==],

  getopt = [[usage: getopt [OPTIONS] [--] [PARAMETERS ...]

Parse command-line options for shell scripts (GNU enhanced form).
  -o, --options STRING       short-option spec (e.g. "ab:c::")
  -l, --long STRING          long-option spec (comma-separated)
  -u, --unquoted             do not shell-quote the output
  -q, --quiet                suppress error messages
  -T, --test                 exit 4 (signals enhanced getopt is available)
  +                          options first (mix-style)
Output is shell-quoted so it can be eval'd safely.
]],

  groups = [[usage: groups [USER ...]

Print groups a user is in. Defaults to the current user.
]],

  id = [[usage: id [-Gnru] [USER]

Print user and group IDs.
  -u, --user        print only the effective user ID
  -g, --group       print only the effective group ID
  -G, --groups      print all group IDs
  -n, --name        print names instead of numbers
  -r, --real        print the real ID instead of effective (no-op on POSIX)
]],

  ["install-aliases"] = [[usage: install-aliases [--aliases] [--all] [-fnq] [TARGET_DIR]

Create one symlink per applet in TARGET_DIR (default: ~/.local/bin or
%LOCALAPPDATA%\moonraker\bin), so users can type `ls`, `cat`, etc.
  --aliases    also link applet aliases (e.g. `dir` for `ls`)
  --all        include lifecycle applets (completions, update,
               install-aliases) — skipped by default
  -n, --dry-run    preview only; don't create files
  -f, --force      overwrite existing files in TARGET_DIR
  -q, --quiet      no per-link output
]],

  printf = [[usage: printf FORMAT [ARG ...]

Format and print data. FORMAT supports %d, %i, %u, %o, %x, %X, %e, %E,
%f, %g, %G, %c, %s, %b (string with backslash escapes), %% literal.
Backslash escapes in FORMAT (\n, \t, \r, \\, \a, \b, \f, \v, \0) are
also processed. The format is repeated when extra args are supplied.
]],

  realpath = [[usage: realpath [-emszL] [--relative-to=DIR] PATH...

Resolve PATH to its canonical absolute form.
  -e, --canonicalize-existing  all components must exist
  -m, --canonicalize-missing   tolerate missing components (default)
  -s, -L, --no-symlinks        do not resolve symbolic links
  -z, --zero                   end output with NUL instead of newline
  --relative-to=DIR            output relative to DIR
]],

  seq = [==[usage: seq [OPTIONS] [FIRST [INCR]] LAST

Print a sequence of numbers from FIRST to LAST.
  -s, --separator=STR    use STR between values (default newline)
  -f, --format=FMT       printf-style format for each value
  -w, --equal-width      pad to equal width with leading zeros
With one argument: 1..N. Two args: FIRST..LAST. Three: FIRST INCR LAST.
]==],

  timeout = [[usage: timeout [OPTIONS] DURATION COMMAND [ARG ...]

Run COMMAND with a time limit. Delegates to the system `timeout`
binary on POSIX (Windows isn't supported in this build).
  -s, --signal=NAME    signal on timeout (default TERM)
  -k, --kill-after=N   send SIGKILL after additional N seconds
  --preserve-status    return the command's exit code instead of 124
  --foreground         run in foreground (allow stdin)
  -v, --verbose        log signal delivery
DURATION suffix: s (default), m, h, d.
]],

  uname = [[usage: uname [-asnrvmpio]

Print system information.
  -s, --kernel-name        kernel name (default)
  -n, --nodename           network host name
  -r, --kernel-release     kernel release
  -v, --kernel-version     kernel version
  -m, --machine            machine architecture
  -p, --processor          processor type
  -i, --hardware-platform  hardware platform
  -o, --operating-system   operating system
  -a, --all                all of the above
]],

  uuidgen = [[usage: uuidgen [--upper] [--hex] [-c COUNT]

Generate UUIDs (v4 random only in this build).
  --upper       output uppercase hex
  --hex         omit dashes
  -c, --count N emit N UUIDs (one per line)
]],

  which = [[usage: which [-a] NAME...

Locate a command on PATH.
  -a    show all matches, not just the first
On Windows, also tries each entry in PATHEXT (.EXE, .BAT, .CMD, ...).
]],

  xargs = [==[usage: xargs [OPTIONS] [COMMAND [INITIAL-ARGS ...]]

Build and execute command lines from standard input.
  -n, --max-args N    use at most N tokens per invocation
  -L N                use up to N input lines per invocation
  -I REPL             one invocation per token; substitute REPL with the token
  -d DELIM            input is delimited by DELIM (single character)
  -0, --null          input is delimited by NUL bytes (e.g. from `find -print0`)
  -a FILE             read input from FILE instead of stdin
  -r, --no-run-if-empty   don't invoke COMMAND if input is empty
  -t                  print each invocation to stderr before running
With no COMMAND, defaults to `echo`.
]==],

  -- Phase 6 entries

  gzip = [==[usage: gzip [-cdfktv] [-1..-9] [FILE ...]

Compress or decompress files with the gzip format.
  -d, --decompress    decompress instead of compress
  -c, --stdout        write output to stdout (don't replace files)
  -k, --keep          keep the input file
  -f, --force         overwrite existing output files
  -t, --test          test integrity only
  -1 ... -9           compression level (1=fastest, 9=best)
  -q, --quiet         suppress noise
  -v, --verbose       (accepted; we don't print per-file progress)
With no FILE, reads stdin and writes stdout.
]==],

  gunzip = [==[usage: gunzip [OPTIONS] [FILE ...]

Decompress gzipped (.gz) files. Equivalent to `gzip -d`.
]==],

  tar = [==[usage: tar -c|-x|-t [-zvf ARCHIVE] [-C DIR] [--exclude PAT] [FILE ...]

Create, extract, or list tar archives (POSIX ustar).
  -c        create a new archive from FILE(s)
  -x        extract from ARCHIVE
  -t        list contents of ARCHIVE
  -f FILE   archive filename (use `-` for stdin/stdout)
  -z        gzip-compressed (auto-detected on .tar.gz / .tgz)
  -v        verbose
  -C DIR    chdir to DIR before operating
  --exclude PATTERN   skip matching paths (glob)

bz2 (-j) and xz (-J) are accepted but rejected with an error in this
build. Use the system `tar` for those formats until they're vendored.
]==],

  -- Phase 9 leftovers

  watch = [[usage: watch [-tgbpx] [-n SECS] COMMAND [ARG ...]

Re-run COMMAND every SECS seconds, redrawing its output.
  -n, --interval SECS    seconds between updates (default 2, min 0.1)
  -t, --no-title         omit the header line
  -x, --exec             run COMMAND as a single argv (no shell)
  -g, --chgexit          exit when output changes
  -b, --beep             beep (BEL) when output changes
  -p, --precise          subtract elapsed time from interval (whole-sec)
  --max-cycles N         stop after N iterations (test/automation hook)
]],

  completions = [[usage: completions {bash | zsh | fish | powershell}

Emit a shell completion script for moonraker. Pipe into your shell's
completion location:

  moonraker completions bash      | sudo tee /etc/bash_completion.d/moonraker
  moonraker completions zsh       > ~/.zsh/completions/_moonraker
  moonraker completions fish      > ~/.config/fish/completions/moonraker.fish
  moonraker completions powershell  # add to $PROFILE

The scripts call back into the running binary at completion time, so
they stay accurate as new applets ship.
]],

  update = [[usage: update [--check] [--force] [--asset NAME]

Self-update from the latest GitHub release.
  --check      print what would change but don't download
  --force      re-download even when on the latest tag
  --asset N    override asset autodetection

Requires `curl` or `wget` on PATH (we don't ship a TLS stack). Replaces
the running binary atomically and keeps the previous one alongside as
`<binary>.old` for one easy revert.
]],

  -- Phase 7 entries

  http = [[usage: http [OPTIONS] URL

Minimal curl-style HTTP client. HTTPS works; we shell out to curl or
wget so the system TLS stack does the verification.
  -X, --request METHOD       request method (default GET, or POST if -d)
  -H, --header HDR           extra header (repeat for multiple)
  -d, --data BODY            request body (use @file to read from disk)
  --json BODY                JSON body (sets Content-Type if missing)
  -i, --include              include response headers in output
  -I, --head                 HEAD-only request
  -L, --location             follow redirects (default on)
  --no-location              do not follow redirects
  -o, --output FILE          write body to FILE
  -s, --silent               suppress progress messages
  -f, --fail                 exit 22 on HTTP 4xx/5xx
  -A, --user-agent UA        override the default User-Agent
  --timeout SECS             request timeout (default 30)
]],

  nc = [[usage: nc [OPTIONS] HOST PORT
       nc -l -p PORT
       nc -z HOST PORT[-PORT2]

Minimal TCP netcat. Connect, listen, or scan ports. UDP (-u) is not
implemented in this build.
  -l               listen mode (accepts one connection then exits)
  -p PORT          listen on PORT
  -z               port-scan mode (no I/O; just probe connectivity)
  -v               verbose (write status lines to stderr)
  -w SECS          connect/recv timeout
  -4 / -6          force IPv4 / IPv6 (accepted but inferred from address)
]],

  dig = [[usage: dig [@SERVER] [TYPE] NAME [+short] [-x ADDR]

Minimal DNS resolver over UDP. Supported record types:
A, AAAA, MX, CNAME, TXT, NS, SOA, PTR, ANY.
  @SERVER            DNS server to query (default: /etc/resolv.conf, then 1.1.1.1)
  -t, --type TYPE    query type (A, AAAA, MX, ...)
  -x ADDR            reverse lookup; sets type to PTR
  +short             output only the answer values
  --timeout SECS     query timeout (default 5)
]],

  -- Phase 7.5 entries

  zip = [[usage: zip [-rjg] [-0..-9] [-d] ARCHIVE FILE...

Package and compress files into a .zip archive (PKZip 2.0).
  -r, --recurse-paths    recurse into directories
  -j, --junk-paths       store only filenames, not full paths
  -g, --grow             append to an existing archive
  -d, --delete           delete the named entries from ARCHIVE
  -0 .. -9               compression level (-0 = stored, default -6)
]],

  unzip = [[usage: unzip [-lopnq] [-d DIR] ARCHIVE [NAME...]

Extract files from a .zip archive.
  -l               list entries (do not extract)
  -p               pipe contents to stdout (no path-creation)
  -d DIR           extract into DIR (default: ".")
  -o               overwrite existing files without prompting
  -n               never overwrite (skip existing)
  -q, -qq          quiet mode
Specify NAME(s) to limit extraction to a subset of entries.
]],

  -- Phase 7.7 entries

  awk = [[usage: awk [-F sep] [-v var=val ...] [-f file | 'program'] [file...]

Pattern-scanning and processing language. Supports a practical
POSIX-awk subset:
  * BEGIN/END blocks, /regex/ patterns, expression patterns,
    range patterns (p1, p2)
  * print, printf with %d %i %o %x %X %f %e %E %g %G %s %c
  * Control flow: if/else, while, do/while, for(;;), for (k in a),
    break, continue, next, exit
  * Associative arrays, delete, `k in a`
  * Field access ($0, $NF, $(expr)), NR, NF, FS, OFS, ORS, RS,
    FILENAME, FNR
  * String operators (juxtaposition), arithmetic, comparison,
    ~ !~, &&/||/!, ternary ?:, assignments (=, +=, -=, *=, /=,
    %=, ^=)
  * Built-ins: length, substr, index, split, sub, gsub, match,
    toupper, tolower, sprintf, int, sqrt, log, exp, sin, cos,
    atan2, rand, srand, system

Not implemented in this build: user-defined functions, getline.
]],

  sed = [[usage: sed [-nEi] [-e SCRIPT | -f FILE] [SCRIPT] [FILE...]

Stream editor: apply SCRIPT to each input line and emit the result.
Supported commands:
  s/pattern/replacement/[gipN]      substitute
  d                                  delete pattern space
  p                                  print pattern space
  q                                  quit
  =                                  print line number
  y/src/dst/                         transliterate

Addresses:
  N           single line
  $           last line
  /regex/     pattern match
  N,M         range
  !           prefix to negate (e.g. `2!d`)

Options:
  -n, --quiet, --silent      suppress automatic line printing
  -E, -r                     use ERE instead of BRE
  -i, --in-place             edit files in place
  -e SCRIPT                  add SCRIPT to the program (repeatable)
  -f FILE                    read script from FILE
]],
}
