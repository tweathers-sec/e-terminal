
if [[ -z "${E_SESSION_LOG_ACTIVE:-}" && -z "${TMUX:-}" && -o interactive ]]; then
  for _eslog in "$HOME/.local/bin/e-session-log" /usr/local/bin/e-session-log; do
    [[ -x "$_eslog" ]] && exec "$_eslog" start "${commands[zsh]:-/bin/zsh}"
  done
  unset _eslog
fi

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS \
       HIST_IGNORE_SPACE HIST_FIND_NO_DUPS SHARE_HISTORY INC_APPEND_HISTORY
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS
bindkey -e

[[ "$OSTYPE" == darwin* && -x /usr/libexec/path_helper ]] && eval "$(/usr/libexec/path_helper -s)"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH"
typeset -U path PATH

autoload -Uz compinit && compinit -C

[[ "$TERM" == linux ]] && export STARSHIP_CONFIG="$HOME/.config/starship-console.toml"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init zsh)"
if command -v carapace >/dev/null 2>&1; then
  export CARAPACE_BRIDGES='zsh,fish,bash'
  source <(carapace _carapace zsh)
fi
if command -v fzf >/dev/null 2>&1; then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    for f in /usr/share/doc/fzf/examples/key-bindings.zsh /usr/share/fzf/key-bindings.zsh \
             /usr/share/doc/fzf/examples/completion.zsh    /usr/share/fzf/completion.zsh; do
      [ -f "$f" ] && source "$f"
    done
  fi
fi
ETERM_ZSH_PLUGINS="$HOME/.local/share/e-terminal/zsh-plugins"
if (( ! ${+functions[_zsh_autosuggest_start]} )) && \
   [ -f "$ETERM_ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$ETERM_ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if (( ! ${+functions[history-substring-search-up]} )) && \
   [ -f "$ETERM_ZSH_PLUGINS/zsh-history-substring-search/zsh-history-substring-search.zsh" ]; then
  source "$ETERM_ZSH_PLUGINS/zsh-history-substring-search/zsh-history-substring-search.zsh"
fi

zmodload zsh/terminfo 2>/dev/null
for _k in '^[[A' '^[OA' "${terminfo[kcuu1]:-}"; do [ -n "$_k" ] && bindkey "$_k" history-substring-search-up; done
for _k in '^[[B' '^[OB' "${terminfo[kcud1]:-}"; do [ -n "$_k" ] && bindkey "$_k" history-substring-search-down; done
unset _k
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1 && alias bat='batcat'
command -v fdfind >/dev/null 2>&1 && ! command -v fd  >/dev/null 2>&1 && alias fd='fdfind'
if command -v eza >/dev/null 2>&1; then
  _icons='--icons'; [[ "$TERM" == linux ]] && _icons=''
  alias ls="eza $_icons --group-directories-first"
  alias ll="eza -la $_icons --group-directories-first"
  alias la="eza -a $_icons --group-directories-first"
  alias lt="eza --tree --level=2 $_icons --git"
  unset _icons
fi
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
alias v='nvim'
alias c='clear'

cx() {
  cd "$@" || return
  local i='--icons'; [[ "$TERM" == linux ]] && i=''
  if command -v eza >/dev/null 2>&1; then eza -l $i --group-directories-first; else ls -lh; fi
}

if (( ! ${+functions[_zsh_highlight]} )) && \
   [ -f "$ETERM_ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$ETERM_ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

_eterm_accept_line() { zle reset-prompt; zle .accept-line; }
zle -N accept-line _eterm_accept_line

if [[ -n "${E_PROMPT_CLOCK:-}" ]]; then
  zmodload zsh/datetime 2>/dev/null
  TMOUT=1
  TRAPALRM() {
    [[ -n "$BUFFER" && "$E_PROMPT_CLOCK" != always ]] && return
    local m; strftime -s m '%H:%M' $EPOCHSECONDS
    [[ "$m" == "$_eterm_clock_min" ]] && return
    _eterm_clock_min="$m"
    zle reset-prompt
  }
fi

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook
_eterm_osc_precmd()  { local e=$?; print -rn -- $'\e]133;D;'"$e"$'\a\e]133;A\a'; }
_eterm_osc_preexec() { print -rn -- $'\e]133;C\a\e]9001;ts;'"$(strftime '%H:%M' $EPOCHSECONDS)"$'\a'; }
add-zsh-hook precmd  _eterm_osc_precmd
add-zsh-hook preexec _eterm_osc_preexec

_eterm_eza_theme() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/e-terminal/eza-colors"
  [[ -s "$f" ]] && export EZA_COLORS="$(<"$f")"
}
add-zsh-hook precmd _eterm_eza_theme

[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
