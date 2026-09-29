---
name: lean-always
description: Toggle tiered lean mode for this session. Use when the user invokes $lean-always, $lean-always on, $lean-always off, $lean-always status, or $lean-always default on|off.
---

# $lean-always

The UserPromptSubmit hook has normally applied this command already and put a `[LEAN] this session: ...` status line in this turn's context. If it is there, reply with that line, minus the `[LEAN]` tag, and nothing else. Do not run anything, and do not reuse a status from an earlier turn.

Only if no such line is present, run this once and reply with its output line or its error:

`bash ~/.codex/hooks/lean-mode.sh codex set "$CODEX_THREAD_ID" always <argument>`

An empty argument means `on`. Never guess a session id; if the thread id or the hook is missing, report that.

- `on` and `off` apply to this session only and survive compaction and resume. Stored in `~/.codex/lean-state/<session_id>.always`.
- `default on|off` sets what every session without its own choice uses, open ones included. Stored as `~/.codex/lean.on`.
- In a prompt, `#lean` forces the minimal tier, `#deep` the full-depth tier, and `#par` full depth plus loading the parallel-orchestration skill.
- The hook changes guidance only. It cannot change the model or the reasoning effort; set `model_reasoning_effort` in `config.toml`.
- Claude Code keeps separate switches under `~/.claude`.
