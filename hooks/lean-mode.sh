#!/usr/bin/env bash
# UserPromptSubmit hook for claude code and codex cli (same stdin/stdout contract).
# usage: lean-mode.sh [claude|codex]                          hook mode, reads stdin JSON
#        lean-mode.sh [claude|codex] set <session_id> always [args]   toggle, prints status
# root: $CLAUDE_HOME / $CODEX_HOME, else ~/.claude / ~/.codex. per-session
# switch <root>/lean-state/<session_id>.always holds on or off; a session without one
# follows the default, <root>/lean.on (lean-always default on|off). the hook applies
# "/lean-always on|off|status|default on|off" ($lean-always on codex) from the prompt.
# input: JSON object, string prompt, session_id [A-Za-z0-9_-]+; else ignored.
# tier from the prompt:
#   T0 trivial  - short question, no action/risk words -> ~40-token directive
#   T1 standard - default, and any edit/run ask         -> full lean rules
#   T2 critical - risk/scope words, or weak ones on a long ask -> depth + scoped parallelism
# overrides, whole tokens anywhere: "#lean" T0, "#deep" T2, "#par" T2 + orchestration skill.
# tier state <root>/lean-state/<session_id>: continuations inherit the tier; the full
# text only on tier/mode change or every 8th prompt, else a reminder. lean-compact.sh
# clears it on PreCompact. a session's first lean prompt prunes other sessions' tier
# caches idle 14 days and .always files idle 60 days. state writes are atomic.
H="${1:-claude}"
case "$H" in claude) HOME_DIR="${CLAUDE_HOME:-$HOME/.claude}" ;; codex) HOME_DIR="${CODEX_HOME:-$HOME/.codex}" ;; *) exit 0 ;; esac
IN=
if [ "${2:-}" != set ]; then
  IN=$(cat)
  sid=$(printf '%s' "$IN" | sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_-]*\)".*/\1/p' | head -1)
  # fast exit only for a known session with nothing on and no toggle command in the prompt
  if [ -n "$sid" ] && [ ! -f "$HOME_DIR/lean.on" ] && [ ! -f "$HOME_DIR/lean-state/$sid.always" ]; then
    case "$IN" in *lean*) ;; *) exit 0 ;; esac
  fi
fi
# the input goes to python on fd 3: an environment variable over ~128 KB makes exec fail
LEAN_HARNESS="$H" LEAN_HOME="$HOME_DIR" exec python3 - "${@:2}" 3< <(printf '%s' "$IN") <<'PY'
import json, os, re, sys, tempfile, time
HOME, HARNESS = os.environ["LEAN_HOME"], os.environ["LEAN_HARNESS"]
sdir, DEFAULT = os.path.join(HOME, "lean-state"), os.path.join(HOME, "lean.on")
SIGIL = "$" if HARNESS == "codex" else "/"
SID = re.compile(r"[A-Za-z0-9_-]+")

def valid(sid):
    return isinstance(sid, str) and SID.fullmatch(sid) is not None

def write(path, text):  # atomic: temp file in the same directory, then os.replace
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise

def flag(sid, mode):  # this session's own choice, else the default (lean-always only)
    try:
        return open(os.path.join(sdir, f"{sid}.{mode}")).read().strip() == "on"
    except OSError:
        return mode == "always" and os.path.exists(DEFAULT)

def apply(sid, mode, arg):  # False when arg is not a toggle
    arg = " ".join(arg.split()).lower() or "on"
    if arg in ("on", "off"):
        write(os.path.join(sdir, f"{sid}.{mode}"), arg + "\n")
    elif mode == "always" and arg in ("default on", "default off"):
        if arg == "default on":
            if not os.path.exists(DEFAULT):
                write(DEFAULT, "")
        elif os.path.exists(DEFAULT):
            os.remove(DEFAULT)
    elif arg != "status":
        return False
    return True

VALID_ARGS = "on, off, status, default on, default off"

def status(sid):
    o = lambda b: "ON" if b else "OFF"
    return (f"[LEAN] this session: lean-always {o(flag(sid, 'always'))}. "
            f"{SIGIL}lean-always on|off affects this session only. the default "
            f"(lean-always {o(os.path.exists(DEFAULT))}, {SIGIL}lean-always default on|off) "
            f"applies to every session without its own on/off choice, open ones included.")

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
    sid = sys.argv[2] if len(sys.argv) > 2 else ""
    mode = sys.argv[3] if len(sys.argv) > 3 else ""
    if not valid(sid) or mode != "always":
        sys.exit("usage: lean-mode.sh [claude|codex] set <session_id> always [on|off|status|default on|default off]")
    if not apply(sid, mode, " ".join(sys.argv[4:])):
        sys.exit("unknown argument; use on, off, status, default on or default off")
    print(status(sid))
    sys.exit()

try:
    with os.fdopen(3, "rb") as f:
        d = json.loads(f.read())
except Exception:
    sys.exit()
if not isinstance(d, dict):
    sys.exit()
p, sid = d.get("prompt"), d.get("session_id")
if not isinstance(p, str) or not valid(sid):
    sys.exit()
low = p.lower()
sfile = os.path.join(sdir, sid)

cmd = parse(p)
note = ""
if cmd:
    if not apply(sid, *cmd):
        emit(f"[LEAN] unknown argument, nothing changed; valid: {SIGIL}lean-always {VALID_ARGS}.")
        sys.exit()
    note = status(sid) + " relay this line to the user in one line."
try:  # keep this session's switch, on or off, clear of the idle prune
    os.utime(f"{sfile}.always")
except OSError:
    pass
if not flag(sid, "always"):
    try:
        os.remove(sfile)  # so the full text is injected when a mode is turned back on
    except OSError:
        pass
    if note:
        emit(note)
    sys.exit()

os.makedirs(sdir, exist_ok=True)
prev, n = None, 0
try:
    f = open(sfile).read().split(); prev, n = int(f[0]), int(f[1])
except Exception:
    pass
if prev is None:  # first prompt: prune idle state of other sessions
    now = time.time()
    try:
        for e in os.scandir(sdir):
            if not e.is_file() or e.name in (sid, f"{sid}.always"):
                continue
            days = 60 if e.name.endswith(".always") else 14
            if now - e.stat().st_mtime > days * 86400:
                os.remove(e.path)
    except OSError:
        pass

STRONG = re.compile(r"(\bprod(uction)?\b|\bsecurity\b|\b(?:o?auth[nz]?|authenticat\w*|authori[sz]\w*)\b|\bmigrat\w*|\bdeploy\w*|\brelease\b|\benterprise\b|\bcritical\b|\bcompliance\b|\bdata loss\b|\brm -rf|\barchitect\w*|\borchestrat\w*|\bparallel\w*|\bcodebase\b|\ball files\b|\bthink hard\w*|\bthorough\w*|\bpayment\w*|\bbilling\b)")
WEAK = re.compile(r"\b(design|refactor\w*|audit|important|delete|drop|verify|carefully|deep\w*|multi-file)\b")
ACTION = re.compile(r"(\b(fix|add|change|edit|update|remove|rename|run|write|implement|create|make|build|install|move|replace|patch|apply|commit|test)\b|/[\w.-]+|\.\w{1,4}\b)")
CONT = re.compile(r"^\s*(y|yes|ok|okay|go|do it|continue|next|proceed|sure|yep|apply|go ahead|thanks?)[\s.!]*$")

OVR = set(re.findall(r"(?<!\S)#(lean|deep|par)(?!\S)", low))  # whole tokens, anywhere

if "lean" in OVR:
    tier = 0
elif OVR:
    tier = 2
elif CONT.match(low):
    tier = prev if prev is not None else 0
elif STRONG.search(low) or len(p) > 600 or (WEAK.search(low) and len(p) > 250):
    tier = 2
elif len(p) < 30:
    tier = prev if prev is not None else 0
elif len(p) < 120 and not ACTION.search(low):
    tier = 0
else:
    tier = 1
if tier == 0 and ACTION.search(low) and not CONT.match(low) and "lean" not in OVR:
    tier = 1
par = tier == 2 and "par" in OVR

full = bool(note) or par or prev != tier or n % 8 == 0
try:
    write(sfile, f"{tier} {n+1}")
except Exception:
    pass

# the only harness-specific wording: the everyday models, and the rare premium one
if os.environ.get("LEAN_HARNESS") == "codex":
    BASE, TOP = "gpt-6-luna mechanical, gpt-6-sol judgment", "gpt-6-astra"
else:
    BASE, TOP = "sonnet mechanical, opus (Opus 5.5) judgment", "fable (Fable 5.1)"

T0 = """[LEAN T0] Answer directly from what you know; open a file only if the answer depends on its contents. High-level summary unless in-depth is requested. Lead with the answer; fragments and bullets; no preamble, recap, or offers. Mark anything unchecked "(unverified)"."""

T1 = f"""[LEAN T1] Reason as much as the problem needs; brevity applies to what you write, not to how carefully you think.
Tools: grep -n / sed -n for the exact lines, filter output (| head -40), batch independent calls in one turn, read a file before speaking about it, no re-reads.
Edits: minimal diff at the asked scope; one verification per change, output filtered but the command's real exit status kept, report its pass/fail line.
Make routine judgment calls yourself; ask only when different readings of the request would lead to materially different work.
Delegate only large, independent work that a worker can finish from a written brief ({BASE}; worker returns <=15 lines). Never spawn agents to re-check your own work.
Output: outcome first, dense bullets or fragments, code only as changed lines. Keep every finding, tag uncertain ones; cut filler, not content. Mark unchecked claims "(unverified)"; never fabricate to stay short."""

T2 = f"""[LEAN T2 critical] Think fully; this task warrants depth. Brevity applies to writing only.
Parallelism by scope: single-file or sequential work -> do it yourself; multi-file with shared state -> yourself or 1 agent; N genuinely independent tracks -> N agents on disjoint files with interfaces fixed up front. For a build with 3 or more tracks, or when asked to parallelise or orchestrate, load the parallel-orchestration skill if available and follow it; it owns packets, gates and fix limits. Otherwise: lookup prompts <=150 words, build briefs as long as ownership, contract and verify command need, each worker returns <=15 lines. Add one independent verifier agent only when a wrong result is costly (prod, security, data). Raise thinking before raising agent count. Never spawn agents to re-check your own work. Models: {BASE}; spawned agents never run {TOP}. If the task needs {TOP} and this session is not on it, say so in one line so the user can switch.
Tools: targeted reads (grep -n / sed -n, | head -40), batch independent calls, read before asserting, no re-reads.
Edits: minimal diffs; one verification per change, output filtered but the command's real exit status kept; state pass/fail.
Make routine judgment calls yourself; ask only when different readings would lead to materially different work.
Output: outcome first, dense; every finding kept with a confidence tag; no padding, no recap. Mark unchecked claims "(unverified)". If blocked, one line: blocker + cheapest next step."""
if par:
    T2 += "\nLoad the parallel-orchestration skill now and follow it."

text = (T0, T1, T2)[tier] if full else f"[LEAN T{tier} on, rules above still apply]"
emit(note + "\n" + text if note else text)
PY
