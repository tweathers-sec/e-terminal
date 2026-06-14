use ./net.nu [ local-ips, myip ]

def dns-servers [] {
  if ($nu.os-info.name == 'macos') {
    (^scutil --dns | complete | get stdout)
    | parse --regex 'nameserver\[[0-9]+\] : (?<ns>\S+)' | get ns | uniq
  } else {
    (try { open /etc/resolv.conf | lines } catch { [] })
    | parse --regex '^nameserver\s+(?<ns>\S+)' | get ns | uniq
  }
}

def usb-list [] {
  if ($nu.os-info.name == 'macos') {
    let root = (try { ^system_profiler SPUSBDataType -json | from json | get SPUSBDataType } catch { [] })
    mut names = []
    mut stack = $root
    while ($stack | is-not-empty) {
      let node = ($stack | first)
      $stack = ($stack | skip 1)
      let nm = ($node._name? | default null)
      if ($nm != null) { $names = ($names | append $nm) }
      $stack = ($stack | append ($node._items? | default []))
    }
    $names | wrap device
  } else {
    (try { ^lsusb | lines } catch { [] })
    | parse --regex 'ID (?<id>[0-9A-Fa-f]+:[0-9A-Fa-f]+) (?<device>.+)'
  }
}

def h [text: string] { print $"\n(ansi yellow_bold)($text)(ansi reset)" }

export def sysinfo [--usb] {
  let host  = (sys host)
  let mem   = (sys mem)
  let cores = (sys cpu | length)
  let load  = (sys cpu | get load_average | first | default '-')

  h 'Host'
  print ([
    { field: 'hostname', value: $host.hostname }
    { field: 'os',       value: $"($host.name) ($host.os_version)" }
    { field: 'kernel',   value: $host.kernel_version }
    { field: 'uptime',   value: $"($host.uptime)" }
    { field: 'load avg', value: $"($load)  \(($cores) cores\)" }
    { field: 'memory',   value: $"($mem.used) / ($mem.total)" }
  ] | table)

  h 'Disks'
  let disks = (sys disks | where total > 0b)
  let disks = (if ($nu.os-info.name == 'macos') {
    $disks | where {|d| $d.mount == '/' or $d.mount == '/System/Volumes/Data' or ($d.mount | str starts-with '/Volumes/') }
  } else { $disks })
  print ($disks | each {|d| {
    mount: $d.mount
    free:  $d.free
    total: $d.total
    'used%': (($d.total - $d.free) / $d.total * 100 | math round --precision 1)
  } })

  h 'Network'
  print (myip)

  h 'DNS'
  let ns = (dns-servers)
  print (if ($ns | is-empty) { '-' } else { $ns | wrap server })

  if $usb {
    h 'USB devices'
    let u = (usb-list)
    print (if ($u | is-empty) { '-' } else { $u })
  }
}

export alias system_info = sysinfo

export def rootsh [shell: string = 'nu'] {
  ^sudo -H $shell
}
