# Autologging — Claude Code Hook Schema (Verified Reference)

Purpose: ground the `omnilog` logging component in facts, not guesses. This captures
what a hook actually receives and what it can reliably produce, verified against the
official docs **and** against this machine's live transcript JSONL.

Legend: **[VERIFIED]** = confirmed by inspecting a real transcript on this machine ·
**[DOCS]** = stated in official docs · **[UNVERIFIED]** = claimed but not confirmed; do not rely on.

---

## 1. Hook events and their stdin payloads

Every hook is invoked with a JSON object on **stdin**. All events include these
common fields **[DOCS]**:

| Field             | Meaning                                          |
| ----------------- | ------------------------------------------------ |
| `session_id`      | Unique session identifier                        |
| `transcript_path` | Absolute path to the conversation JSONL (see §2) |
| `cwd`             | Working directory when the hook fired            |
| `hook_event_name` | The event that triggered the hook                |

Newer fields also appear on many events: `prompt_id`, `permission_mode`, `effort`, and,
inside subagents, `agent_id`/`agent_type`. Tool events carry `tool_use_id`. **[DOCS]**

Event-specific fields **[DOCS]**:

| Event                | Extra fields                                                                                    | Matcher filters on             | Notes                                                    |
| -------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------- |
| `PreToolUse`         | `tool_name`, `tool_input`                                                                       | tool name (e.g. `Edit\|Write`) | Can block a tool call                                    |
| `PostToolUse`        | `tool_name`, `tool_input`, `tool_response`, `duration_ms`                                       | tool name                      | Fires only when a tool call **succeeds**                 |
| `PostToolUseFailure` | `tool_name`, `tool_input`, `error`, `is_interrupt`                                              | tool name                      | Fires when a tool call fails; `error` may echo raw input |
| `UserPromptSubmit`   | `prompt`                                                                                        | —                              | stdout **is** injected into context                      |
| `SessionStart`       | `source` (`startup`\|`resume`\|`clear`\|`compact`\|`fork`)                                      | `source`                       | stdout **is** injected into context                      |
| `SessionEnd`         | `reason` (`clear`\|`resume`\|`logout`\|`prompt_input_exit`\|`other`)                            | `reason`                       |                                                          |
| `Stop`               | `stop_hook_active`, `last_assistant_message`                                                    | — (always fires)               | Once per response; **not** on user interrupt             |
| `StopFailure`        | `error` (`rate_limit`, `overloaded`, ...)                                                       | `error`                        | Replaces `Stop` when an API error ends the turn          |
| `SubagentStop`       | `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message` | —                              | Once per subagent finish                                 |

The docs also warn that the transcript "isn't guaranteed to include the final message at
Stop time on all versions" **[DOCS]**. In a sweep of 614 real turns, the transcript
walk agreed with an independent reference every time, so this has not been observed
here **[VERIFIED]**.

`stop_hook_active` is a loop guard: it is `true` when the Stop hook already forced a
continuation. Only relevant if the hook **blocks** (exit 2). A pure logging hook that
always exits 0 cannot loop, so it can ignore this field. **[DOCS]**

---

## 2. Transcript structure and token cost **[VERIFIED]**

`transcript_path` points to a JSONL file — **one line per content block**, not per
message. An assistant reply that thinks, writes text, then calls two tools produces
**four** lines.

Assistant lines carry a message-level `usage` object. Observed shape on this machine:

```json
"usage": {
  "input_tokens": 10,
  "cache_creation_input_tokens": 9893,
  "cache_read_input_tokens": 16301,
  "output_tokens": 301,
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
  "service_tier": "standard",
  "cache_creation": { "ephemeral_1h_input_tokens": 9893, "ephemeral_5m_input_tokens": 0 }
}
```

`usage` key set: `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
`cache_creation_input_tokens`, `cache_creation` (nested), `server_tool_use` (nested),
`service_tier`, `inference_geo`, `iterations`, `speed`. Two keys were added later:
`output_tokens_details` (CLI 2.1.229+) and `fallback_credit` (2.1.285+). A few lines
omit `iterations`/`server_tool_use`/`speed`; `output_tokens` has never been missing.
Path is `.message.usage`; `requestId` is top-level on the line.

### The gotcha that breaks naive implementations

All content-block lines from a single API request **share one `requestId` and repeat
the identical `usage`**. Example: lines with `requestId: req_011CcG...` appeared 4×,
each reporting `output_tokens: 301`. Across the 10-transcript sample, assistant lines
outnumbered distinct requests roughly 2–3×. Summing `output_tokens` across raw lines
multi-counts by the number of content blocks.

**Subagent transcripts differ.** In `subagents/agent-*.jsonl`, about half of the
multi-line requests hold _streaming partials_: early lines carry a small, provisional
`output_tokens` and `stop_reason: null`, and only the **last** line holds the true value.
Main transcripts showed no partials (0 of 2,373 multi-line requests). Any subagent cost
must keep the last line per `requestId`. The main walk already does, because it runs
backward and keeps the first line it meets. **[VERIFIED]**

**Correct rule for a turn's token cost:**

1. Read the JSONL, walk backward from the end.
2. Keep only lines where top-level `type == "assistant"`. Real transcripts are full of
   non-message lines (`attachment`, `file-history-snapshot`, `system`, `api-request`,
   `api-request-blob`, `cost-state`, `tools-used`, and many more — the set grows with
   each CLI release). Skip anything that isn't `user` or `assistant`. Note that
   `api-request-blob` has a top-level `message` key, so test `type` before `.message`.
3. **Exclude `message.model == "<synthetic>"`.** These are locally injected messages
   (API-error notices and the like), not billed API calls. They carry 0 tokens, so the
   rule is about correctness, not inflation.
4. Collect assistant lines until the turn's prompt. Two kinds of user line are
   **mid-turn** and must be stepped over:
   - `tool_result` lines (`message.content[0].type == "tool_result"`);
   - `isMeta: true` lines written while a tool call is still open, such as a skill body
     injected after a `Skill` call. "Open" means the nearest earlier message is a
     `tool_result` or an assistant line holding a `tool_use`. Only 43 of the 53 mid-turn
     `isMeta` lines observed carry `sourceToolUseID`, so that field alone is not enough.
     An `isMeta` line after a _finished_ reply (a peer or task notification) opens a new
     turn and ends the walk.

   Stopping at every non-`tool_result` user line undercounted 46 of 614 real turns.

5. **Deduplicate by `requestId`** (one usage record per API request).
6. Sum `output_tokens` (and, if wanted, `input_tokens` + cache fields) across the distinct requests.

A single user turn spans **multiple** `requestId`s — one per tool-use step — so the
turn cost is the sum over all of them, not just the final wrap-up message.

**Empty-turn edge case:** a transcript can contain **zero** assistant lines (aborted /
interrupted turn — seen in the sample). When no assistant usage can be computed, **omit
the token-cost field entirely** (write `<actionType>`, never `:0` or a placeholder) and
still exit 0 — never divide-by-zero or crash.

### Cross-transcript verification **[CROSS-VERIFIED]**

Originally checked on 10 transcripts (CLI 2.1.118–2.1.191). Re-checked on 2026-10-29 on
all 65 main transcripts and 225 subagent files on this machine:

| Aspect                     | Result                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| CLI versions sampled       | 22 releases, 2.1.222 → 2.1.314 (older ones are no longer on disk)                          |
| Models sampled             | opus-5-5, opus-5, fable-5, sonnet-5-5, sonnet-5, haiku-5-5, haiku-4-5, `<synthetic>`       |
| `usage` key set            | stable core; two keys added (see above)                                                    |
| `usage` path               | `.message.usage` (nested), consistent                                                      |
| Multi-line-per-`requestId` | about 2.75 lines per request; identical `usage` in main transcripts                        |
| Subagent turns             | separate files (`<session>/subagents/`), `isSidechain: true`; never in the main transcript |
| Hook vs. reference         | 0 mismatches on 78 hook runs over real turns, including all 46 the old rule got wrong      |
| Fixtures                   | stored under `evals/fixtures/*.jsonl` (raw) + `evals/readable/*.md` (digest)               |

### Stability caveat

The transcript format is not a documented interface. The current hooks pages describe
the transcript as written asynchronously (it "may lag the in-memory conversation") but
no longer state that it is internal. The mid-turn `isMeta` lines above show the format
does change between releases. A logging hook should
fail soft — on any parse failure or schema mismatch, **omit the token-cost field
entirely** (never a placeholder value) rather than crash — and should not hard-assume field names.

---

## 3. `settings.json` registration **[DOCS]**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "<shell command>" }]
      }
    ]
  }
}
```

- Root `hooks` object → event-name keys → array of matcher groups.
- Each matcher group: optional `matcher` (string; regex/alternation for tool events) + `hooks` array.
- For `Stop` the `matcher` is meaningless (no tool to match) — omit it.
- For tool events, `"matcher": "Edit|Write"` selects which tools trigger the hook.
- The documented hook object is `{ "type": "command", "command": "<string>" }`.
  An `"args": [...]` array is also documented: it switches to exec form, with no shell.
  `timeout` defaults to 600s for command hooks. This plugin keeps the single command string.

---

## 4. Windows / PowerShell execution **[DOCS + LOCAL]**

- On Windows, command hooks run through **Git Bash** by default (or PowerShell when Git
  Bash isn't installed). A `"shell": "powershell"` option now exists too.
- This plugin invokes PowerShell explicitly in the command string, as `hooks/hooks.json` does:

```json
{
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/omnilog-tool.ps1\""
}
```

- `${CLAUDE_PLUGIN_ROOT}` expands to the installed plugin's directory, and the path
  must stay double-quoted because plugin cache paths contain spaces.
  `$CLAUDE_PROJECT_DIR` expands to the project root and stays fixed inside worktrees.
  Forward slashes work with `powershell -File` even on Windows.
- `jq`-based examples are fragile here — jq is not guaranteed present in Git Bash.
  A PowerShell script that reads stdin and parses the transcript with `ConvertFrom-Json` is the robust path on this machine.

---

## 5. Exit codes **[DOCS]**

| Exit  | Effect                                                                                        |
| ----- | --------------------------------------------------------------------------------------------- |
| `0`   | Success. For `Stop`, stdout is **not** injected into context.                                 |
| `2`   | Block. For `Stop`, forces Claude to continue (feeds stderr back). **Never use for a logger.** |
| other | Non-blocking error; first stderr line shown in transcript as a hook error.                    |

A logging hook should **always exit 0** and write to the file directly.

---

## 6. Implications for the `omnilog` component

- **Append-only, immutable log:** the hook only ever _appends_; existing lines are never
  rewritten or backfilled — even entries with known-bad values (the model's early
  fabricated `<init:2500>`) remain as an immutable record. Corrections are made by
  appending a new line, never editing an old one.
- **Timestamp & token cost are now honorable for real** — the hook reads wall-clock
  time and the transcript's `usage`. This replaces the fabricated `<init:2500>`-style
  numbers the model was inventing.
- **Failure convention (never placeholder):** when a real token count can't be computed
  — parse error, schema drift, empty/aborted turn, or only `<synthetic>` messages — emit
  the line with **no** cost field at all (`… <actionType>`), never `:?`, `:0`, or `:unknown`.
  The `:tokens` suffix appears **only** when a genuine number was measured.
- **`Stop` is the natural granularity for "every response"** — one line per turn,
  with a real token total computed per §2.
- **"Every action" (`PostToolUse` + `PostToolUseFailure`) fires per tool call** — noisy
  by design (fine per the logging philosophy). Both are needed: `PostToolUse` no longer
  fires on failure. Crucially, for `Bash`/`PowerShell`/`Agent` it CAN log a real summary:
  the model-authored `description` param travels inside `tool_input`, so the hook logs it
  verbatim — no synthesis needed.
- **Resolved — log the model-authored description where it exists; `<toolName>` always:**
  - `Bash`/`PowerShell`/`Agent` → log `tool_input.description` (the one-line summary I wrote
    when calling the tool). Never the raw command — which also keeps secrets out of the log.
  - `Edit`/`Write`/`Read` → the file's path relative to `$CLAUDE_PROJECT_DIR`, or the path as
    given when it lies outside the project (never file content); `Grep`/`Glob` → the pattern.
  - `WebFetch` → the URL's host only (a URL can carry a token). MCP and any other unlisted
    tool → nothing but `<toolName>`: their `description` input is user data (a task body,
    an email), not a model-authored summary.
  - `{actionType}` = the literal tool name; the `:cost` suffix appears only on the `Stop` line.

Sources: `code.claude.com/docs/en/hooks.md`, `hooks-guide.md`, `sessions.md`;
plus direct inspection of `~/.claude/projects/…/19a69f52-*.jsonl` on this machine.

## 7. Implemented (this repo)

Three scripts in `hooks/scripts/`, registered for five events in the plugin's
`hooks/hooks.json` (each with `"matcher": "*"`):

| Event                                | Script                     | Line format                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------------------ | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PostToolUse` / `PostToolUseFailure` | `omnilog-tool.ps1`         | `[ts] <detail> <ToolName>`, where detail is: shell → `tool_input.description`; `Agent`/`Task` → `Spun off new subagent (#id8) for <purpose>`; `Read`/`Edit`/`Write`/`MultiEdit`/`NotebookEdit` → project-relative path; `Grep`/`Glob` → pattern; `Skill` → skill name; `ToolSearch`/`WebSearch` → query; `WebFetch` → host; anything else → empty. A failure prefixes `failed:` to the detail. Logged in full, no width cap; no `:cost`. |
| `Stop` / `StopFailure`               | `omnilog-stop.ps1`         | `[ts] response - N tool call(s) <Stop:tokens>`, or `[ts] response failed - N tool call(s) <StopFailure:tokens>`. Tokens = summed `output_tokens` for the turn, omitted if unmeasurable. Skipped when `stop_hook_active` is set.                                                                                                                                                                                                          |
| `SubagentStop`                       | `omnilog-subagentstop.ps1` | `[ts] Subagent finished (#id8) <type> <SubagentStop>`; the id and type parts are dropped when the payload lacks them                                                                                                                                                                                                                                                                                                                     |

All scripts read the hook JSON from stdin, append one line, and `exit 0` (never block).
The log path resolves in `omnilog-lib.ps1#Resolve-OmnilogTarget`, highest priority first:
`$env:OMNILOG_ENABLED=off` (kill switch) → `$env:OMNILOG_FILE` (trimmed; the test
override) → `enabled: false` in `.claude/omnilog.local.md` → `scope:` from the same file
(only keys inside the YAML `---` fence count):

- `per-project` (default): `$CLAUDE_PROJECT_DIR/.claude/.omnilog/.omnilog.md`, or the
  same path under `$PWD` when the variable is unset. A project dir that doesn't exist
  means no log.
- `global`: the config's `path:`, else `$CLAUDE_CONFIG_DIR` or `~/.claude`, plus `/omnilog.md`.
- `off`: no log.

The file is created on first write (`Initialize-OmnilogFile`). When its folder is named
`.omnilog`, a `.gitignore` holding `*` is seeded beside it, so the log stays out of git in
any project; a log anywhere else (`OMNILOG_FILE`, `path:`) gets no `.gitignore`.

Verified offline against `evals/fixtures/` before activation: real turn -> summed cost;
empty-turn and synthetic-only turns -> no cost field; agent spawn -> id reference captured.

**Secrets (resolved):** the log stores model-authored _descriptions_, not raw material. Shell/agent
tools log `tool_input.description` (e.g. `Rotate GitHub auth token <Bash>`) — never the
command string; file tools log only the file's path, never content; `WebFetch` logs only
the host; MCP tools and failure `error` text are never logged. So secret _values_ never
reach the log. The per-project log is still git-ignored (its folder's seeded `.gitignore`): it records what was
worked on, which is private even when it holds no secrets.

### Shared lib & tests

All three hooks read stdin as UTF-8 and write through `omnilog-lib.ps1`, the single place
that enforces the log invariants: **ASCII-only** (Unicode transliterated, else stripped to
`?`) and **one line per entry** (whitespace collapsed; never truncated). Verified by atomic tests under
`tests/` (e.g. `ascii-sanitizer.ps1`, `hooks-ascii-output.ps1`; the Stop walk in
`stop-cost.ps1`); `tests/run-all.ps1` discovers and runs them all.
