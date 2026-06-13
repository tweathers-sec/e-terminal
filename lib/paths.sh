#!/usr/bin/env bash

ETERM_ZSH_MARK_BEGIN="# >>> e-terminal carried zsh setup (managed) >>>"
ETERM_ZSH_MARK_END="# <<< e-terminal carried zsh setup <<<"
ETERM_PATH_MARK_BEGIN="# >>> e-terminal carried PATH (managed) >>>"
ETERM_PATH_MARK_END="# <<< e-terminal carried PATH <<<"

ETERM_ZSH_CARRY=""
ETERM_CARRIED_PATHS=""

_eterm_baseline_paths() {
  if [ "$OS" = macos ] && [ -x /usr/libexec/path_helper ]; then
    /usr/libexec/path_helper -s 2>/dev/null \
      | sed -n 's/^PATH="\(.*\)"; export PATH;$/\1/p' | tr ':' '\n'
  fi
  printf '%s\n' \
    "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/go/bin" \
    /opt/homebrew/bin /opt/homebrew/sbin \
    /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin
}

_eterm_shell_path() {
  local sh="$1" out
  has "$sh" || return 0
  if has perl; then
    out="$(env -i HOME="$HOME" TERM="${TERM:-xterm}" LANG="${LANG:-en_US.UTF-8}" \
           PATH="/usr/bin:/bin:/usr/sbin:/sbin" E_SESSION_LOG_ACTIVE=1 \
           perl -e 'alarm 10; exec @ARGV or exit 127' \
           "$sh" -lic 'printf "\nETERMPATH:%s\n" "$PATH"' 2>/dev/null)" || true
  else
    out="$(env -i HOME="$HOME" TERM="${TERM:-xterm}" LANG="${LANG:-en_US.UTF-8}" \
           PATH="/usr/bin:/bin:/usr/sbin:/sbin" E_SESSION_LOG_ACTIVE=1 \
           "$sh" -lic 'printf "\nETERMPATH:%s\n" "$PATH"' 2>/dev/null)" || true
  fi
  printf '%s\n' "$out" | sed -n 's/^ETERMPATH://p' | tail -1 | tr ':' '\n'
}

_eterm_is_ours() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in "$DOTFILES_DIR"/*) return 0 ;; *) return 1 ;; esac
}

capture_user_config() {
  info "Capturing existing shell setup"

  local zrc="$HOME/.zshrc"
  if [ -f "$zrc" ] && ! _eterm_is_ours "$zrc"; then
    ETERM_ZSH_CARRY="$(cat "$zrc")"
    ok "carrying your ~/.zshrc verbatim (nvm, version managers, aliases, env)"
  fi

  local baseline; baseline="$(_eterm_baseline_paths | sort -u)"
  local cur; cur="$(login_shell)"
  local candidates
  candidates="$( { _eterm_shell_path "$cur"; _eterm_shell_path zsh; _eterm_shell_path bash; } 2>/dev/null )"
  local extras="" d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$d" in /*) ;; *) continue ;; esac
    [ -d "$d" ] || continue
    printf '%s\n' "$baseline" | grep -qxF "$d" && continue
    printf '%s\n' "$extras"   | grep -qxF "$d" && continue
    extras="${extras}${d}"$'\n'
  done <<EOF
$candidates
EOF
  ETERM_CARRIED_PATHS="$(printf '%s' "$extras" | sed '/^[[:space:]]*$/d')"
  local n; n="$(printf '%s\n' "$ETERM_CARRIED_PATHS" | grep -c . || true)"
  [ -n "$ETERM_CARRIED_PATHS" ] && ok "carrying $n custom PATH dir(s) for nushell"
}

_eterm_strip_block() {
  local f="$1" b="$2" e="$3" tmp
  [ -f "$f" ] || return 0
  tmp="$(mktemp)"
  awk -v b="$b" -v e="$e" '$0==b{s=1;next} $0==e{s=0;next} s!=1{print}' "$f" > "$tmp" && mv "$tmp" "$f"
}

apply_user_config() {
  { [ -n "$ETERM_ZSH_CARRY" ] || [ -n "$ETERM_CARRIED_PATHS" ]; } || return 0
  local zlocal="$HOME/.zshrc.local" nulocal; nulocal="$(nu_config_dir)/env.local.nu"
  info "Restoring your setup into local overrides"
  if [ -n "${DRY_RUN:-}" ]; then
    log "  [dry-run] would update $(abbrev "$zlocal") and $(abbrev "$nulocal")"
    return 0
  fi

  mkdir -p "$(dirname "$zlocal")"; [ -f "$zlocal" ] || : > "$zlocal"
  if [ -n "$ETERM_ZSH_CARRY" ]; then
    _eterm_strip_block "$zlocal" "$ETERM_ZSH_MARK_BEGIN" "$ETERM_ZSH_MARK_END"
    { printf '\n%s\n' "$ETERM_ZSH_MARK_BEGIN"
      printf '%s\n' "$ETERM_ZSH_CARRY"
      printf '%s\n' "$ETERM_ZSH_MARK_END"
    } >> "$zlocal"
    ok "restored your ~/.zshrc into $(abbrev "$zlocal")"
  fi

  [ -n "$ETERM_CARRIED_PATHS" ] || return 0
  local joined; joined="$(printf '%s\n' "$ETERM_CARRIED_PATHS" | grep . | paste -sd: -)"
  _eterm_strip_block "$zlocal" "$ETERM_PATH_MARK_BEGIN" "$ETERM_PATH_MARK_END"
  { printf '\n%s\n' "$ETERM_PATH_MARK_BEGIN"
    printf 'export PATH="%s:$PATH"\n' "$joined"
    printf '%s\n' "$ETERM_PATH_MARK_END"
  } >> "$zlocal"

  mkdir -p "$(dirname "$nulocal")"; [ -f "$nulocal" ] || : > "$nulocal"
  _eterm_strip_block "$nulocal" "$ETERM_PATH_MARK_BEGIN" "$ETERM_PATH_MARK_END"
  { printf '\n%s\n' "$ETERM_PATH_MARK_BEGIN"
    printf 'use std "path add"\n'
    printf '%s\n' "$ETERM_CARRIED_PATHS" | grep . | while IFS= read -r d; do
      printf 'path add "%s"\n' "$d"
    done
    printf '%s\n' "$ETERM_PATH_MARK_END"
  } >> "$nulocal"
  ok "carried custom PATH into $(abbrev "$nulocal")"
}
