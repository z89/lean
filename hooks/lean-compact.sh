#!/usr/bin/env bash
# PreCompact hook for claude code and codex cli: forget the lean tier state for
# this session so the full directive is re-injected after compaction. the
# session's on/off switch (<session_id>.always) is kept.
# usage: lean-compact.sh [claude|codex]   default claude
# root: $CLAUDE_HOME / $CODEX_HOME if set, else ~/.claude / ~/.codex.
case "${1:-claude}" in claude) D="${CLAUDE_HOME:-$HOME/.claude}" ;; codex) D="${CODEX_HOME:-$HOME/.codex}" ;; *) exit 0 ;; esac
LEAN_HOME="$D" python3 -c '
import json, os, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit()
sid = d.get("session_id") if isinstance(d, dict) else None
if isinstance(sid, str) and re.fullmatch(r"[A-Za-z0-9_-]+", sid):
    try:
        os.remove(os.path.join(os.environ["LEAN_HOME"], "lean-state", sid))
    except OSError:
        pass
' 2>/dev/null
exit 0
