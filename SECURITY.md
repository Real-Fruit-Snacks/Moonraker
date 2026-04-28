# Security policy

## Supported versions

Only the `main` branch is supported.

## Reporting a vulnerability

If you discover a security vulnerability, please **do not** open a public issue. Instead, report it privately via [GitHub Security Advisories](https://github.com/Real-Fruit-Snacks/Moonraker/security/advisories/new).

Include:
- A description of the issue and its impact.
- Steps to reproduce, including affected applet and arguments.
- Platform (OS, Lua version, Moonraker version or commit).
- Any suggested mitigation.

We will acknowledge receipt within 7 days and aim to provide a fix or mitigation timeline within 30 days.

## Scope

In scope:
- Memory-safety issues in vendored C dependencies (`src/cdeps/`).
- Path-traversal, command-injection, or argument-handling issues in applets.
- Network applets (`http`, `dig`, `nc`) misusing TLS, DNS, or socket primitives.
- Cryptographic correctness in hashing applets.

Out of scope:
- Issues in upstream Lua, OpenSSL, or zlib that have not been re-introduced by Moonraker.
- POSIX-conformance gaps in applet behavior — those are bugs, not vulnerabilities.
