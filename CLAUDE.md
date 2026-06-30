# e-terminal

One-command, cross-platform terminal setup (Starship + tmux + zellij + Nushell/zsh + a structured command toolbelt). Same prompt and tools on macOS and Debian/Ubuntu/Kali/Parrot. Installs by COPYING configs into `~/.config` (root gets symlinks), and sets the OS login shell. Source-available, non-commercial (Mayweather Group / VTEM / Travis Weathers).

## Install / update / uninstall
- Install: `git clone <repo> ~/.e-terminal && ~/.e-terminal/install.sh`. Idempotent; safe to re-run.
- Entrypoint: `install.sh` sources `lib/*.sh`; `main()` (install.sh:157) runs packages, ghostty, font, plugins, capture/clean/link configs, terminfo, tmux plugins, root, history import, set login shell. Strips its own `.git` afterward (cleanup.sh:32) so the deployed copy has no remote.
- Update: `e-update` (config/bin/e-update) clones latest `main` to a tmp dir and re-runs `install.sh` with `SKIP_ROOT SKIP_SHELL_CHANGE SKIP_BREW SKIP_APT`. Compares `~/.config/e-terminal/commit` to remote HEAD. Flags: `-f/--force`, `-V/--version`. Overrides: `E_TERMINAL_REPO`, `E_TERMINAL_REPO_URL`.
- Uninstall: `~/.e-terminal/uninstall.sh` removes managed files, restores saved originals, restores login shell, leaves packages.

## Layout
- `install.sh`, `uninstall.sh`, `Brewfile`.
- `lib/`: `common.sh` (logging, `detect_os`, `preferred_shell`, `login_shell`, `nu_config_dir`), `packages.sh` (brew bundle vs apt + release downloads), `font.sh`, `plugins.sh` (zsh plugins + TPM), `ghostty.sh` (Linux .deb, headed-only), `cleanup.sh` (quarantine frameworks, strip git), `symlink.sh` (`install_path` copy + backup), `paths.sh` (carry user `.zshrc`/PATH into local overrides), `root.sh` (share setup with root).
- `config/`: `starship/` (starship.toml, 31 `[palettes.*]`, + console variant), `tmux/` (tmux.conf, tmux.reset.conf, scripts/ status, themes/ 31 `@thm_*`), `zellij/themes/` (31 KDL), `nushell/` (config.nu, env.nu, scripts/ = the toolbelt), `zsh/.zshrc`, `ghostty/` (config + themes), `terminfo/xterm-ghostty`, `bin/` (swapshell, theme, e-session-log, e-update + per-arch `e-session-rec`/`e-session-view`).
- `viewer/`: Go module; source for the session recorder/viewer binaries shipped in `config/bin/`.

## Platform handling (common.sh)
- macOS: `OS=macos PKG=brew`; default shell **nu**; packages via `brew bundle` (Brewfile) + hcloud/doctl; font cask; nu config in `~/Library/Application Support/nushell`; root home `/var/root`.
- Linux (debian/ubuntu/kali/parrot via /etc/os-release): `PKG=apt`; default shell **zsh**; core via apt, then release/installer downloads for starship, zoxide, eza, nushell, carapace, zellij, hcloud, doctl; `bat`/`fd` shimmed from `batcat`/`fdfind`; Nerd Font tarball + `fc-cache`; Ghostty .deb only on headed systems; nu config in `~/.config/nushell`; root home `/root`.

## Gotchas
- Sets the OS login shell via `sudo chsh`; original saved to `~/.config/e-terminal/login-shell.orig`. Open a NEW terminal after install. Change later with `swapshell`.
- Linux needs `sudo` (apt installs, /etc/shells, root setup). macOS needs Homebrew.
- Existing configs backed up: per-run conflicts to `~/.e-terminal-backup/<timestamp>/`, pre-install originals once to `~/.e-terminal-backup/original/<name>.bak` (restored on uninstall).
- Conflicting zsh frameworks (oh-my-zsh, prezto, zinit, zplug, antigen, p10k) are MOVED to the backup dir, never deleted.
- Root parity: `install_root` symlinks configs + tools into root's home and `/usr/local/bin` so `sudo nu` / `rootsh` are styled. Skip with `SKIP_ROOT=1`; all human users (Linux) with `INSTALL_ALL_USERS=1`.
- Secrets never committed; git-ignored overrides `~/.zshrc.local` and nushell `env.local.nu` are sourced last.
- Install flags (env-prefix): `DRY_RUN`, `SKIP_BREW`/`SKIP_APT`, `SKIP_FONT`, `SKIP_PLUGINS`/`SKIP_TMUX_PLUGINS`, `SKIP_CLEANUP`, `SKIP_SHELL_CHANGE`, `SKIP_ROOT`, `SKIP_GHOSTTY`, `SKIP_HCLOUD`/`SKIP_DOCTL`, `INSTALL_ALL_USERS`, `KEEP_GIT`, `NO_COLOR`.

## Conventions
- Themes are unified: `theme <name>` recolors Starship + tmux + zellij + eza output together; persists. Add a theme = matching `tmux/themes/<n>.conf` + starship `[palettes.<n>]` + optional `zellij/themes/<n>.kdl`.
- POSIX/bash 3.2-safe shell; output via `info/ok/warn/err` (common.sh); every mutation wrapped in `run` for `DRY_RUN`.
- Template clones get e-terminal from external Proxmox vendor provisioning (infra), not a repo feature.
