#!/usr/bin/env bash
FONT_TARBALL="JetBrainsMono"

font_installed() {
  if has fc-list; then
    fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" && return 0
  fi
  ls "$HOME/Library/Fonts"/JetBrainsMono*NerdFont* >/dev/null 2>&1 && return 0
  ls "$HOME/.local/share/fonts"/JetBrainsMono*NerdFont* >/dev/null 2>&1 && return 0
  return 1
}

install_nerd_font() {
  if [ -n "${SKIP_FONT:-}" ]; then warn "SKIP_FONT set; skipping font"; return 0; fi
  if font_installed; then ok "JetBrains Mono Nerd Font present"; return 0; fi

  info "Installing JetBrains Mono Nerd Font"
  if [ "$OS" = macos ] && has brew; then
    run brew install --cask font-jetbrains-mono-nerd-font
    return 0
  fi

  local dest
  if [ "$OS" = macos ]; then dest="$HOME/Library/Fonts"; else dest="$HOME/.local/share/fonts"; fi
  run mkdir -p "$dest"

  if [ -n "${DRY_RUN:-}" ]; then
    log "  [dry-run] download ${FONT_TARBALL}.tar.xz -> $dest"
  else
    local tmp url
    tmp="$(mktemp -d)"
    url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_TARBALL}.tar.xz"
    if curl -fsSL "$url" -o "$tmp/font.tar.xz" && tar -xJf "$tmp/font.tar.xz" -C "$dest"; then
      ok "font extracted to ${dest/#$HOME/~}"
    else
      warn "font download failed ($url) — install JetBrainsMono Nerd Font manually"
    fi
    rm -rf "$tmp"
  fi

  if [ "$OS" != macos ] && has fc-cache; then
    run fc-cache -f "$dest"
  fi
}
