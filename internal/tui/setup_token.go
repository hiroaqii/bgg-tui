package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

type setupTokenModel struct {
	styles     Styles
	keys       KeyMap
	tokenInput textinput.Model
	done       bool
	config     *config.Config
}

func newSetupTokenModel(cfg *config.Config, styles Styles, keys KeyMap) setupTokenModel {
	ti := textinput.New()
	ti.Placeholder = "paste your token here"
	ti.Focus()
	ti.CharLimit = 256
	ti.Width = 40

	return setupTokenModel{
		styles:     styles,
		keys:       keys,
		tokenInput: ti,
		config:     cfg,
	}
}

func (m setupTokenModel) Update(msg tea.Msg) (setupTokenModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keys.Enter):
			token := strings.TrimSpace(m.tokenInput.Value())
			if token != "" {
				m.config.API.Token = token
				_ = m.config.Save()
				m.done = true
			}
			return m, nil
		case key.Matches(msg, m.keys.Quit):
			return m, tea.Quit
		}
	}

	var cmd tea.Cmd
	m.tokenInput, cmd = m.tokenInput.Update(msg)
	return m, cmd
}

func (m setupTokenModel) View(width, height int) string {
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(ColorAccent)

	var b strings.Builder

	b.WriteString(titleStyle.Render("Setup Required"))
	b.WriteString("\n\n")
	b.WriteString("BGG API Token is required.\n\n")
	b.WriteString("1. Go to https://boardgamegeek.com/applications\n")
	b.WriteString("2. Create an application\n")
	b.WriteString("3. Generate a token\n")
	b.WriteString("4. Enter it below:\n\n")
	b.WriteString(fmt.Sprintf("Token: %s\n", m.tokenInput.View()))
	b.WriteString("\n")
	b.WriteString(m.styles.Help.Render("Enter: Save  q: Quit"))

	content := b.String()
	return centerContent(content, width, height)
}
