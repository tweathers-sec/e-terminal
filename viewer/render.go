package main

import (
	"strconv"
	"strings"
	"unicode"
)

func highlightLine(l Line, ql string) Line {
	qr := []rune(ql)
	n := len(qr)
	if n == 0 || n > len(l) {
		return l
	}
	out := l
	copied := false
	for i := 0; i+n <= len(l); i++ {
		if cellsMatch(l, qr, i) {
			if !copied {
				out = make(Line, len(l))
				copy(out, l)
				copied = true
			}
			for k := 0; k < n; k++ {
				out[i+k].S.Reverse = true
				out[i+k].S.Bold = true
			}
			i += n - 1
		}
	}
	return out
}

func cellsMatch(l Line, qr []rune, i int) bool {
	for k := 0; k < len(qr); k++ {
		r := l[i+k].R
		if r == 0 {
			r = ' '
		}
		if unicode.ToLower(r) != qr[k] {
			return false
		}
	}
	return true
}

func (l Line) ANSI() string {
	var b strings.Builder
	var cur Style
	first := true
	for _, c := range l {
		if first || c.S != cur {
			b.WriteString(sgrFor(c.S))
			cur = c.S
			first = false
		}
		if c.R == 0 {
			b.WriteByte(' ')
		} else {
			b.WriteRune(c.R)
		}
	}
	if !first {
		b.WriteString("\x1b[0m")
	}
	return b.String()
}

func lineWidth(l Line) int { return len(l) }

func reflowPrompt(l Line, w int) (Line, bool) {
	if w <= 0 {
		return Line{}, false
	}
	bs, bl := -1, 0
	for i := 0; i < len(l); {
		if l[i].R == ' ' {
			j := i
			for j < len(l) && l[j].R == ' ' {
				j++
			}
			if j-i > bl {
				bs, bl = i, j-i
			}
			i = j
		} else {
			i++
		}
	}
	if bs < 0 || bl < 4 {
		return nil, false
	}
	left := l[:bs]
	right := l[bs+bl:]
	fillStyle := l[bs].S
	lw, rw := len(left), len(right)
	if rw >= w {
		return right.Window(rw-w, w), true
	}
	if lw+rw > w {
		left = left[:w-rw]
		lw = len(left)
	}
	out := make(Line, 0, w)
	out = append(out, left...)
	for k := 0; k < w-lw-rw; k++ {
		out = append(out, Cell{R: ' ', S: fillStyle})
	}
	out = append(out, right...)
	return out, true
}

func (l Line) Window(off, width int) Line {
	if off < 0 {
		off = 0
	}
	if off >= len(l) || width <= 0 {
		return Line{}
	}
	end := off + width
	if end > len(l) {
		end = len(l)
	}
	return l[off:end]
}

func (l Line) Plain() string {
	var b strings.Builder
	for _, c := range l {
		if c.R == 0 {
			b.WriteByte(' ')
		} else {
			b.WriteRune(c.R)
		}
	}
	return b.String()
}

func sgrFor(s Style) string {
	parts := []string{"0"}
	if s.Bold {
		parts = append(parts, "1")
	}
	if s.Faint {
		parts = append(parts, "2")
	}
	if s.Italic {
		parts = append(parts, "3")
	}
	if s.Under {
		parts = append(parts, "4")
	}
	if s.Reverse {
		parts = append(parts, "7")
	}
	parts = append(parts, colorSGR(s.Fg, true)...)
	parts = append(parts, colorSGR(s.Bg, false)...)
	return "\x1b[" + strings.Join(parts, ";") + "m"
}

func colorSGR(c Color, fg bool) []string {
	switch c.Kind {
	case 1:
		base := 30
		if !fg {
			base = 40
		}
		if c.N >= 8 {
			base += 60
			return []string{strconv.Itoa(base + int(c.N) - 8)}
		}
		return []string{strconv.Itoa(base + int(c.N))}
	case 2:
		lead := "38"
		if !fg {
			lead = "48"
		}
		return []string{lead, "5", strconv.Itoa(int(c.N))}
	case 3:
		lead := "38"
		if !fg {
			lead = "48"
		}
		return []string{lead, "2", strconv.Itoa(int(c.R)), strconv.Itoa(int(c.G)), strconv.Itoa(int(c.B))}
	}
	return nil
}
