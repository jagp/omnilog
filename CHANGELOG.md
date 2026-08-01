# Changelog

All notable changes to dev-strap are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Added

- `/ado` command now ships with the plugin (moved from the project-local
  `.claude/commands/` into the plugin-root `commands/`), so an install gets the
  task-board viewer, not just the mirror hook.
- `ado-path:` key in `.claude/omnilog.local.md` pins the board to an explicit
  location (parity with omnilog's `path:`), e.g. a shared file under your home dir.

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
