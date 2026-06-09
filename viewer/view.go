package main

import (
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

func (m *model) outInnerW() int { return m.w }

func (m *model) layout() {
	footerH := 1
	avail := m.h - footerH
	if avail < 8 {
		avail = 8
	}
	if m.full {
		m.outRect = rect{x: 0, y: 1, w: m.w, h: avail - 2}
		m.vp.Width = m.outRect.w
		m.vp.Height = m.outRect.h
		return
	}
	outTotal := avail * 64 / 100
	if outTotal < 6 {
		outTotal = 6
	}
	topTotal := avail - outTotal
	if topTotal < 5 {
		topTotal = 5
	}
	sessW := clamp(m.w*34/100, 28, 54)
	cmdW := m.w - sessW

	m.sessRect = rect{x: 1, y: 1, w: sessW - 2, h: topTotal - 2}
	m.cmdRect = rect{x: sessW + 1, y: 1, w: cmdW - 2, h: topTotal - 2}
	m.outRect = rect{x: 0, y: topTotal + 1, w: m.w, h: outTotal - 2}

	m.vp.Width = m.outRect.w
	m.vp.Height = m.outRect.h
}

func (m model) View() string {
	if !m.ready || m.w < 30 || m.h < 12 {
		return "loading sessions…"
	}
	if m.full {
		out := ruleLabel(m.fullLabel(), m.w, true) + "\n" + m.vp.View() + "\n" + rule(m.w, true)
		return lipgloss.JoinVertical(lipgloss.Left, out, m.footer())
	}

	sessW := m.sessRect.w + 2
	cmdW := m.cmdRect.w + 2
	topH := m.sessRect.h + 2
	outH := m.outRect.h + 2

	sessActive := m.focus == paneSessions && !m.filtering
	cmdActive := m.focus == paneCommands || m.filtering

	sessLabel := "sessions"
	if m.filter != "" {
		sessLabel = "sessions " + stMeta.Render("“"+m.filter+"” "+strconv.Itoa(m.matchingSessions())+"/"+strconv.Itoa(len(m.sessions)))
	} else if n := len(m.sessions); n > 0 {
		sessLabel = "sessions " + dimNum(n) + stMeta.Render(" · "+m.sortLabel())
	}
	cmdLabel := m.cmdLabel()

	left := box(sessLabel, sessW, topH, sessActive, m.renderSessions(m.sessRect.w, m.sessRect.h))
	right := box(cmdLabel, cmdW, topH, cmdActive, m.renderCommands(m.cmdRect.w, m.cmdRect.h))
	top := lipgloss.JoinHorizontal(lipgloss.Top, left, right)

	_ = outH
	out := ruleLabel(m.outLabel(), m.w, false) + "\n" + m.vp.View() + "\n" + rule(m.w, false)

	return lipgloss.JoinVertical(lipgloss.Left, top, out, m.footer())
}

func ruleLabel(label string, w int, active bool) string {
	c := cDimmer
	if active {
		c = cAccent
	}
	b := lipgloss.NewStyle().Foreground(c)
	lab := ""
	labW := 0
	if label != "" {
		lab = b.Render("─ ") + label + b.Render(" ")
		labW = 2 + lipgloss.Width(label) + 1
	}
	dash := w - labW
	if dash < 0 {
		dash = 0
	}
	return lab + b.Render(strings.Repeat("─", dash))
}

func rule(w int, active bool) string {
	c := cDimmer
	if active {
		c = cAccent
	}
	return lipgloss.NewStyle().Foreground(c).Render(strings.Repeat("─", w))
}

func (m model) fullLabel() string {
	s := m.curSession()
	if s == nil {
		return "session"
	}
	return "session " + stMeta.Render("· ") + stItem.Render(s.Name)
}

func dimNum(n int) string { return stMeta.Render("(" + strconv.Itoa(n) + ")") }

func (m model) cmdLabel() string {
	s := m.curSession()
	if s == nil {
		return "commands"
	}
	if m.filtering || m.filter != "" {
		return "commands " + stMeta.Render(m.searchModeShort()+" · "+strconv.Itoa(len(m.filtered))+"/"+strconv.Itoa(len(s.Cmds)))
	}
	return "commands " + stMeta.Render("("+strconv.Itoa(len(s.Cmds))+")")
}

func (m model) outLabel() string {
	c := m.curCmd()
	if c == nil {
		return "output"
	}
	return "output " + stMeta.Render("· "+c.Time+" ") + stPrompt.Render("❯ ") + stItem.Render(truncRunes(c.Text, 60))
}

func sessVisible(innerH int) int {
	v := innerH / 2
	if v < 1 {
		v = 1
	}
	return v
}

func (m model) renderSessions(innerW, innerH int) string {
	if len(m.sessions) == 0 {
		return padBody(stEmpty.Render("  no sessions"), innerW, innerH)
	}
	off := scrollOffset(m.selS, len(m.sessions), sessVisible(innerH))
	q := strings.ToLower(strings.TrimSpace(m.filter))
	var lines []string
	for v := 0; v < sessVisible(innerH); v++ {
		i := off + v
		if i >= len(m.sessions) {
			lines = append(lines, strings.Repeat(" ", innerW), strings.Repeat(" ", innerW))
			continue
		}
		match := q != "" && m.sessionMatches(&m.sessions[i], q)
		t, b := sessionRows(m.sessions[i], innerW, i == m.selS, q != "", match)
		lines = append(lines, t, b)
	}
	for len(lines) < innerH {
		lines = append(lines, strings.Repeat(" ", innerW))
	}
	return strings.Join(lines[:innerH], "\n")
}

func (m model) renderCommands(innerW, innerH int) string {
	s := m.curSession()
	if s == nil {
		return padBody("", innerW, innerH)
	}
	if len(m.filtered) == 0 {
		msg := "  no commands"
		if m.filter != "" {
			msg = "  no match for “" + m.filter + "”"
		}
		return padBody(stEmpty.Render(msg), innerW, innerH)
	}
	off := scrollOffset(m.selC, len(m.filtered), innerH)
	var lines []string
	for r := 0; r < innerH; r++ {
		i := off + r
		if i >= len(m.filtered) {
			lines = append(lines, strings.Repeat(" ", innerW))
			continue
		}
		c := s.Cmds[m.filtered[i]]
		lines = append(lines, commandRow(c.Time, c.Text, innerW, i == m.selC))
	}
	return strings.Join(lines, "\n")
}

func sessionRows(s Session, innerW int, sel, filtering, match bool) (string, string) {
	cmds := "s"
	if len(s.Cmds) == 1 {
		cmds = ""
	}
	marker := " "
	if filtering && match {
		marker = "›"
	}
	top := marker + s.Date + " " + first(s.Start, 5) + "  ·  " + s.Shell + " · " + strconv.Itoa(len(s.Cmds)) + " cmd" + cmds
	bot := "  " + s.Name
	if sel {
		bg := lipgloss.NewStyle().Background(cSelBg)
		return bg.Foreground(cWhite).Bold(true).Render(fitPlain(top, innerW)),
			bg.Foreground(cAccent).Render(fitPlain(bot, innerW))
	}
	if filtering {
		if match {
			return lipgloss.NewStyle().Foreground(cAccent).Bold(true).Render(fitPlain(top, innerW)),
				lipgloss.NewStyle().Foreground(cAccent).Render(fitPlain(bot, innerW))
		}
		return lipgloss.NewStyle().Foreground(cDimmer).Render(fitPlain(top, innerW)),
			lipgloss.NewStyle().Foreground(cDimmer).Render(fitPlain(bot, innerW))
	}
	return lipgloss.NewStyle().Foreground(cFg).Render(fitPlain(top, innerW)),
		stMeta.Render(fitPlain(bot, innerW))
}

func fitPlain(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		return truncRunes(s, n)
	}
	return s + strings.Repeat(" ", n-len(r))
}

func commandRow(t, cmd string, innerW int, sel bool) string {
	prefix := " " + first(t, 8) + " "
	prompt := "❯ "
	cmdW := innerW - lipgloss.Width(prefix) - lipgloss.Width(prompt) - 1
	cmd = truncRunes(cmd, max(1, cmdW))
	pad := innerW - lipgloss.Width(prefix) - lipgloss.Width(prompt) - lipgloss.Width(cmd)
	if pad < 0 {
		pad = 0
	}
	if sel {
		bg := lipgloss.NewStyle().Background(cSelBg)
		return clipLine(
			bg.Foreground(cAccent).Bold(true).Render(prefix)+
				bg.Foreground(cAccent).Render(prompt)+
				bg.Foreground(cWhite).Bold(true).Render(cmd+strings.Repeat(" ", pad)),
			innerW, cSelBg)
	}
	return clipLine(
		stTime.Render(prefix)+
			stPrompt.Render(prompt)+
			stItem.Render(cmd+strings.Repeat(" ", pad)),
		innerW, "")
}

func (m model) footer() string {
	tz := stBarKey.Render(m.clock) + stBarSep.Render(" · ") + stTime.Render(m.tz) + " "
	tzW := lipgloss.Width(tz)
	sep := stBarSep.Render("  ·  ")

	var left string
	switch {
	case m.filtering:
		mode := lipgloss.NewStyle().Foreground(cAccent).Bold(true).Render("[" + m.searchModeLabel() + "]")
		toggle := "⇥ +output"
		if m.searchOutput {
			toggle = "⇥ command only"
		}
		left = stSearch.Render(" search ") + mode + " " + stBarKey.Render("❯ ") +
			lipgloss.NewStyle().Foreground(cWhite).Render(m.filter) +
			stPrompt.Render("▌") + "  " + stBar.Render(toggle+" · enter apply · esc clear")
	case m.full:
		left = " " + strings.Join([]string{
			stBarKey.Render("↑↓ ^U/^D") + stBar.Render(" scroll"),
			stBarKey.Render("←→") + stBar.Render(" pan"),
			stBarKey.Render("g/G") + stBar.Render(" ends"),
			stBarKey.Render("esc") + stBar.Render(" back"),
		}, sep)
	default:
		left = " " + strings.Join([]string{
			stBarKey.Render("↑↓") + stBar.Render(" select"),
			stBarKey.Render("⇥") + stBar.Render(" pane"),
			stBarKey.Render("↵") + stBar.Render(" drop in"),
			stBarKey.Render("/") + stBar.Render(" search"),
			stBarKey.Render("s") + stBar.Render(" sort"),
			stBarKey.Render("q") + stBar.Render(" quit"),
		}, sep)
	}
	gap := m.w - lipgloss.Width(left) - tzW
	if gap < 1 {
		left = clipLine(left, max(0, m.w-tzW-1), "")
		gap = 1
	}
	return left + strings.Repeat(" ", gap) + tz
}

func box(label string, w, h int, active bool, body string) string {
	bc, lc := cDimmer, cGray
	if active {
		bc, lc = cAccent, cAccent
	}
	b := lipgloss.NewStyle().Foreground(bc)
	l := lipgloss.NewStyle().Foreground(lc).Bold(active)

	var lab string
	labW := 0
	if label != "" {
		lab = b.Render("─ ") + l.Render(stripto(label)) + b.Render(" ")
		labW = 2 + lipgloss.Width(label) + 1
	}
	dash := w - 2 - labW
	if dash < 0 {
		dash = 0
	}
	top := b.Render("╭") + lab + b.Render(strings.Repeat("─", dash)) + b.Render("╮")
	bottom := b.Render("╰" + strings.Repeat("─", w-2) + "╯")

	bodyLines := strings.Split(body, "\n")
	inner := h - 2
	side := b.Render("│")
	var sb strings.Builder
	sb.WriteString(top)
	sb.WriteByte('\n')
	for i := 0; i < inner; i++ {
		var line string
		if i < len(bodyLines) {
			line = bodyLines[i]
		}
		line = padTo(line, w-2)
		sb.WriteString(side + line + side)
		sb.WriteByte('\n')
	}
	sb.WriteString(bottom)
	return sb.String()
}

func padBody(body string, innerW, innerH int) string {
	lines := strings.Split(body, "\n")
	out := make([]string, innerH)
	for i := 0; i < innerH; i++ {
		if i < len(lines) {
			out[i] = padTo(lines[i], innerW)
		} else {
			out[i] = strings.Repeat(" ", innerW)
		}
	}
	return strings.Join(out, "\n")
}

func first(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

func truncRunes(s string, n int) string {
	if n < 0 {
		n = 0
	}
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	if n <= 1 {
		return string(r[:n])
	}
	return string(r[:n-1]) + "…"
}

func stripto(s string) string { return s }

func padTo(s string, w int) string {
	vw := lipgloss.Width(s)
	if vw == w {
		return s
	}
	if vw < w {
		return s + strings.Repeat(" ", w-vw)
	}
	return clipLine(s, w, "")
}

func clipLine(s string, w int, _ lipgloss.Color) string {
	if lipgloss.Width(s) <= w {
		return s
	}
	var b strings.Builder
	vis := 0
	rs := []rune(s)
	for i := 0; i < len(rs); i++ {
		if rs[i] == 0x1b {
			b.WriteRune(rs[i])
			i++
			for i < len(rs) && rs[i] != 'm' {
				b.WriteRune(rs[i])
				i++
			}
			if i < len(rs) {
				b.WriteRune(rs[i])
			}
			continue
		}
		if vis >= w {
			continue
		}
		b.WriteRune(rs[i])
		vis++
	}
	b.WriteString("\x1b[0m")
	return b.String()
}
