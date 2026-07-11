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
| **Testing** | Atomic PowerShell test suite, run from the ground up | ✅ 3 tests, all green |

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

`run-all.ps1` auto-discovers every `tests/*.ps1`, so adding a test needs no wiring.

---

## Repository layout

```text
dev-strap/
├── CLAUDE.md                      # instructions Claude Code loads each session
├── omnilog.md                     # the action log (append-only ledger)
├── .claude/
│   ├── settings.json              # hook registrations
│   └── hooks/
│       ├── omnilog-lib.ps1        # shared: UTF-8 stdin, ASCII + 78-width, path
│       ├── omnilog-tool.ps1       # PostToolUse
│       ├── omnilog-stop.ps1       # Stop (real token cost)
│       └── omnilog-subagentstop.ps1
├── docs/
│   ├── autologging.md             # verified hook-schema reference
│   └── plugin-conversion-todo.md  # decisions parked for plugin conversion
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
