#!/usr/bin/env bash

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

strip_repo_git() {
  [ -e "$DOTFILES_DIR/.git" ] || [ -e "$DOTFILES_DIR/.gitignore" ] || [ -e "$DOTFILES_DIR/.gitmodules" ] || return 0
  if [ -n "${KEEP_GIT:-}" ]; then warn "KEEP_GIT set; leaving git metadata in $(abbrev "$DOTFILES_DIR")"; return 0; fi
  if [ -z "${DRY_RUN:-}" ] && command -v git >/dev/null 2>&1 && [ -d "$DOTFILES_DIR/.git" ]; then
    git -C "$DOTFILES_DIR" rev-parse HEAD > "$DOTFILES_DIR/.e-terminal-commit" 2>/dev/null || true
  fi
  info "Removing git metadata (deployed copy has no remote and can't push to the repo)"
  run rm -rf "$DOTFILES_DIR/.git" "$DOTFILES_DIR/.gitignore" "$DOTFILES_DIR/.gitattributes" \
             "$DOTFILES_DIR/.gitmodules" "$DOTFILES_DIR/.github"
  ok "git metadata removed from $(abbrev "$DOTFILES_DIR")"
}
