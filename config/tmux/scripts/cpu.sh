#!/usr/bin/env bash
# macOS: serve cached value immediately; `top -l 1` takes ~1s and would block tmux's #() loop.
cache="/tmp/e-terminal-cpu.cache"
ttl=5
if [ "$(uname -s)" = "Darwin" ]; then
  if [ -f "$cache" ]; then
    now=$(date +%s); mt=$(stat -f %m "$cache" 2>/dev/null || echo 0)
    cat "$cache"
    [ $((now - mt)) -le "$ttl" ] && exit 0
  else
    printf '  0%%'
  fi
  ( top -l 1 -n 0 2>/dev/null \
      | awk -F'[ %]+' '/CPU usage/ {printf "%3.0f%%", $3 + $5; exit}' > "$cache.tmp" 2>/dev/null \
      && mv "$cache.tmp" "$cache" ) >/dev/null 2>&1 &
else
  read -r _ a b c d _ < /proc/stat
  pi=$d; pt=$((a + b + c + d)); sleep 0.2
  read -r _ a b c d _ < /proc/stat
  awk -v di=$((d - pi)) -v dt=$(((a + b + c + d) - pt)) \
    'BEGIN { if (dt <= 0) dt = 1; printf "%3.0f%%", (1 - di / dt) * 100 }'
fi
