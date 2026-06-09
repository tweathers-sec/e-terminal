#!/usr/bin/env bash
install_packages() {
  case "$PKG" in
    brew) install_packages_brew ;;
    apt)  install_packages_apt  ;;
    *)    abort "Unknown package manager: $PKG" ;;
  esac
}

install_packages_brew() {
  has brew || abort "Homebrew not found. Install it from https://brew.sh and re-run."
  if [ -n "${SKIP_BREW:-}" ]; then warn "SKIP_BREW set; skipping brew bundle"; return 0; fi
  info "Installing packages via Homebrew (brew bundle)"
  run brew bundle --file="$DOTFILES_DIR/Brewfile"
  [ -z "${SKIP_HCLOUD:-}" ] && ensure_brew_formula hcloud
  [ -z "${SKIP_DOCTL:-}" ]  && ensure_brew_formula doctl
  return 0
}

ensure_brew_formula() {
  local f="$1"
  if brew list --formula "$f" >/dev/null 2>&1; then ok "$f present"; else run brew install "$f"; fi
}

install_packages_apt() {
  if [ -n "${SKIP_APT:-}" ]; then warn "SKIP_APT set; skipping apt installs"; return 0; fi
  export DEBIAN_FRONTEND=noninteractive
  run mkdir -p "$HOME/.local/bin" /tmp >/dev/null 2>&1 || true

  info "apt update + core packages"
  run sudo apt-get update -y
  apt_install zsh tmux git curl wget unzip gpg ca-certificates build-essential \
              fontconfig net-tools dnsutils iproute2 openssl \
              zstd xz-utils p7zip-full fzf ripgrep jq bat fd-find
  link_bat_fd_shims

  ensure_starship
  ensure_zoxide
  ensure_atuin
  ensure_eza
  ensure_nushell
  ensure_carapace
  ensure_zellij
  [ -z "${SKIP_HCLOUD:-}" ] && ensure_release_bin hcloud hetznercloud/cli
  [ -z "${SKIP_DOCTL:-}" ]  && ensure_release_bin doctl  digitalocean/doctl
  return 0
}

apt_install() {
  local pkgs=() p
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || pkgs+=("$p"); done
  if [ ${#pkgs[@]} -eq 0 ]; then ok "apt: all present"; return 0; fi
  run sudo apt-get install -y "${pkgs[@]}"
}

# Debian/Ubuntu/Kali ship bat as batcat and fd as fdfind.
link_bat_fd_shims() {
  run mkdir -p "$HOME/.local/bin"
  if has batcat && ! has bat; then run ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"; ok "shim bat -> batcat"; fi
  if has fdfind && ! has fd;  then run ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd";  ok "shim fd -> fdfind";  fi
}

ensure_starship() {
  if has starship; then ok "starship present"; return 0; fi
  info "Installing starship"
  run sh -c "curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b \"$HOME/.local/bin\""
}

ensure_zoxide() {
  if has zoxide; then ok "zoxide present"; return 0; fi
  info "Installing zoxide"
  run sh -c "curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
}

ensure_atuin() {
  if has atuin; then ok "atuin present"; return 0; fi
  info "Installing atuin"
  run sh -c "curl -fsSL https://setup.atuin.sh | sh"
}

ensure_eza() {
  if has eza; then ok "eza present"; return 0; fi
  info "Installing eza"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] add eza apt repo (deb.gierens.de) then apt-get install eza"; return 0; fi
  if sudo mkdir -p /etc/apt/keyrings \
     && curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
          | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null \
     && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
          | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null \
     && sudo apt-get update -y && sudo apt-get install -y eza; then
    ok "eza via apt"
  elif has cargo; then
    warn "eza apt repo failed; building via cargo"
    cargo install eza
  else
    warn "could not install eza (no apt repo, no cargo) — skipping"
  fi
}

ensure_nushell() {
  if has nu; then ok "nushell present"; return 0; fi
  info "Installing nushell"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] add nushell fury repo then apt-get install nushell"; return 0; fi
  if sudo mkdir -p /etc/apt/keyrings \
     && curl -fsSL https://apt.fury.io/nushell/gpg.key \
          | sudo gpg --dearmor -o /etc/apt/keyrings/fury-nushell.gpg 2>/dev/null \
     && echo "deb [signed-by=/etc/apt/keyrings/fury-nushell.gpg] https://apt.fury.io/nushell/ /" \
          | sudo tee /etc/apt/sources.list.d/fury-nushell.list >/dev/null \
     && sudo apt-get update -y && sudo apt-get install -y nushell; then
    ok "nushell via apt"
  elif has cargo; then
    warn "nushell apt repo failed; building via cargo (slow)"
    cargo install nu
  else
    warn "could not install nushell — skipping (zsh remains available)"
  fi
}

ensure_carapace() {
  if has carapace; then ok "carapace present"; return 0; fi
  info "Installing carapace"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] install carapace-bin .deb from latest release"; return 0; fi
  local arch deb_arch url tmp
  arch="$(uname -m)"; case "$arch" in x86_64) deb_arch=amd64;; aarch64|arm64) deb_arch=arm64;; *) deb_arch=amd64;; esac
  url="$(curl -fsSL https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest \
         | jq -r --arg a "$deb_arch" '.assets[] | select(.name | test("linux." + $a + ".deb$")) | .browser_download_url' \
         | head -1)"
  if [ -n "$url" ]; then
    tmp="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp/carapace.deb" && sudo apt-get install -y "$tmp/carapace.deb"; then
      ok "carapace via deb"
    else
      warn "carapace install failed — completions still work without it"
    fi
    rm -rf "$tmp"
  else
    warn "could not resolve carapace release — skipping"
  fi
}

# zellij asset names use x86_64/aarch64, not amd64/arm64, so it gets its own installer.
ensure_zellij() {
  if has zellij; then ok "zellij present"; return 0; fi
  info "Installing zellij"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] download zellij musl release tarball"; return 0; fi
  local arch rel url tmp
  arch="$(uname -m)"; case "$arch" in x86_64) rel=x86_64;; aarch64|arm64) rel=aarch64;; *) rel=x86_64;; esac
  url="$(curl -fsSL https://api.github.com/repos/zellij-org/zellij/releases/latest \
         | jq -r --arg a "$rel" '.assets[] | select(.name | test("zellij-" + $a + "-unknown-linux-musl.tar.gz$")) | .browser_download_url' \
         | head -1)"
  if [ -n "$url" ]; then
    tmp="$(mktemp -d)"
    if curl -fsSL "$url" | tar -xz -C "$tmp" 2>/dev/null && [ -f "$tmp/zellij" ]; then
      install -m 0755 "$tmp/zellij" "$HOME/.local/bin/zellij" && ok "zellij installed"
    else
      warn "zellij extract failed — skipping (optional, tmux remains the default)"
    fi
    rm -rf "$tmp"
  else
    warn "could not resolve zellij release — skipping (optional)"
  fi
}

ensure_release_bin() {
  local bin="$1" repo="$2"
  if has "$bin"; then ok "$bin present"; return 0; fi
  info "Installing $bin ($repo)"
  if [ -n "${DRY_RUN:-}" ]; then log "  [dry-run] download $bin from $repo latest release"; return 0; fi
  local arch rel_arch url tmp
  arch="$(uname -m)"; case "$arch" in x86_64) rel_arch=amd64;; aarch64|arm64) rel_arch=arm64;; *) rel_arch=amd64;; esac
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
         | jq -r --arg a "$rel_arch" '.assets[] | select(.name | test("linux.*" + $a + ".tar.gz$")) | .browser_download_url' \
         | head -1)"
  if [ -n "$url" ]; then
    tmp="$(mktemp -d)"
    if curl -fsSL "$url" | tar -xz -C "$tmp" 2>/dev/null && [ -f "$tmp/$bin" ]; then
      install -m 0755 "$tmp/$bin" "$HOME/.local/bin/$bin" && ok "$bin installed"
    else
      warn "$bin extract failed — skipping (optional)"
    fi
    rm -rf "$tmp"
  else
    warn "could not resolve $bin release — skipping (optional)"
  fi
}
