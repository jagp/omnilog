# Changelog

All notable changes to omnilog are recorded here. Entries before 1.0.0 are from
the `dev-strap` plugin omnilog was split out of. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The per-project log moved into `.claude/`.** It is now
  `.claude/.omnilog/.omnilog.md` instead of `omnilog.md` in the repo root. On first
  write omnilog also seeds `.claude/.omnilog/.gitignore` holding `*`, so the log stays
  out of git in every project, with no edit to the project's own `.gitignore`. That
  `.gitignore` is only seeded in a folder named `.omnilog`: an `OMNILOG_FILE` or
  global `path:` log gets none, and an existing one is never overwritten. A project that
  already has a root `omnilog.md` keeps appending to it (no new file is created); that
  legacy file is not auto-ignored.

### Fixed

- `.claude/*.local.md` (e.g. `.claude/omnilog.local.md`) is now actually git-ignored in
  this repo; `.gitignore` had the comment but no pattern.
- `/omnilog-scope` no longer describes the marker-file gate that 1.0.0 removed.

## [1.0.1]

### Fixed

- **Stop token cost no longer undercounts.** Current Claude Code versions write `isMeta`
  user lines in the middle of a turn (skill bodies, reminders). The transcript walk took
  them for the turn's prompt and stopped early. Across 614 real turns, 46 were
  undercounted, some by more than 90%. The walk now steps over an `isMeta` line while a
  tool call is still open.
- **Never `:0`.** A usage block with no `output_tokens` now leaves the cost off instead
  of logging `<Stop:0>`.
- **No raw material from MCP tools or WebFetch.** MCP and other unlisted tools now log
  a bare `<ToolName>` (their `description` input is user data, not a model summary).
  `WebFetch` logs only the URL's host, never its path, query or credentials.
- **Config edge cases.** A whitespace-only `OMNILOG_FILE` is ignored as documented, and
  a `CLAUDE_PROJECT_DIR` that does not exist turns logging off instead of creating that
  folder.

### Added

- **Failed tool calls and failed responses are logged.** `PostToolUse` no longer fires
  when a tool fails, so `PostToolUseFailure` is registered too: those lines read
  `failed: <detail> <ToolName>`. A turn ended by an API error fires `StopFailure`, which
  logs `response failed - N tool call(s) <StopFailure[:cost]>`. The `error` text is never
  logged.

## [1.0.0]

### Changed

- **Split out of dev-strap as its own plugin.** The plugin is now `omnilog`
  (`omnilog@interface-layer`), published through the InterfaceLayer marketplace
  (`jagp/interface-layer`). The repo no longer ships its own `marketplace.json`.
  Install: `/plugin marketplace add jagp/interface-layer`, then
  `/plugin install omnilog@interface-layer`.

- **File-tool lines keep the path.** `Read`/`Edit`/`Write`/`MultiEdit` lines in
  `omnilog.md` now log the file's path relative to `$CLAUDE_PROJECT_DIR`
  (e.g. `hooks\scripts\omnilog-tool.ps1 <Read>`) instead of the bare filename. Files
  outside the project are logged with the path as given. Covered by
  `tests/file-path-logging.ps1`.

### Removed

- **The `ado` task board** (`ado-tool.ps1`, `ado-lib.ps1`, `/ado`, and the `ado:` /
  `ado-path:` config keys). dev-strap is retired and ado was not carried over.

## [0.3.1]

### Fixed

- **Corrupt `plugin.json`.** The develop merge in `36c74b7` was hand-resolved and left
  two stray `},` fragments in `.claude-plugin/plugin.json` — the manifest stopped
  parsing, and installs surfaced "corrupt manifest file" in the plugin manager.
  Structure repaired (first check of `tests/plugin-manifest.ps1` covers this), the
  "Bootstrasp" typo fixed, and the same description mirrored into `marketplace.json`.
  Patch bump so the version-keyed plugin cache re-extracts a clean copy on update.

## [0.3.0]

### Changed

- **Logging is on by default.** The per-project opt-in gate ("log only if an
  `omnilog.md` marker already exists, otherwise stay silent") is gone. omnilog now
  seeds a fresh `omnilog.md` in the calling project on first write, so a newly
  scaffolded repo starts logging itself with no manual setup.
- Because the ado board rides the same marker, it likewise becomes active in projects
  that log. Revisit when the activation-semantics design settles.

### Added

- `enabled:` master switch in `.claude/omnilog.local.md` — explicit opt-out
  (`false`/`off`/`no`/`0`) or opt-in (`true`/`on`/`yes`/`1`), independent of `scope:`.
- `$env:OMNILOG_ENABLED=off` — machine-wide kill switch; outranks everything,
  including `$env:OMNILOG_FILE` (mirrors how `ADO_SCOPE=off` beats `ADO_FILE`).
- `Initialize-OmnilogFile` — best-effort seeding of a fresh empty log; never throws,
  so a hook can't break a session.

### Marketplace note

`.claude-plugin/marketplace.json` pins `version` per plugin entry; bumped to 0.3.0.

## [0.2.1]

### Added

- Five hardening test suites for installation/activation and hook robustness:
  - `tests/plugin-manifest.ps1` — the plugin is installable as shipped: manifests
    parse, plugin/marketplace versions stay in sync, every hook command quotes its
    `${CLAUDE_PLUGIN_ROOT}` path (cache paths contain spaces), scripts parse under
    Windows PowerShell 5.1 and are pure-ASCII source, commands carry frontmatter.
  - `tests/hook-resilience.ps1` — file-creation edge cases: missing parent dirs,
    read-only targets, exclusively locked files, target-is-a-directory.
  - `tests/env-collisions.ps1` — stray/whitespace env values, `ADO_SCOPE` case,
    trailing-slash and missing `CLAUDE_PROJECT_DIR`, BOM/CRLF configs, locked
    configs, duplicate keys, forward-slash paths.
  - `tests/third-party-interop.ps1` — foreign MCP tool names, schema drift,
    format-injection payloads, hostile board subjects, Stop-hook transcript
    garbage, and six parallel agents mirroring to one board.
  - `tests/portability.ps1` — hooks run from a simulated plugin-cache path with
    spaces, from a foreign cwd, plus optional pwsh (7+) parity.

### Fixed

- `Write-OmnilogEntry` now creates the target's parent directory (parity with
  `Write-AdoMirror`) — a `path:`/`OMNILOG_FILE` aimed into a not-yet-created
  folder no longer drops every line silently.
- `ConvertTo-Ascii` maps whitespace controls (newline/tab) to spaces before the
  printable-ASCII catch-all; multi-line text renders as `a b`, not `a?b`.
- `Get-OmnilogConfig` honors keys only inside the YAML frontmatter fence (prose
  in the markdown body quoting `scope: off` no longer flips the config; fenceless
  files keep the lenient whole-file scan) and treats an unreadable config as
  defaults instead of throwing.
- Whitespace-only `OMNILOG_FILE`/`ADO_FILE` values leaked into the environment
  are treated as unset instead of becoming a "path" of spaces.

## [0.2.0]

### Added

- `/ado` command now ships with the plugin (moved from the project-local
  `.claude/commands/` into the plugin-root `commands/`), so an install gets the
  task-board viewer, not just the mirror hook.
- `ado-path:` key in `.claude/omnilog.local.md` pins the board to an explicit
  location (parity with omnilog's `path:`), e.g. a shared file under your home dir.
- `.claude-plugin/marketplace.json` — the repo now doubles as a single-plugin
  marketplace (`source: "./"`), installable via `/plugin marketplace add jagp/dev-strap`
  then `/plugin install dev-strap@dev-strap`, or autoloaded via `~/.claude/settings.json`.

### Fixed

- Artifact path resolution no longer falls back to the plugin's own directory when
  `CLAUDE_PROJECT_DIR` is unset. Both omnilog and the ado board now fall back to the
  runtime working directory, so an installed plugin writes into the calling project,
  never into the plugin cache.

### Docs

- Documented the `/ado` command and the `ado-path:` override in the README.

## [0.1.0]

- Initial plugin conversion: omnilog action-logging + ado task-board hooks packaged
  as a Claude Code plugin (`.claude-plugin/plugin.json`, `hooks/hooks.json`,
  `hooks/scripts/`), per-project / global / off logging scope with an opt-in marker,
  and the `/omnilog-scope` command.
