#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  hetzner) icon="󰒋" ;;
  do)      icon="󰇄" ;;
  *) exit 0 ;;
esac
val="$("$here/cloud-ctx.sh" "$1" 2>/dev/null)"
[ -n "$val" ] || exit 0
bg2="$(tmux show-option -gqv @thm_bg2 2>/dev/null)"; bg2="${bg2:-#262626}"
acc="$(tmux show-option -gqv @thm_aqua 2>/dev/null)"; acc="${acc:-#1ab2a8}"
printf '#[fg='"$bg2"',bg=default]#[fg='"$acc"',bg='"$bg2"'] %s %s #[fg='"$bg2"',bg=default] ' "$icon" "$val"
