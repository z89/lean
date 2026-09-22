---
name: lean-always
description: Toggle persistent lean mode. A hook then injects a tiered token-saving directive on every prompt in every session until turned off. Use when the user invokes /lean-always, /lean-always on, /lean-always off, or /lean-always status.
argument-hint: [on|off|status]
allowed-tools: Bash
---

# /lean-always

Flag file: `~/.claude/lean.on`. Hook: `~/.claude/hooks/lean-mode.sh` (UserPromptSubmit).

Scope: the flag is global to claude code, not per session. `on` and `off` take effect in every open session at its next prompt and in every session started later, and persist across restarts. There is no per-session toggle; `#lean` or `#deep` force a tier for a single prompt. `~/.codex/lean.on` is a separate flag and is not affected.

Run exactly one command based on `$ARGUMENTS` (default: `on`), then reply in one line.

- `on`: `touch ~/.claude/lean.on` -> reply `lean mode ON (every prompt, all sessions). tiers: T0 trivial / T1 standard / T2 critical, auto-picked per prompt; force with #lean or #deep. /lean-always off to disable.`
- `off`: `rm -f ~/.claude/lean.on` -> reply `lean mode OFF (all sessions, this harness).`
- `status`: `test -f ~/.claude/lean.on && echo ON || echo OFF` -> reply with the result plus the tier line above if ON, noting it is global to claude code.

## How the hook tiers (for reference, do not repeat to the user)

- T0 trivial: prompt under 120 chars with no risk words. Answer from knowledge, minimal output.
- T1 standard: everything else. Full thinking, targeted reads, minimal diffs, dense output, <=2 agents only for independent large work.
- T2 critical: risk or scope words (prod, security, auth, migration, deploy, refactor, codebase, parallel, design, thorough, deep...) or prompt over 600 chars. Full depth, parallel agents scoped to the number of genuinely independent tracks (cap 5), optional single verifier when a wrong result is costly.
- `#lean` anywhere in a prompt forces T0, `#deep` forces T2.
- Every tier keeps: read before asserting, never fabricate to stay short, keep all findings (cut filler not content).

While the flag is on, this very turn is already lean: obey the injected directive. No other output.
