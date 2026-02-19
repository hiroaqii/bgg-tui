package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

type searchState int

const minSearchLen = 3

const (
	searchStateInput searchState = iota
	searchStateLoading
	searchStateResults
	searchStateError
)

type searchModel struct {
	state    searchState
	config   *config.Config
	styles   Styles
	keys     KeyMap
	input    textinput.Model
	errMsg   string
	selected *int // Selected game ID for detail view

	filter filterState[bgg.GameSearchResult]

	wantsBack bool
	wantsMenu bool

	img        listImageState
	lastGameID int            // last loaded game ID (tracked by ID since search results lack thumb URLs)
	thumbURLs  map[int]string // gameID → thumbnail URL cache
}

func (m *searchModel) WantsMenu() bool  { return m.wantsMenu }
func (m *searchModel) WantsBack() bool  { return m.wantsBack }
func (m *searchModel) Selected() *int   { return m.selected }
func (m *searchModel) ClearSignals()    { m.wantsMenu = false; m.wantsBack = false; m.selected = nil }

// searchResultMsg is sent when search results are received.
type searchResultMsg struct {
	results []bgg.GameSearchResult
	err     error
}

// searchThumbMsg is sent when a search thumbnail has been fetched via GetGame and rendered.
type searchThumbMsg struct {
	gameID         int
	thumbURL       string
	imgTransmit    string
	imgPlaceholder string
	err            error
}

func newSearchModel(cfg *config.Config, styles Styles, keys KeyMap, imageEnabled bool, cache *imageCache) searchModel {
	ti := textinput.New()
	ti.Placeholder = "Enter game name..."
	ti.CharLimit = 100
	ti.Width = 40
	ti.Focus()

	return searchModel{
		state:     searchStateInput,
		config:    cfg,
		styles:    styles,
		keys:      keys,
		input:     ti,
		img:       listImageState{enabled: imageEnabled, cache: cache},
		thumbURLs: make(map[int]string),
		filter: filterState[bgg.GameSearchResult]{
			getName: func(r bgg.GameSearchResult) string { return r.Name },
			getID:   func(r bgg.GameSearchResult) int { return r.ID },
		},
	}
}

func (m searchModel) doSearch(client *bgg.Client, query string) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return searchResultMsg{err: fmt.Errorf(errNoToken)}
		}
		results, err := client.SearchGames(query)
		return searchResultMsg{results: results, err: err}
	}
}

func (m searchModel) currentGameID() int {
	items := m.filter.displayItems()
	if m.filter.cursor >= 0 && m.filter.cursor < len(items) {
		return items[m.filter.cursor].ID
	}
	return 0
}

func (m searchModel) maybeLoadThumb(client *bgg.Client) (searchModel, tea.Cmd) {
	if !m.img.enabled || m.img.cache == nil {
		return m, nil
	}
	gameID := m.currentGameID()
	if gameID == 0 || gameID == m.lastGameID {
		return m, nil
	}
	m.lastGameID = gameID
	m.img.loading = true
	m.img.hasError = false
	m.img.transmit = ""
	m.img.placeholder = ""

	// If we already have the thumb URL cached, use the standard loadListImage path
	if url, ok := m.thumbURLs[gameID]; ok {
		return m, loadListImage(m.img.cache, url)
	}

	// Otherwise fetch the thumb URL via GetGame
	return m, loadSearchThumb(client, m.img.cache, gameID)
}

// loadSearchThumb fetches thumbnail URL via GetGame, downloads and renders the image.
func loadSearchThumb(client *bgg.Client, cache *imageCache, gameID int) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return searchThumbMsg{gameID: gameID, err: fmt.Errorf("no client")}
		}
		game, err := client.GetGame(gameID)
		if err != nil {
			return searchThumbMsg{gameID: gameID, err: err}
		}
		if game.Thumbnail == "" {
			return searchThumbMsg{gameID: gameID, err: fmt.Errorf("no thumbnail")}
		}

		ri, err := renderKittyImage(cache, game.Thumbnail, listImageID, listImageCols, listImageRows, true)
		if err != nil {
			return searchThumbMsg{gameID: gameID, thumbURL: game.Thumbnail, err: err}
		}
		return searchThumbMsg{
			gameID:         gameID,
			thumbURL:       game.Thumbnail,
			imgTransmit:    ri.transmit,
			imgPlaceholder: ri.placeholder,
		}
	}
}

func (m searchModel) Update(msg tea.Msg, client *bgg.Client) (searchModel, tea.Cmd) {
	var cmd tea.Cmd

	switch m.state {
	case searchStateInput:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				query := strings.TrimSpace(m.input.Value())
				if len(query) >= minSearchLen {
					m.state = searchStateLoading
					return m, m.doSearch(client, query)
				}
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
				return m, nil
			}
		}
		m.input, cmd = m.input.Update(msg)
		return m, cmd

	case searchStateLoading:
		switch msg := msg.(type) {
		case searchResultMsg:
			if msg.err != nil {
				m.state = searchStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = searchStateResults
				m.filter.items = msg.results
				m.filter.cursor = 0
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			}
		}
		return m, nil

	case searchStateResults:
		// Handle search thumbnail loaded (from GetGame fetch)
		if msg, ok := msg.(searchThumbMsg); ok {
			if msg.gameID == m.lastGameID {
				m.img.loading = false
				if msg.err != nil {
					m.img.hasError = true
				} else {
					m.thumbURLs[msg.gameID] = msg.thumbURL
					m.img.transmit = msg.imgTransmit
					m.img.placeholder = msg.imgPlaceholder
				}
			}
			return m, nil
		}

		// Handle list image loaded (from cached URL path)
		if msg, ok := msg.(listImageMsg); ok {
			if m.thumbURLs[m.lastGameID] == msg.url {
				m.img.loading = false
				if msg.err != nil {
					m.img.hasError = true
				} else {
					m.img.transmit = msg.imgTransmit
					m.img.placeholder = msg.imgPlaceholder
				}
			}
			return m, nil
		}

		if m.filter.active {
			result, _, cmd := m.filter.updateFilter(msg, m.keys)
			switch result {
			case filterExited:
				m, thumbCmd := m.maybeLoadThumb(client)
				return m, thumbCmd
			case filterSelected:
				m.selected = m.filter.selectedID()
				return m, nil
			}
			m, thumbCmd := m.maybeLoadThumb(client)
			return m, tea.Batch(cmd, thumbCmd)
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.filter.cursor > 0 {
					m.filter.cursor--
				}
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			case key.Matches(msg, m.keys.Down):
				if m.filter.cursor < len(m.filter.items)-1 {
					m.filter.cursor++
				}
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			case key.Matches(msg, m.keys.Enter):
				if len(m.filter.items) > 0 {
					id := m.filter.items[m.filter.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Filter):
				filterCmd := m.filter.startFilter()
				m, thumbCmd := m.maybeLoadThumb(client)
				return m, tea.Batch(filterCmd, thumbCmd)
			case key.Matches(msg, m.keys.Search):
				// New search
				m.state = searchStateInput
				m.input.SetValue("")
				m.input.Focus()
				m.filter.items = nil
				m.filter.cursor = 0
				return m, textinput.Blink
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case searchStateError:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter), key.Matches(msg, m.keys.Search):
				// Retry search
				m.state = searchStateInput
				m.input.Focus()
				m.errMsg = ""
				return m, textinput.Blink
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil
	}

	return m, nil
}

func (m searchModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case searchStateInput:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString("Enter game name:\n")
		b.WriteString(m.input.View())
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Search (3+ chars)  Esc: Menu"))

	case searchStateLoading:
		writeLoadingView(&b, m.styles, "Search Games", "Searching...")

	case searchStateResults:
		b.WriteString(m.styles.Title.Render("Search Results"))
		if m.filter.active {
			b.WriteString("  Filter: ")
			b.WriteString(m.filter.input.View())
		}
		b.WriteString("\n")

		displayItems := m.filter.displayItems()

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d games found", min(m.filter.cursor+1, len(displayItems)), len(displayItems))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No results found."))
			b.WriteString("\n")
		} else {
			// Show results with scrolling
			listHeight := height
			if HasBorder(m.config.Interface.BorderStyle) {
				listHeight -= BorderHeightOverhead
			}
			start, end := calcListRange(m.filter.cursor, len(displayItems), listHeight, m.config.Interface.ListDensity)

			for i := start; i < end; i++ {
				result := displayItems[i]

				year := result.Year
				if year == "" {
					year = "N/A"
				}

				typeIndicator := ""
				if result.Type == "boardgameexpansion" {
					typeIndicator = " [Expansion]"
				}

				prefix, name := renderListItem(i, m.filter.cursor, result.Name, m.styles, selType, animFrame)
				line := fmt.Sprintf("%s%s (%s)%s", prefix, name, year, typeIndicator)
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filter.active {
			b.WriteString(m.styles.Help.Render(helpFilterActive))
		} else {
			b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Detail  /: Filter  s: New Search  ?: Help  b: Back  Esc: Menu"))
		}

		// Add image panel
		transmit = renderImagePanel(&b, m.img.enabled, m.img.placeholder, m.img.transmit, m.img.loading, m.img.hasError)

	case searchStateError:
		writeErrorView(&b, m.styles, "Search Games", m.errMsg, "Enter: Retry  b: Back  Esc: Menu")
	}

	content := b.String()
	borderStyle := m.config.Interface.BorderStyle
	return transmit + renderView(content, m.styles, width, height, borderStyle)
}
