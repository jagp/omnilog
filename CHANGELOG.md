# Changelog

All notable changes to dev-strap are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/spec/v2.0.0.html).

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
