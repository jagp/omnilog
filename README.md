# omnilog

**An append-only action log for Claude Code.** It answers one question continuously:
**what is the agent actually doing that I can't see?** Every tool call, every response,
every subagent finish — appended to `.claude/.omnilog/.omnilog.md` as one factual line by hooks, with no
dependence on the model remembering to write it.

Split out of the retired `dev-strap` plugin in 1.0.0; history is preserved.

## Install

omnilog is published through the [InterfaceLayer](https://github.com/jagp/interface-layer)
marketplace:

```text
/plugin marketplace add jagp/interface-layer
/plugin install omnilog@interface-layer
```

## What the log looks like

```text
[26-07-01 06:58] Searched for log file <PowerShell>
[26-07-01 06:58] config.json <Edit>
[26-07-01 06:58] Spun off new subagent (#a4864e00) for find the auth code <Agent>
[26-07-01 06:58] Subagent finished (#a4864e00) claude-code-guide <SubagentStop>
[26-07-01 06:58] response - 9 tool call(s) <Stop:25548>
```

Format: `[YY-MM-DD HH:mm] {description} <{actionType}[:{tokenCost}]>`

## Design principles

- **Log what you can't see.** Your prompts and the assistant's visible replies don't need restating; the _invisible_ work — tool calls, subagent spawns — does.
- **Descriptions, never raw material.** Shell/agent lines log the model-authored `description` (e.g. `Rotate GitHub auth token`), never the command string; file tools log only the file's project-relative path, never contents; `WebFetch` logs only the URL's host; MCP and other tools log just their name, since their inputs are user data. **Secrets can't reach the log.**
- **Only real, verified costs.** A `:tokenCost` appears solely on the `Stop` line, computed from the transcript. If a number can't be verified, no number is written — never a placeholder.
- **Append-only & immutable.** The log is a ledger. Lines are only ever appended; nothing is edited or backfilled, even to fix a past mistake.
- **Portable output.** Every line is pure ASCII, so it renders identically in a terminal, an editor, and `git diff`.

## How it works

Three hook scripts, registered for five [Claude Code hook](https://code.claude.com/docs/en/hooks) events in `hooks/hooks.json`, all routing through one shared library:

| Event                                | Script                     | Emits                                                                                                            |
| ------------------------------------ | -------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `PostToolUse` / `PostToolUseFailure` | `omnilog-tool.ps1`         | one line per tool call — `description` / project-relative path / pattern / host; failures are prefixed `failed:` |
| `Stop` / `StopFailure`               | `omnilog-stop.ps1`         | one line per response, with the real per-turn token cost; a turn ended by an API error logs as `response failed` |
| `SubagentStop`                       | `omnilog-subagentstop.ps1` | one line when a spawned agent finishes                                                                           |

`omnilog-lib.ps1` is the single source of truth for the log's invariants: it reads stdin as UTF-8, forces **ASCII-only** single-line output, and resolves the log path.

The `Stop` token cost is computed by walking the session transcript backward to the start of the turn (stepping over tool results and the `isMeta` lines Claude Code injects mid-turn), deduplicating by `requestId` (Claude Code writes one JSONL line per content block, all sharing a request's `usage`), excluding `<synthetic>` messages, and summing `output_tokens`. The full, cross-version-verified schema is documented in [`docs/autologging.md`](docs/autologging.md).

## Logging scope

Logging is **on by default**: in any project you work in, omnilog seeds a fresh
`.claude/.omnilog/.omnilog.md` on the first logged action and appends from there. The
`.omnilog/` folder carries its own `.gitignore` (`*`), so the log is never committed —
no edit to your project's `.gitignore` needed.
Configure per project with `/omnilog-scope`, or by hand in `.claude/omnilog.local.md`
(git-ignored):

| Scope                   | Behavior                                                                     |
| ----------------------- | ---------------------------------------------------------------------------- |
| `per-project` (default) | writes `.claude/.omnilog/.omnilog.md`, creating it (self-ignoring) if absent |
| `global`                | writes one shared log at `path:` (default `~/.claude/omnilog.md`)            |
| `off`                   | omnilog disabled for this project                                            |

```yaml
---
scope: per-project
---
```

`enabled: false` is a master switch independent of scope (accepts `false` / `off` / `no`
/ `0`, and `true` / `on` / `yes` / `1` to force on). `$env:OMNILOG_ENABLED=off` is the
machine-wide kill switch and beats everything; `$env:OMNILOG_FILE` overrides the path
(used by the test suite). Scope changes take effect on the next Claude Code session. The
log always resolves into the calling project's directory (or a path you configure) —
never into the plugin's own dir.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-all.ps1
```

`run-all.ps1` auto-discovers every `tests/*.ps1`, so adding a test needs no wiring.
Everything targets Windows PowerShell 5.1.

## Repository layout

```text
omnilog/
├── .claude-plugin/plugin.json     # plugin manifest
├── commands/omnilog-scope.md      # /omnilog-scope logging-scope chooser
├── hooks/
│   ├── hooks.json                 # hook registrations
│   └── scripts/
│       ├── omnilog-lib.ps1        # shared: UTF-8 stdin, ASCII one-liners, scope
│       ├── omnilog-tool.ps1       # PostToolUse
│       ├── omnilog-stop.ps1       # Stop (real token cost)
│       └── omnilog-subagentstop.ps1
├── docs/autologging.md            # verified hook-schema reference
├── tests/                         # atomic PowerShell tests + run-all.ps1
├── evals/                         # transcript-fixture corpus (fixtures git-ignored)
└── .trunk/                        # Trunk linter configuration
```
