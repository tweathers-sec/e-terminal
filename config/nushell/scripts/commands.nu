# NOT named `help`: shadowing the built-in breaks `<command> --help` everywhere.
const E_COMMANDS = [
  [group     command      usage                          description];
  [network   ifconfig     "[-a|--ipv6|-r] [adapter..]"   "host adapter table (active by default; -a all, -r raw)"]
  [network   myip         "[-l]"                         "public IP + provider + location, then internal addresses"]
  [network   ports        "[-u] [--sudo]"                "listening sockets with owning pid/process/user"]
  [network   dns          "<host>"                       "A/AAAA/MX/NS/TXT/CNAME records, or PTR for an IP"]
  [network   sslcheck     "<host> [port]"                "TLS cert subject/issuer/SAN + days-to-expiry"]
  [network   scan         ""                             "hosts on the local network (ARP/neighbour cache)"]
  [network   geoip        "<ip>"                         "geolocate any IP (org/city/region/country)"]
  [system    sysinfo      "[--usb]"                      "host/load/memory/disk/network/dns dashboard"]
  [system    rootsh       "[nu|zsh|bash]"                "drop into a styled root session (macOS + Linux)"]
  [cloud     servers      ""                             "unified Hetzner + DigitalOcean inventory"]
  [cloud     sshm         "[-u <user>]"                  "fuzzy-pick a server and ssh in"]
  [security  genpass      "[len] [-s]"                   "random password (-s adds symbols)"]
  [security  b64          "<text> [-d]"                  "base64 encode, or decode with -d"]
  [security  digest       "<text> [--md5|--sha512]"      "hash a string (sha256 by default)"]
  [security  urlencode    "<text>"                       "percent-encode (urldecode reverses it)"]
  [util      extract      "<archive>"                    "unpack any common archive by extension"]
  [util      weather      "[city..]"                     "one-line wttr.in summary"]
  [util      psg          "<pattern>"                    "find running processes by name"]
  [util      killp        ""                             "fuzzy-pick a process and kill it"]
  [shell     swapshell      "[--no-launch|--here]"       "set default shell + start it now (never silently)"]
  [shell     e-session-log  "view|status|off|on|dir"     "session logging (on by default); `view` = browse past sessions (TUI)"]
  [shell     theme          "[name|list]"                "switch Starship + tmux color theme (arrow-through picker)"]
]

export def ehelp [...terms: string] {
  if ($terms | is-empty) { return $E_COMMANDS }
  let f = ($terms | str join ' ' | str downcase)
  let hits = ($E_COMMANDS | where {|r|
    ($r.group | str contains $f) or ($r.command | str contains $f) or ($r.description | str downcase | str contains $f)
  })
  if ($hits | is-empty) {
    print $"no e-terminal command matches '($f)'. For any command's own help, run:  ($f) --help"
  } else {
    $hits
  }
}
