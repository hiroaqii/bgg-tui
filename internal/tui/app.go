package tui

import (
	tea "github.com/charmbracelet/bubbletea"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

// Model is the main application model.
type Model struct {
	config *config.Config
	keys   KeyMap
	styles Styles

	// Current view
	currentView View

	// Window dimensions
	width  int
	height int

	// Sub-models
	menu     menuModel
	settings settingsModel
}

// New creates a new application model.
func New(cfg *config.Config) Model {
	styles := DefaultStyles()
	keys := DefaultKeyMap()

	return Model{
		config:      cfg,
		keys:        keys,
		styles:      styles,
		currentView: ViewMenu,
		menu:        newMenuModel(styles, keys),
		settings:    newSettingsModel(cfg, styles, keys),
	}
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Handle window size for all views
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}

	// Delegate to current view
	switch m.currentView {
	case ViewMenu:
		return m.updateMenu(msg)
	case ViewSettings:
		return m.updateSettings(msg)
	}

	return m, nil
}

func (m Model) updateMenu(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.menu, cmd = m.menu.Update(msg)

	// Check if menu selected something
	if m.menu.selected != nil {
		view := *m.menu.selected
		m.menu.selected = nil

		switch view {
		case ViewSettings:
			m.currentView = ViewSettings
			m.settings = newSettingsModel(m.config, m.styles, m.keys)
		}
	}

	return m, cmd
}

func (m Model) updateSettings(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.settings, cmd = m.settings.Update(msg)

	if m.settings.wantsBack {
		m.settings.wantsBack = false
		m.currentView = ViewMenu
	}

	return m, cmd
}

// View implements tea.Model.
func (m Model) View() string {
	switch m.currentView {
	case ViewMenu:
		return m.menu.View(m.width, m.height)
	case ViewSettings:
		return m.settings.View(m.width, m.height)
	}
	return ""
}
