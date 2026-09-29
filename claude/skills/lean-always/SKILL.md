---
name: lean-always
description: Toggle tiered lean mode for this session. Use when the user invokes /lean-always, /lean-always on, /lean-always off, /lean-always status, or /lean-always default on|off.
argument-hint: [on|off|status|default on|default off]
allowed-tools: Bash
---

# /lean-always

The UserPromptSubmit hook has normally applied this command already and put a `[LEAN] this session: ...` status line in this turn's context. If it is there, reply with that line, minus the `[LEAN]` tag, and nothing else. Do not run anything.

Only if no such line is present, run this once and reply with its output line or its error:

`bash ~/.claude/hooks/lean-mode.sh claude set "$CLAUDE_CODE_SESSION_ID" always $ARGUMENTS`

Empty `$ARGUMENTS` means `on`. Never guess a session id.

- `on` and `off` apply to this session only and survive compaction and `--resume`. Stored in `~/.claude/lean-state/<session_id>.always`.
- `default on|off` sets what every session without its own choice uses, open ones included. Stored as `~/.claude/lean.on`.
- In a prompt, `#lean` forces the minimal tier, `#deep` the full-depth tier, and `#par` full depth plus loading the parallel-orchestration skill.
- Codex keeps separate switches under `~/.codex`.
