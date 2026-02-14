package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

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
	setupToken setupTokenModel
	menu       menuModel
	settings   settingsModel
	search     searchModel
	hot        hotModel
	collection collectionModel
	detail     detailModel
	forum      forumModel
	thread     threadModel

	// Navigation history
	previousView View

	// Image support
	imageEnabled     bool
	imageCache       *imageCache
	needsClearImages bool

	// Help overlay
	showHelp bool
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

	// Initialize image support
	var imgEnabled bool
	var imgCache *imageCache
	if cfg.Display.ShowImages {
		protocol := detectProtocol(cfg.Display.ImageProtocol)
		if protocol == ProtocolKitty {
			if c, err := newImageCache(); err == nil {
				imgEnabled = true
				imgCache = c
			}
		}
	}

	startView := ViewMenu
	if !cfg.HasToken() {
		startView = ViewSetupToken
	}

	return Model{
		config:       cfg,
		bggClient:    client,
		keys:         keys,
		styles:       styles,
		currentView:  startView,
		setupToken:   newSetupTokenModel(cfg, styles, keys),
		menu:         newMenuModel(styles, keys, cfg.HasToken()),
		settings:     newSettingsModel(cfg, styles, keys),
		search:       newSearchModel(styles, keys),
		hot:          newHotModel(styles, keys, imgEnabled, imgCache),
		collection:   newCollectionModel(cfg, styles, keys, imgEnabled, imgCache),
		imageEnabled: imgEnabled,
		imageCache:   imgCache,
	}
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	if m.currentView == ViewSetupToken {
		return textinput.Blink
	}
	return nil
}

// Update implements tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.needsClearImages {
		m.needsClearImages = false
	}

	// Handle window size for all views
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}

	// Help overlay handling
	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		if m.showHelp {
			// Any key closes the help overlay
			m.showHelp = false
			return m, nil
		}
		if key.Matches(keyMsg, m.keys.Help) {
			m.showHelp = true
			return m, nil
		}
	}

	// Delegate to current view
	switch m.currentView {
	case ViewSetupToken:
		return m.updateSetupToken(msg)
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
	case ViewForumList, ViewThreadList:
		return m.updateForum(msg)
	case ViewThreadView:
		return m.updateThread(msg)
	}

	return m, nil
}

func (m Model) updateSetupToken(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.setupToken, cmd = m.setupToken.Update(msg)

	if m.setupToken.done {
		m.setupToken.done = false
		// Create BGG client with new token
		m.bggClient, _ = bgg.NewClient(bgg.Config{
			Token: m.config.API.Token,
		})
		m.menu = newMenuModel(m.styles, m.keys, true)
		m.currentView = ViewMenu
	}

	return m, cmd
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
			m.hot = newHotModel(m.styles, m.keys, m.imageEnabled, m.imageCache)
			return m, m.hot.loadHotGames(m.bggClient)
		case ViewCollectionInput:
			m.currentView = ViewCollectionInput
			m.collection = newCollectionModel(m.config, m.styles, m.keys, m.imageEnabled, m.imageCache)
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
		m.detail = newDetailModel(gameID, m.styles, m.keys, m.imageEnabled, m.imageCache)
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
		if m.imageEnabled {
			m.needsClearImages = true
		}
	}

	// Handle detail selection
	if m.hot.selected != nil {
		gameID := *m.hot.selected
		m.hot.selected = nil
		m.previousView = ViewHot
		m.detail = newDetailModel(gameID, m.styles, m.keys, m.imageEnabled, m.imageCache)
		m.currentView = ViewDetail
		if m.imageEnabled {
			m.needsClearImages = true
		}
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
		if m.imageEnabled {
			m.needsClearImages = true
		}
	}

	// Handle detail selection
	if m.collection.selected != nil {
		gameID := *m.collection.selected
		m.collection.selected = nil
		m.previousView = ViewCollectionList
		m.detail = newDetailModel(gameID, m.styles, m.keys, m.imageEnabled, m.imageCache)
		m.currentView = ViewDetail
		if m.imageEnabled {
			m.needsClearImages = true
		}
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
		if m.imageEnabled {
			m.needsClearImages = true
		}
	}

	// Handle forum navigation
	if m.detail.wantsForum {
		m.detail.wantsForum = false
		if m.imageEnabled {
			m.needsClearImages = true
		}
		gameName := ""
		if m.detail.game != nil {
			gameName = m.detail.game.Name
		}
		m.forum = newForumModel(m.detail.gameID, gameName, m.styles, m.keys)
		m.currentView = ViewForumList
		return m, m.forum.loadForums(m.bggClient)
	}

	return m, cmd
}

func (m Model) updateForum(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.forum, cmd = m.forum.Update(msg, m.bggClient)

	// Update current view based on forum state
	switch m.forum.state {
	case forumStateForumList, forumStateLoadingForums:
		m.currentView = ViewForumList
	case forumStateThreadList, forumStateLoadingThreads:
		m.currentView = ViewThreadList
	}

	if m.forum.wantsBack {
		m.forum.wantsBack = false
		m.currentView = ViewDetail
	}

	// Handle thread selection
	if m.forum.wantsThread != nil {
		threadID := *m.forum.wantsThread
		m.forum.wantsThread = nil
		m.thread = newThreadModel(threadID, m.styles, m.keys)
		m.currentView = ViewThreadView
		return m, m.thread.loadThread(m.bggClient)
	}

	return m, cmd
}

func (m Model) updateThread(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	m.thread, cmd = m.thread.Update(msg)

	if m.thread.wantsBack {
		m.thread.wantsBack = false
		m.currentView = ViewThreadList
	}

	return m, cmd
}

// View implements tea.Model.
func (m Model) View() string {
	if m.showHelp {
		return m.renderHelpOverlay()
	}

	var prefix string
	if m.needsClearImages {
		prefix = kittyDeleteSeq
	}

	switch m.currentView {
	case ViewSetupToken:
		return prefix + m.setupToken.View(m.width, m.height)
	case ViewMenu:
		return prefix + m.menu.View(m.width, m.height)
	case ViewSettings:
		return prefix + m.settings.View(m.width, m.height)
	case ViewSearchInput, ViewSearchResults:
		return prefix + m.search.View(m.width, m.height)
	case ViewHot:
		return prefix + m.hot.View(m.width, m.height)
	case ViewCollectionInput, ViewCollectionList:
		return prefix + m.collection.View(m.width, m.height)
	case ViewDetail:
		return m.detail.View(m.width, m.height)
	case ViewForumList, ViewThreadList:
		return prefix + m.forum.View(m.width, m.height)
	case ViewThreadView:
		return prefix + m.thread.View(m.width, m.height)
	}
	return ""
}

// renderHelpOverlay renders a centered keybindings overlay.
func (m Model) renderHelpOverlay() string {
	groups := m.keys.FullHelp()

	// Build two-column rows: groups[0]+groups[1], groups[2]+groups[3]
	var rows []string
	for i := 0; i < len(groups); i += 2 {
		left := groups[i]
		var right []key.Binding
		if i+1 < len(groups) {
			right = groups[i+1]
		}

		maxLen := len(left)
		if len(right) > maxLen {
			maxLen = len(right)
		}

		for j := 0; j < maxLen; j++ {
			var lKey, lDesc, rKey, rDesc string
			if j < len(left) {
				lKey = left[j].Help().Key
				lDesc = left[j].Help().Desc
			}
			if j < len(right) {
				rKey = right[j].Help().Key
				rDesc = right[j].Help().Desc
			}
			row := fmt.Sprintf("  %-10s %-14s %-10s %s", lKey, lDesc, rKey, rDesc)
			rows = append(rows, row)
		}
		rows = append(rows, "")
	}

	title := lipgloss.NewStyle().Bold(true).Foreground(ColorPrimary).Render("Keybindings")
	footer := lipgloss.NewStyle().Foreground(ColorMuted).Render("Press any key to close")

	var b strings.Builder
	b.WriteString(lipgloss.PlaceHorizontal(40, lipgloss.Center, title))
	b.WriteString("\n")
	for _, row := range rows {
		b.WriteString(row)
		b.WriteString("\n")
	}
	b.WriteString(lipgloss.PlaceHorizontal(40, lipgloss.Center, footer))

	content := m.styles.Border.Render(b.String())
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, content)
}
