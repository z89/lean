#!/usr/bin/env bash
# PreCompact hook for claude code and codex cli: forget the lean tier state for
# this session so the full directive is re-injected after compaction. the
# session's on/off switch (<session_id>.always) is kept.
# usage: lean-compact.sh [claude|codex]   default claude
case "${1:-claude}" in claude) D="$HOME/.claude" ;; codex) D="$HOME/.codex" ;; *) exit 0 ;; esac
sid=$(sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_-]*\)".*/\1/p' | head -1)
[ -n "$sid" ] && rm -f "$D/lean-state/$sid"
exit 0
