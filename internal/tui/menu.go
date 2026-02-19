package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/hiroaqii/bgg-tui/internal/config"
)

type menuItem struct {
	label string
	key   string
	view  View
}

type menuModel struct {
	cursor   int
	items    []menuItem
	config   *config.Config
	styles   Styles
	keys     KeyMap
	selected *View
	hasToken bool
}

func newMenuModel(cfg *config.Config, styles Styles, keys KeyMap, hasToken bool) menuModel {
	return menuModel{
		cursor: 0,
		items: []menuItem{
			{label: "Search Games", key: "1", view: ViewSearchInput},
			{label: "Hot Games", key: "2", view: ViewHot},
			{label: "User Collection", key: "3", view: ViewCollectionInput},
			{label: "Settings", key: "4", view: ViewSettings},
		},
		config:   cfg,
		styles:   styles,
		keys:     keys,
		hasToken: hasToken,
	}
}

func (m menuModel) Update(msg tea.Msg) (menuModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keys.Quit):
			return m, tea.Quit
		case key.Matches(msg, m.keys.Up):
			if m.cursor > 0 {
				m.cursor--
			}
		case key.Matches(msg, m.keys.Down):
			if m.cursor < len(m.items)-1 {
				m.cursor++
			}
		case key.Matches(msg, m.keys.Enter):
			view := m.items[m.cursor].view
			m.selected = &view
		case key.Matches(msg, m.keys.Settings):
			view := ViewSettings
			m.selected = &view
		case key.Matches(msg, m.keys.Search):
			view := ViewSearchInput
			m.selected = &view
		case key.Matches(msg, m.keys.Hot):
			view := ViewHot
			m.selected = &view
		case key.Matches(msg, m.keys.Collect):
			view := ViewCollectionInput
			m.selected = &view
		}
	}
	return m, nil
}

func (m menuModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder

	// Title
	title := m.styles.Title.Render("BGG TUI")
	subtitle := m.styles.Subtitle.Render("BoardGameGeek Terminal Client")

	b.WriteString(title)
	b.WriteString("\n")
	b.WriteString(subtitle)
	b.WriteString("\n\n")

	if !m.hasToken {
		b.WriteString(m.styles.Error.Render(errNoToken))
		b.WriteString("\n\n")
	}

	// Menu items
	for i, item := range m.items {
		cursor := "  "
		style := m.styles.MenuItem
		if i == m.cursor {
			cursor = "> "
			style = m.styles.MenuItemFocus
		}

		label := style.Render(item.label)
		if i == m.cursor {
			label = renderSelectionAnim(item.label, selType, animFrame)
		}
		line := fmt.Sprintf("%s[%s] %s", cursor, item.key, label)
		b.WriteString(line)
		b.WriteString("\n")
	}

	b.WriteString("\n")

	// Quit option
	b.WriteString(fmt.Sprintf("  [q] %s\n", m.styles.MenuItem.Render("Quit")))

	// Help
	b.WriteString("\n")
	help := m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Select  ?: Help  q: Quit")
	b.WriteString(help)

	content := b.String()
	return renderView(content, m.styles, width, height, m.config.Interface.BorderStyle)
}
