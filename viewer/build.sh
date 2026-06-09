#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
OUT="../config/bin"
mkdir -p "$OUT"
LD="-s -w"

for t in darwin/arm64 darwin/amd64 linux/amd64 linux/arm64; do
  os="${t%/*}"
  arch="${t#*/}"
  for spec in ".:e-session-view" "./rec:e-session-rec"; do
    pkg="${spec%:*}"
    name="${spec#*:}"
    bin="$OUT/${name}-${os}-${arch}"
    CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -trimpath -buildvcs=false -ldflags "$LD" -o "$bin" "$pkg"
    printf '  built %-32s %s\n' "$(basename "$bin")" "$(ls -lh "$bin" | awk '{print $5}')"
  done
done
echo "done."
