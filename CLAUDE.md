# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

omnilog is a **Claude Code plugin**, written entirely in Windows PowerShell: an
append-only action log. Hooks append one ASCII line to `.claude/.omnilog/.omnilog.md` per tool
call, per response (with real token cost), and per subagent finish. It was split out of the
retired `dev-strap` plugin (history preserved, the `ado` task board dropped).

It is published through the **InterfaceLayer** marketplace (`jagp/interface-layer`),
which pins each plugin to a release tag + commit. This repo ships no `marketplace.json`
of its own. There is no build step; the plugin is the source tree.

**Logging is done by hooks, not by you.** Never hand-write, edit, or backfill entries in
the log — the entire design exists so the log does not depend on the model
remembering (or inventing) anything. Its folder carries a seeded `.gitignore` (`*`) and it is exempt from all linters.

## Commands

```powershell
# Full test suite (auto-discovers tests/*.ps1 — a new test needs no registration)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-all.ps1

# Single test (each is atomic, self-contained; exit 0 = pass, 1 = fail)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/omnilog-scope.ps1

# Lint / format (Trunk meta-linter: prettier, markdownlint, checkov, trufflehog, git-diff-check)
trunk check
trunk fmt
```

Everything targets **Windows PowerShell 5.1** (`powershell`, not `pwsh`);
`tests/portability.ps1` optionally checks pwsh 7+ parity when available. On a
non-Windows machine without PowerShell installed, the suite cannot run — say so rather
than substituting a different verification.

Known failures: none. The full suite is expected to pass.

## Architecture

### Event flow

```text
PostToolUse, PostToolUseFailure ──> omnilog-tool.ps1 (one line per tool call)
Stop, StopFailure ───────────────> omnilog-stop.ps1 (one line per response, real token cost)
SubagentStop ────────────────────> omnilog-subagentstop.ps1
```

Hooks are registered in `hooks/hooks.json`. Paths use `${CLAUDE_PLUGIN_ROOT}` and must
stay double-quoted (plugin cache paths contain spaces).

All scripts read the hook JSON from stdin and route through
`hooks/scripts/omnilog-lib.ps1` — the single source of truth for the log's invariants
(UTF-8 stdin, ASCII-only single-line output, scope/path resolution).
`docs/autologging.md` is the verified hook/transcript schema reference (every claim
tagged VERIFIED / DOCS / UNVERIFIED) — read it before touching the parsers, and keep its
tags honest when the schema evolves.

### Non-negotiable invariants

- **Hooks always exit 0 and never throw.** A hook must be incapable of breaking a
  session: swallow failures, treat unreadable config as defaults, fail soft on schema
  drift.
- **Append-only ledger.** Log lines are only ever appended — never rewritten,
  even to correct a known-bad entry.
- **Descriptions, never raw material.** Shell/agent tools log `tool_input.description`,
  file tools the project-relative path only, Grep/Glob the pattern, WebFetch the URL's
  host — never command strings, file content, MCP tool inputs, or a failure's `error`
  text, so secrets cannot reach the log.
- **Only real, verified token costs.** The Stop hook walks the transcript backward to
  the turn's prompt (stepping over `tool_result` lines and `isMeta` lines injected while
  a tool call is open), keeps top-level `type == "assistant"` lines, excludes
  `model == "<synthetic>"`,
  **dedupes by `requestId`** (one JSONL line per content block; blocks of one request
  repeat identical `usage`), and sums `output_tokens`. If a number can't be computed,
  omit the `:cost` suffix entirely — never `:0` or a placeholder.
- **The log resolves into the calling project** (or an explicitly configured path),
  never into the plugin's own directory or cache.

### Scope resolution (who wins)

Config lives in `.claude/omnilog.local.md` (git-ignored), keys honored only inside the
YAML `---` frontmatter fence. Precedence, highest first: `$env:OMNILOG_ENABLED=off`
(kill switch) → `$env:OMNILOG_FILE` (path override, used by tests) → `enabled: false` →
`scope:` (`per-project` default — seeds `.claude/.omnilog/.omnilog.md` + its `*` `.gitignore` on first write; `global`; `off`).

### Test corpus

`evals/fixtures/` holds real session transcripts (git-ignored — may contain PII; only
the README is tracked) used to validate the token-cost parser across CLI versions.
Refresh instructions are in `evals/README.md`.

## Conventions

- **git-flow**: `develop` is the default/integration branch, `main` is releases;
  branch prefixes `feature/`, `release/`, `hotfix/`, `bugfix/`. PRs target `develop`.
- **Versioning**: SemVer with a `CHANGELOG.md` entry (Keep a Changelog format). A
  release is merged to `main` and tagged `vX.Y.Z`; then the omnilog entry in
  `jagp/interface-layer` gets the new `version`, `ref` and `sha`.
  `tests/plugin-manifest.ps1` checks: manifests parse, hook commands quote
  `${CLAUDE_PLUGIN_ROOT}`, scripts parse under PowerShell 5.1, script source is pure
  ASCII, and command files carry frontmatter.
- **Slash commands** (`commands/*.md`) need `name:` + `description:` YAML frontmatter.
- Hook script **source must be pure ASCII** and PowerShell 5.1-parseable.
