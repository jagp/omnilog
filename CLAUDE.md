# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

dev-strap is a **Claude Code plugin**, written entirely in Windows PowerShell, that ships
two hook-driven features plus their slash commands:

- **omnilog** — an append-only action log: hooks append one ASCII line to `omnilog.md`
  per tool call, per response (with real token cost), and per subagent finish.
- **ado** — a live task board: a PostToolUse hook mirrors every agent/subagent task list
  into `.claude/task.ado` (observe-only; never touches the real task system).

The repo doubles as its own single-plugin marketplace (`.claude-plugin/marketplace.json`,
`source: "./"`). There is no build step; the plugin is the source tree.

**Logging is done by hooks, not by you.** Never hand-write, edit, or backfill entries in
`omnilog.md` — the entire design exists so the log does not depend on the model
remembering (or inventing) anything. The file is git-ignored and exempt from all linters.

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

## Architecture

### Dual hook registration — keep both in sync

The same three scripts are registered twice:

- `hooks/hooks.json` — the **installed plugin**. Paths use `${CLAUDE_PLUGIN_ROOT}` and
  must stay double-quoted (plugin cache paths contain spaces).
- `.claude/settings.json` — this repo **dogfooding** its own hooks via
  `$CLAUDE_PROJECT_DIR`.

Any change to hook wiring must be made in both files. Never autoload the installed
plugin inside this repo — both copies would fire and double-log.

### Event flow

```text
PostToolUse ──> omnilog-tool.ps1 (one log line per tool call)
            └─> ado-tool.ps1     (task-board mirror)
Stop        ──> omnilog-stop.ps1 (one line per response, real token cost)
SubagentStop ─> omnilog-subagentstop.ps1
```

All scripts read the hook JSON from stdin and route through
`hooks/scripts/omnilog-lib.ps1` — the single source of truth for the log's invariants
(UTF-8 stdin, ASCII-only single-line output, scope/path resolution). `ado-lib.ps1`
dot-sources it. `docs/autologging.md` is the verified hook/transcript schema reference
(every claim tagged VERIFIED / DOCS / UNVERIFIED) — read it before touching the parsers,
and keep its tags honest when the schema evolves.

### Non-negotiable invariants

- **Hooks always exit 0 and never throw.** A hook must be incapable of breaking a
  session: swallow failures, treat unreadable config as defaults, fail soft on schema
  drift.
- **Append-only ledger.** `omnilog.md` lines are only ever appended — never rewritten,
  even to correct a known-bad entry. (ado differs: block *order* is append-only, item
  *state* is rewritten in place.)
- **Descriptions, never raw material.** Shell/agent tools log `tool_input.description`,
  file tools the filename only, Grep/Glob the pattern — never command strings or file
  content, so secrets cannot reach the log.
- **Only real, verified token costs.** The Stop hook walks the transcript backward,
  keeps top-level `type == "assistant"` lines, excludes `model == "<synthetic>"`,
  **dedupes by `requestId`** (one JSONL line per content block; blocks of one request
  repeat identical `usage`), and sums `output_tokens`. If a number can't be computed,
  omit the `:cost` suffix entirely — never `:0` or a placeholder.
- **Artifacts resolve into the calling project** (or an explicitly configured path),
  never into the plugin's own directory or cache.

### Scope resolution (who wins)

Config lives in `.claude/omnilog.local.md` (git-ignored), keys honored only inside the
YAML `---` frontmatter fence. Precedence, highest first:

- omnilog: `$env:OMNILOG_ENABLED=off` (kill switch) → `$env:OMNILOG_FILE` (path
  override, used by tests) → `enabled: false` → `scope:` (`per-project` default — seeds
  `omnilog.md` on first write; `global`; `off`).
- ado: `$env:ADO_SCOPE=off` → `$env:ADO_FILE` → `ado: off` / `scope: off` →
  `ado-path:` → `ado: on` → otherwise rides the per-project `omnilog.md` marker
  (`global` scope alone never enables the board).

### Test corpus

`evals/fixtures/` holds real session transcripts (git-ignored — may contain PII; only
the README is tracked) used to validate the token-cost parser across CLI versions.
Refresh instructions are in `evals/README.md`.

## Conventions

- **git-flow**: `develop` is the default/integration branch, `main` is releases;
  branch prefixes `feature/`, `release/`, `hotfix/`, `bugfix/`. PRs target `develop`.
- **Versioning**: SemVer with a `CHANGELOG.md` entry (Keep a Changelog format). The
  `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must
  match — `tests/plugin-manifest.ps1` enforces this, along with: manifests parse, hook
  commands quote `${CLAUDE_PLUGIN_ROOT}`, scripts parse under PowerShell 5.1, script
  source is pure ASCII, and command files carry frontmatter. Bump the patch version
  even for manifest-only fixes, so the version-keyed plugin cache re-extracts.
- **Slash commands** (`commands/*.md`) need `name:` + `description:` YAML frontmatter.
- Hook script **source must be pure ASCII** and PowerShell 5.1-parseable.
