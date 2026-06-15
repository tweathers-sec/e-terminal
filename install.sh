#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

source "$DOTFILES_DIR/lib/common.sh"
source "$DOTFILES_DIR/lib/symlink.sh"
source "$DOTFILES_DIR/lib/cleanup.sh"
source "$DOTFILES_DIR/lib/root.sh"
source "$DOTFILES_DIR/lib/packages.sh"
source "$DOTFILES_DIR/lib/ghostty.sh"
source "$DOTFILES_DIR/lib/font.sh"
source "$DOTFILES_DIR/lib/plugins.sh"
source "$DOTFILES_DIR/lib/paths.sh"

trap 'rc=$?; err "install aborted unexpectedly (${BASH_SOURCE[0]##*/}:${LINENO}, exit ${rc}) - please report this"' ERR

link_configs() {
  info "Installing configs"
  local C="$DOTFILES_DIR/config"
  local prev_theme; prev_theme="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/theme" 2>/dev/null || true)"
  [ -n "$prev_theme" ] || prev_theme="$(sed -n 's/^palette = "\(.*\)"/\1/p' "$HOME/.config/starship.toml" 2>/dev/null | head -1 || true)"

  install_path "$C/zsh/.zshrc"               "$HOME/.zshrc"
  install_path "$C/starship/starship.toml"   "$HOME/.config/starship.toml"
  install_path "$C/starship/starship-console.toml" "$HOME/.config/starship-console.toml"
  install_path "$C/ghostty/config"           "$HOME/.config/ghostty/config"
  install_path "$C/ghostty/themes"            "$HOME/.config/ghostty/themes"
  install_path "$C/tmux/tmux.conf"           "$HOME/.config/tmux/tmux.conf"
  install_path "$C/tmux/tmux.reset.conf"     "$HOME/.config/tmux/tmux.reset.conf"
  install_path "$C/tmux/scripts"             "$HOME/.config/tmux/scripts"
  install_path "$C/tmux/themes"              "$HOME/.config/tmux/themes"
  install_path "$C/zellij/themes"            "$HOME/.config/zellij/themes"
  local NU_DIR; NU_DIR="$(nu_config_dir)"
  install_path "$C/nushell/config.nu"        "$NU_DIR/config.nu"
  install_path "$C/nushell/env.nu"           "$NU_DIR/env.nu"
  install_path "$C/nushell/scripts"          "$NU_DIR/scripts"

  run mkdir -p "$HOME/.local/bin"
  run chmod +x "$C/bin/swapshell" "$C/bin/e-session-log" "$C/bin/theme" "$C/bin/e-update" "$C/tmux/scripts/"*.sh 2>/dev/null || true
  install_path "$C/bin/swapshell"            "$HOME/.local/bin/swapshell"
  install_path "$C/bin/e-session-log"        "$HOME/.local/bin/e-session-log"
  install_path "$C/bin/theme"                "$HOME/.local/bin/theme"
  install_path "$C/bin/e-update"             "$HOME/.local/bin/e-update"
  _esv_os="$(uname -s | tr 'A-Z' 'a-z')"
  case "$(uname -m)" in x86_64|amd64) _esv_arch=amd64 ;; aarch64|arm64) _esv_arch=arm64 ;; *) _esv_arch="" ;; esac
  if [ -n "$_esv_arch" ]; then
    for _b in e-session-view e-session-rec; do
      [ -x "$C/bin/${_b}-${_esv_os}-${_esv_arch}" ] && install_path "$C/bin/${_b}-${_esv_os}-${_esv_arch}" "$HOME/.local/bin/${_b}"
    done
  fi

  ok "configs copied into place"

  seed_local "$C/zsh/.zshrc.local.example"          "$HOME/.zshrc.local"
  seed_local "$C/nushell/env.local.example.nu"      "$NU_DIR/env.local.nu"
  seed_local "$C/tmux/themes/arrow.conf"       "$HOME/.config/tmux/theme.conf"
  if [ -z "${DRY_RUN:-}" ] && [ "$OS" != macos ] && [ ! -e "$HOME/.config/ghostty/config.local" ]; then
    mkdir -p "$HOME/.config/ghostty"
    printf 'font-size = 14\nwindow-width = 120\nwindow-height = 34\n' > "$HOME/.config/ghostty/config.local"
    ok "seeded ghostty local overrides ($(abbrev "$HOME/.config/ghostty/config.local"))"
  fi
  if [ -z "${DRY_RUN:-}" ]; then
    local zc="$HOME/.config/zellij/config.kdl"; mkdir -p "$HOME/.config/zellij"; [ -f "$zc" ] || : > "$zc"
    grep -qE '^[[:space:]]*theme[[:space:]]+"' "$zc" || { printf 'theme "arrow"\n' >> "$zc"; ok "zellij theme set to arrow"; }
  fi
  if [ -z "${DRY_RUN:-}" ]; then
    if [ -n "$prev_theme" ] && [ -f "$HOME/.config/tmux/themes/$prev_theme.conf" ]; then
      sh "$C/bin/theme" __apply "$prev_theme" >/dev/null 2>&1 && ok "theme restored: $prev_theme" || true
    else
      sh "$C/bin/theme" __output >/dev/null 2>&1 && ok "themed command output (eza colors)" || true
    fi
  fi
}

seed_local() {
  local example="$1" dest="$2"
  if [ -e "$dest" ]; then ok "local override present: $(abbrev "$dest")"; return 0; fi
  run mkdir -p "$(dirname "$dest")"
  if [ -z "${DRY_RUN:-}" ]; then cp "$example" "$dest"; fi
  ok "seeded $(abbrev "$dest") (edit it for machine-specific env/secrets)"
}

ensure_ghostty_terminfo() {
  has tic || return 0
  infocmp xterm-ghostty >/dev/null 2>&1 && { ok "xterm-ghostty terminfo present"; return 0; }
  info "Installing xterm-ghostty terminfo (so SSH-in from Ghostty has a correct TERM)"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] tic -x config/terminfo/xterm-ghostty.terminfo"; return 0; fi
  if tic -x "$DOTFILES_DIR/config/terminfo/xterm-ghostty.terminfo" 2>/dev/null; then
    ok "xterm-ghostty terminfo installed"
  else
    warn "could not install xterm-ghostty terminfo (tmux/SSH may warn about TERM)"
  fi
}

import_history() {
  local zsh_hist="$HOME/.zsh_history" nu_hist; nu_hist="$(nu_config_dir)/history.txt"
  [ -f "$zsh_hist" ] || return 0
  local lines; lines="$( [ -f "$nu_hist" ] && wc -l < "$nu_hist" 2>/dev/null || echo 0 )"
  if [ "${lines:-0}" -lt 100 ]; then
    info "Seeding nushell history from zsh (inline suggestions)"
    if [ -z "${DRY_RUN:-}" ]; then
      mkdir -p "$(dirname "$nu_hist")"
      local tmp; tmp="$(mktemp)"
      LC_ALL=C sed -E 's/^: [0-9]+:[0-9]+;//' "$zsh_hist" 2>/dev/null \
        | iconv -c -f UTF-8 -t UTF-8 \
        | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' \
        | awk 'length>0 && length<800 && !seen[$0]++' > "$tmp"
      [ -f "$nu_hist" ] && cat "$nu_hist" >> "$tmp"
      mv "$tmp" "$nu_hist"
    fi
    ok "seeded nushell history ($(abbrev "$nu_hist"))"
  else
    ok "nushell history already populated ($(abbrev "$nu_hist"))"
  fi
}

set_default_shell() {
  local pref path user cur stored
  stored="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/shell" 2>/dev/null || true)"
  if [ -n "$stored" ] && [ -x "$stored" ]; then
    path="$stored"; pref="$(basename "$stored")"
  else
    pref="$(preferred_shell)"; path="$(command -v "$pref" 2>/dev/null)"
  fi
  user="$(id -un)"
  cur="$(login_shell)"
  info "Default shell"
  if [ -n "${SKIP_SHELL_CHANGE:-}" ]; then
    log "  SKIP_SHELL_CHANGE set; leaving $cur (default for $OS: $pref)"
    return 0
  fi
  if [ -z "$path" ]; then warn "  $pref not installed; leaving shell as $cur"; return 0; fi
  if [ "$cur" = "$path" ]; then ok "  already $pref ($path)"; return 0; fi
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] would set login shell to $path"; return 0; fi
  local osf; osf="$(orig_shell_file)"; [ -f "$osf" ] || { mkdir -p "$(dirname "$osf")"; printf '%s\n' "$cur" > "$osf"; }
  grep -qxF "$path" /etc/shells 2>/dev/null || run sudo sh -c "printf '%s\n' '$path' >> /etc/shells"
  if run sudo chsh -s "$path" "$user"; then
    ok "  login shell set to $pref ($path) - open a new terminal to use it"
  else
    warn "  could not set the login shell; run 'swapshell' to set it manually"
  fi
}

post_install_notes() {
  info "Next steps"
  log "  • tmux: open tmux and press 'prefix + I' (Ctrl-a then Shift-i) to install plugins"
  log "  • shell: login shell set automatically; run 'swapshell' anytime to change it"
  [ "$OS" != macos ] && log "  • Ghostty: auto-installed on headed (GUI) Linux, skipped on headless; config is in place either way"
  log "  • open a NEW terminal window to load everything"
  if [ -d "${BACKUP_DIR:-/nonexistent}" ]; then
    warn "previous files backed up to: $(abbrev "$BACKUP_DIR")"
  fi
}

main() {
  info "e-terminal installer"
  detect_os
  log "  OS=$OS  PKG=$PKG  ${DRY_RUN:+(dry-run)}"
  warn "Recommended on a fresh VM or container first - this changes your shell, prompt, and configs."
  log "  Existing files are backed up to ~/.e-terminal-backup/<timestamp>/ (run uninstall.sh to roll back)."

  install_packages
  install_ghostty_linux
  install_nerd_font
  install_plugins
  capture_user_config
  clean_conflicts
  link_configs
  apply_user_config
  ensure_ghostty_terminfo
  install_tmux_plugins
  install_root
  import_history
  set_default_shell
  post_install_notes
  strip_repo_git

  info "Done."
}

main "$@"
