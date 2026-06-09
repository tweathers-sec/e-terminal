package main

import "github.com/charmbracelet/lipgloss"

var (
	cAccent = lipgloss.Color("#ff5a2c")
	cOrange = lipgloss.Color("#ff7a18")
	cFg     = lipgloss.Color("#eaeaea")
	cGray   = lipgloss.Color("#8a8a8a")
	cDim    = lipgloss.Color("#5a5a5a")
	cDimmer = lipgloss.Color("#3a3a3a")
	cSelBg  = lipgloss.Color("#1c1c1c")
	cWhite  = lipgloss.Color("#ffffff")
)

var (
	stPaneActive = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).BorderForeground(cAccent)
	stPaneIdle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).BorderForeground(cDimmer)

	stLabel     = lipgloss.NewStyle().Foreground(cAccent).Bold(true)
	stLabelIdle = lipgloss.NewStyle().Foreground(cGray)

	stItemSel = lipgloss.NewStyle().Background(cSelBg).Foreground(cWhite).Bold(true)
	stItem    = lipgloss.NewStyle().Foreground(cFg)
	stTime    = lipgloss.NewStyle().Foreground(cGray)
	stTimeSel = lipgloss.NewStyle().Background(cSelBg).Foreground(cAccent).Bold(true)
	stMeta    = lipgloss.NewStyle().Foreground(cDim)
	stPrompt  = lipgloss.NewStyle().Foreground(cAccent)

	stBar    = lipgloss.NewStyle().Foreground(cGray)
	stBarKey = lipgloss.NewStyle().Foreground(cAccent).Bold(true)
	stBarSep = lipgloss.NewStyle().Foreground(cDimmer)
	stEmpty  = lipgloss.NewStyle().Foreground(cDim).Italic(true)
	stSearch = lipgloss.NewStyle().Foreground(cOrange)
	stMatch  = lipgloss.NewStyle().Foreground(cAccent).Bold(true).Underline(true)
)
