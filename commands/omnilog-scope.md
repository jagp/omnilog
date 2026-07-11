---
name: omnilog-scope
description: Choose where omnilog writes (per-project / global / off) for this project.
---

Ask the user which logging scope they want for this project, then write
`.claude/omnilog.local.md` accordingly. Use AskUserQuestion with these options:

- **per-project** (default): log to `omnilog.md` in this repo root. Requires the
  marker file `omnilog.md` to exist (create it if the user picks this and it is missing).
- **global**: log to one shared file across all projects. Ask for a path; default to
  `%USERPROFILE%\.claude\omnilog.md` if they have no preference.
- **off**: disable omnilog for this project.

Write the file as YAML frontmatter, e.g. for global:

    ---
    scope: global
    path: C:\Users\<name>\.claude\omnilog.md
    ---

For per-project or off, write just the `scope:` line (omit `path:`). Then remind the
user that hook changes take effect on the next Claude Code session (restart required),
and that `.claude/*.local.md` is git-ignored.
