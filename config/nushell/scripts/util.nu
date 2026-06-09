export def extract [file: path] {
  if (not ($file | path exists)) {
    error make --unspanned { msg: $'no such file: ($file)' }
  }
  let n = ($file | path basename | str downcase)
  if ($n | str ends-with '.tar.gz')  or ($n | str ends-with '.tgz')  { ^tar xzf $file }
  else if ($n | str ends-with '.tar.bz2') or ($n | str ends-with '.tbz2') { ^tar xjf $file }
  else if ($n | str ends-with '.tar.xz')  or ($n | str ends-with '.txz')  { ^tar xJf $file }
  else if ($n | str ends-with '.tar.zst') { ^tar --use-compress-program=unzstd -xf $file }
  else if ($n | str ends-with '.tar')     { ^tar xf $file }
  else if ($n | str ends-with '.zip')     { ^unzip $file }
  else if ($n | str ends-with '.7z')      { ^7z x $file }
  else if ($n | str ends-with '.rar')     { ^unrar x $file }
  else if ($n | str ends-with '.gz')      { ^gunzip -k $file }
  else if ($n | str ends-with '.bz2')     { ^bunzip2 -k $file }
  else if ($n | str ends-with '.xz')      { ^unxz -k $file }
  else if ($n | str ends-with '.zst')     { ^unzstd -k $file }
  else { error make --unspanned { msg: $'don\u(27)t know how to extract ($file | path basename)' } }
}

export def weather [...city: string] {
  let place = ($city | str join '+')
  (try {
    http get --max-time 6sec $'https://wttr.in/($place)?format=%l:+%C+%t,+wind+%w,+humidity+%h'
  } catch { '(no network)' }) | str trim
}

export def psg [pattern: string] {
  ps | where name =~ $pattern | select pid name cpu mem status | sort-by cpu --reverse
}

export def killp [] {
  let pick = (ps
    | sort-by cpu --reverse
    | each {|p| $'($p.pid)\t($p.name)  cpu:($p.cpu | math round)  mem:($p.mem)' }
    | str join "\n"
    | ^fzf --with-nth '2..' --prompt 'kill > ' --height '40%' --reverse)
  if ($pick | str trim | is-empty) { return }
  let pid = ($pick | split row "\t" | first | into int)
  print $'killing ($pid)'
  kill $pid
}
