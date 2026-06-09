package main

import (
	"fmt"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"
)

func main() {
	dir := os.Getenv("E_SESSION_LOG_DIR")
	if dir == "" {
		home, _ := os.UserHomeDir()
		dir = filepath.Join(home, "terminal_logs")
	}

	if !term.IsTerminal(int(os.Stdout.Fd())) {
		fmt.Fprintln(os.Stderr, "e-session-view: needs an interactive terminal")
		os.Exit(1)
	}

	sessions := loadSessions(dir)
	if len(sessions) == 0 {
		fmt.Fprintf(os.Stderr, "no recorded sessions in %s\n", dir)
		os.Exit(1)
	}

	p := tea.NewProgram(newModel(sessions), tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
