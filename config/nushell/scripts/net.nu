def popcount [n: int] {
  mut c = 0
  mut v = $n
  while $v > 0 { $c = $c + ($v mod 2); $v = ($v // 2) }
  $c
}

def mask-to-prefix [mask: string] {
  if ($mask | str starts-with '0x') {
    popcount ($mask | into int)
  } else if ($mask | str contains '.') {
    $mask | split row '.' | each {|o| popcount ($o | into int) } | math sum
  } else {
    $mask | into int
  }
}

def default-route [] {
  if ($nu.os-info.name == 'macos') {
    let o = (^route -n get default | complete)
    if $o.exit_code != 0 { return { iface: null, gateway: null } }
    {
      iface:   ($o.stdout | parse --regex 'interface:\s+(?<i>\S+)' | get i.0?)
      gateway: ($o.stdout | parse --regex 'gateway:\s+(?<g>\S+)'   | get g.0?)
    }
  } else {
    let o = (^ip -j route show default | complete)
    if $o.exit_code != 0 { return { iface: null, gateway: null } }
    let r = (try { $o.stdout | from json | where dst == 'default' | first } catch { {} })
    { iface: ($r.dev? | default null), gateway: ($r.gateway? | default null) }
  }
}

def parse-ifconfig [dump: string] {
  mut blocks = []
  mut cur = []
  for line in ($dump | lines) {
    if ($line | str trim | is-empty) { continue }
    if ($line =~ '^[ \t]') {
      $cur = ($cur | append $line)
    } else {
      if ($cur | is-not-empty) { $blocks = ($blocks | append [$cur]) }
      $cur = [$line]
    }
  }
  if ($cur | is-not-empty) { $blocks = ($blocks | append [$cur]) }

  $blocks | each {|b|
    let header = ($b | first)
    let name   = ($header | parse --regex '^(?<n>[^:]+):' | get n.0? | default '?')
    let flags  = ($header | parse --regex '<(?<f>[^>]*)>' | get f.0? | default '')
    let mtu    = ($header | parse --regex 'mtu (?<m>[0-9]+)' | get m.0? | default '')
    let status = ($b | parse --regex 'status:\s+(?<s>\w+)' | get s.0?)

    let v4 = ($b
      | parse --regex 'inet (?<addr>[0-9]+(?:\.[0-9]+){3})(?:\s+-->\s+[0-9.]+)?\s+netmask\s+(?<mask>0x[0-9A-Fa-f]+|[0-9.]+)'
      | each {|x| { addr: $x.addr, prefix: (mask-to-prefix $x.mask) } })
    let v6 = ($b
      | parse --regex '\binet6 (?<ip>[0-9A-Fa-f:]+)'
      | get ip
      | where {|x| (not ($x | str downcase | str starts-with 'fe80')) and ($x != '::1') })
    let mac = ($b | parse --regex '(?:ether|lladdr)\s+(?<m>[0-9A-Fa-f:]{17})' | get m.0? | default '')

    let up = if ($status != null) { $status == 'active' } else { $flags | str contains 'RUNNING' }

    { name: $name, up: $up, mtu: $mtu, ipv4: $v4, ipv6: $v6, mac: $mac }
  }
}

def ip-adapters [] {
  let raw = (^ip -j addr | complete)
  if $raw.exit_code != 0 {
    error make --unspanned { msg: $"ip addr failed: ($raw.stderr | str trim)" }
  }
  $raw.stdout | from json | each {|a|
    let info = ($a.addr_info? | default [])
    let mac  = ($a.address? | default '')
    {
      name: $a.ifname
      up:   ('UP' in ($a.flags? | default []))
      mtu:  ($a.mtu? | default '' | into string)
      ipv4: ($info | where {|x| $x.family == 'inet' } | each {|x| { addr: $x.local, prefix: $x.prefixlen } })
      ipv6: ($info | where {|x| ($x.family == 'inet6') and (($x.scope? | default '') == 'global') } | each {|x| $x.local })
      mac:  (if ($mac == '00:00:00:00:00:00') { '' } else { $mac })
    }
  }
}

export def net-adapters [] {
  if ($nu.os-info.name == 'macos') {
    let dump = (^ifconfig -a | complete)
    if $dump.exit_code != 0 {
      error make --unspanned { msg: $"ifconfig failed: ($dump.stderr | str trim)" }
    }
    parse-ifconfig $dump.stdout
  } else {
    ip-adapters
  }
}

def active? [r] {
  $r.up and ((($r.ipv4 | where {|x| $x.addr != '127.0.0.1'}) | is-not-empty) or ($r.ipv6 | is-not-empty))
}

export def ifconfig [
  --raw (-r)
  --all (-a)
  --ipv6
  ...adapters: string
] {
  if $raw {
    let out = (if (($nu.os-info.name == 'macos') or (which ifconfig | is-not-empty)) {
      if ($adapters | is-empty) { ^ifconfig -a | complete } else { ^ifconfig ...$adapters | complete }
    } else {
      if ($adapters | is-empty) { ^ip addr | complete } else { ^ip addr show ($adapters | first) | complete }
    })
    return ($out.stdout)
  }

  let rt = (default-route)
  mut rows = (net-adapters)
  if ($adapters | is-not-empty) {
    $rows = ($rows | where name in $adapters)
  } else if (not $all) {
    $rows = ($rows | where {|r| active? $r })
  }

  let show_v6 = ($ipv6 or ($adapters | is-not-empty))
  $rows | each {|r|
    let primary = ($r.name == $rt.iface)
    let row = {
      adapter: $r.name
      status:  (if $r.up {
                  $"(ansi green)●(ansi reset) up(if $primary { ' (primary)' } else { '' })"
                } else {
                  $"(ansi red)●(ansi reset) down"
                })
      ipv4:    ($r.ipv4 | each {|x| $x.addr } | str join ', ')
      cidr:    ($r.ipv4 | each {|x| $"/($x.prefix)" } | uniq | str join ', ')
      gateway: (if $primary { ($rt.gateway | default '—') } else { '—' })
      mtu:     $r.mtu
      mac:     (if ($r.mac | is-empty) { '—' } else { $r.mac })
    }
    if $show_v6 { $row | insert ipv6 ($r.ipv6 | str join "\n") } else { $row }
  }
}

export def local-ips [] {
  net-adapters
  | where {|r| active? $r }
  | each {|r| {
      adapter: $r.name
      ipv4: ($r.ipv4 | each {|x| $x.addr } | where {|a| $a != '127.0.0.1' } | str join ', ')
      ipv6: ($r.ipv6 | str join ', ')
    } }
}

export def myip [--local (-l)] {
  let lan = (local-ips)
  if $local { return $lan }

  let info = (try { http get --max-time 5sec https://ipinfo.io/json } catch {|e| {} })
  let public = ([
    { field: 'external ip', value: ($info.ip?  | default '(no network)') }
    { field: 'provider',    value: ($info.org? | default '—') }
    { field: 'location',    value: (if (($info.city? | default '') | is-not-empty) {
                                       $'($info.city), ($info.region?), ($info.country?)'
                                     } else { '—' }) }
  ])
  print ($public | table)
  print ''
  $lan
}

def parse-lsof [raw: string, proto: string] {
  $raw
  | lines
  | skip 1
  | parse --regex '^(?<process>\S+)\s+(?<pid>\d+)\s+(?<user>\S+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(?<name>\S+)'
  | each {|r|
      let m = ($r.name | parse --regex '^(?<addr>.*):(?<port>[0-9]+)$')
      {
        proto:   $proto
        address: ($m.addr.0? | default $r.name)
        port:    ($m.port.0? | default '0' | into int)
        pid:     ($r.pid | into int)
        process: ($r.process | str replace --all '\x20' ' ')
        user:    $r.user
      }
    }
  | where port != 0
  | uniq
}

def parse-ss [raw: string, proto: string] {
  $raw | lines | each {|l|
    let f = ($l | split row --regex '\s+')
    let m = (($f | get 3? | default '') | parse --regex '^(?<addr>.*):(?<port>[0-9]+)$')
    let pi = ($l | parse --regex 'users:\(\("(?<name>[^"]+)",pid=(?<pid>[0-9]+)')
    {
      proto:   $proto
      address: ($m.addr.0? | default '')
      port:    ($m.port.0? | default '0' | into int)
      pid:     ($pi.pid.0? | default '')
      process: ($pi.name.0? | default '')
      user:    ''
    }
  } | where address != '' | uniq
}

export def ports [--udp (-u), --sudo] {
  if ($nu.os-info.name == 'macos') {
    let tcp = (if $sudo { ^sudo lsof -nP -iTCP -sTCP:LISTEN | complete } else { ^lsof -nP -iTCP -sTCP:LISTEN | complete } | get stdout)
    mut out = (parse-lsof $tcp 'tcp')
    if $udp {
      let u = (if $sudo { ^sudo lsof -nP -iUDP | complete } else { ^lsof -nP -iUDP | complete } | get stdout)
      $out = ($out | append (parse-lsof $u 'udp'))
    }
    $out | sort-by port
  } else {
    let tcp = (if $sudo { ^sudo ss -tlnpH | complete } else { ^ss -tlnpH | complete } | get stdout)
    mut out = (parse-ss $tcp 'tcp')
    if $udp {
      let u = (if $sudo { ^sudo ss -ulnpH | complete } else { ^ss -ulnpH | complete } | get stdout)
      $out = ($out | append (parse-ss $u 'udp'))
    }
    $out | sort-by port
  }
}

def dig-answers [label: string, ...args: string] {
  ^dig +short ...$args | complete | get stdout | lines
  | each {|l| $l | str trim }
  | where {|l| ($l != '') and (not ($l | str starts-with ';')) }
  | each {|v| { type: $label, value: $v } }
}

export def dns [host: string] {
  if ($host =~ '^[0-9.]+$') {
    dig-answers 'PTR' '-x' $host
  } else {
    [A AAAA MX NS TXT CNAME] | each {|t| dig-answers $t $t $host } | flatten
  }
}

export def sslcheck [host: string, port: int = 443] {
  let r = ('' | ^openssl s_client -connect $'($host):($port)' -servername $host | complete)
  if ($r.stdout | str trim | is-empty) {
    error make --unspanned { msg: $'could not connect to ($host):($port)' }
  }
  let info = ($r.stdout | ^openssl x509 -noout -issuer -subject -dates | complete | get stdout)
  let txt  = ($r.stdout | ^openssl x509 -noout -text | complete | get stdout)
  let notafter = ($info | parse --regex 'notAfter=(?<v>.*)' | get v.0? | default '')
  let expiry = (try { $notafter | into datetime --format '%b %e %H:%M:%S %Y %Z' } catch { null })
  let days = (if $expiry != null { ($expiry - (date now)) / 1day | math round } else { null })
  let dot = (if $days == null { '' } else if $days > 30 { $'(ansi green)●(ansi reset)' } else if $days > 7 { $'(ansi yellow)●(ansi reset)' } else { $'(ansi red)●(ansi reset)' })
  {
    host:      $host
    subject:   ($info | parse --regex 'subject=(?<v>.*)' | get v.0? | default '—')
    issuer:    ($info | parse --regex 'issuer=(?<v>.*)'  | get v.0? | default '—')
    expires:   ($notafter | str replace ' GMT' '')
    days_left: (if $days == null { '—' } else { $'($dot) ($days)' })
    san:       ($txt | parse --regex 'DNS:(?<d>[^,\s]+)' | get d | uniq | str join ', ')
  }
}

export def scan [] {
  if ($nu.os-info.name == 'macos') {
    ^arp -an | complete | get stdout | lines
    | parse --regex '\((?<ip>[0-9.]+)\) at (?<mac>[0-9A-Fa-f:]+) on (?<iface>\S+)'
    | where mac != '(incomplete)'
  } else {
    ^ip -j neigh | complete | get stdout | from json
    | where {|n| ($n.dst =~ '^[0-9]+(\.[0-9]+){3}$') and (($n.lladdr? | default '') != '') }
    | each {|n| { ip: $n.dst, mac: $n.lladdr, iface: $n.dev } }
  } | select ip mac iface | sort-by iface ip
}

export def geoip [ip: string] {
  let info = (try { http get --max-time 5sec $'https://ipinfo.io/($ip)/json' } catch {|e| {} })
  if ($info | is-empty) { return '(no network)' }
  $info | select ip? org? city? region? country? loc? timezone?
}
