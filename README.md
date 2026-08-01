# dev-strap

**A Claude Code + VSCode project scaffold** — the best-practice setup worth having from commit #1, wired up and ready: git-flow, an automatic action log, linting, and tests.

Today dev-strap is where those pieces are being built and hardened locally. The endgame is a **distributable Claude Code plugin** that stamps this setup into any new repo (see [Roadmap](#roadmap)).

---

## What's in the box

| Area | What you get | Status |
|------|--------------|--------|
| **Version control** | `git` + **git-flow** (`main` / `develop` + feature/release/hotfix flows) | ✅ set up |
| **Autologging** | Every action Claude takes is appended to `omnilog.md` automatically, via Claude Code hooks | ✅ built + tested |
| **Linting** | [Trunk](https://trunk.io) meta-linter: `prettier`, `markdownlint`, `checkov`, `trufflehog`, `git-diff-check` | ✅ configured |
| **Testing** | Atomic PowerShell test suite, run from the ground up | ✅ 6 tests, all green |

---

## The omnilog autologging system

The centerpiece. It answers one question continuously: **what is the agent actually doing that I can't see?** Every tool call, every response — appended to `omnilog.md` as one factual line, with no dependence on the model remembering to write it.

### What the log looks like

```text
[26-07-01 06:58] Searched for log file <PowerShell>
[26-07-01 06:58] config.json <Edit>
[26-07-01 06:58] Spun off new subagent (#a4864e00) for find the auth code <Agent>
[26-07-01 06:58] Subagent finished (#a4864e00) claude-code-guide <SubagentStop>
[26-07-01 06:58] response - 9 tool call(s) <Stop:25548>
```

Format: `[YY-MM-DD HH:mm] {description} <{actionType}[:{tokenCost}]>`

### Design principles

- **Log what you can't see.** Your prompts and the assistant's visible replies don't need restating; the *invisible* work — tool calls, subagent spawns — does.
- **Descriptions, never raw material.** Shell/agent lines log the model-authored `description` (e.g. `Rotate GitHub auth token`), never the command string; file tools log only the filename, never contents. **Secrets can't reach the log.**
- **Only real, verified costs.** A `:tokenCost` appears solely on the `Stop` line, computed from the transcript. If a number can't be verified, no number is written — never a placeholder.
- **Append-only & immutable.** The log is a ledger. Lines are only ever appended; nothing is edited or backfilled, even to fix a past mistake.
- **Portable output.** Every line is pure ASCII and ≤ 78 chars, so it renders identically in a terminal, an editor, and `git diff`.

### How it works

Three [Claude Code hooks](https://code.claude.com/docs/en/hooks) registered in `.claude/settings.json`, all routing through one shared library:

| Event | Script | Emits |
|-------|--------|-------|
| `PostToolUse` | `omnilog-tool.ps1` | one line per tool call — `description` / filename / pattern |
| `Stop` | `omnilog-stop.ps1` | one line per response, with the real per-turn token cost |
| `SubagentStop` | `omnilog-subagentstop.ps1` | one line when a spawned agent finishes |

`omnilog-lib.ps1` is the single source of truth for the log's invariants: it reads stdin as UTF-8, forces **ASCII-only** output, enforces the **78-char** width, and resolves the log path.

The `Stop` token cost is computed by walking the session transcript backward to the start of the turn, deduplicating by `requestId` (Claude Code writes one JSONL line per content block, all sharing a request's `usage`), excluding `<synthetic>` messages, and summing `output_tokens`. The full, cross-version-verified schema is documented in [`docs/autologging.md`](docs/autologging.md).

### Tests

```powershell
powershell -File tests/run-all.ps1
```

| Test | Guards |
|------|--------|
| `ascii-sanitizer.ps1` | arbitrary Unicode → pure printable ASCII |
| `hooks-ascii-output.ps1` | hooks never emit a non-ASCII byte; lines stay ≤ 78 |
| `line-format.ps1` | every line matches `[yy-MM-dd HH:mm] … <tag>` |
| `omnilog-scope.ps1` | scope resolution: per-project opt-in, global, off, env override |
| `ado.ps1` | ado task-board mirroring stays observe-only and ASCII |
| `ado-scope.ps1` | board writes only where opted in; `ado:` key on/off/marker gate |

`run-all.ps1` auto-discovers every `tests/*.ps1`, so adding a test needs no wiring.

---

## Install as a plugin

dev-strap is a Claude Code plugin distributed from its own repo, which doubles as a
single-plugin marketplace (`.claude-plugin/marketplace.json`). Install it, then choose a
logging scope in each project.

```install
/plugin marketplace add jagp/dev-strap
/plugin install dev-strap@dev-strap
```

For local/experimental use before pulling from GitHub, add the marketplace from a path:
`/plugin marketplace add ./path/to/dev-strap`.

### Autoload (enable on every session)

To load dev-strap automatically with no manual install step, register the marketplace and
enable the plugin in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "dev-strap": { "source": { "source": "github", "repo": "jagp/dev-strap" } }
  },
  "enabledPlugins": {
    "dev-strap@dev-strap": true
  }
}
```

Plugin hooks fire in every project, but omnilog and the ado board only write where you
opt in (see Logging scope below), so global autoload is safe. **One exception — the
dev-strap repo itself** already dogfoods these hooks via its project
`.claude/settings.json`; don't also autoload the plugin there, or both copies fire
(double logging).

### Logging scope

Logging is **on by default**: in any project you work in, omnilog seeds a fresh
`omnilog.md` in the repo root on the first logged action and appends from there. Nothing
to create by hand — install the plugin and a new project starts logging itself. Configure
per project with `/omnilog-scope`, or by hand in `.claude/omnilog.local.md` (git-ignored):

| Scope | Behavior | Writes when |
|-------|----------|-------------|
| `per-project` (default) | writes `omnilog.md` in the repo root, creating it if absent | unless switched off |
| `global` | writes one shared log at `path:` (default `~/.claude/omnilog.md`) | unless switched off |
| `off` | omnilog disabled for this project | never |

```yaml
---
scope: per-project
---
```

**Turning it off.** `enabled:` is an explicit master switch, independent of scope —
useful when a repo shouldn't log at all (e.g. developing the plugin itself):

```yaml
---
enabled: false
---
```

It accepts `false` / `off` / `no` / `0` (and `true` / `on` / `yes` / `1` to force on).
`$env:OMNILOG_ENABLED=off` is the machine-wide kill switch and beats everything,
including `$env:OMNILOG_FILE`.

`$env:OMNILOG_FILE` overrides all of the above (used by the test suite). Scope changes
take effect on the next Claude Code session. Both artifacts always resolve into the
calling project's directory (or a path you configure) — never into the plugin's own dir.

The ado task-board mirror follows the same file with its own `ado:` key: it rides the
per-project opt-in marker by default, `ado: on` forces it on (even under `global` scope,
which alone never enables it), and `ado: off` disables it independently. Pin the board to
an explicit location with `ado-path:` (parity with omnilog's `path:`), e.g.
`ado-path: C:\Users\<name>\.claude\task.ado`.

### Task board (`/ado`)

`ado` is a live, aggregated view of every task list the session's agents and subagents
spin up, mirrored automatically by the `ado-tool` hook into `.claude/task.ado`
(git-ignored working state). The mirror is **observe-only** — it holds a separate master
copy and never touches an agent's real list.

| Command | Does |
|---------|------|
| `/ado` | show the board verbatim (says "empty" until an agent creates a task) |
| `/ado add "<text>"` | append your own item to a `### user` block, alongside the agents' lists |

Enable/disable it per project with the `ado:` key described above, or pin its location
with `ado-path:`. `$env:ADO_FILE` overrides everything; `$env:ADO_SCOPE=off` force-disables.

---

## Repository layout

```text
dev-strap/
├── CLAUDE.md                      # instructions Claude Code loads each session
├── omnilog.md                     # the action log (append-only ledger)
├── .claude-plugin/
│   ├── marketplace.json           # single-plugin marketplace (source: "./")
│   └── plugin.json                # plugin manifest (name, version, metadata)
├── .claude/
│   └── settings.json              # dev-strap's own (dogfooding) hook registrations
├── commands/
│   ├── ado.md                     # /ado task-board viewer + add
│   └── omnilog-scope.md           # /omnilog-scope logging-scope chooser
├── hooks/
│   ├── hooks.json                 # plugin hook registrations (installed copies)
│   └── scripts/
│       ├── omnilog-lib.ps1        # shared: UTF-8 stdin, ASCII + 78-width, scope
│       ├── omnilog-tool.ps1       # PostToolUse
│       ├── omnilog-stop.ps1       # Stop (real token cost)
│       ├── omnilog-subagentstop.ps1
│       ├── ado-lib.ps1            # ado task-board shared helpers
│       └── ado-tool.ps1           # PostToolUse (task-board mirror)
├── docs/
│   └── autologging.md             # verified hook-schema reference
├── tests/                         # atomic PowerShell tests + run-all.ps1
├── evals/
│   ├── README.md                  # transcript-fixture corpus + schema notes
│   ├── fixtures/  (git-ignored)   # real session transcripts for parser tests
│   └── readable/  (git-ignored)   # human-readable digests of each fixture
└── .trunk/                        # Trunk linter configuration
```

---

## Tooling

- **git-flow** — `main` (releases) and `develop` (integration), with `feature/`, `release/`, `hotfix/`, and `bugfix/` prefixes.
- **Trunk** — runtimes `node@22.16.0` and `python@3.14.4`; linters enabled: `prettier`, `markdownlint` (prettier-friendly), `checkov`, `trufflehog`, `git-diff-check`. Auto-commit/pre-push actions are intentionally disabled — see `.trunk/trunk.yaml`.

---

## Roadmap

**Endgame:** a distributable Claude Code plugin that stamps this setup into any new repo. The near-term work is packaging dev-strap as that plugin — most notably making **logging scope** (per-project / global / off) a first-activation choice. Detailed phase planning is tracked privately by the maintainer, not in this repo.
