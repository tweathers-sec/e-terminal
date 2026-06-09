package main

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var mouseArtifact = regexp.MustCompile(`\[?<?\d*;\d+;\d+[Mm]`)

func sanitizeSearch(s string) string {
	if mouseArtifact.MatchString(s) {
		return ""
	}
	var b strings.Builder
	for _, r := range s {
		if unicode.IsPrint(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

type pane int

const (
	paneSessions pane = iota
	paneCommands
)

type rect struct{ x, y, w, h int }

func (r rect) has(x, y int) bool {
	return x >= r.x && x < r.x+r.w && y >= r.y && y < r.y+r.h
}

type model struct {
	sessions []Session
	selS     int
	selC     int
	focus    pane

	filter       string
	filtering    bool
	filtered     []int
	searchOutput bool
	sortMode     int

	w, h int

	full    bool
	hScroll int
	clock   string
	tz      string

	vp    viewport.Model
	ready bool

	sessRect, cmdRect, outRect rect
}

type clockMsg time.Time

func tickClock() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg { return clockMsg(t) })
}

func newModel(sessions []Session) model {
	m := model{sessions: sessions, focus: paneCommands}
	now := time.Now()
	zone, off := now.Zone()
	m.tz = fmt.Sprintf("%s UTC%+03d:%02d", zone, off/3600, (abs(off)%3600)/60)
	m.clock = now.Format("Mon Jan 02 15:04:05")
	m.vp = viewport.New(0, 0)
	m.refilter()
	return m
}

func (m model) Init() tea.Cmd { return tickClock() }

func (m *model) curSession() *Session {
	if m.selS < 0 || m.selS >= len(m.sessions) {
		return nil
	}
	return &m.sessions[m.selS]
}

func (m *model) refilter() {
	m.filtered = m.filtered[:0]
	s := m.curSession()
	if s == nil {
		m.selC = 0
		return
	}
	q := strings.ToLower(strings.TrimSpace(m.filter))
	for i := range s.Cmds {
		if q == "" || m.cmdMatches(s.Cmds[i], q) {
			m.filtered = append(m.filtered, i)
		}
	}
	if m.selC >= len(m.filtered) {
		m.selC = len(m.filtered) - 1
	}
	if m.selC < 0 {
		m.selC = 0
	}
}

func outputMatches(c Command, q string) bool {
	if q == "" {
		return false
	}
	for _, ln := range c.Out {
		if strings.Contains(strings.ToLower(ln.Plain()), q) {
			return true
		}
	}
	return false
}

func (m *model) curCmd() *Command {
	s := m.curSession()
	if s == nil || m.selC < 0 || m.selC >= len(m.filtered) {
		return nil
	}
	idx := m.filtered[m.selC]
	if idx < 0 || idx >= len(s.Cmds) {
		return nil
	}
	return &s.Cmds[idx]
}

func (m *model) loadSession() {
	s := m.curSession()
	if s == nil || len(s.Full) == 0 {
		m.vp.SetContent(stEmpty.Render("  (empty session)"))
		return
	}
	ql := strings.ToLower(strings.TrimSpace(m.filter))
	var b strings.Builder
	for i, ln := range s.Full {
		if i > 0 {
			b.WriteByte('\n')
		}
		disp := m.displayLine(ln)
		if ql != "" {
			disp = highlightLine(disp, ql)
		}
		b.WriteString(disp.ANSI())
	}
	m.vp.SetContent(b.String())
	m.scrollToCmd()
}

func (m *model) displayLine(ln Line) Line {
	if reTime.MatchString(ln.Plain()) {
		if r, ok := reflowPrompt(ln, m.vp.Width); ok {
			return r
		}
	}
	return ln.Window(m.hScroll, m.vp.Width)
}

func (m *model) scrollToCmd() {
	c := m.curCmd()
	if c == nil {
		m.vp.GotoTop()
		return
	}
	target := c.LineIdx
	if ql := strings.ToLower(strings.TrimSpace(m.filter)); ql != "" {
		if s := m.curSession(); s != nil && m.selC < len(m.filtered) {
			ci := m.filtered[m.selC]
			end := len(s.Full)
			if ci+1 < len(s.Cmds) {
				end = s.Cmds[ci+1].LineIdx
			}
			for i := c.LineIdx; i < end && i < len(s.Full); i++ {
				if strings.Contains(strings.ToLower(s.Full[i].Plain()), ql) {
					target = i
					break
				}
			}
		}
	}
	m.vp.SetYOffset(target)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.layout()
		m.ready = true
		m.clampHScroll()
		m.loadSession()
		return m, nil

	case clockMsg:
		m.clock = time.Time(msg).Format("Mon Jan 02 15:04:05")
		return m, tickClock()

	case tea.MouseMsg:
		return m.mouse(msg)

	case tea.KeyMsg:
		return m.key(msg)
	}
	return m, nil
}

func (m *model) maxLineWidth() int {
	s := m.curSession()
	if s == nil {
		return 0
	}
	mx := 0
	for _, ln := range s.Full {
		if w := lineWidth(ln); w > mx {
			mx = w
		}
	}
	return mx
}

func (m *model) clampHScroll() {
	max := m.maxLineWidth() - m.vp.Width
	if max < 0 {
		max = 0
	}
	if m.hScroll > max {
		m.hScroll = max
	}
	if m.hScroll < 0 {
		m.hScroll = 0
	}
}

func (m *model) panBy(d int) {
	y := m.vp.YOffset
	m.hScroll += d
	m.clampHScroll()
	m.loadSession()
	m.vp.SetYOffset(y)
}

func (m model) key(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.full {
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "q", "esc", "enter":
			m.full = false
			m.layout()
			m.scrollToCmd()
		case "up", "k":
			m.vp.ScrollUp(1)
		case "down", "j":
			m.vp.ScrollDown(1)
		case "left", "h":
			m.panBy(-8)
		case "right", "l":
			m.panBy(8)
		case "ctrl+d":
			m.vp.HalfPageDown()
		case "ctrl+u":
			m.vp.HalfPageUp()
		case "pgdown", " ":
			m.vp.PageDown()
		case "pgup", "b":
			m.vp.PageUp()
		case "g", "home":
			m.vp.GotoTop()
		case "G", "end":
			m.vp.GotoBottom()
		case "0":
			m.hScroll = 0
			m.loadSession()
		}
		return m, nil
	}

	if m.filtering {
		var cmd tea.Cmd
		switch msg.Type {
		case tea.KeyEnter:
			m.filtering = false
			cmd = tea.EnableMouseCellMotion
		case tea.KeyTab:
			m.searchOutput = !m.searchOutput
			m.refilter()
			m.jumpToFirstMatch()
			m.scrollToCmd()
		case tea.KeyEsc:
			m.filtering = false
			m.filter = ""
			m.refilter()
			m.scrollToCmd()
			cmd = tea.EnableMouseCellMotion
		case tea.KeyBackspace:
			if len(m.filter) > 0 {
				m.filter = m.filter[:len(m.filter)-1]
				m.refilter()
				m.jumpToFirstMatch()
				m.scrollToCmd()
			}
		case tea.KeyRunes, tea.KeySpace:
			in := string(msg.Runes)
			if msg.Type == tea.KeySpace {
				in = " "
			}
			if in = sanitizeSearch(in); in == "" {
				return m, nil
			}
			m.filter += in
			m.refilter()
			m.jumpToFirstMatch()
			m.scrollToCmd()
		}
		return m, cmd
	}

	switch msg.String() {
	case "q", "ctrl+c", "esc":
		return m, tea.Quit
	case "enter":
		m.full = true
		m.layout()
		m.scrollToCmd()
		return m, nil
	case "s":
		m.sortMode = (m.sortMode + 1) % 3
		m.sortSessions()
		m.selC = 0
		m.refilter()
		m.loadSession()
		return m, nil
	case "/":
		m.filtering = true
		return m, tea.DisableMouse // prevent mouse codes from reaching the search box
	case "tab":
		m.focus = (m.focus + 1) % 2
		return m, nil
	case "left", "h":
		m.focus = paneSessions
		return m, nil
	case "right", "l":
		m.focus = paneCommands
		return m, nil
	case "up", "k":
		m.move(-1)
		return m, nil
	case "down", "j":
		m.move(1)
		return m, nil
	case "g", "home":
		m.moveTo(0)
		return m, nil
	case "G", "end":
		m.moveTo(1 << 30)
		return m, nil
	case "<", "shift+left":
		m.panBy(-8)
		return m, nil
	case ">", "shift+right":
		m.panBy(8)
		return m, nil
	case "ctrl+d":
		m.vp.HalfPageDown()
		return m, nil
	case "ctrl+u":
		m.vp.HalfPageUp()
		return m, nil
	case "pgdown":
		m.vp.PageDown()
		return m, nil
	case "pgup":
		m.vp.PageUp()
		return m, nil
	}
	return m, nil
}

func (m *model) move(d int) {
	switch m.focus {
	case paneSessions:
		m.selS = clamp(m.selS+d, 0, len(m.sessions)-1)
		m.selC = 0
		m.hScroll = 0
		m.refilter()
		m.loadSession()
	case paneCommands:
		m.selC = clamp(m.selC+d, 0, len(m.filtered)-1)
		m.scrollToCmd()
	}
}

func (m *model) moveTo(i int) {
	switch m.focus {
	case paneSessions:
		m.selS = clamp(i, 0, len(m.sessions)-1)
		m.selC = 0
		m.hScroll = 0
		m.refilter()
		m.loadSession()
	case paneCommands:
		m.selC = clamp(i, 0, len(m.filtered)-1)
		m.scrollToCmd()
	}
}

// Name encodes the start timestamp, so Name-desc is newest-first.
func (m *model) sortSessions() {
	switch m.sortMode {
	case 1:
		sort.SliceStable(m.sessions, func(i, j int) bool { return m.sessions[i].Name < m.sessions[j].Name })
	case 2:
		sort.SliceStable(m.sessions, func(i, j int) bool { return len(m.sessions[i].Cmds) > len(m.sessions[j].Cmds) })
	default:
		sort.SliceStable(m.sessions, func(i, j int) bool { return m.sessions[i].Name > m.sessions[j].Name })
	}
	m.selS = 0
}

func (m *model) sortLabel() string {
	switch m.sortMode {
	case 1:
		return "oldest"
	case 2:
		return "most cmds"
	default:
		return "newest"
	}
}

func (m *model) jumpToFirstMatch() {
	q := strings.ToLower(strings.TrimSpace(m.filter))
	if q == "" || len(m.filtered) > 0 {
		return
	}
	for i := range m.sessions {
		if m.sessionMatches(&m.sessions[i], q) {
			m.selS = i
			m.selC = 0
			m.hScroll = 0
			m.refilter()
			m.loadSession()
			return
		}
	}
}

func (m *model) cmdMatches(c Command, q string) bool {
	if strings.Contains(strings.ToLower(c.Text), q) {
		return true
	}
	return m.searchOutput && outputMatches(c, q)
}

func (m *model) sessionMatches(s *Session, q string) bool {
	if q == "" {
		return false
	}
	for i := range s.Cmds {
		if m.cmdMatches(s.Cmds[i], q) {
			return true
		}
	}
	return false
}

func (m *model) matchingSessions() int {
	q := strings.ToLower(strings.TrimSpace(m.filter))
	if q == "" {
		return 0
	}
	n := 0
	for i := range m.sessions {
		if m.sessionMatches(&m.sessions[i], q) {
			n++
		}
	}
	return n
}

func (m *model) searchModeLabel() string {
	if m.searchOutput {
		return "command + output"
	}
	return "command"
}

func (m *model) searchModeShort() string {
	if m.searchOutput {
		return "cmd+out"
	}
	return "cmd"
}

func (m model) mouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if m.full {
		switch msg.Button {
		case tea.MouseButtonWheelUp:
			m.vp.ScrollUp(3)
		case tea.MouseButtonWheelDown:
			m.vp.ScrollDown(3)
		}
		return m, nil
	}
	switch msg.Button {
	case tea.MouseButtonWheelUp:
		if m.outRect.has(msg.X, msg.Y) {
			m.vp.ScrollUp(3)
		} else {
			m.move(-1)
		}
		return m, nil
	case tea.MouseButtonWheelDown:
		if m.outRect.has(msg.X, msg.Y) {
			m.vp.ScrollDown(3)
		} else {
			m.move(1)
		}
		return m, nil
	}
	if msg.Action == tea.MouseActionPress && msg.Button == tea.MouseButtonLeft {
		switch {
		case m.sessRect.has(msg.X, msg.Y):
			idx := scrollOffset(m.selS, len(m.sessions), sessVisible(m.sessRect.h)) + (msg.Y-m.sessRect.y)/2
			if idx >= 0 && idx < len(m.sessions) {
				m.focus = paneSessions
				m.selS = idx
				m.selC = 0
				m.hScroll = 0
				m.refilter()
				m.loadSession()
			}
		case m.cmdRect.has(msg.X, msg.Y):
			idx := scrollOffset(m.selC, len(m.filtered), m.cmdRect.h) + (msg.Y - m.cmdRect.y)
			if idx >= 0 && idx < len(m.filtered) {
				m.focus = paneCommands
				m.selC = idx
				m.scrollToCmd()
			}
		case m.outRect.has(msg.X, msg.Y):
			m.full = true
			m.layout()
			m.scrollToCmd()
		}
	}
	return m, nil
}

func clamp(v, lo, hi int) int {
	if hi < lo {
		return lo
	}
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func scrollOffset(sel, n, h int) int {
	if n <= h || sel < h {
		return 0
	}
	off := sel - h/2
	if off < 0 {
		off = 0
	}
	if off > n-h {
		off = n - h
	}
	return off
}

var _ = fmt.Sprintf
var _ = lipgloss.Width
