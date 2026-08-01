# Changelog

All notable changes to dev-strap are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/spec/v2.0.0.html).

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
