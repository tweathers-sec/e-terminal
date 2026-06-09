#!/usr/bin/env bash
# Frameworks like oh-my-zsh / prezto / zinit hook the same ZLE widgets and prompt that
# the e-terminal .zshrc + Starship own. Leaving a framework on disk risks double-loads
# (e.g. a stray `source $ZSH/oh-my-zsh.sh` in a machine-local file), which wraps
# `self-insert` twice and causes doubled keystrokes. Conflicts are moved into the
# per-run backup dir (reversible), never hard-deleted.

quarantine() {
  local target="$1" label="$2"
  [ -e "$target" ] || [ -L "$target" ] || return 0
  if [ -n "${DRY_RUN:-}" ]; then
    warn "[dry-run] would quarantine ${label}: $(abbrev "$target")"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  if mv "$target" "$BACKUP_DIR/$(basename "$target").conflict" 2>/dev/null; then
    warn "quarantined ${label}: $(abbrev "$target") -> $(abbrev "$BACKUP_DIR")"
  else
    warn "could not move ${label}: $(abbrev "$target") (leave it; not fatal)"
  fi
}

clean_conflicts() {
  if [ -n "${SKIP_CLEANUP:-}" ]; then warn "SKIP_CLEANUP set; leaving prior frameworks in place"; return 0; fi
  info "Quarantining conflicting shell frameworks (reversible — moved to backup)"
  quarantine "$HOME/.oh-my-zsh"     "oh-my-zsh"
  quarantine "$HOME/.zprezto"       "prezto"
  quarantine "$HOME/.zinit"         "zinit"
  quarantine "$HOME/.zi"            "zinit"
  quarantine "$HOME/.zplug"         "zplug"
  quarantine "$HOME/.antigen"       "antigen"
  quarantine "$HOME/.antigen.zsh"   "antigen"
  quarantine "$HOME/.p10k.zsh"      "powerlevel10k config"
  ok "conflict scan complete"
}
