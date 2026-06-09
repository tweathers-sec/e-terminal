#!/usr/bin/env bash
# Cached: hcloud/doctl have high startup cost; run at most once per $ttl seconds.
prov="${1:-}"
cache="/tmp/e-terminal-cloud-${prov}.cache"
ttl=15

if [ -f "$cache" ]; then
  now=$(date +%s)
  if [ "$(uname -s)" = "Darwin" ]; then mt=$(stat -f %m "$cache" 2>/dev/null || echo 0); else mt=$(stat -c %Y "$cache" 2>/dev/null || echo 0); fi
  if [ $((now - mt)) -le "$ttl" ]; then cat "$cache"; exit 0; fi
fi

val=""
case "$prov" in
  hetzner) command -v hcloud >/dev/null 2>&1 && val="$(hcloud context active 2>/dev/null)" ;;
  do)      command -v doctl  >/dev/null 2>&1 && val="$(doctl auth list 2>/dev/null | awk '/\(current\)/{print $1}')" ;;
esac

printf '%s' "$val" | tee "$cache"
