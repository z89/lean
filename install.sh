#!/usr/bin/env bash
# installs lean into ~/.claude by symlink and wires the two hooks into
# settings.json. idempotent: run again after a git pull and nothing changes.
# --adopt: replace matching real files already in ~/.claude with symlinks.
#          without it, a real file in the way is an error.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL="${CLAUDE_HOME:-$HOME/.claude}"
S="$CL/settings.json"
ADOPT=0; [ "${1:-}" = "--adopt" ] && ADOPT=1
say() { printf 'lean: %s\n' "$*"; }
die() { say "error: $*" >&2; exit 1; }
command -v python3 >/dev/null || die "python3 is required (macOS: xcode-select --install   arch: sudo pacman -S python)"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq   arch: sudo pacman -S jq)"
mkdir -p "$CL/hooks" "$CL/skills"

link() { # link <repo-relative source> <target path>
  local src="$REPO/$1" dst="$2"
  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && { say "ok      $dst"; return; }
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    [ "$ADOPT" = 1 ] || die "$dst exists and is not a symlink. re-run with --adopt to replace it"
    rm -rf "$dst"; say "adopted $dst"
  fi
  ln -s "$src" "$dst"; say "linked  $dst"
}
link hooks/lean-mode.sh    "$CL/hooks/lean-mode.sh"
link hooks/lean-compact.sh "$CL/hooks/lean-compact.sh"
link skills/lean           "$CL/skills/lean"
link skills/lean-always    "$CL/skills/lean-always"
chmod +x "$REPO/hooks/"*.sh

# settings.json: add each hook once, keyed on its command string
[ -f "$S" ] || echo '{}' > "$S"
CMD_MODE="bash $CL/hooks/lean-mode.sh"; CMD_COMPACT="bash $CL/hooks/lean-compact.sh"
jq --arg m "$CMD_MODE" --arg c "$CMD_COMPACT" '
  def ensure($ev; $cmd):
    .hooks //= {} | .hooks[$ev] //= [] |
    if ([.hooks[$ev][]?.hooks[]?.command] | index($cmd)) then . else
      .hooks[$ev] += [{"hooks":[{"type":"command","command":$cmd}]}] end;
  ensure("UserPromptSubmit"; $m) | ensure("PreCompact"; $c)
' "$S" > "$S.lean-tmp" || die "settings.json merge failed (invalid JSON?)"
jq -e . "$S.lean-tmp" >/dev/null || die "merge produced invalid JSON, original untouched"
mv "$S.lean-tmp" "$S"; say "wired   $S (UserPromptSubmit + PreCompact)"
say "installed. lean is OFF until you run /lean-always on in claude code"
