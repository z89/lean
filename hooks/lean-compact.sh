#!/usr/bin/env bash
# PreCompact hook: forget the lean tier state for this session so the full
# directive is re-injected on the first prompt after compaction.
sid=$(sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_-]*\)".*/\1/p' | head -1)
[ -n "$sid" ] && rm -f "$HOME/.claude/lean-state/$sid"
exit 0
