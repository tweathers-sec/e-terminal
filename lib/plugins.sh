#!/usr/bin/env bash
ZSH_PLUGIN_DIR="$HOME/.local/share/e-terminal/zsh-plugins"
TPM_DIR="$HOME/.config/tmux/plugins/tpm"

clone_if_absent() {
  local repo="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    ok "plugin present: $(basename "$dest")"
    return 0
  fi
  run git clone --depth=1 "https://github.com/$repo" "$dest"
}

install_zsh_plugins() {
  run mkdir -p "$ZSH_PLUGIN_DIR"
  clone_if_absent zsh-users/zsh-autosuggestions          "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
  clone_if_absent zsh-users/zsh-syntax-highlighting      "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
  clone_if_absent zsh-users/zsh-history-substring-search "$ZSH_PLUGIN_DIR/zsh-history-substring-search"
}

install_tpm() {
  if [ -n "${SKIP_TMUX_PLUGINS:-}" ]; then warn "SKIP_TMUX_PLUGINS set; skipping TPM"; return 0; fi
  clone_if_absent tmux-plugins/tpm "$TPM_DIR"
}

install_plugins() {
  if [ -n "${SKIP_PLUGINS:-}" ]; then warn "SKIP_PLUGINS set; skipping plugins"; return 0; fi
  info "Installing shell + tmux plugins"
  install_zsh_plugins
  install_tpm
}

install_tmux_plugins() {
  if [ -n "${SKIP_PLUGINS:-}" ] || [ -n "${SKIP_TMUX_PLUGINS:-}" ]; then return 0; fi
  [ -x "$TPM_DIR/bin/install_plugins" ] || { warn "TPM not present; run 'prefix + I' in tmux"; return 0; }
  info "Installing tmux plugins via TPM"
  run env TMUX_PLUGIN_MANAGER_PATH="$HOME/.config/tmux/plugins" "$TPM_DIR/bin/install_plugins" \
    || warn "  some tmux plugins did not install; open tmux and press prefix + I to finish"
  return 0
}
