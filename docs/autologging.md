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

| Field | Meaning |
|-------|---------|
| `session_id` | Unique session identifier |
| `transcript_path` | Absolute path to the conversation JSONL (see §2) |
| `cwd` | Working directory when the hook fired |
| `hook_event_name` | The event that triggered the hook |

Event-specific fields:

| Event | Extra fields | Matcher filters on | Notes |
|-------|-------------|--------------------|-------|
| `PreToolUse`  | `tool_name`, `tool_input` | tool name (e.g. `Edit\|Write`) | Can block a tool call |
| `PostToolUse` | `tool_name`, `tool_input`, `tool_response` | tool name | Fires after each tool call |
| `UserPromptSubmit` | `prompt` | — | stdout **is** injected into context |
| `SessionStart` | `source` (`startup`\|`resume`\|`clear`\|`compact`) | `source` | stdout **is** injected into context |
| `SessionEnd` | `reason` | reason *(claim, unverified)* | |
| `Stop` | `stop_hook_active` (bool) | — (always fires) | Once per assistant response |
| `SubagentStop` | `stop_hook_active` (+ `agent_id`/`agent_type` **[UNVERIFIED]**) | — | Once per subagent finish |

`stop_hook_active` is a loop guard: it is `true` when the Stop hook already forced a
continuation. Only relevant if the hook **blocks** (exit 2). A pure logging hook that
always exits 0 cannot loop, so it can ignore this field. **[DOCS]**

---

## 2. Transcript structure and token cost  **[VERIFIED]**

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

Full `usage` key set, observed **identical across CLI 2.1.118 → 2.1.191** (10 transcripts):
`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`,
`cache_creation` (nested), `server_tool_use` (nested), `service_tier`, `inference_geo`,
`iterations`, `speed`. Path is `.message.usage`; `requestId` is top-level on the line.

### The gotcha that breaks naive implementations

All content-block lines from a single API request **share one `requestId` and repeat
the identical `usage`**. Example: lines with `requestId: req_011CcG...` appeared 4×,
each reporting `output_tokens: 301`. Across the 10-transcript sample, assistant lines
outnumbered distinct requests roughly 2–3×. Summing `output_tokens` across raw lines
multi-counts by the number of content blocks.

**Correct rule for a turn's token cost:**

1. Read the JSONL, walk backward from the end.
2. Keep only lines where top-level `type == "assistant"` — real transcripts are full of
   non-message lines (`attachment`, `file-history-snapshot`, `permission-mode`, `mode`,
   `system`, `ai-title`, `agent-name`, `queue-operation`, `last-prompt`). Skip them.
3. **Exclude `message.model == "<synthetic>"`** — these are locally injected messages,
   not billed API calls. Counting them inflates cost.
4. Collect assistant lines until the last real user prompt (skip `tool_result` user lines — those are mid-turn).
5. **Deduplicate by `requestId`** (one usage record per API request).
6. Sum `output_tokens` (and, if wanted, `input_tokens` + cache fields) across the distinct requests.

A single user turn spans **multiple** `requestId`s — one per tool-use step — so the
turn cost is the sum over all of them, not just the final wrap-up message.

**Empty-turn edge case:** a transcript can contain **zero** assistant lines (aborted /
interrupted turn — seen in the sample). When no assistant usage can be computed, **omit
the token-cost field entirely** (write `<actionType>`, never `:0` or a placeholder) and
still exit 0 — never divide-by-zero or crash.

### Cross-transcript verification  **[CROSS-VERIFIED across 10 projects]**

| Aspect | Result |
|--------|--------|
| CLI versions sampled | 2.1.118, 2.1.138, 2.1.183, 2.1.186, 2.1.187, 2.1.191 |
| Models sampled | sonnet-4-6, haiku-4-5, opus-4-8, `<synthetic>` |
| `usage` key set | identical across all versions above |
| `usage` path | `.message.usage` (nested), consistent |
| Multi-line-per-`requestId` | confirmed wherever a turn had >1 assistant message |
| Fixtures | stored under `evals/fixtures/*.jsonl` (raw) + `evals/readable/*.md` (digest) |

### Stability caveat  **[DOCS]**

Official docs state the transcript format is *internal and may change between versions*.
The sample above is stable, but **all of it is CLI 2.1.x** — no pre-2.1 data was
available, so stability is only established within that band. A logging hook should
fail soft — on any parse failure or schema mismatch, **omit the token-cost field
entirely** (never a placeholder value) rather than crash — and should not hard-assume field names.

---

## 3. `settings.json` registration  **[DOCS]**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "<shell command>" }
        ]
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
  A separate `"args": [...]` array form was claimed by research but is **[UNVERIFIED]** — prefer a single command string.

---

## 4. Windows / PowerShell execution  **[DOCS + LOCAL]**

- On Windows, command hooks run through **Git Bash** (`sh -c "<command>"`) by default.
- To run PowerShell, invoke it explicitly in the command string:

```json
{
  "type": "command",
  "command": "powershell -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/omnilog.ps1\""
}
```

- `$CLAUDE_PROJECT_DIR` is provided as an env var and expands to the project root.
  Forward slashes work with `powershell -File` even on Windows.
- `jq`-based examples are fragile here — jq is not guaranteed present in Git Bash.
  A PowerShell script that reads stdin and parses the transcript with `ConvertFrom-Json` is the robust path on this machine.

---

## 5. Exit codes  **[DOCS]**

| Exit | Effect |
|------|--------|
| `0` | Success. For `Stop`, stdout is **not** injected into context. |
| `2` | Block. For `Stop`, forces Claude to continue (feeds stderr back). **Never use for a logger.** |
| other | Non-blocking error; first stderr line shown in transcript as a hook error. |

A logging hook should **always exit 0** and write to the file directly.

---

## 6. Implications for the `omnilog` component

- **Append-only, immutable log:** the hook only ever *appends*; existing lines are never
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
- **"Every action" (`PostToolUse`) fires per tool call** — noisy by design (fine per the
  logging philosophy). Crucially, for `Bash`/`PowerShell`/`Agent` it CAN log a real summary:
  the model-authored `description` param travels inside `tool_input`, so the hook logs it
  verbatim — no synthesis needed.
- **Resolved — log the model-authored description where it exists; `<toolName>` always:**
  - `Bash`/`PowerShell`/`Agent` → log `tool_input.description` (the one-line summary I wrote
    when calling the tool). Never the raw command — which also keeps secrets out of the log.
  - `Edit`/`Write`/`Read` → filename only (never file content); `Grep`/`Glob` → the pattern.
  - `{actionType}` = the literal tool name; the `:cost` suffix appears only on the `Stop` line.

Sources: `code.claude.com/docs/en/hooks.md`, `hooks-guide.md`, `sessions.md`;
plus direct inspection of `~/.claude/projects/…/19a69f52-*.jsonl` on this machine.

## 7. Implemented (this repo)

Three hooks in `.claude/hooks/`, registered in `.claude/settings.json`:

| Event | Script | Line format |
|-------|--------|-------------|
| `PostToolUse` (all tools) | `omnilog-tool.ps1` | `[ts] <description> <ToolName>` — shell/agent → `tool_input.description` (the summary I wrote, secret-safe); file tools → filename; `Grep`/`Glob` → pattern; Agent → `Spun off new subagent (#id) for <purpose>`. Whole line capped to 78 chars + ellipsis; no `:cost`. |
| `Stop` | `omnilog-stop.ps1` | `[ts] response - N tool call(s) <Stop:tokens>` - tokens = summed output_tokens for the turn, omitted if unmeasurable |
| `SubagentStop` | `omnilog-subagentstop.ps1` | `[ts] subagent <id> (<type>) finished <SubagentStop>` |

All scripts read the hook JSON from stdin, append one line, and `exit 0` (never block).
They honor `$env:OMNILOG_FILE` (test override), else `$CLAUDE_PROJECT_DIR/omnilog.md`.

Verified offline against `evals/fixtures/` before activation: real turn -> summed cost;
empty-turn and synthetic-only turns -> no cost field; agent spawn -> id reference captured.

**Secrets (resolved):** the log stores model-authored *descriptions*, not raw material. Shell/agent
tools log `tool_input.description` (e.g. `Rotate GitHub auth token <Bash>`) — never the
command string; file tools log only the filename, never content. So secret *values* never
reach the log, and `omnilog.md` is safe to track. (Belt-and-suspenders: the repo's
trufflehog / git-diff-check still scan on commit.)

### Shared lib & tests

All three hooks read stdin as UTF-8 and write through `omnilog-lib.ps1`, the single place
that enforces the log invariants: **ASCII-only** (Unicode transliterated, else stripped to
`?`) and **<= 78 chars** (whole line, ASCII `...` ellipsis). Verified by atomic tests under
`tests/` (`ascii-sanitizer.ps1`, `hooks-ascii-output.ps1`); run all with `tests/run-all.ps1`.
