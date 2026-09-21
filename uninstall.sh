#!/usr/bin/env bash
# removes lean from claude code and/or codex cli: symlinks, hook
# entries, the codex feature flag line, the on/off flag and per-session state.
#   ./uninstall.sh               detect installs, ask which to remove
#   ./uninstall.sh --claude | --codex | --all
set -euo pipefail
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'; C=$'\e[36m'; G=$'\e[32m'; X=$'\e[31m'
else B=; D=; R=; C=; G=; X=; fi
ok()   { printf '  %s🧹%s %s\n' "$G" "$R" "$*"; }
head_() { printf '\n%s%s%s\n' "$B" "$*" "$R"; }
die()  { printf '  %s❌ %s%s\n' "$X" "$*" "$R" >&2; exit 1; }

WANT_CLAUDE=0; WANT_CODEX=0; ASKED=0
for a in "$@"; do case "$a" in
  --claude) WANT_CLAUDE=1; ASKED=1 ;; --codex) WANT_CODEX=1; ASKED=1 ;; --all) WANT_CLAUDE=1; WANT_CODEX=1; ASKED=1 ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; *) die "unknown option $a" ;;
esac; done
printf '\n%s🌿 lean%s %suninstaller%s\n' "$B" "$R" "$D" "$R"

HAS_CLAUDE=0; HAS_CODEX=0
[ -L "$CLAUDE_HOME/hooks/lean-mode.sh" ] || [ -f "$CLAUDE_HOME/lean.on" ] && HAS_CLAUDE=1
[ -L "$CODEX_HOME/hooks/lean-mode.sh" ]  || [ -f "$CODEX_HOME/lean.on" ]  && HAS_CODEX=1
if [ "$ASKED" = 0 ]; then
  if [ "$HAS_CLAUDE" = 1 ] && [ "$HAS_CODEX" = 1 ] && [ -t 0 ]; then
    head_ "🎯 remove from which harness?"
    printf '  %s1%s) claude code\n  %s2%s) codex cli\n  %s3%s) both\n  %s>%s ' "$C" "$R" "$C" "$R" "$C" "$R" "$B" "$R"; read -r pick
    case "$pick" in 1) WANT_CLAUDE=1 ;; 2) WANT_CODEX=1 ;; 3|"") WANT_CLAUDE=1; WANT_CODEX=1 ;; *) die "pick 1, 2 or 3" ;; esac
  else WANT_CLAUDE=$HAS_CLAUDE; WANT_CODEX=$HAS_CODEX; fi
fi
[ "$WANT_CLAUDE" = 1 ] || [ "$WANT_CODEX" = 1 ] || { printf '  %snothing installed%s\n\n' "$D" "$R"; exit 0; }

unlink_() { for t in "$@"; do
  if [ -L "$t" ]; then rm -f "$t"; ok "$t"
  elif [ -e "$t" ]; then printf '  %s➖ %s is not a symlink, left in place%s\n' "$D" "$t" "$R"; fi
done; }
unwire_json() { local f="$1"; [ -f "$f" ] || return 0
  jq '
    def strip($ev): if .hooks[$ev]? then
      .hooks[$ev] |= map(select([.hooks[]?.command] | any(test("/lean-(mode|compact)\\.sh( codex)?$")) | not)) |
      if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end
    else . end;
    strip("UserPromptSubmit") | strip("PreCompact")
  ' "$f" > "$f.lean-tmp" && jq -e . "$f.lean-tmp" >/dev/null && mv "$f.lean-tmp" "$f" && ok "$f ${D}hook entries removed${R}"
}
command -v jq >/dev/null || die "jq is required to edit the hook config"

if [ "$WANT_CLAUDE" = 1 ]; then
  head_ "🤖 claude code"
  unlink_ "$CLAUDE_HOME/hooks/lean-mode.sh" "$CLAUDE_HOME/hooks/lean-compact.sh" "$CLAUDE_HOME/skills/lean" "$CLAUDE_HOME/skills/lean-always"
  unwire_json "$CLAUDE_HOME/settings.json"
  rm -f "$CLAUDE_HOME/lean.on"; rm -rf "$CLAUDE_HOME/lean-state"; ok "flag and state cleared"
fi
if [ "$WANT_CODEX" = 1 ]; then
  head_ "🧭 codex cli"
  unlink_ "$CODEX_HOME/hooks/lean-mode.sh" "$CODEX_HOME/hooks/lean-compact.sh" "$AGENTS_HOME/skills/lean" "$AGENTS_HOME/skills/lean-always"
  unwire_json "$CODEX_HOME/hooks.json"
  [ -f "$CODEX_HOME/hooks.json" ] && [ "$(jq '.hooks // {} | length' "$CODEX_HOME/hooks.json")" = 0 ] && [ "$(jq 'length' "$CODEX_HOME/hooks.json")" = 1 ] && rm -f "$CODEX_HOME/hooks.json" && ok "$CODEX_HOME/hooks.json ${D}empty, removed${R}"
  if [ -f "$CODEX_HOME/config.toml" ] && grep -q '# lean$' "$CODEX_HOME/config.toml"; then
    sed -i.lean-tmp '/# lean$/d' "$CODEX_HOME/config.toml" && rm -f "$CODEX_HOME/config.toml.lean-tmp" && ok "config.toml ${D}hooks flag line removed${R}"
  fi
  rm -f "$CODEX_HOME/lean.on"; rm -rf "$CODEX_HOME/lean-state"; ok "flag and state cleared"
fi
head_ "👋 uninstalled"; echo
