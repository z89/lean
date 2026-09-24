---
name: lean-always
description: Toggle tiered lean mode for this session only. While on, a hook injects a tiered token-saving directive on every prompt of this session. Use when the user invokes /lean-always, /lean-always on, /lean-always off, /lean-always status, or /lean-always default on|off.
argument-hint: [on|off|status|default on|default off]
allowed-tools: Bash
---

# /lean-always

Switch: `~/.claude/lean-state/<session_id>.always` (on or off). Default for sessions that never toggled: `~/.claude/lean.on`. Hook: `~/.claude/hooks/lean-mode.sh` (UserPromptSubmit).

Scope: `on` and `off` apply to this session only; other open sessions and new ones are unaffected, and the choice survives compaction and `--resume`. `default on|off` sets what sessions without their own choice use, new ones included. `#lean` or `#deep` force a tier for a single prompt. The codex switches under `~/.codex` are separate.

Run exactly one command, then reply with its output line (minus the `[LEAN]` tag) and nothing else:

`bash ~/.claude/hooks/lean-mode.sh claude set "$CLAUDE_CODE_SESSION_ID" always $ARGUMENTS`

Empty `$ARGUMENTS` means `on`. If the command exits non-zero, relay its error line. The hook usually applies the same change from the prompt before this turn; running it again is harmless.

## How the hook tiers (for reference, do not repeat to the user)

- T0 trivial: prompt under 120 chars with no risk words. Answer from knowledge, minimal output.
- T1 standard: everything else. Full thinking, targeted reads, minimal diffs, dense output, <=2 agents only for independent large work.
- T2 critical: risk or scope words (prod, security, auth, migration, deploy, refactor, codebase, parallel, design, thorough, deep...) or prompt over 600 chars. Full depth, parallel agents scoped to the number of genuinely independent tracks (cap 5), optional single verifier when a wrong result is costly.
- `#lean` anywhere in a prompt forces T0, `#deep` forces T2.
- Agent models: sonnet mechanical, opus (Opus 5.5) judgment. fable (Fable 5.1) is rare: when asked, for absolutely critical or extremely complex work, after opus fails a step twice, and one review of any plan fanning out to 3+ agents.
- Every tier keeps: read before asserting, never fabricate to stay short, keep all findings (cut filler not content).

While this session's switch is on, this very turn is already lean: obey the injected directive. No other output.
