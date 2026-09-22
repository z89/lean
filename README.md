# lean

a `UserPromptSubmit` hook for claude code and codex cli that sizes a token-saving directive to each prompt. it cuts output, narration and file reads, never thinking. two skills ride along: `lean-always on|off|status` toggles it, `lean <prompt>` runs one prompt leanly.

## install

needs `python3` and `jq`.

```sh
git clone git@github.com:z89/lean.git && cd lean && ./install.sh
```

the installer detects claude code and codex cli and asks which to set up. `--claude`, `--codex` or `--all` skip the question, `--adopt` replaces existing files at the target paths with symlinks. `./uninstall.sh` asks the same way and reverses everything.

| harness | enable | skills | hook wiring |
| --- | --- | --- | --- |
| claude code | `/lean-always on` | `~/.claude/skills/lean`, `lean-always` | `~/.claude/settings.json` |
| codex cli | `$lean-always on` | `~/.agents/skills/lean`, `lean-always` | `~/.codex/hooks.json` + `[features] hooks = true` in `config.toml` |

the hook script is shared; only the delegation wording differs (sonnet/opus names for claude, generic for codex). codex cannot change reasoning effort from a hook, so set `model_reasoning_effort` in `config.toml` yourself.

## scope

the toggle is global per harness, not per session. `~/.claude/lean.on` (or `~/.codex/lean.on`) is a single flag file and the hook checks it on every prompt, so turning it off in one window turns it off in every other open session at its next prompt, and in every session you start later. it stays off until you turn it back on, restarts included. there is no per-session switch: use `#lean` or `#deep` to force a tier for one prompt. the two harnesses keep separate flags and do not affect each other.

## tiers

| tier | picked when | directive says | injected (first / later) | est. saving per turn |
| --- | --- | --- | --- | --- |
| T0 | under 120 chars, no action verb or risk word, or `#lean` | answer from knowledge, open a file only if needed | ~45 / ~10 tokens | 60 to 80% of output, most tool calls gone |
| T1 | everything else, any edit or run ask | exact-line reads, minimal diffs, one verify per change, no narration | ~170 / ~10 tokens | 40 to 60% of output and tool tokens |
| T2 | production, security, auth, migration, deploy, codebase, parallel, orchestrate, architecture, over 600 chars, or `#deep` | full depth, agents only for independent tracks (cap 5), one verifier when a miss is costly | ~230 / ~10 tokens | 20 to 40%, mainly from avoided agent fan-out |

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
hooks/lean-mode.sh      tiering hook (UserPromptSubmit), takes claude|codex
hooks/lean-compact.sh   clears session state (PreCompact)
claude/skills/          /lean, /lean-always
codex/skills/           $lean, $lean-always
install.sh uninstall.sh
```

## license

MIT
