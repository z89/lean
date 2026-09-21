#!/usr/bin/env bash
# removes the lean symlinks, the two settings.json hook entries, the
# on/off flag and per-session state.
set -euo pipefail
CL="${CLAUDE_HOME:-$HOME/.claude}"
S="$CL/settings.json"
say() { printf 'lean: %s\n' "$*"; }
for t in "$CL/hooks/lean-mode.sh" "$CL/hooks/lean-compact.sh" "$CL/skills/lean" "$CL/skills/lean-always"; do
  if [ -L "$t" ]; then rm -f "$t"; say "removed $t"
  elif [ -e "$t" ]; then say "skipped $t (not a symlink, left in place)"; fi
done
if [ -f "$S" ] && command -v jq >/dev/null; then
  jq '
    def strip($ev): if .hooks[$ev]? then
      .hooks[$ev] |= map(select([.hooks[]?.command] | any(test("/lean-(mode|compact)\\.sh$")) | not)) |
      if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end
    else . end;
    strip("UserPromptSubmit") | strip("PreCompact")
  ' "$S" > "$S.lean-tmp" && jq -e . "$S.lean-tmp" >/dev/null && mv "$S.lean-tmp" "$S" && say "unwired $S"
fi
rm -f "$CL/lean.on"; rm -rf "$CL/lean-state"; say "flag and state cleared"
say "uninstalled"
