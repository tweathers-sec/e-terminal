package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Command struct {
	Time     string
	Text     string
	LineIdx  int
	OutStart int
	Out      []Line
}

type Session struct {
	Path  string
	Name  string
	Date  string
	Start string
	Shell string
	Size  int64
	Full  []Line
	Cmds  []Command
	raw   []byte
}

const scanW = 1000

// parse renders at the exact recorded dimensions. Height matters because line editors (reedline/zle)
// position cursors absolutely against the real terminal height; a mismatch corrupts erase/scroll.
func (s *Session) parse() {
	w, h := recordedSize(s.raw) // exact rows x cols from the recorder, when present
	if h == 0 {
		h = recordHeight(s.raw)
	}
	var v *vt
	if w > 0 {
		v = newVT(w, h)
		v.Feed(s.raw)
	} else {
		v = newVT(scanW, h)
		v.Feed(s.raw)
		if cw := recordWidth(v.Lines()); cw > 0 && cw < scanW {
			v = newVT(cw, h)
			v.Feed(s.raw)
		}
	}
	s.Full = v.Lines()
	s.Cmds = segment(s.Full, v.marks, s.Start)
}

var reSizeMarker = regexp.MustCompile("\x1b\\]9002;size;(\\d+);(\\d+)\x07")

func recordedSize(raw []byte) (w, h int) {
	m := reSizeMarker.FindSubmatch(raw)
	if m == nil {
		return 0, 0
	}
	r, _ := strconv.Atoi(string(m[1]))
	c, _ := strconv.Atoi(string(m[2]))
	return c, r
}

var reCursorRow = regexp.MustCompile("\x1b\\[(\\d+)(?:;\\d+)?[Hf]")

func recordHeight(raw []byte) int {
	mx := 0
	for _, m := range reCursorRow.FindAllSubmatch(raw, -1) {
		n, _ := strconv.Atoi(string(m[1]))
		if n > mx {
			mx = n
		}
	}
	if mx < 4 || mx > 2000 {
		return 50
	}
	return mx
}

func recordWidth(lines []Line) int {
	mx := 0
	for _, l := range lines {
		if reTime.MatchString(l.Plain()) {
			if w := lineWidth(l); w > mx {
				mx = w
			}
		}
	}
	return mx
}

var (
	reName = regexp.MustCompile(`^session_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_([^_]+)_`)
	reTime = regexp.MustCompile(`[A-Z][a-z][a-z] +[A-Z][a-z][a-z] +\d+ +(\d\d:\d\d(?::\d\d)?)`)
	rePrmt = regexp.MustCompile(`^[\x{276f}\x{276e}]\s+(\S.*?)\s*$`) // ❯ / ❮  command
)

// Sorts by filename timestamp, not mtime: a long-running earlier session can have an mtime newer than a later one.
func loadSessions(dir string) []Session {
	paths, _ := filepath.Glob(filepath.Join(dir, "session_*.log"))
	sort.Slice(paths, func(i, j int) bool { return paths[i] > paths[j] })
	out := make([]Session, 0, len(paths))
	for _, p := range paths {
		s := parseSession(p)
		if len(s.Cmds) > 0 {
			out = append(out, s)
		}
	}
	return out
}

var viewerSig = [][]byte{
	[]byte("scroll output"), []byte(" drop in"), []byte("search sessions"),
	[]byte("indexing sessions"), []byte("top/bottom"), []byte("esc back"),
	[]byte("─ sessions "), []byte("─ commands "), []byte("─ terminal view"),
}

func isViewerLog(raw []byte) bool {
	for _, sig := range viewerSig {
		if bytes.Contains(raw, sig) {
			return true
		}
	}
	return false
}

func parseSession(path string) Session {
	s := Session{Path: path, Name: filepath.Base(path)}
	if st, err := os.Stat(path); err == nil {
		s.Size = st.Size()
	}
	if m := reName.FindStringSubmatch(s.Name); m != nil {
		s.Date = m[2] + "-" + m[3]
		s.Start = m[4] + ":" + m[5] + ":" + m[6]
		s.Shell = m[7]
	}
	data, err := os.ReadFile(path)
	if err != nil || isViewerLog(data) {
		return s
	}
	s.raw = data
	s.parse()
	return s
}

func segment(lines []Line, tsMarks []tsMark, fallbackTime string) []Command {
	type mark struct {
		cmdLine int
		promptL int // the prompt's first (time) line, or cmdLine if none
		time    string
		text    string
	}
	var marks []mark
	lastTime := fallbackTime
	lastTimeLine := -1
	for i, ln := range lines {
		p := ln.Plain()
		if m := reTime.FindStringSubmatch(p); m != nil {
			lastTime = m[1]
			lastTimeLine = i
		}
		t := strings.TrimSpace(p)
		if mm := rePrmt.FindStringSubmatch(t); mm != nil {
			cmd := strings.TrimSpace(mm[1])
			if cmd == "" || isNoise(cmd) {
				continue
			}
			// A "❯" with no Starship time line immediately above is an inline input prompt from
			// another tool, not a shell command; skip it to keep the command list accurate.
			if lastTimeLine < 0 || i-lastTimeLine > 2 {
				continue
			}
			marks = append(marks, mark{cmdLine: i, promptL: lastTimeLine, time: lastTime, text: cmd})
		}
	}
	cmds := make([]Command, 0, len(marks))
	for k, mk := range marks {
		end := len(lines)
		if k+1 < len(marks) {
			end = marks[k+1].promptL
		}
		start := mk.cmdLine + 1
		var out []Line
		if start < end {
			out = append(out, lines[start:end]...)
		}
		t := mk.time
		for _, tm := range tsMarks {
			if tm.line >= mk.cmdLine && tm.line < end {
				t = tm.t
				if mk.promptL >= 0 && mk.promptL < len(lines) {
					setLineTime(lines[mk.promptL], t)
				}
				break
			}
		}
		cmds = append(cmds, Command{Time: t, Text: mk.text, LineIdx: mk.promptL, OutStart: start, Out: trimBlankEdges(out)})
	}
	return cmds
}

func setLineTime(l Line, t string) {
	idx := -1
	for i := 0; i+5 <= len(l); i++ {
		if isHM(l, i) && (i == 0 || (l[i-1].R != ':' && !isDigit(l[i-1].R))) {
			idx = i
		}
	}
	if idx < 0 {
		return
	}
	for i := 0; i < len(t) && idx+i < len(l); i++ {
		l[idx+i].R = rune(t[i])
	}
}

func isDigit(r rune) bool { return r >= '0' && r <= '9' }

func isHM(l Line, i int) bool {
	return isDigit(l[i].R) && isDigit(l[i+1].R) && l[i+2].R == ':' && isDigit(l[i+3].R) && isDigit(l[i+4].R)
}

func isNoise(cmd string) bool {
	c := strings.ToLower(strings.TrimSpace(cmd))
	return strings.Contains(c, "e-session-log view") ||
		strings.Contains(c, "e-session-view") ||
		c == "e-session-log"
}

func trimBlankEdges(ls []Line) []Line {
	start, end := 0, len(ls)
	for start < end && strings.TrimSpace(ls[start].Plain()) == "" {
		start++
	}
	for end > start && strings.TrimSpace(ls[end-1].Plain()) == "" {
		end--
	}
	return ls[start:end]
}
