#!/usr/bin/env bash
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=''; C_DIM=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

log()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
info()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
ok()    { printf '  %sok%s   %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '  %swarn%s %s\n'   "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '  %serr%s  %s\n'   "$C_RED"    "$C_RESET" "$*" >&2; }
abort() { err "$*"; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

abbrev() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    "$HOME")   printf '~' ;;
    *)         printf '%s' "$1" ;;
  esac
}

run() {
  if [ -n "${DRY_RUN:-}" ]; then
    printf '  %s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# parrot is checked before debian because Parrot's ID_LIKE is "debian".
detect_os() {
  case "$(uname -s)" in
    Darwin) OS=macos; PKG=brew ;;
    Linux)
      OS=debian; PKG=apt
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case " ${ID:-} ${ID_LIKE:-} " in
          *parrot*) OS=parrot ;;
          *kali*)   OS=kali ;;
          *ubuntu*) OS=ubuntu ;;
          *debian*) OS=debian ;;
        esac
      fi
      ;;
    *) abort "Unsupported OS: $(uname -s)" ;;
  esac
  export OS PKG
}

preferred_shell() {
  case "$OS" in
    kali|parrot) echo zsh ;;
    *)           echo nu ;;
  esac
}

login_shell() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd "$(id -un)" | cut -d: -f7
  else
    dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}'
  fi
}

# File where the installer records the pre-change login shell, so uninstall can revert it.
orig_shell_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/login-shell.orig"; }

# macOS uses ~/Library/Application Support/nushell (NOT ~/.config/nushell) unless
# XDG_CONFIG_HOME is set; symlinking elsewhere means nu silently loads empty defaults.
nu_config_dir() {
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s/nushell' "$XDG_CONFIG_HOME"
  elif [ "$(uname -s)" = "Darwin" ]; then
    printf '%s/Library/Application Support/nushell' "$HOME"
  else
    printf '%s/.config/nushell' "$HOME"
  fi
}
