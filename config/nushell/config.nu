let jb = {
  bg: "#121212", bg1: "#1c1c1c", bg2: "#262626", surface: "#2d2d2d", overlay: "#3a3a3a",
  gray: "#929292", subtle: "#bdbdbd", fg: "#dedede", white: "#ffffff",
  red: "#e27373", bred: "#ffa1a1", green: "#94b979", bgreen: "#bddeab",
  yellow: "#ffba7b", byellow: "#ffdca0", blue: "#97bedc", bblue: "#b1d8f6",
  purple: "#e1c0fa", bpurple: "#fbdaff", cyan: "#1ab2a8", teal: "#00988e",
  orange: "#ffa560",
}

let jb_theme = {
  separator: $jb.gray
  leading_trailing_space_bg: { attr: n }
  header: { fg: $jb.blue attr: b }
  empty: $jb.bblue
  bool: $jb.bblue
  int: $jb.fg
  filesize: $jb.bblue
  duration: $jb.fg
  date: $jb.orange
  range: $jb.fg
  float: $jb.fg
  string: $jb.green
  nothing: $jb.fg
  binary: $jb.fg
  cell-path: $jb.fg
  row_index: { fg: $jb.purple attr: b }
  record: $jb.fg
  list: $jb.fg
  block: $jb.fg
  hints: $jb.gray
  search_result: { fg: $jb.red bg: $jb.fg }
  shape_and: { fg: $jb.purple attr: b }
  shape_binary: { fg: $jb.purple attr: b }
  shape_block: { fg: $jb.blue attr: b }
  shape_bool: $jb.cyan
  shape_custom: $jb.green
  shape_datetime: { fg: $jb.cyan attr: b }
  shape_directory: $jb.cyan
  shape_external: $jb.cyan
  shape_externalarg: { fg: $jb.green attr: b }
  shape_filepath: $jb.cyan
  shape_flag: { fg: $jb.blue attr: b }
  shape_float: { fg: $jb.red attr: b }
  shape_garbage: { fg: $jb.fg bg: $jb.red attr: b }
  shape_globpattern: { fg: $jb.cyan attr: b }
  shape_int: { fg: $jb.purple attr: b }
  shape_internalcall: { fg: $jb.cyan attr: b }
  shape_list: { fg: $jb.cyan attr: b }
  shape_literal: $jb.blue
  shape_match_pattern: $jb.green
  shape_matching_brackets: { attr: u }
  shape_nothing: $jb.cyan
  shape_operator: $jb.orange
  shape_or: { fg: $jb.purple attr: b }
  shape_pipe: { fg: $jb.purple attr: b }
  shape_range: { fg: $jb.orange attr: b }
  shape_record: { fg: $jb.cyan attr: b }
  shape_redirection: { fg: $jb.purple attr: b }
  shape_signature: { fg: $jb.green attr: b }
  shape_string: $jb.green
  shape_string_interpolation: { fg: $jb.cyan attr: b }
  shape_table: { fg: $jb.blue attr: b }
  shape_variable: $jb.purple
  shape_vardecl: $jb.purple
}

let carapace_completer = {|spans|
  carapace $spans.0 nushell ...$spans | from json
}

$env.config = {
  show_banner: false
  edit_mode: vi
  use_ansi_coloring: true
  bracketed_paste: true
  error_style: "fancy"
  color_config: $jb_theme
  cursor_shape: {
    vi_insert: line
    vi_normal: block
  }
  completions: {
    case_sensitive: false
    quick: true
    partial: true
    algorithm: "fuzzy"
    external: {
      enable: true
      max_results: 100
      completer: $carapace_completer
    }
  }
}

$env.config.hooks = {
  pre_prompt: [{||
    let esc = (char -u "1b"); let bel = (char -u "07")
    print -rn $"($esc)]133;A($bel)"
  }]
  pre_execution: [{||
    let t = (date now | format date "%H:%M")
    let esc = (char -u "1b"); let bel = (char -u "07")
    print -rn $"($esc)]133;C($bel)($esc)]9001;ts;($t)($bel)"
  }]
}

alias l = ls --all
alias ll = ls --long
alias la = ls --all --long
alias lt = eza --tree --level=2 --long --git
alias c = clear
alias v = nvim
alias gst = git status
alias gc = git commit -m
alias gp = git push origin HEAD

def --env cx [path: string] { cd $path; ls --long }

const e_scripts = ($nu.default-config-dir | path join "scripts")
use ($e_scripts | path join "net.nu") *
use ($e_scripts | path join "sys.nu") *
use ($e_scripts | path join "cloud.nu") *
use ($e_scripts | path join "sec.nu") *
use ($e_scripts | path join "util.nu") *
use ($e_scripts | path join "commands.nu") *

source ~/.cache/starship/init.nu
source ~/.cache/zoxide.nu
source ~/.cache/carapace/init.nu

$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
