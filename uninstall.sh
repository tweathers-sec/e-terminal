#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/common.sh"

NU_DIR="$(nu_config_dir)"
MANAGED=(
  "$HOME/.zshrc"
  "$HOME/.config/starship.toml"
  "$HOME/.config/starship-console.toml"
  "$HOME/.config/ghostty/config"
  "$HOME/.config/tmux/tmux.conf"
  "$HOME/.config/tmux/tmux.reset.conf"
  "$HOME/.config/tmux/scripts"
  "$HOME/.config/tmux/themes"
  "$HOME/.config/zellij/themes"
  "$NU_DIR/config.nu"
  "$NU_DIR/env.nu"
  "$HOME/.local/bin/swapshell"
  "$HOME/.local/bin/e-session-log"
  "$HOME/.local/bin/e-session-rec"
  "$HOME/.local/bin/e-session-view"
  "$HOME/.local/bin/theme"
  "$HOME/.local/bin/e-update"
)

ETERM_ORIG="$HOME/.e-terminal-backup/original"

main() {
  info "e-terminal uninstall"
  detect_os

  local dst base
  for dst in "${MANAGED[@]}"; do
    base="$(basename "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      run rm -rf "$dst"
      ok "removed ${dst/#$HOME/~}"
    fi
    if [ -e "$ETERM_ORIG/$base.bak" ]; then
      run cp -RP "$ETERM_ORIG/$base.bak" "$dst" && ok "restored original ${dst/#$HOME/~}" || true
    fi
  done

  run rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/commit" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/eza-colors"

  local t
  for b in swapshell e-session-log e-session-rec e-session-view theme e-update; do
    t="/usr/local/bin/$b"
    [ -L "$t" ] || continue
    case "$(readlink "$t")" in
      "$DOTFILES_DIR"/*) run sudo rm -f "$t" && ok "removed system link $t" || warn "could not remove $t" ;;
    esac
  done

  local osf; osf="$(orig_shell_file)"
  if [ -f "$osf" ]; then
    local orig; orig="$(cat "$osf" 2>/dev/null || true)"
    if [ -n "$orig" ] && [ "$orig" != "$(login_shell)" ]; then
      info "Restoring login shell to $orig"
      run sudo chsh -s "$orig" "$(id -un)" && ok "login shell restored to $orig" || warn "run 'chsh -s $orig' to restore it"
    fi
    rm -f "$osf"
  fi

  info "Packages left installed (remove manually if desired)"
  if [ "$OS" = macos ]; then
    log "  brew uninstall starship fzf zoxide eza bat fd nushell carapace tmux"
    log "  brew uninstall --cask font-jetbrains-mono-nerd-font"
  else
    log "  sudo apt-get remove starship fzf zoxide eza bat fd-find nushell tmux  # plus ~/.local/bin installs"
  fi
  warn "Pre-install rollback snapshot (if present): ~/e-terminal-rollback/"
  info "Done. Open a new terminal."
}

main "$@"
