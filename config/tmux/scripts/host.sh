#!/bin/sh
hn="$(hostname -s 2>/dev/null || hostname 2>/dev/null | cut -d. -f1)"
if command -v ip >/dev/null 2>&1; then
  pip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
else
  dif="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  [ -n "$dif" ] && pip="$(ipconfig getifaddr "$dif" 2>/dev/null)"
fi
tip="$( { ip -4 -o addr show 2>/dev/null || ifconfig 2>/dev/null; } | grep -oE '100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+' | head -1 )"
[ -n "$hn$pip" ] || exit 0
bg2="$(tmux show-option -gqv @thm_bg2 2>/dev/null)"; bg2="${bg2:-#262626}"
fg="$(tmux show-option -gqv @thm_fg 2>/dev/null)";   fg="${fg:-#dedede}"
acc="$(tmux show-option -gqv @thm_accent 2>/dev/null)"; acc="${acc:-#97bedc}"
aq="$(tmux show-option -gqv @thm_aqua 2>/dev/null)";  aq="${aq:-#1ab2a8}"
out="#[fg=$bg2,bg=default]#[fg=$acc,bg=$bg2] 󰒋 $hn "
[ -n "$pip" ] && out="$out#[fg=$fg,bg=$bg2]$pip "
[ -n "$tip" ] && out="$out#[fg=$aq,bg=$bg2]$tip "
out="$out#[fg=$bg2,bg=default] "
printf '%s' "$out"
