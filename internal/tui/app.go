package tui

import (
	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
)

// Model is the main application model.
type Model struct {
	keys   KeyMap
	styles Styles

	// Window dimensions
	width  int
	height int

	// Menu
	menu menuModel
}

// New creates a new application model.
func New() Model {
	styles := DefaultStyles()
	keys := DefaultKeyMap()

	return Model{
		keys:   keys,
		styles: styles,
		menu:   newMenuModel(styles, keys),
	}
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		if key.Matches(msg, m.keys.Quit) {
			return m, tea.Quit
		}
	}

	// Delegate to menu
	var cmd tea.Cmd
	m.menu, cmd = m.menu.Update(msg)
	return m, cmd
}

// View implements tea.Model.
func (m Model) View() string {
	return m.menu.View(m.width, m.height)
}
