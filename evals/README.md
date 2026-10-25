# evals/ — Real transcript fixtures for the autologging hook

Test corpus for building and regression-testing the `omnilog` autologging hook
(design: [`../docs/autologging.md`](../docs/autologging.md)). These are **real** Claude
Code session transcripts captured from this machine, used to validate the token-cost
parser against actual data across CLI versions.

## Layout

- `fixtures/*.jsonl` — exact raw copies of session transcripts (the true parser input).
- `readable/*.md` — human-readable digests: one row per JSONL line
  (timestamp · type · model · token usage · content preview).
- Both folders are **git-ignored** — transcripts originate from *other* projects and may
  contain secrets / PII (trufflehog is enabled here). Only this README is tracked.

## Provenance

10 sessions, one per project, chosen to span CLI versions and models:

| Fixture | CLI ver | Model(s) | Lines | Asst / distinct reqId | Note |
|---------|---------|----------|-------|-----------------------|------|
| `playground__dcc73aa6` | 2.1.118 | sonnet-4-6, haiku-4-5, synthetic | 210 | 27 / 12 | oldest |
| `claude-test__7c808837` | 2.1.138 | sonnet-4-6 | 25 | 9 / 5 | |
| `skill-rental-car-quote__79f08151` | 2.1.183 | sonnet-4-6, synthetic | 58 | 8 / 3 | |
| `C--Users-jared__ccd45309` | 2.1.183 | sonnet-4-6 | 63 | 8 / 4 | |
| `tidy-up...__cd04643d` | 2.1.183 | opus-4-8 | 12 | 2 / 1 | |
| `rgspt-site__023d1190` | 2.1.183 | haiku-4-5 | 62 | 21 / 7 | |
| `physicaltherapist...__89bb5109` | 2.1.187 | (none) | 10 | 0 / 0 | **empty-turn edge case** |
| `skill-jagp...__d7093b8d` | 2.1.191 | opus-4-8 | 47 | 13 / 5 | |
| `rgspt-webroot...__132c708c` | 2.1.186 | haiku-4-5 | 192 | 83 / 32 | largest |
| `dev-strap__088ffe19` | 2.1.183 | synthetic | 20 | 1 / 1 | synthetic-only |

## What these fixtures verify

A correct turn-cost parser must:

1. **Filter to top-level `type == "assistant"`** — skip `attachment`,
   `file-history-snapshot`, `permission-mode`, `mode`, `system`, `ai-title`,
   `agent-name`, `queue-operation`, `last-prompt`.
2. **Read usage at `.message.usage`** — key set stable across 2.1.118 → 2.1.191:
   `input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens,
   cache_creation, server_tool_use, service_tier, inference_geo, iterations, speed`.
3. **Dedupe by top-level `requestId`** — content blocks of one API request repeat
   identical usage; raw-summing multi-counts (see the Asst / distinct-reqId column).
4. **Exclude `message.model == "<synthetic>"`** — locally injected, not a billed call.
5. **Handle the empty-turn fixture** (`physicaltherapist...__89bb5109`, 0 assistant
   lines) by emitting **no** cost field — never crash, never a placeholder.

## Refreshing

Fixtures are point-in-time. To update, re-copy from
`~/.claude/projects/<project>/<session>.jsonl` and regenerate the digest. Keep the
version/model spread wide so schema drift stays visible.
