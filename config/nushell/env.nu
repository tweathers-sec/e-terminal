if ("E_SESSION_LOG_ACTIVE" not-in $env) and ("TMUX" not-in $env) and $nu.is-interactive {
  let elog = ([
    ($nu.home-dir | path join ".local" "bin" "e-session-log")
    "/usr/local/bin/e-session-log"
  ] | where {|p| $p | path exists } | get 0?)
  if ($elog | is-not-empty) {
    exec $elog start $nu.current-exe
  }
}

use std "path add"
if ($nu.os-info.name == "macos") {
  if ("/usr/libexec/path_helper" | path exists) {
    let helped = (^/usr/libexec/path_helper -s
      | split row (char dq) | get 1? | default ""
      | split row ":" | where {|p| $p | is-not-empty })
    if ($helped | is-not-empty) { $env.PATH = $helped }
  }
  path add "/opt/homebrew/bin"
  path add "/opt/homebrew/sbin"
} else {
  path add "/usr/local/sbin"
  path add "/usr/sbin"
  path add "/sbin"
}
path add ($nu.home-dir | path join ".cargo" "bin")
path add ($nu.home-dir | path join ".local" "bin")
path add ($nu.home-dir | path join "go" "bin")

$env.EDITOR = "nvim"
$env.CARAPACE_BRIDGES = 'zsh,fish,bash'

if (($env.TERM? | default "") == "linux") {
  $env.STARSHIP_CONFIG = ($nu.home-dir | path join ".config" "starship-console.toml")
}

let starship_cache = ($nu.home-dir | path join ".cache" "starship" "init.nu")
let zoxide_cache   = ($nu.home-dir | path join ".cache" "zoxide.nu")
let carapace_cache = ($nu.home-dir | path join ".cache" "carapace" "init.nu")

mkdir ($nu.home-dir | path join ".cache" "starship")
mkdir ($nu.home-dir | path join ".cache" "carapace")

if (which starship | is-not-empty) { starship init nu     | save -f $starship_cache } else { "" | save -f $starship_cache }
if (which zoxide   | is-not-empty) { zoxide init nushell  | save -f $zoxide_cache   } else { "" | save -f $zoxide_cache }
if (which carapace | is-not-empty) { carapace _carapace nushell | save -f $carapace_cache } else { "" | save -f $carapace_cache }

source ($nu.default-config-dir | path join "env.local.nu")
