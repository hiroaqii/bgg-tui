package tui

import (
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

// Model is the main application model.
type Model struct {
	config    *config.Config
	bggClient *bgg.Client
	keys      KeyMap
	styles    Styles

	// Current view
	currentView View

	// Window dimensions
	width  int
	height int

	// Sub-models
	menu       menuModel
	settings   settingsModel
	search     searchModel
	hot        hotModel
	collection collectionModel
	detail     detailModel

	// Navigation history
	previousView View
}

// New creates a new application model.
func New(cfg *config.Config) Model {
	styles := DefaultStyles()
	keys := DefaultKeyMap()

	// Create BGG client if token is available
	var client *bgg.Client
	if cfg.API.Token != "" {
		client, _ = bgg.NewClient(bgg.Config{
			Token: cfg.API.Token,
		})
	}

	return Model{
		config:      cfg,
		bggClient:   client,
		keys:        keys,
		styles:      styles,
		currentView: ViewMenu,
		menu:        newMenuModel(styles, keys),
		settings:    newSettingsModel(cfg, styles, keys),
		search:      newSearchModel(styles, keys),
		hot:         newHotModel(styles, keys),
		collection:  newCollectionModel(cfg, styles, keys),
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
	case ViewSearchInput, ViewSearchResults:
		return m.updateSearch(msg)
	case ViewHot:
		return m.updateHot(msg)
	case ViewCollectionInput, ViewCollectionList:
		return m.updateCollection(msg)
	case ViewDetail:
		return m.updateDetail(msg)
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
		case ViewSearchInput:
			m.currentView = ViewSearchInput
			m.search = newSearchModel(m.styles, m.keys)
			return m, textinput.Blink
		case ViewHot:
			m.currentView = ViewHot
			m.hot = newHotModel(m.styles, m.keys)
			return m, m.hot.loadHotGames(m.bggClient)
		case ViewCollectionInput:
			m.currentView = ViewCollectionInput
			m.collection = newCollectionModel(m.config, m.styles, m.keys)
			return m, textinput.Blink
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

func (m Model) updateSearch(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.search, cmd = m.search.Update(msg, m.bggClient)

	// Update current view based on search state
	switch m.search.state {
	case searchStateInput:
		m.currentView = ViewSearchInput
	case searchStateLoading, searchStateResults, searchStateError:
		m.currentView = ViewSearchResults
	}

	if m.search.wantsBack {
		m.search.wantsBack = false
		m.currentView = ViewMenu
	}

	// Handle detail selection
	if m.search.selected != nil {
		gameID := *m.search.selected
		m.search.selected = nil
		m.previousView = ViewSearchResults
		m.detail = newDetailModel(gameID, m.styles, m.keys)
		m.currentView = ViewDetail
		return m, m.detail.loadGame(m.bggClient)
	}

	return m, cmd
}

func (m Model) updateHot(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.hot, cmd = m.hot.Update(msg, m.bggClient)

	if m.hot.wantsBack {
		m.hot.wantsBack = false
		m.currentView = ViewMenu
	}

	// Handle detail selection
	if m.hot.selected != nil {
		gameID := *m.hot.selected
		m.hot.selected = nil
		m.previousView = ViewHot
		m.detail = newDetailModel(gameID, m.styles, m.keys)
		m.currentView = ViewDetail
		return m, m.detail.loadGame(m.bggClient)
	}

	return m, cmd
}

func (m Model) updateCollection(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.collection, cmd = m.collection.Update(msg, m.bggClient)

	// Update current view based on collection state
	switch m.collection.state {
	case collectionStateInput:
		m.currentView = ViewCollectionInput
	case collectionStateLoading, collectionStateResults, collectionStateError:
		m.currentView = ViewCollectionList
	}

	if m.collection.wantsBack {
		m.collection.wantsBack = false
		m.currentView = ViewMenu
	}

	// Handle detail selection
	if m.collection.selected != nil {
		gameID := *m.collection.selected
		m.collection.selected = nil
		m.previousView = ViewCollectionList
		m.detail = newDetailModel(gameID, m.styles, m.keys)
		m.currentView = ViewDetail
		return m, m.detail.loadGame(m.bggClient)
	}

	return m, cmd
}

func (m Model) updateDetail(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.detail, cmd = m.detail.Update(msg)

	if m.detail.wantsBack {
		m.detail.wantsBack = false
		m.currentView = m.previousView
	}

	// Handle forum navigation (for future Task 14)
	if m.detail.wantsForum {
		m.detail.wantsForum = false
		// TODO: Navigate to forum view
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
	case ViewSearchInput, ViewSearchResults:
		return m.search.View(m.width, m.height)
	case ViewHot:
		return m.hot.View(m.width, m.height)
	case ViewCollectionInput, ViewCollectionList:
		return m.collection.View(m.width, m.height)
	case ViewDetail:
		return m.detail.View(m.width, m.height)
	}
	return ""
}
