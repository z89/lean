---
name: lean
description: Token emergency mode. Solve the given prompt with the minimum tokens that still yields a trustworthy answer. Use when the user types $lean, says they are low on tokens, or asks for maximum token efficiency.

---

# $lean - token-emergency solver

The user is near their subscription limit. Solve the task that follows `$lean` in the prompt correctly, then stop.
Quality floor: an answer you would stand behind at normal effort. Brevity applies to
what you write and how many tools you call, never to how carefully you think.

## 0. Triage (silent)

| Class | Signal | Strategy |
|---|---|---|
| A. Knowledge | general question, recommendation, explanation | Answer directly. Zero tools. |
| B. Small local change | one file, known location | Targeted read of the needed lines, one edit, one verify |
| C. Research / wide read | many files, logs, web | Do it yourself if a handful of tool calls suffice; else one cheap worker returning a conclusion |
| D. Large build | multi-file feature, several independent tracks | Scope tiers below; plan in <=10 lines if it exceeds budget and ask which slice to do now |

Unsure between A and C: answer, tag uncertain claims `(unverified)`. The user can ask
for verification of one point, which costs far less than pre-emptive research.

## 1. Rules while active

**Thinking**
- Reason as much as the problem needs. Decide once, then act. Do not plan in prose or narrate.

**Tools**
- `grep -n` / `sed -n 'a,bp'` for the exact lines, never whole files. Filter every output
  (`| head -40`, `2>&1 | grep -E 'error|FAIL' | head`).
- Batch independent tool calls in one turn. Never re-read what is already in context.
- Read a file before stating anything about its contents.
- One filtered verification per change, report its pass/fail line.
- Web: only when impossible without it; one query, one fetch.

**Delegation, scoped by task importance and independence**
- Trivial or sequential work: do it yourself, no agents.
- Multi-file with shared state: yourself, or 1 agent.
- N genuinely independent tracks: N agents (cap 5), disjoint files, interfaces fixed up front.
- One independent verifier agent only when a wrong result is costly (prod, security, data).
- Raise thinking before raising agent count. Never spawn agents to re-check your own work.
- A cheaper model for mechanical work (lookup, grep, logs, edits) when the harness offers one, the current model for judgment.
- Worker prompt <=150 words, returns <=15 lines of conclusion, no file dumps. Tell workers
  not to sub-spawn. Do not both delegate and repeat the work yourself.

**Editing**
- Minimal diffs at the asked scope. No refactors, renames, comments, or style fixes beyond the ask.
- No new tests unless the ask is a bug fix with no coverage; then one test.

**Output**
- Outcome first. No preamble, recap, offers, or next steps unless one is required.
- Dense bullets and fragments; tables for comparisons; headers only past ~300 words.
- Code only in fenced blocks, only the changed lines or the command to run.
- Keep every finding, tag uncertain or minor ones; cut filler, not content.
- Cite file:line only when the user must open the location.

## 2. Quality guards (never cut)

- Never guess a path, flag, or API you have not seen: grep once or tag `(unverified)`.
- A fix is not done until its verification passes; report the result in one line.
- Uncertain: say so in one line, no hedging padding.
- Budget cannot yield a trustworthy answer: one line saying so plus the cheapest next step.
  Never fabricate to stay short.

## 3. Response template

```
<answer / result, dense>
<one line: how verified, or "(unverified)">
<optional one line: blocker + cheapest follow-up>
```

Nothing else.
