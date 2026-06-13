#!/usr/bin/env bash
BACKUP_DIR="${BACKUP_DIR:-$HOME/.e-terminal-backup/$(date +%Y%m%d-%H%M%S)}"
ETERM_ORIG="$HOME/.e-terminal-backup/original"

install_path() {
  local src="$1" dst="$2" base
  if [ ! -e "$src" ]; then
    warn "missing source, skipping: $src"
    return 1
  fi
  run mkdir -p "$(dirname "$dst")"
  base="$(basename "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -z "${DRY_RUN:-}" ]; then
      if [ ! -e "$ETERM_ORIG/$base.bak" ]; then
        mkdir -p "$ETERM_ORIG"
        cp -RP "$dst" "$ETERM_ORIG/$base.bak"
        warn "saved original $(abbrev "$dst") -> $(abbrev "$ETERM_ORIG")/$base.bak"
      fi
      rm -rf "$dst"
    fi
  fi
  if [ -d "$src" ]; then run cp -Rp "$src" "$dst"; else run cp -p "$src" "$dst"; fi
  ok "copy  $(abbrev "$dst")"
}
