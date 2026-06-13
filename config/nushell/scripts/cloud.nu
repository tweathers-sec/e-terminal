def json-list [out: string] {
  let v = (try { $out | from json } catch { [] })
  if (($v | describe) =~ '^(list|table)') { $v } else { [] }
}

export def servers [] {
  mut rows = []

  if (which hcloud | is-not-empty) {
    let h = (json-list (^hcloud server list -o json | complete | get stdout))
    $rows = ($rows | append ($h | each {|s| {
      cloud:  'hetzner'
      name:   ($s.name? | default '—')
      ip:     ($s.public_net?.ipv4?.ip? | default '—')
      region: ($s.datacenter?.location?.name? | default '—')
      status: ($s.status? | default '—')
      type:   ($s.server_type?.name? | default '—')
    } }))
  }

  if (which doctl | is-not-empty) {
    let d = (json-list (^doctl compute droplet list -o json | complete | get stdout))
    $rows = ($rows | append ($d | each {|s| {
      cloud:  'do'
      name:   ($s.name? | default '—')
      ip:     ($s.networks?.v4? | default [] | where type == 'public' | get ip_address.0? | default '—')
      region: ($s.region?.slug? | default '—')
      status: ($s.status? | default '—')
      type:   ($s.size_slug? | default '—')
    } }))
  }

  $rows | sort-by cloud name
}

export def sshm [--user (-u): string = 'root'] {
  let s = (servers)
  if ($s | is-empty) {
    print 'no servers found (is hcloud / doctl configured?)'
    return
  }
  let line = ($s
    | each {|r| $'($r.ip)\t($r.cloud)/($r.name)  ($r.region)  ($r.status)  ($r.type)' }
    | str join "\n"
    | ^fzf --with-nth '2..' --prompt 'ssh > ' --height '40%' --reverse)
  if ($line | str trim | is-empty) { return }
  let ip = ($line | split row "\t" | first)
  print $'→ ssh ($user)@($ip)'
  ^ssh $'($user)@($ip)'
}
