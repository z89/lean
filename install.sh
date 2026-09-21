#!/usr/bin/env bash
# installs lean into claude code and/or codex cli by symlink and wires
# the two hooks. idempotent: run again after a git pull and nothing changes.
#   ./install.sh                 detect harnesses, ask which to install
#   ./install.sh --claude        no prompt
#   ./install.sh --codex         no prompt
#   ./install.sh --all           every detected harness, no prompt
#   --adopt                      replace real files already at the target paths with symlinks
#                                (lists them and asks first; --yes skips the question)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'; C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; X=$'\e[31m'
else B=; D=; R=; C=; G=; Y=; X=; fi
ok()   { printf '  %s✅%s %s\n' "$G" "$R" "$*"; }
info() { printf '  %s🔗%s %s\n' "$C" "$R" "$*"; }
warn() { printf '  %s⚠️ %s %s\n' "$Y" "$R" "$*"; }
head_() { printf '\n%s%s%s\n' "$B" "$*" "$R"; }
die()  { printf '  %s❌ %s%s\n' "$X" "$*" "$R" >&2; exit 1; }

ADOPT=0; WANT_CLAUDE=0; WANT_CODEX=0; ALL=0; ASKED=0; YES=0
for a in "$@"; do case "$a" in
  --adopt) ADOPT=1 ;; --yes|-y) YES=1 ;; --claude) WANT_CLAUDE=1; ASKED=1 ;; --codex) WANT_CODEX=1; ASKED=1 ;; --all) ALL=1; ASKED=1 ;;
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option $a" ;;
esac; done

printf '\n%s🌿 lean%s %sinstaller%s\n' "$B" "$R" "$D" "$R"
command -v python3 >/dev/null || die "python3 is required (macOS: xcode-select --install   arch: sudo pacman -S python)"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq   arch: sudo pacman -S jq)"

head_ "🔍 detecting harnesses"
HAS_CLAUDE=0; HAS_CODEX=0
{ [ -d "$CLAUDE_HOME" ] || command -v claude >/dev/null; } && HAS_CLAUDE=1
{ [ -d "$CODEX_HOME" ] || command -v codex >/dev/null; } && HAS_CODEX=1
[ "$HAS_CLAUDE" = 1 ] && ok "claude code  ${D}$CLAUDE_HOME${R}" || printf '  %s➖ claude code  not found%s\n' "$D" "$R"
[ "$HAS_CODEX" = 1 ]  && ok "codex cli    ${D}$CODEX_HOME${R}"  || printf '  %s➖ codex cli    not found%s\n' "$D" "$R"
[ "$HAS_CLAUDE" = 1 ] || [ "$HAS_CODEX" = 1 ] || die "no harness found. install claude code or codex cli first"

if [ "$ALL" = 1 ]; then WANT_CLAUDE=$HAS_CLAUDE; WANT_CODEX=$HAS_CODEX
elif [ "$ASKED" = 0 ]; then
  if [ "$HAS_CLAUDE" = 1 ] && [ "$HAS_CODEX" = 1 ] && [ -t 0 ]; then
    head_ "🎯 which harness?"
    printf '  %s1%s) claude code\n  %s2%s) codex cli\n  %s3%s) both\n' "$C" "$R" "$C" "$R" "$C" "$R"
    printf '  %s>%s ' "$B" "$R"; read -r pick
    case "$pick" in 1) WANT_CLAUDE=1 ;; 2) WANT_CODEX=1 ;; 3|"") WANT_CLAUDE=1; WANT_CODEX=1 ;; *) die "pick 1, 2 or 3" ;; esac
  else WANT_CLAUDE=$HAS_CLAUDE; WANT_CODEX=$HAS_CODEX; fi
fi
[ "$WANT_CLAUDE" = 1 ] && [ "$HAS_CLAUDE" = 0 ] && die "claude code not found"
[ "$WANT_CODEX" = 1 ]  && [ "$HAS_CODEX" = 0 ]  && die "codex cli not found"

# install_pairs <src|dst> ...   links each pair, but never deletes anything the
# user has not been shown first: real files in the way are listed and confirmed.
install_pairs() {
  local pair src dst conflicts=()
  for pair in "$@"; do
    src="$REPO/${pair%%|*}"; dst="${pair##*|}"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then continue; fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then conflicts+=("$dst"); fi
  done
  if [ "${#conflicts[@]}" -gt 0 ]; then
    if [ "$ADOPT" != 1 ]; then
      printf '  %s❌ these exist and are not symlinks:%s\n' "$X" "$R" >&2
      printf '     %s\n' "${conflicts[@]}" >&2
      die "re-run with --adopt to replace them"
    fi
    warn "--adopt will permanently delete and replace:"
    printf '     %s%s%s\n' "$Y" "${conflicts[@]}" "$R"
    if [ -t 0 ] && [ "$YES" != 1 ]; then
      printf '  %sdelete these? [y/N]%s ' "$B" "$R"; read -r reply
      case "$reply" in y|Y|yes) ;; *) die "aborted, nothing changed" ;; esac
    fi
  fi
  for pair in "$@"; do
    src="$REPO/${pair%%|*}"; dst="${pair##*|}"
    if [ -L "$dst" ]; then
      [ "$(readlink "$dst")" = "$src" ] && { ok "$dst ${D}already linked${R}"; continue; }
      rm -f "$dst"
    elif [ -e "$dst" ]; then
      rm -rf "$dst"; warn "replaced $dst"
    fi
    ln -s "$src" "$dst"; info "$dst"
  done
}
wire_json() { # wire_json <file> <mode cmd> <compact cmd>
  local f="$1"
  [ -f "$f" ] || { mkdir -p "$(dirname "$f")"; echo '{}' > "$f"; }
  jq --arg m "$2" --arg c "$3" '
    def ensure($ev; $cmd):
      .hooks //= {} | .hooks[$ev] //= [] |
      if ([.hooks[$ev][]?.hooks[]?.command] | index($cmd)) then . else
        .hooks[$ev] += [{"hooks":[{"type":"command","command":$cmd}]}] end;
    ensure("UserPromptSubmit"; $m) | ensure("PreCompact"; $c)
  ' "$f" > "$f.lean-tmp" || die "$f merge failed (invalid JSON?)"
  jq -e . "$f.lean-tmp" >/dev/null || die "merge produced invalid JSON, $f untouched"
  mv "$f.lean-tmp" "$f"; ok "$f ${D}UserPromptSubmit + PreCompact${R}"
}
chmod +x "$REPO/hooks/"*.sh

if [ "$WANT_CLAUDE" = 1 ]; then
  head_ "🤖 claude code"
  mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/skills"
  install_pairs \
    "hooks/lean-mode.sh|$CLAUDE_HOME/hooks/lean-mode.sh" \
    "hooks/lean-compact.sh|$CLAUDE_HOME/hooks/lean-compact.sh" \
    "claude/skills/lean|$CLAUDE_HOME/skills/lean" \
    "claude/skills/lean-always|$CLAUDE_HOME/skills/lean-always"
  wire_json "$CLAUDE_HOME/settings.json" "bash $CLAUDE_HOME/hooks/lean-mode.sh" "bash $CLAUDE_HOME/hooks/lean-compact.sh"
fi

if [ "$WANT_CODEX" = 1 ]; then
  head_ "🧭 codex cli"
  mkdir -p "$CODEX_HOME/hooks" "$AGENTS_HOME/skills"
  install_pairs \
    "hooks/lean-mode.sh|$CODEX_HOME/hooks/lean-mode.sh" \
    "hooks/lean-compact.sh|$CODEX_HOME/hooks/lean-compact.sh" \
    "codex/skills/lean|$AGENTS_HOME/skills/lean" \
    "codex/skills/lean-always|$AGENTS_HOME/skills/lean-always"
  wire_json "$CODEX_HOME/hooks.json" "bash $CODEX_HOME/hooks/lean-mode.sh codex" "bash $CODEX_HOME/hooks/lean-compact.sh codex"
  # codex gates hooks behind [features] hooks = true; add it once, tagged so uninstall can find it
  HL_D="$D" HL_R="$R" python3 - "$CODEX_HOME/config.toml" <<'PY'
import re, sys, os
D, R = os.environ.get("HL_D", ""), os.environ.get("HL_R", "")
p = sys.argv[1]; s = open(p).read() if os.path.exists(p) else ""
if re.search(r"^\s*hooks\s*=\s*true", s, re.M) and "[features]" in s:
    print(f"  ✅ config.toml {D}hooks already enabled{R}"); sys.exit()
line = "hooks = true # lean\n"
m = re.search(r"^\[features\]\s*\n", s, re.M)
s = s[:m.end()] + line + s[m.end():] if m else s.rstrip("\n") + ("\n\n" if s else "") + "[features]\n" + line
tmp = p + ".lean-tmp"
with open(tmp, "w") as f:
    f.write(s); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)  # atomic: a crash mid-write cannot truncate the user's config
print(f"  ✅ config.toml {D}[features] hooks = true{R}")
PY
fi

head_ "🎉 installed"
[ "$WANT_CLAUDE" = 1 ] && printf '  claude code: %s/lean-always on%s to enable\n' "$C" "$R"
[ "$WANT_CODEX" = 1 ]  && printf '  codex cli:   %s$lean-always on%s to enable\n' "$C" "$R"
printf '  %s./uninstall.sh reverses everything%s\n\n' "$D" "$R"
