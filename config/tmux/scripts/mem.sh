#!/usr/bin/env bash
if [ "$(uname -s)" = "Darwin" ]; then
  total_bytes=$(sysctl -n hw.memsize)
  page=$(sysctl -n hw.pagesize)
  used_pages=$(vm_stat | awk '
    /Pages active/                 { gsub(/\./,"",$3); a=$3 }
    /Pages wired down/             { gsub(/\./,"",$4); w=$4 }
    /Pages occupied by compressor/ { gsub(/\./,"",$5); c=$5 }
    END { print a + w + c }')
  awk -v u="$used_pages" -v p="$page" -v t="$total_bytes" \
    'BEGIN { printf "%.1f/%.0fG", u * p / 1073741824, t / 1073741824 }'
else
  free -m | awk '/^Mem:/ { printf "%.1f/%.0fG", $3 / 1024, $2 / 1024 }'
fi
