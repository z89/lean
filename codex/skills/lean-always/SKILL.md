---
name: lean-always
description: Toggle tiered lean mode for this codex session only. While on, a hook injects a tiered token-saving directive on every prompt of this session. Use when the user types $lean-always, $lean-always on, $lean-always off, $lean-always status, or $lean-always default on|off.
---

# $lean-always

Switch: `~/.codex/lean-state/<session_id>.always` (on or off). Default for sessions that never toggled: `~/.codex/lean.on`. Hook: `~/.codex/hooks/lean-mode.sh` (UserPromptSubmit, wired in `~/.codex/hooks.json`).

Scope: `on` and `off` apply to this session only; other open sessions and new ones are unaffected, and the choice survives compaction and resume. `default on|off` sets what sessions without their own choice use, new ones included. `#lean` or `#deep` force a tier for a single prompt. The claude code switches under `~/.claude` are separate.

The argument is whatever follows `$lean-always` in the prompt (empty means `on`; valid: `on`, `off`, `status`, `default on`, `default off`). The hook has already applied it before this turn and injected a `[LEAN] this session: ...` line: reply with that line (minus the tag) and nothing else.

Only if no such line is in context (hook not wired), run `bash ~/.codex/hooks/lean-mode.sh codex set "$CODEX_THREAD_ID" always <argument>` and reply with its output line. If `CODEX_THREAD_ID` is empty, say the hook is not installed and to run `./install.sh --codex`.

## How the hook tiers (for reference, do not repeat to the user)

- T0 trivial: prompt under 120 chars with no action or risk words. Answer from knowledge, minimal output.
- T1 standard: everything else. Full reasoning, targeted reads, minimal diffs, dense output, agents only for large independent work.
- T2 critical: risk or scope words (prod, security, auth, migration, deploy, refactor, codebase, parallel, design, thorough, deep...) or prompt over 600 chars. Full depth, parallel agents scoped to the number of genuinely independent tracks (cap 5), optional single verifier when a wrong result is costly.
- `#lean` anywhere in a prompt forces T0, `#deep` forces T2.
- Agent models: `gpt-6-luna` mechanical, `gpt-6-sol` judgment. `gpt-6-astra` is rare: when asked, for absolutely critical or extremely complex work, after `gpt-6-sol` fails a step twice, and one review of any plan fanning out to 3+ agents.
- Every tier keeps: read before asserting, never fabricate to stay short, keep all findings (cut filler not content).
- Reasoning effort cannot be changed per turn from a hook in codex; set `model_reasoning_effort` in `~/.codex/config.toml` or `/model` for that.

While this session's switch is on, this very turn is already lean: obey the injected directive. No other output.
