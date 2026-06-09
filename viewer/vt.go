package main

import (
	"strconv"
	"strings"
	"unicode/utf8"
)

type Color struct {
	Kind uint8
	N    uint8
	R    uint8
	G    uint8
	B    uint8
}

type Style struct {
	Fg, Bg                              Color
	Bold, Faint, Italic, Under, Reverse bool
}

type Cell struct {
	R rune
	S Style
}

type Line []Cell

type vt struct {
	w, h        int
	grid        [][]Cell
	scroll      [][]Cell
	scrollCells int
	cr, cc      int
	cur         Style
	saved       [3]int
	savedOK     bool
	// alt-screen content renders into a throwaway buffer so TUIs never reach the history.
	alt      bool
	mainGrid [][]Cell
	mainR    int
	mainC    int
	marks    []tsMark
}

type tsMark struct {
	line int
	t    string
}

// maxW/maxH/maxScrollCells bound allocations so a crafted log cannot trigger a huge grid or exhaust
// memory with a flood of newlines.
const (
	maxW           = 2000
	maxH           = 2000
	maxScrollCells = 10_000_000
)

func newVT(width, height int) *vt {
	switch {
	case width < 20:
		width = 200
	case width > maxW:
		width = maxW
	}
	switch {
	case height < 4:
		height = 50
	case height > maxH:
		height = maxH
	}
	v := &vt{w: width, h: height}
	v.grid = blank(v.h, v.w)
	return v
}

func blank(h, w int) [][]Cell {
	g := make([][]Cell, h)
	for i := range g {
		g[i] = make([]Cell, w)
		for j := range g[i] {
			g[i][j] = Cell{R: ' '}
		}
	}
	return g
}

func (v *vt) blankRow() []Cell {
	r := make([]Cell, v.w)
	for j := range r {
		r[j] = Cell{R: ' '}
	}
	return r
}

func (v *vt) Feed(b []byte) {
	for i := 0; i < len(b); {
		c := b[i]
		switch {
		case c == 0x1b:
			adv := v.esc(b[i:])
			if adv <= 0 {
				adv = 1
			}
			i += adv
		case c == '\r':
			v.cc = 0
			i++
		case c == '\n':
			v.lineFeed()
			i++
		case c == '\b':
			if v.cc > 0 {
				v.cc--
			}
			i++
		case c == '\t':
			v.cc = ((v.cc / 8) + 1) * 8
			if v.cc >= v.w {
				v.cc = v.w - 1
			}
			i++
		case c == 0x07:
			i++
		case c < 0x20:
			i++
		default:
			r, sz := utf8.DecodeRune(b[i:])
			if r == utf8.RuneError && sz <= 1 {
				i++
				continue
			}
			v.put(r)
			i += sz
		}
	}
}

func (v *vt) put(r rune) {
	if v.cc >= v.w {
		v.cc = 0
		v.lineFeed()
	}
	if v.cr < 0 {
		v.cr = 0
	}
	if v.cr >= v.h {
		v.cr = v.h - 1
	}
	v.grid[v.cr][v.cc] = Cell{R: r, S: v.cur}
	v.cc++
}

func (v *vt) lineFeed() {
	v.cr++
	if v.cr >= v.h {
		v.cr = v.h - 1
		top := v.grid[0]
		if !v.alt {
			v.scroll = append(v.scroll, top)
			v.scrollCells += len(top)
			for v.scrollCells > maxScrollCells && len(v.scroll) > 1 {
				v.scrollCells -= len(v.scroll[0])
				v.scroll = v.scroll[1:]
			}
		}
		copy(v.grid, v.grid[1:])
		v.grid[v.h-1] = v.blankRow()
	}
}

func (v *vt) esc(b []byte) int {
	if len(b) < 2 {
		return 1
	}
	switch b[1] {
	case '[':
		return v.csi(b)
	case ']':
		return v.osc(b)
	case '7':
		v.saved = [3]int{v.cr, v.cc, 0}
		v.savedOK = true
		return 2
	case '8':
		if v.savedOK {
			v.cr, v.cc = v.saved[0], v.saved[1]
		}
		return 2
	case '(', ')', '*', '+':
		return 3
	case '=', '>':
		return 2
	case 'M':
		v.cr--
		if v.cr < 0 {
			v.cr = 0
		}
		return 2
	case 'c':
		return 2
	default:
		return 2
	}
}

func (v *vt) csi(b []byte) int {
	i := 2
	for i < len(b) && (b[i] < 0x40 || b[i] > 0x7e) {
		i++
	}
	if i >= len(b) {
		return len(b)
	}
	final := b[i]
	params := string(b[2:i])
	priv := strings.HasPrefix(params, "?")
	if priv {
		params = params[1:]
	}
	nums := parseParams(params)
	n := func(idx, def int) int {
		if idx < len(nums) && nums[idx] > 0 {
			return nums[idx]
		}
		if idx < len(nums) && nums[idx] == 0 && def == 0 {
			return 0
		}
		return def
	}

	switch final {
	case 'm':
		v.sgr(nums)
	case 'A':
		v.cr -= n(0, 1)
		if v.cr < 0 {
			v.cr = 0
		}
	case 'B', 'e':
		v.cr += n(0, 1)
		if v.cr >= v.h {
			v.cr = v.h - 1
		}
	case 'C', 'a':
		v.cc += n(0, 1)
		if v.cc >= v.w {
			v.cc = v.w - 1
		}
	case 'D':
		v.cc -= n(0, 1)
		if v.cc < 0 {
			v.cc = 0
		}
	case 'E':
		v.cr += n(0, 1)
		v.cc = 0
	case 'F':
		v.cr -= n(0, 1)
		if v.cr < 0 {
			v.cr = 0
		}
		v.cc = 0
	case 'G', '`':
		v.cc = n(0, 1) - 1
		v.clampCursor()
	case 'd':
		v.cr = n(0, 1) - 1
		v.clampCursor()
	case 'H', 'f':
		v.cr = n(0, 1) - 1
		v.cc = n(1, 1) - 1
		v.clampCursor()
	case 'J':
		v.eraseDisplay(n(0, 0))
	case 'K':
		v.eraseLine(n(0, 0))
	case 'L':
		v.insertLines(n(0, 1))
	case 'M':
		v.deleteLines(n(0, 1))
	case 'P':
		v.deleteChars(n(0, 1))
	case '@':
		v.insertChars(n(0, 1))
	case 'X':
		v.eraseChars(n(0, 1))
	case 'S':
		for k := 0; k < clampCount(n(0, 1), v.h); k++ {
			v.lineFeed()
		}
	case 's':
		v.saved = [3]int{v.cr, v.cc, 0}
		v.savedOK = true
	case 'u':
		if v.savedOK {
			v.cr, v.cc = v.saved[0], v.saved[1]
		}
	case 'h', 'l':
		if priv {
			v.privMode(nums, final == 'h')
		}
	}
	v.clampCursor() // clampCursor runs after every CSI so a crafted sequence can't index past the grid
	return i + 1
}

func (v *vt) clampCursor() {
	if v.cr < 0 {
		v.cr = 0
	}
	if v.cr >= v.h {
		v.cr = v.h - 1
	}
	if v.cc < 0 {
		v.cc = 0
	}
	if v.cc >= v.w {
		v.cc = v.w - 1
	}
}

func (v *vt) osc(b []byte) int {
	i := 2
	for i < len(b) {
		if b[i] == 0x07 {
			v.captureOSC(b[2:i])
			return i + 1
		}
		if b[i] == 0x1b && i+1 < len(b) && b[i+1] == '\\' {
			v.captureOSC(b[2:i])
			return i + 2
		}
		i++
	}
	return len(b)
}

func (v *vt) captureOSC(c []byte) {
	if v.alt {
		return
	}
	const pfx = "9001;ts;"
	if len(c) > len(pfx) && string(c[:len(pfx)]) == pfx {
		if ts := string(c[len(pfx):]); plausibleTime(ts) {
			v.marks = append(v.marks, tsMark{line: len(v.scroll) + v.cr, t: ts})
		}
	}
}

// plausibleTime rejects anything non-numeric so a crafted marker cannot inject escape sequences
// into the rendered prompt via setLineTime.
func plausibleTime(s string) bool {
	if len(s) == 0 || len(s) > 8 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !((s[i] >= '0' && s[i] <= '9') || s[i] == ':') {
			return false
		}
	}
	return true
}

func (v *vt) privMode(nums []int, set bool) {
	for _, m := range nums {
		switch m {
		case 1049, 1047, 47:
			if set && !v.alt {
				v.mainGrid = v.grid
				v.mainR, v.mainC = v.cr, v.cc
				v.alt = true
				v.grid = blank(v.h, v.w)
				v.cr, v.cc = 0, 0
			} else if !set && v.alt {
				v.grid = v.mainGrid
				v.cr, v.cc = v.mainR, v.mainC
				v.alt = false
			}
		}
	}
}

func (v *vt) eraseDisplay(mode int) {
	switch mode {
	case 0:
		v.eraseLine(0)
		for r := v.cr + 1; r < v.h; r++ {
			v.grid[r] = v.blankRow()
		}
	case 1:
		v.eraseLine(1)
		for r := 0; r < v.cr; r++ {
			v.grid[r] = v.blankRow()
		}
	case 2, 3:
		for r := 0; r < v.h; r++ {
			v.grid[r] = v.blankRow()
		}
	}
}

func (v *vt) eraseLine(mode int) {
	row := v.grid[v.cr]
	switch mode {
	case 0:
		for c := v.cc; c < v.w; c++ {
			row[c] = Cell{R: ' '}
		}
	case 1:
		for c := 0; c <= v.cc && c < v.w; c++ {
			row[c] = Cell{R: ' '}
		}
	case 2:
		for c := 0; c < v.w; c++ {
			row[c] = Cell{R: ' '}
		}
	}
}

func (v *vt) eraseChars(nn int) {
	row := v.grid[v.cr]
	for c := v.cc; c < v.cc+nn && c < v.w; c++ {
		row[c] = Cell{R: ' '}
	}
}

func (v *vt) deleteChars(nn int) {
	if nn > v.w-v.cc { // bounds nn so row[v.cc+nn:] never indexes past the row
		nn = v.w - v.cc
	}
	if nn <= 0 {
		return
	}
	row := v.grid[v.cr]
	copy(row[v.cc:], row[v.cc+nn:])
	for c := v.w - nn; c < v.w; c++ {
		if c >= 0 {
			row[c] = Cell{R: ' '}
		}
	}
}

func (v *vt) insertChars(nn int) {
	row := v.grid[v.cr]
	if v.cc+nn < v.w {
		copy(row[v.cc+nn:], row[v.cc:])
	}
	for c := v.cc; c < v.cc+nn && c < v.w; c++ {
		row[c] = Cell{R: ' '}
	}
}

func (v *vt) insertLines(nn int) {
	nn = clampCount(nn, v.h)
	for k := 0; k < nn; k++ {
		copy(v.grid[v.cr+1:], v.grid[v.cr:])
		v.grid[v.cr] = v.blankRow()
	}
}

func (v *vt) deleteLines(nn int) {
	nn = clampCount(nn, v.h)
	for k := 0; k < nn; k++ {
		copy(v.grid[v.cr:], v.grid[v.cr+1:])
		v.grid[v.h-1] = v.blankRow()
	}
}

func clampCount(n, max int) int {
	if n < 0 {
		return 0
	}
	if n > max {
		return max
	}
	return n
}

func (v *vt) sgr(nums []int) {
	if len(nums) == 0 {
		nums = []int{0}
	}
	for i := 0; i < len(nums); i++ {
		p := nums[i]
		switch {
		case p == 0:
			v.cur = Style{}
		case p == 1:
			v.cur.Bold = true
		case p == 2:
			v.cur.Faint = true
		case p == 3:
			v.cur.Italic = true
		case p == 4:
			v.cur.Under = true
		case p == 7:
			v.cur.Reverse = true
		case p == 22:
			v.cur.Bold, v.cur.Faint = false, false
		case p == 23:
			v.cur.Italic = false
		case p == 24:
			v.cur.Under = false
		case p == 27:
			v.cur.Reverse = false
		case p >= 30 && p <= 37:
			v.cur.Fg = Color{Kind: 1, N: uint8(p - 30)}
		case p == 39:
			v.cur.Fg = Color{}
		case p >= 40 && p <= 47:
			v.cur.Bg = Color{Kind: 1, N: uint8(p - 40)}
		case p == 49:
			v.cur.Bg = Color{}
		case p >= 90 && p <= 97:
			v.cur.Fg = Color{Kind: 1, N: uint8(p - 90 + 8)}
		case p >= 100 && p <= 107:
			v.cur.Bg = Color{Kind: 1, N: uint8(p - 100 + 8)}
		case p == 38 || p == 48:
			col, used := parseColor(nums[i:])
			if p == 38 {
				v.cur.Fg = col
			} else {
				v.cur.Bg = col
			}
			i += used
		}
	}
}

func parseColor(nums []int) (Color, int) {
	if len(nums) >= 3 && nums[1] == 5 {
		return Color{Kind: 2, N: uint8(nums[2])}, 2
	}
	if len(nums) >= 5 && nums[1] == 2 {
		return Color{Kind: 3, R: uint8(nums[2]), G: uint8(nums[3]), B: uint8(nums[4])}, 4
	}
	return Color{}, 0
}

func parseParams(s string) []int {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ";")
	out := make([]int, len(parts))
	for i, p := range parts {
		n, _ := strconv.Atoi(p)
		out[i] = n
	}
	return out
}

func (v *vt) Lines() []Line {
	all := make([][]Cell, 0, len(v.scroll)+v.h)
	all = append(all, v.scroll...)
	all = append(all, v.grid...)
	last := -1
	for i, row := range all {
		if !blankCells(row) {
			last = i
		}
	}
	out := make([]Line, 0, last+1)
	for i := 0; i <= last; i++ {
		out = append(out, trimRight(all[i]))
	}
	return out
}

func blankCells(row []Cell) bool {
	for _, c := range row {
		if c.R != ' ' && c.R != 0 {
			return false
		}
	}
	return true
}

func trimRight(row []Cell) Line {
	end := len(row)
	for end > 0 && (row[end-1].R == ' ' || row[end-1].R == 0) && row[end-1].S == (Style{}) {
		end--
	}
	out := make(Line, end)
	for i := 0; i < end; i++ {
		if row[i].R == 0 {
			out[i] = Cell{R: ' '}
		} else {
			out[i] = row[i]
		}
	}
	return out
}
