#!/usr/bin/env bash
# UserPromptSubmit hook for claude code and codex cli (same stdin/stdout contract).
# usage: lean-mode.sh [claude|codex]                          hook mode, reads stdin JSON
#        lean-mode.sh [claude|codex] set <session_id> always [args]   toggle, prints status
# one per-session switch, <harness home>/lean-state/<session_id>.always: the tiered
# directive on every prompt of that session. the file holds on or off; a session
# with no file follows the default, <harness home>/lean.on (lean-always default on|off).
# the hook applies "/lean-always on|off|status|default on|off" (or $lean-always on
# codex) itself, from the prompt, before the model runs.
# tier from the prompt (stdin JSON "prompt"):
#   T0 trivial  - short question, no action/risk words -> ~40-token directive
#   T1 standard - default, and any edit/run ask         -> full lean rules
#   T2 critical - strong risk/scope words, or weak ones on a long ask -> depth + scoped parallelism
# overrides: "#lean" forces T0, "#deep" forces T2.
# per-session tier state (<harness home>/lean-state/<session_id>): short follow-ups
# inherit the previous tier; the full text is injected only when the tier or mode
# changes or every 8th prompt, else a tiny reminder. lean-compact.sh clears
# the tier state on PreCompact so the full text returns after compaction; a new
# session prunes state files idle for 14 days.
H="${1:-claude}"
case "$H" in claude) HOME_DIR="$HOME/.claude" ;; codex) HOME_DIR="$HOME/.codex" ;; *) exit 0 ;; esac
IN=
if [ "${2:-}" != set ]; then
  IN=$(cat)
  sid=$(printf '%s' "$IN" | sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_-]*\)".*/\1/p' | head -1)
  S="$HOME_DIR/lean-state/${sid:-default}"
  # fast exit: nothing on for this session and no toggle command in the prompt
  [ -f "$HOME_DIR/lean.on" ] || [ -f "$S.always" ] || case "$IN" in *lean*) ;; *) exit 0 ;; esac
fi
LEAN_INPUT="$IN" LEAN_HARNESS="$H" LEAN_HOME="$HOME_DIR" exec python3 - "${@:2}" <<'PY'
import json, os, re, sys, time
HOME, HARNESS = os.environ["LEAN_HOME"], os.environ["LEAN_HARNESS"]
sdir, DEFAULT = os.path.join(HOME, "lean-state"), os.path.join(HOME, "lean.on")
SIGIL = "$" if HARNESS == "codex" else "/"

def clean(x):
    return re.sub(r"[^A-Za-z0-9_-]", "", x or "")

def flag(sid, mode):  # this session's own choice, else the default (lean-always only)
    try:
        return open(os.path.join(sdir, f"{sid}.{mode}")).read().strip() == "on"
    except OSError:
        return mode == "always" and os.path.exists(DEFAULT)

def apply(sid, mode, arg):  # False when arg is not a toggle
    arg = " ".join(arg.split()).lower() or "on"
    if arg in ("on", "off"):
        os.makedirs(sdir, exist_ok=True)
        with open(os.path.join(sdir, f"{sid}.{mode}"), "w") as f:
            f.write(arg + "\n")
    elif mode == "always" and arg in ("default on", "default off"):
        if arg == "default on":
            open(DEFAULT, "a").close()
        elif os.path.exists(DEFAULT):
            os.remove(DEFAULT)
    elif arg != "status":
        return False
    return True

def status(sid):
    o = lambda b: "ON" if b else "OFF"
    return (f"[LEAN] this session: lean-always {o(flag(sid, 'always'))}. "
            f"other open sessions are unaffected. new sessions start with lean-always "
            f"{o(os.path.exists(DEFAULT))} ({SIGIL}lean-always default on|off).")

def emit(text):
    # JSON output on both harnesses: codex sniffs a leading "[" as JSON and rejects plain text
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}))

MODES = {"lean-always": "always"}
def parse(p):  # the toggle command, if the prompt is one
    m = re.match(r"\s*(?:<command-message>[^<]*</command-message>\s*)?<command-name>/(lean-always)</command-name>", p)
    if m:
        a = re.search(r"<command-args>(.*?)</command-args>", p, re.S)
        return MODES[m.group(1)], a.group(1) if a else ""
    m = re.match(r"\s*(?:\[\$(lean-always)\]\([^)]*\)|[/$](lean-always))(?=\s|$)(.*)", p, re.S)
    if m:
        return MODES[m.group(1) or m.group(2)], m.group(3)
    return None

# set mode, run by the skill: lean-mode.sh <harness> set <session_id> always [args]
if len(sys.argv) > 1 and sys.argv[1] == "set":
    sid = clean(sys.argv[2] if len(sys.argv) > 2 else "")
    mode = sys.argv[3] if len(sys.argv) > 3 else ""
    if not sid or mode != "always":
        sys.exit("usage: lean-mode.sh [claude|codex] set <session_id> always [on|off|status|default on|default off]")
    if not apply(sid, mode, " ".join(sys.argv[4:])):
        sys.exit("unknown argument; use on, off, status, default on or default off")
    print(status(sid))
    sys.exit()

try:
    d = json.loads(os.environ.get("LEAN_INPUT", ""))
except Exception:
    d = {}
p = d.get("prompt", "") or ""
sid = clean(d.get("session_id")) or "default"
low = p.lower()
sfile = os.path.join(sdir, sid)

cmd = parse(p)
note = status(sid) + " relay this line to the user in one line." if cmd and apply(sid, *cmd) else ""
if not flag(sid, "always"):
    try:
        os.remove(sfile)  # so the full text is injected when a mode is turned back on
    except OSError:
        pass
    if note:
        emit(note)
    sys.exit()

os.makedirs(sdir, exist_ok=True)
try:  # keep this session's switch clear of the idle prune
    os.utime(f"{sfile}.always")
except OSError:
    pass
prev, n = None, 0
try:
    f = open(sfile).read().split(); prev, n = int(f[0]), int(f[1])
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

full = bool(note) or prev != tier or n % 8 == 0
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
emit(note + "\n" + text if note else text)
PY
