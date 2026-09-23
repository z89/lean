---
name: lean-always
description: Toggle persistent lean mode for codex. A hook then injects a tiered token-saving directive on every prompt in every session until turned off. Use when the user types $lean-always, $lean-always on, $lean-always off, or $lean-always status.
---

# $lean-always

Flag file: `~/.codex/lean.on`. Hook: `~/.codex/hooks/lean-mode.sh` (UserPromptSubmit, wired in `~/.codex/hooks.json`).

Scope: the flag is global to codex, not per session. `on` and `off` take effect in every open session at its next prompt and in every session started later, and persist across restarts. There is no per-session toggle; `#lean` or `#deep` force a tier for a single prompt. `~/.claude/lean.on` is a separate flag and is not affected.

The argument is whatever follows `$lean-always` in the prompt (default: `on`). Run exactly one command, then reply in one line.

- `on`: `touch ~/.codex/lean.on` -> reply `lean mode ON (every prompt, all sessions). tiers: T0 trivial / T1 standard / T2 critical, auto-picked per prompt; force with #lean or #deep. $lean-always off to disable.`
- `off`: `rm -f ~/.codex/lean.on` -> reply `lean mode OFF (all sessions, this harness).`
- `status`: `test -f ~/.codex/lean.on && echo ON || echo OFF` -> reply with the result plus the tier line above if ON, noting it is global to codex.

## How the hook tiers (for reference, do not repeat to the user)

- T0 trivial: prompt under 120 chars with no action or risk words. Answer from knowledge, minimal output.
- T1 standard: everything else. Full reasoning, targeted reads, minimal diffs, dense output, agents only for large independent work.
- T2 critical: risk or scope words (prod, security, auth, migration, deploy, refactor, codebase, parallel, design, thorough, deep...) or prompt over 600 chars. Full depth, parallel agents scoped to the number of genuinely independent tracks (cap 5), optional single verifier when a wrong result is costly.
- `#lean` anywhere in a prompt forces T0, `#deep` forces T2.
- Agent models: `gpt-6-luna` mechanical, `gpt-6-sol` judgment. `gpt-6-astra` is rare: when asked, for absolutely critical or extremely complex work, after `gpt-6-sol` fails a step twice, and one review of any plan fanning out to 3+ agents.
- Every tier keeps: read before asserting, never fabricate to stay short, keep all findings (cut filler not content).
- Reasoning effort cannot be changed per turn from a hook in codex; set `model_reasoning_effort` in `~/.codex/config.toml` or `/model` for that.

While the flag is on, this very turn is already lean: obey the injected directive. No other output.
