GHOSTTY_DEB_REPO="${GHOSTTY_DEB_REPO:-mkasberg/ghostty-ubuntu}"

is_headed_linux() {
  [ "$OS" = macos ] && return 1
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return 0
  case "${XDG_SESSION_TYPE:-}" in x11|wayland) return 0 ;; esac
  [ -e /etc/systemd/system/display-manager.service ] && return 0
  if command -v loginctl >/dev/null 2>&1; then
    local s t
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
      t="$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)"
      case "$t" in x11|wayland|mir) return 0 ;; esac
    done
  fi
  return 1
}

_ghostty_vm_softgl() {
  command -v ghostty >/dev/null 2>&1 || return 0
  systemd-detect-virt -q 2>/dev/null || return 0
  local sys="/usr/share/applications/com.mitchellh.ghostty.desktop"
  local usr="$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"
  [ -f "$sys" ] || return 0
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] would route Ghostty through software GL (VM)"; return 0; fi
  mkdir -p "$HOME/.local/share/applications"
  sed -e 's|^Exec=\(/usr/bin/\)\{0,1\}ghostty|Exec=env LIBGL_ALWAYS_SOFTWARE=1 \1ghostty|' \
      -e 's|^DBusActivatable=true|DBusActivatable=false|' "$sys" > "$usr"
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  ok "  $(systemd-detect-virt) VM: routed Ghostty through software GL (VM GPUs cap below the OpenGL 4.3 it needs)"
}

install_ghostty_linux() {
  [ "$OS" = macos ] && return 0
  [ -n "${SKIP_GHOSTTY:-}" ] && { log "  SKIP_GHOSTTY set; leaving Ghostty alone"; return 0; }
  command -v dpkg >/dev/null 2>&1 || return 0
  command -v curl >/dev/null 2>&1 || return 0

  info "Ghostty terminal (Linux)"
  if ! is_headed_linux; then
    ok "  headless system; skipping Ghostty app (config is still in place for SSH-in)"
    return 0
  fi

  local arch; arch="$(dpkg --print-architecture 2>/dev/null || true)"
  case "$arch" in
    amd64|arm64) ;;
    *) warn "  unsupported arch '$arch'; install Ghostty manually (https://ghostty.org)"; return 0 ;;
  esac

  local api="https://api.github.com/repos/$GHOSTTY_DEB_REPO/releases/latest"
  local tag; tag="$(curl -fsSL "$api" 2>/dev/null | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
  if [ -z "$tag" ]; then warn "  could not reach ghostty-ubuntu releases; skipping"; return 0; fi
  local ver="${tag%%-*}"

  if command -v ghostty >/dev/null 2>&1 && ghostty --version 2>/dev/null | grep -qF "$ver"; then
    ok "  Ghostty $ver already current"
    _ghostty_vm_softgl
    return 0
  fi
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] would install/upgrade Ghostty to $ver"; return 0; fi

  local osver oscode
  osver="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-}")"
  oscode="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")"
  local suites
  case "$OS" in
    ubuntu)      suites="$osver 26.04 24.04" ;;
    debian)      suites="$oscode trixie forky 24.04" ;;
    kali|parrot) suites="trixie forky 24.04" ;;
    *)           suites="$oscode $osver trixie 24.04" ;;
  esac

  local rel; rel="$(curl -fsSL "$api" 2>/dev/null | grep browser_download_url | cut -d'"' -f4 || true)"
  local s url=""
  for s in $suites; do
    [ -n "$s" ] || continue
    url="$(printf '%s\n' "$rel" | grep -m1 "_${arch}_${s}\.deb$" || true)"
    [ -n "$url" ] && break
  done
  if [ -z "$url" ]; then
    warn "  no prebuilt Ghostty .deb for ${OS} ${osver:-} ($arch); see https://ghostty.org"
    return 0
  fi

  if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
    warn "  Ghostty $ver is available but sudo is unavailable here; run install.sh on the box to update it"
    return 0
  fi

  local tmp; tmp="$(mktemp --suffix=.deb 2>/dev/null || mktemp)"
  if curl -fsSL -o "$tmp" "$url"; then
    if sudo dpkg -i "$tmp" >/dev/null 2>&1 || sudo apt-get -f install -y >/dev/null 2>&1; then
      ok "  Ghostty $ver installed ($(basename "$url"))"
    else
      warn "  Ghostty package install failed; see https://ghostty.org"
    fi
  else
    warn "  Ghostty download failed; skipping"
  fi
  rm -f "$tmp"
  _ghostty_vm_softgl
}
