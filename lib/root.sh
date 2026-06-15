#!/usr/bin/env bash
nu_dir_for() {
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '%s/Library/Application Support/nushell' "$1"
  else
    printf '%s/.config/nushell' "$1"
  fi
}

link_user_configs() {
  local home="$1" C="$DOTFILES_DIR/config" nud; nud="$(nu_dir_for "$home")"
  run sudo mkdir -p "$nud" "$home/.config/tmux"
  run sudo ln -sfn "$C/nushell/config.nu"      "$nud/config.nu"
  run sudo ln -sfn "$C/nushell/env.nu"         "$nud/env.nu"
  run sudo ln -sfn "$C/nushell/scripts"        "$nud/scripts"
  run sudo ln -sfn "$C/zsh/.zshrc"             "$home/.zshrc"
  run sudo ln -sfn "$C/starship/starship.toml" "$home/.config/starship.toml"
  run sudo ln -sfn "$C/tmux/tmux.conf"         "$home/.config/tmux/tmux.conf"
  run sudo ln -sfn "$C/tmux/tmux.reset.conf"   "$home/.config/tmux/tmux.reset.conf"
  run sudo ln -sfn "$C/tmux/scripts"           "$home/.config/tmux/scripts"
  run sudo ln -sfn "$C/tmux/themes"            "$home/.config/tmux/themes"
  run sudo mkdir -p "$home/.config/zellij"
  run sudo ln -sfn "$C/zellij/themes"          "$home/.config/zellij/themes"
  run sudo mkdir -p "$home/.local/share/e-terminal"
  run sudo ln -sfn "$HOME/.local/share/e-terminal/zsh-plugins" "$home/.local/share/e-terminal/zsh-plugins"
  if [ -z "${DRY_RUN:-}" ]; then
    sudo cp -n "$C/nushell/env.local.example.nu" "$nud/env.local.nu"               2>/dev/null || true
    sudo cp -n "$C/zsh/.zshrc.local.example"      "$home/.zshrc.local"             2>/dev/null || true
    sudo cp -n "$C/tmux/themes/arrow.conf"        "$home/.config/tmux/theme.conf"  2>/dev/null || true
  fi
}

link_tools_systemwide() {
  local b p d
  local dirs=("$HOME/.local/bin" "$HOME/.cargo/bin" "/opt/homebrew/bin")
  for b in starship zoxide carapace zellij hcloud doctl; do
    p="$(command -v "$b" 2>/dev/null || true)"
    if [ -z "$p" ]; then
      for d in "${dirs[@]}"; do [ -x "$d/$b" ] && { p="$d/$b"; break; }; done
    fi
    [ -n "$p" ] || continue
    case "$p" in /usr/local/bin/*) continue ;; esac
    run sudo ln -sf "$p" "/usr/local/bin/$b"
  done
  local pair real
  for pair in fd:fdfind bat:batcat; do
    real="$(command -v "${pair##*:}" 2>/dev/null || true)"
    [ -n "$real" ] && run sudo ln -sf "$real" "/usr/local/bin/${pair%%:*}"
  done
}

install_root() {
  if [ -n "${SKIP_ROOT:-}" ]; then warn "SKIP_ROOT set; not configuring root"; return 0; fi
  command -v sudo >/dev/null 2>&1 || { warn "sudo not available; skipping root setup"; return 0; }

  local rhome; [ "$OS" = macos ] && rhome=/var/root || rhome=/root

  info "Sharing e-terminal with root (sudo) - so 'sudo nu' / rootsh are styled too"
  run sudo mkdir -p /usr/local/bin
  link_tools_systemwide
  run sudo ln -sf "$DOTFILES_DIR/config/bin/swapshell"      /usr/local/bin/swapshell
  run sudo ln -sf "$DOTFILES_DIR/config/bin/e-session-log"  /usr/local/bin/e-session-log
  run sudo ln -sf "$DOTFILES_DIR/config/bin/theme"          /usr/local/bin/theme
  local esv_os esv_arch
  esv_os="$(uname -s | tr 'A-Z' 'a-z')"
  case "$(uname -m)" in x86_64|amd64) esv_arch=amd64 ;; aarch64|arm64) esv_arch=arm64 ;; *) esv_arch="" ;; esac
  if [ -n "$esv_arch" ]; then
    for b in e-session-view e-session-rec; do
      [ -x "$DOTFILES_DIR/config/bin/${b}-${esv_os}-${esv_arch}" ] && run sudo ln -sf "$DOTFILES_DIR/config/bin/${b}-${esv_os}-${esv_arch}" "/usr/local/bin/${b}"
    done
  fi
  link_user_configs "$rhome"
  ok "root configured - drop in with: rootsh   (or: sudo -H nu)"

  if [ -n "${INSTALL_ALL_USERS:-}" ] && [ "$OS" != macos ]; then
    info "Linking configs for all human users (INSTALL_ALL_USERS)"
    local u uid h
    while IFS=: read -r u _ uid _ _ h _; do
      [ "${uid:-0}" -ge 1000 ] && [ "${uid:-0}" -lt 65000 ] && [ -d "$h" ] || continue
      [ "$h" = "$HOME" ] && continue
      link_user_configs "$h"
      run sudo chown -h "$u" "$h/.zshrc" "$h/.config/starship.toml" 2>/dev/null || true
      ok "linked $u ($h)"
    done < <(getent passwd)
  fi
}
