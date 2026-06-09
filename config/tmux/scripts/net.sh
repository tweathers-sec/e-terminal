#!/usr/bin/env bash
state="/tmp/e-terminal-net.state"
os="$(uname -s)"

if [ "$os" = "Darwin" ]; then
  iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
  [ -z "$iface" ] && { printf "↓   0K ↑   0K"; exit 0; }
  set -- $(netstat -ibn 2>/dev/null | awk -v i="$iface" '$1==i {print $7, $10; exit}')
  rx="${1:-0}"; tx="${2:-0}"
else
  iface=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
  [ -z "$iface" ] && { printf "↓   0K ↑   0K"; exit 0; }
  rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
  tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
fi

now=$(date +%s); prx=$rx; ptx=$tx; pt=$now
[ -r "$state" ] && read -r prx ptx pt < "$state" 2>/dev/null
dt=$((now - pt)); [ "$dt" -lt 1 ] && dt=1
drx=$(((rx - prx) / dt / 1024)); [ "$drx" -lt 0 ] && drx=0
dtx=$(((tx - ptx) / dt / 1024)); [ "$dtx" -lt 0 ] && dtx=0
tmpf="$state.$$"; printf '%s %s %s\n' "$rx" "$tx" "$now" > "$tmpf" && mv "$tmpf" "$state"

fmt() {
  local v=$1
  if   [ "$v" -lt 1000 ];  then printf '%3dK' "$v"
  elif [ "$v" -lt 10240 ]; then printf '%d.%dM' $((v / 1024)) $(((v * 10 / 1024) % 10))
  else printf '%3dM' $((v / 1024)); fi
}
printf "↓%s ↑%s" "$(fmt "$drx")" "$(fmt "$dtx")"
