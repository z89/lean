<h1 align="center">lean</h1>

<p align="center">
  <a href="https://github.com/z89/lean/stargazers"><img src="https://img.shields.io/github/stars/z89/lean?style=flat-square&color=a6e3a1&labelColor=1b1a20" alt="stars"></a>
  <a href="https://github.com/z89/lean/commits/main"><img src="https://img.shields.io/github/last-commit/z89/lean?style=flat-square&color=a6e3a1&labelColor=1b1a20" alt="last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/z89/lean?style=flat-square&color=a6e3a1&labelColor=1b1a20" alt="license"></a>
  <img src="https://img.shields.io/badge/claude%20code-hook%20%2B%20skill-a6e3a1?style=flat-square&labelColor=1b1a20" alt="claude code hook and skill">
  <img src="https://img.shields.io/badge/codex%20cli-hook%20%2B%20skill-a6e3a1?style=flat-square&labelColor=1b1a20" alt="codex cli hook and skill">
</p>

lean is a `UserPromptSubmit` hook for claude code and codex cli that adds a token-saving directive to each prompt. it sorts the prompt into one of three tiers, from a direct answer for a quick question to full depth with scoped parallel agents for production or security work. each tier cuts output, narration and file reads, and none of them limit how much the model thinks.

the switch is per session, with a default for sessions that never set their own, and `#lean`, `#deep` and `#par` override the tier for a single prompt. the full directive is sent on a tier change, every eighth prompt and after compaction, with a ten token reminder in between.

## ✨ highlights

- 🎚 **three tiers**: a short answer for quick questions, exact-line reads and minimal diffs for edits, full depth for risky or wide work.
- 🧠 **thinking untouched**: every tier limits what the model writes and reads, never how carefully it reasons.
- 🔍 **targeted reads**: `grep -n` and `sed -n` for the exact lines, filtered command output, one verification per change, no re-reads.
- 🤖 **scoped delegation**: agents only for independent tracks, mechanical and judgment work on different models, the premium model never spawned.
- 🔁 **per-session switch**: on or off for one window, kept through compaction and resume, with a default for new sessions.
- 🪶 **small footprint**: a ten token reminder on most prompts, the full directive only when the tier changes.

## 📦 install

needs `python3` and `jq`.

```sh
git clone git@github.com:z89/lean.git && cd lean && ./install.sh
```

the installer detects claude code and codex cli and asks which to set up. `--claude`, `--codex` or `--all` skip the question, `--adopt` replaces existing files at the target paths with symlinks. `./uninstall.sh` asks the same way and reverses everything.

| harness | enable | skill | hook wiring |
| --- | --- | --- | --- |
| 🤖 claude code | `/lean-always on` | `~/.claude/skills/lean-always` | `~/.claude/settings.json` |
| 🧭 codex cli | `$lean-always on` | `~/.agents/skills/lean-always` | `~/.codex/hooks.json` + `[features] hooks = true` in `config.toml` |

lean is off after install. `lean-always on` turns it on for one session, `lean-always default on` for every session.

## 🤖 models

the hook script is shared by both harnesses. the only difference is which models the directive names for delegated work.

| work | claude code | codex cli |
| --- | --- | --- |
| 🔧 mechanical | sonnet | `gpt-6-luna` |
| 🧩 judgment | opus (Opus 5.5) | `gpt-6-sol` |
| 🚫 never spawned | fable (Fable 5.1) | `gpt-6-astra` |

the session does the planning itself. when a task needs the premium model and the session runs on another one, it says so in one line. codex cannot change reasoning effort from a hook, so set `model_reasoning_effort` in `config.toml` yourself.

## 🎚 commands

`/lean-always on` in one window affects that window only. every other open session and every new one keeps its own setting, and a session's choice survives compaction and resume.

| command | effect |
| --- | --- |
| `lean-always on` / `off` | tiered directive for this session |
| `lean-always status` | this session's switch, plus the default |
| `lean-always default on` / `off` | what sessions that never ran `lean-always on` or `off` get, new ones included |
| `#lean`, `#deep`, `#par` in a prompt | force T0, T2, or T2 plus loading the parallel-orchestration skill |

the hook applies the command from the prompt before the model sees it, so it takes effect on the same turn. on claude code the skill also runs `lean-mode.sh claude set "$CLAUDE_CODE_SESSION_ID" ...`, which changes nothing if the hook already did it.

## 🧮 tiers

| tier | picked when | directive says | injected (first / later) | est. saving per turn |
| --- | --- | --- | --- | --- |
| 🟢 T0 | under 120 chars, no action verb or risk word, or `#lean` | answer from knowledge, open a file only if needed | ~65 / ~10 tokens | 60 to 80% of output, most tool calls gone |
| 🟡 T1 | everything else, any edit or run ask | exact-line reads, minimal diffs, one verify per change, no narration | ~240 / ~10 tokens | 40 to 60% of output and tool tokens |
| 🔴 T2 | production, security, auth, migration, deploy, codebase, parallel, orchestrate, architecture, over 600 chars, `design` / `refactor` / `audit` / `delete` in a prompt over 250 chars, or `#deep` | full depth, agents only for independent tracks, one verifier when a miss is costly, the parallel-orchestration skill for builds with 3 or more tracks | ~390 / ~10 tokens | 20 to 40%, mainly from avoided agent fan-out |

savings are estimates from typical claude code sessions, not benchmarks. sizes are character counts divided by four. `yes`, `ok`, `continue` and other short follow-ups inherit the previous tier.

## 🔍 before and after

| prompt | without | with | est. tokens |
| --- | --- | --- | --- |
| `what does git rebase do` | 400 word explanation with headers, examples, caveats | five bullets, answer first | ~600 to ~150 |
| `fix the null check in user.ts` | reads whole file, explains plan, edits, re-reads, runs full test suite, recaps | `grep -n` the function, one edit, one filtered test run, one line result | ~4k to ~1.2k |
| `refactor auth across the codebase for prod` | 4 to 6 exploratory agents, narrated progress, long summary | one plan, agents matched to independent tracks, one verifier, dense outcome | ~60k to ~25k |
| `ok` (after an edit task) | treated as a fresh question | inherits T1 rules, continues the task | no regression |

## 💾 state

a session's switch lives in `<harness home>/lean-state/<session_id>.always` and the default in `<harness home>/lean.on`. the tier and prompt count sit beside the switch and are cleared on compaction. the first prompt of a session prunes other sessions' tier state idle 14 days and switches idle 60 days. the two harnesses keep separate state.

## 📁 layout

```
hooks/lean-mode.sh      tiering hook (UserPromptSubmit) and per-session switch, takes claude|codex
hooks/lean-compact.sh   clears session tier state, keeps the switch (PreCompact)
claude/skills/          /lean-always
codex/skills/           $lean-always
install.sh uninstall.sh
```

## 📄 license

MIT
