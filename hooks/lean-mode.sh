#!/usr/bin/env bash
# UserPromptSubmit hook for claude code and codex cli (same stdin/stdout contract).
# usage: lean-mode.sh [claude|codex]   default claude
# active while <harness home>/lean.on exists (~/.claude/lean.on or ~/.codex/lean.on).
# tier from the prompt (stdin JSON "prompt"):
#   T0 trivial  - short question, no action/risk words -> ~40-token directive
#   T1 standard - default, and any edit/run ask         -> full lean rules
#   T2 critical - strong risk/scope words, or weak ones on a long ask -> depth + scoped parallelism
# overrides: "#lean" forces T0, "#deep" forces T2.
# per-session state (<harness home>/lean-state/<session_id>): short follow-ups
# inherit the previous tier; the full text is injected only when the tier
# changes or every 8th prompt, else a tiny reminder. lean-compact.sh clears
# the state on PreCompact so the full text returns after compaction; a new
# session prunes state files idle for 14 days.
H="${1:-claude}"
case "$H" in claude) HOME_DIR="$HOME/.claude" ;; codex) HOME_DIR="$HOME/.codex" ;; *) exit 0 ;; esac
[ -f "$HOME_DIR/lean.on" ] || exit 0
LEAN_INPUT=$(cat) LEAN_HARNESS="$H" LEAN_HOME="$HOME_DIR" exec python3 - <<'PY'
import json, os, re, time
try:
    d = json.loads(os.environ.get("LEAN_INPUT", ""))
except Exception:
    d = {}
p = d.get("prompt", "") or ""
sid = re.sub(r"[^A-Za-z0-9_-]", "", d.get("session_id", "") or "") or "default"
low = p.lower()
sdir = os.path.join(os.environ["LEAN_HOME"], "lean-state"); os.makedirs(sdir, exist_ok=True)
sfile = os.path.join(sdir, sid)
prev, n = None, 0
try:
    a, b = open(sfile).read().split(); prev, n = int(a), int(b)
except Exception:
    pass
if prev is None:
    cutoff = time.time() - 14 * 86400
    try:
        for e in os.scandir(sdir):
            if e.is_file() and e.stat().st_mtime < cutoff:
                os.remove(e.path)
    except OSError:
        pass

STRONG = re.compile(r"(\bprod(uction)?\b|\bsecurity\b|\b(?:o?auth[nz]?|authenticat\w*|authori[sz]\w*)\b|\bmigrat\w*|\bdeploy\w*|\brelease\b|\benterprise\b|\bcritical\b|\bcompliance\b|\bdata loss\b|\brm -rf|\barchitect\w*|\borchestrat\w*|\bparallel\w*|\bcodebase\b|\ball files\b|\bthink hard\w*|\bthorough\w*|\bpayment\w*|\bbilling\b)")
WEAK = re.compile(r"\b(design|refactor\w*|audit|important|delete|drop|verify|carefully|deep\w*|multi-file)\b")
ACTION = re.compile(r"(\b(fix|add|change|edit|update|remove|rename|run|write|implement|create|make|build|install|move|replace|patch|apply|commit|test)\b|/[\w.-]+|\.\w{1,4}\b)")
CONT = re.compile(r"^\s*(y|yes|ok|okay|go|do it|continue|next|proceed|sure|yep|apply|go ahead|thanks?)[\s.!]*$")

if "#lean" in low:
    tier = 0
elif "#deep" in low:
    tier = 2
elif CONT.match(low) or len(p) < 30:
    tier = prev if prev is not None else 0
elif STRONG.search(low) or len(p) > 600 or (WEAK.search(low) and len(p) > 250):
    tier = 2
elif len(p) < 120 and not ACTION.search(low):
    tier = 0
else:
    tier = 1
if tier == 0 and ACTION.search(low) and not CONT.match(low) and "#lean" not in low:
    tier = 1

full = prev != tier or n % 8 == 0
try:
    open(sfile, "w").write(f"{tier} {n+1}")
except Exception:
    pass

# the only harness-specific wording: the everyday models, and the rare premium one
if os.environ.get("LEAN_HARNESS") == "codex":
    BASE, JUDGE, TOP = "gpt-6-luna mechanical, gpt-6-sol judgment", "gpt-6-sol", "gpt-6-astra"
else:
    BASE, JUDGE, TOP = "sonnet mechanical, opus (Opus 5.5) judgment", "opus", "fable (Fable 5.1)"

T0 = """[LEAN T0] Answer directly from what you know; open a file only if the answer depends on its contents. High-level summary unless in-depth is requested. Lead with the answer; fragments and bullets; no preamble, recap, or offers. Mark anything unchecked "(unverified)"."""

T1 = f"""[LEAN T1] Reason as much as the problem needs; brevity applies to what you write, not to how carefully you think.
Tools: grep -n / sed -n for the exact lines, filter output (| head -40), batch independent calls in one turn, read a file before speaking about it, no re-reads.
Edits: minimal diff at the asked scope; one filtered verification per change, report its pass/fail line.
Make routine judgment calls yourself; ask only when different readings of the request would lead to materially different work.
Delegate only for large, genuinely independent work you cannot finish in a handful of tool calls ({BASE}; {TOP} only if asked or after {JUDGE} fails the same step twice; worker returns <=15 lines). Never spawn agents to re-check your own work.
Output: outcome first, dense bullets or fragments, code only as changed lines. Keep every finding, tag uncertain ones; cut filler, not content. Mark unchecked claims "(unverified)"; never fabricate to stay short."""

T2 = f"""[LEAN T2 critical] Think fully; this task warrants depth. Brevity applies to writing only.
Parallelism by scope: single-file or sequential work -> do it yourself; multi-file with shared state -> yourself or 1 agent; N genuinely independent tracks -> N agents (cap 5) on disjoint files with interfaces fixed up front, each prompt <=150 words, each returns <=15 lines of conclusion. Add one independent verifier agent only when a wrong result is costly (prod, security, data). Raise thinking before raising agent count. Never spawn agents to re-check your own work. Models: {BASE}. {TOP} is rare: only if asked, for absolutely critical or extremely complex work, or after {JUDGE} fails the same step twice; never mechanical. Before fanning a plan out to 3+ agents, one {TOP} agent reviews it once (accuracy, gaps, interfaces), then cheaper workers execute.
Tools: targeted reads (grep -n / sed -n, | head -40), batch independent calls, read before asserting, no re-reads.
Edits: minimal diffs; one filtered verification per change; state pass/fail.
Make routine judgment calls yourself; ask only when different readings would lead to materially different work.
Output: outcome first, dense; every finding kept with a confidence tag; no padding, no recap. Mark unchecked claims "(unverified)". If blocked, one line: blocker + cheapest next step."""

text = (T0, T1, T2)[tier] if full else f"[LEAN T{tier} on, rules above still apply]"
# JSON output on both harnesses: codex sniffs a leading "[" as JSON and rejects plain text
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}))
PY
