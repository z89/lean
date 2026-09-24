# lean

a `UserPromptSubmit` hook for claude code and codex cli that sizes a token-saving directive to each prompt. it cuts output, narration and file reads, never thinking. one skill rides along: `lean-always on|off|status` turns it on or off for the current session.

## install

needs `python3` and `jq`.

```sh
git clone git@github.com:z89/lean.git && cd lean && ./install.sh
```

the installer detects claude code and codex cli and asks which to set up. `--claude`, `--codex` or `--all` skip the question, `--adopt` replaces existing files at the target paths with symlinks. `./uninstall.sh` asks the same way and reverses everything.

| harness | enable | skills | hook wiring |
| --- | --- | --- | --- |
| claude code | `/lean-always on` | `~/.claude/skills/lean-always` | `~/.claude/settings.json` |
| codex cli | `$lean-always on` | `~/.agents/skills/lean-always` | `~/.codex/hooks.json` + `[features] hooks = true` in `config.toml` |

the hook script is shared; only the delegation wording differs: claude hands mechanical work to sonnet and judgment to opus (Opus 5.5); codex uses `gpt-6-luna` and `gpt-6-sol`. the premium model (fable (Fable 5.1) on claude, `gpt-6-astra` on codex) is rare: only when asked, for absolutely critical or extremely complex work, after the judgment model fails the same step twice, and for one review of any plan that fans out to 3+ agents before the cheaper workers start. codex cannot change reasoning effort from a hook, so set `model_reasoning_effort` in `config.toml` yourself.

## scope

the switch is per session. `/lean-always on` in one window affects that window only; every other open session and every new one keeps its own setting. a session's choice survives compaction and resume.

| command | effect |
| --- | --- |
| `lean-always on` / `off` | tiered directive for this session |
| `lean-always status` | this session's switch, plus the default |
| `lean-always default on` / `off` | what sessions that never ran `lean-always on` or `off` get, new ones included |
| `#lean`, `#deep` in a prompt | force T0 or T2 for that prompt only |

the hook applies the command from the prompt before the model sees it, so it works on the same turn. on claude code the skill also runs `lean-mode.sh claude set "$CLAUDE_CODE_SESSION_ID" ...` directly, which is a no-op if the hook already did it. the switch lives in `<harness home>/lean-state/<session_id>.always`, the default in `<harness home>/lean.on`. the two harnesses keep separate state and do not affect each other.

## tiers

| tier | picked when | directive says | injected (first / later) | est. saving per turn |
| --- | --- | --- | --- | --- |
| T0 | under 120 chars, no action verb or risk word, or `#lean` | answer from knowledge, open a file only if needed | ~45 / ~10 tokens | 60 to 80% of output, most tool calls gone |
| T1 | everything else, any edit or run ask | exact-line reads, minimal diffs, one verify per change, no narration | ~180 / ~10 tokens | 40 to 60% of output and tool tokens |
| T2 | production, security, auth, migration, deploy, codebase, parallel, orchestrate, architecture, over 600 chars, or `#deep` | full depth, agents only for independent tracks (cap 5), one verifier when a miss is costly, one premium review of any plan fanning out to 3+ agents | ~290 / ~10 tokens | 20 to 40%, mainly from avoided agent fan-out |

savings are estimates from typical claude code sessions, not benchmarks. the full text is injected on a tier change and every eighth prompt, a ten token reminder otherwise, and again after compaction. `yes`, `ok`, `continue` and other short follow-ups inherit the previous tier.

## before and after

| prompt | without | with | est. tokens |
| --- | --- | --- | --- |
| `what does git rebase do` | 400 word explanation with headers, examples, caveats | five bullets, answer first | ~600 to ~150 |
| `fix the null check in user.ts` | reads whole file, explains plan, edits, re-reads, runs full test suite, recaps | `grep -n` the function, one edit, one filtered test run, one line result | ~4k to ~1.2k |
| `refactor auth across the codebase for prod` | 4 to 6 exploratory agents, narrated progress, long summary | one plan, agents matched to independent tracks, one verifier, dense outcome | ~60k to ~25k |
| `ok` (after an edit task) | treated as a fresh question | inherits T1 rules, continues the task | no regression |

## layout

```
hooks/lean-mode.sh      tiering hook (UserPromptSubmit) and per-session switch, takes claude|codex
hooks/lean-compact.sh   clears session tier state, keeps the switch (PreCompact)
claude/skills/          /lean-always
codex/skills/           $lean-always
install.sh uninstall.sh
```

## license

MIT
