package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type menuItem struct {
	label string
	key   string
	view  View
}

type menuModel struct {
	cursor   int
	items    []menuItem
	styles   Styles
	keys     KeyMap
	selected *View
}

func newMenuModel(styles Styles, keys KeyMap) menuModel {
	return menuModel{
		cursor: 0,
		items: []menuItem{
			{label: "Search Games", key: "1", view: ViewSearchInput},
			{label: "Hot Games", key: "2", view: ViewHot},
			{label: "User Collection", key: "3", view: ViewCollectionInput},
			{label: "Settings", key: "4", view: ViewSettings},
		},
		styles: styles,
		keys:   keys,
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
		}
	}
	return m, nil
}

func (m menuModel) View(width, height int) string {
	var b strings.Builder

	// Title
	title := m.styles.Title.Render("BGG TUI")
	subtitle := m.styles.Subtitle.Render("BoardGameGeek Terminal Client")

	b.WriteString(title)
	b.WriteString("\n")
	b.WriteString(subtitle)
	b.WriteString("\n\n")

	// Menu items
	for i, item := range m.items {
		cursor := "  "
		style := m.styles.MenuItem
		if i == m.cursor {
			cursor = "> "
			style = m.styles.MenuItemFocus
		}

		line := fmt.Sprintf("%s[%s] %s", cursor, item.key, style.Render(item.label))
		b.WriteString(line)
		b.WriteString("\n")
	}

	b.WriteString("\n")

	// Quit option
	b.WriteString(fmt.Sprintf("  [q] %s\n", m.styles.MenuItem.Render("Quit")))

	// Help
	b.WriteString("\n")
	help := m.styles.Help.Render("j/k: Navigate  Enter: Select  q: Quit")
	b.WriteString(help)

	// Center the content
	content := b.String()
	contentHeight := strings.Count(content, "\n") + 1

	// Vertical padding
	topPadding := (height - contentHeight) / 3
	if topPadding < 0 {
		topPadding = 0
	}

	// Horizontal centering (block as a whole, left-aligned inside)
	lines := strings.Split(content, "\n")

	// Find max width
	maxWidth := 0
	for _, line := range lines {
		if w := lipgloss.Width(line); w > maxWidth {
			maxWidth = w
		}
	}

	// Apply same padding to all lines
	leftPadding := (width - maxWidth) / 2
	if leftPadding < 0 {
		leftPadding = 0
	}

	var centered []string
	for _, line := range lines {
		centered = append(centered, strings.Repeat(" ", leftPadding)+line)
	}

	result := strings.Repeat("\n", topPadding) + strings.Join(centered, "\n")
	return lipgloss.NewStyle().Width(width).Height(height).Render(result)
}
