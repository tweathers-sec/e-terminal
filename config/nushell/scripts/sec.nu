def arg-or-in [val: any, pipe: any] {
  if ($val | is-empty) { $pipe } else { $val }
}

export def genpass [length: int = 20, --symbols (-s)] {
  if $symbols {
    let pool = ('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*-_=+' | split chars)
    0..<$length | each {|_| $pool | shuffle | first } | str join
  } else {
    random chars --length $length
  }
}

export def b64 [text?: string, --decode (-d)] {
  let s = (arg-or-in $text $in)
  if $decode { $s | decode base64 | decode } else { $s | encode base64 }
}

export def digest [text?: string, --md5, --sha512] {
  let s = (arg-or-in $text $in)
  if $md5 {
    $s | hash md5
  } else if $sha512 {
    $s | ^openssl dgst -sha512 | complete | get stdout | parse --regex '=\s*(?<h>\w+)' | get h.0? | default ''
  } else {
    $s | hash sha256
  }
}

export def urlencode [text?: string] { (arg-or-in $text $in) | url encode }
export def urldecode [text?: string] { (arg-or-in $text $in) | url decode }
