#!/usr/bin/env bash
BACKUP_DIR="${BACKUP_DIR:-$HOME/.e-terminal-backup/$(date +%Y%m%d-%H%M%S)}"

symlink_with_backup() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    warn "missing source, skipping: $src"
    return 1
  fi

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    ok "link  $(abbrev "$dst")"
    return 0
  fi

  run mkdir -p "$(dirname "$dst")"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -z "${DRY_RUN:-}" ]; then
      mkdir -p "$BACKUP_DIR"
      mv "$dst" "$BACKUP_DIR/$(basename "$dst").bak"
    fi
    warn "backup $(abbrev "$dst") -> $(abbrev "$BACKUP_DIR")/$(basename "$dst").bak"
  fi

  run ln -s "$src" "$dst"
  ok "link  $(abbrev "$dst") -> $(abbrev "$src")"
}
