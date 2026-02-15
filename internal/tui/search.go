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

type searchState int

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
	results  []bgg.GameSearchResult
	cursor   int
	errMsg   string
	selected *int // Selected game ID for detail view

	filtering       bool
	filterInput     textinput.Model
	filteredResults []bgg.GameSearchResult

	wantsBack bool
	wantsMenu bool

	// Image fields
	imageEnabled   bool
	cache          *imageCache
	imgTransmit    string
	imgPlaceholder string
	imgLoading     bool
	imgError       bool
	lastGameID     int            // last loaded game ID (tracked by ID since search results lack thumb URLs)
	thumbURLs      map[int]string // gameID → thumbnail URL cache
}

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
		state:        searchStateInput,
		config:       cfg,
		styles:       styles,
		keys:         keys,
		input:        ti,
		imageEnabled: imageEnabled,
		cache:        cache,
		thumbURLs:    make(map[int]string),
	}
}

func (m searchModel) doSearch(client *bgg.Client, query string) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return searchResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		results, err := client.SearchGames(query)
		return searchResultMsg{results: results, err: err}
	}
}

func (m searchModel) currentGameID() int {
	items := m.results
	if m.filtering || m.filteredResults != nil {
		items = m.filteredResults
	}
	if m.cursor >= 0 && m.cursor < len(items) {
		return items[m.cursor].ID
	}
	return 0
}

func (m searchModel) maybeLoadThumb(client *bgg.Client) (searchModel, tea.Cmd) {
	if !m.imageEnabled || m.cache == nil {
		return m, nil
	}
	gameID := m.currentGameID()
	if gameID == 0 || gameID == m.lastGameID {
		return m, nil
	}
	m.lastGameID = gameID
	m.imgLoading = true
	m.imgError = false
	m.imgTransmit = ""
	m.imgPlaceholder = ""

	// If we already have the thumb URL cached, use the standard loadListImage path
	if url, ok := m.thumbURLs[gameID]; ok {
		return m, loadListImage(m.cache, url)
	}

	// Otherwise fetch the thumb URL via GetGame
	return m, loadSearchThumb(client, m.cache, gameID)
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

		path, err := cache.Download(game.Thumbnail)
		if err != nil {
			return searchThumbMsg{gameID: gameID, thumbURL: game.Thumbnail, err: err}
		}

		cellW, cellH := termCellSize()
		pixW := listImageCols * cellW
		pixH := listImageRows * cellH

		img, err := loadAndResize(path, pixW, pixH)
		if err != nil {
			return searchThumbMsg{gameID: gameID, thumbURL: game.Thumbnail, err: err}
		}

		bounds := img.Bounds()
		actualCols := (bounds.Dx() + cellW - 1) / cellW
		actualRows := (bounds.Dy() + cellH - 1) / cellH
		if actualCols < 1 {
			actualCols = 1
		}
		if actualRows < 1 {
			actualRows = 1
		}

		transmit, err := kittyTransmitString(img, listImageID)
		if err != nil {
			return searchThumbMsg{gameID: gameID, thumbURL: game.Thumbnail, err: err}
		}

		placeholder := kittyPlaceholder(listImageID, actualRows, actualCols)
		placeholder = padPlaceholder(placeholder, listImageRows, listImageCols)
		return searchThumbMsg{
			gameID:         gameID,
			thumbURL:       game.Thumbnail,
			imgTransmit:    transmit,
			imgPlaceholder: placeholder,
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
				if query != "" {
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
				m.results = msg.results
				m.cursor = 0
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			}
		}
		return m, nil

	case searchStateResults:
		// Handle search thumbnail loaded (from GetGame fetch)
		if msg, ok := msg.(searchThumbMsg); ok {
			if msg.gameID == m.lastGameID {
				m.imgLoading = false
				if msg.err != nil {
					m.imgError = true
				} else {
					m.thumbURLs[msg.gameID] = msg.thumbURL
					m.imgTransmit = msg.imgTransmit
					m.imgPlaceholder = msg.imgPlaceholder
				}
			}
			return m, nil
		}

		// Handle list image loaded (from cached URL path)
		if msg, ok := msg.(listImageMsg); ok {
			if m.thumbURLs[m.lastGameID] == msg.url {
				m.imgLoading = false
				if msg.err != nil {
					m.imgError = true
				} else {
					m.imgTransmit = msg.imgTransmit
					m.imgPlaceholder = msg.imgPlaceholder
				}
			}
			return m, nil
		}

		if m.filtering {
			switch msg := msg.(type) {
			case tea.KeyMsg:
				switch {
				case key.Matches(msg, m.keys.Escape):
					m.filtering = false
					m.filteredResults = nil
					m.filterInput.SetValue("")
					m.cursor = 0
					m, cmd := m.maybeLoadThumb(client)
					return m, cmd
				case key.Matches(msg, m.keys.Enter):
					if len(m.filteredResults) > 0 {
						id := m.filteredResults[m.cursor].ID
						m.selected = &id
					}
					return m, nil
				case msg.String() == "up":
					if m.cursor > 0 {
						m.cursor--
					}
					m, cmd := m.maybeLoadThumb(client)
					return m, cmd
				case msg.String() == "down":
					if m.cursor < len(m.filteredResults)-1 {
						m.cursor++
					}
					m, cmd := m.maybeLoadThumb(client)
					return m, cmd
				}
			}
			var cmd tea.Cmd
			m.filterInput, cmd = m.filterInput.Update(msg)
			// Recompute filtered results
			query := strings.ToLower(m.filterInput.Value())
			m.filteredResults = nil
			for _, r := range m.results {
				if strings.Contains(strings.ToLower(r.Name), query) {
					m.filteredResults = append(m.filteredResults, r)
				}
			}
			if m.cursor >= len(m.filteredResults) {
				m.cursor = max(0, len(m.filteredResults)-1)
			}
			m2, cmd2 := m.maybeLoadThumb(client)
			return m2, tea.Batch(cmd, cmd2)
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.cursor > 0 {
					m.cursor--
				}
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			case key.Matches(msg, m.keys.Down):
				if m.cursor < len(m.results)-1 {
					m.cursor++
				}
				m, cmd := m.maybeLoadThumb(client)
				return m, cmd
			case key.Matches(msg, m.keys.Enter):
				if len(m.results) > 0 {
					id := m.results[m.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Filter):
				m.filtering = true
				m.filterInput = newFilterInput()
				m.filterInput.Focus()
				m.filteredResults = make([]bgg.GameSearchResult, len(m.results))
				copy(m.filteredResults, m.results)
				m.cursor = 0
				m, cmd := m.maybeLoadThumb(client)
				return m, tea.Batch(textinput.Blink, cmd)
			case key.Matches(msg, m.keys.Search):
				// New search
				m.state = searchStateInput
				m.input.SetValue("")
				m.input.Focus()
				m.results = nil
				m.cursor = 0
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
		b.WriteString(m.styles.Help.Render("Enter: Search  Esc: Menu"))

	case searchStateLoading:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Searching..."))

	case searchStateResults:
		b.WriteString(m.styles.Title.Render("Search Results"))
		if m.filtering {
			b.WriteString("  Filter: ")
			b.WriteString(m.filterInput.View())
		}
		b.WriteString("\n")

		displayItems := m.results
		if m.filtering || m.filteredResults != nil {
			displayItems = m.filteredResults
		}

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d games found", len(displayItems), len(m.results))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No results found."))
			b.WriteString("\n")
		} else {
			// Show results with scrolling
			start := 0
			visible := m.config.Display.ListPageSize
			if m.cursor >= visible {
				start = m.cursor - visible + 1
			}
			end := start + visible
			if end > len(displayItems) {
				end = len(displayItems)
			}

			for i := start; i < end; i++ {
				result := displayItems[i]
				cursor := "  "
				style := m.styles.ListItem
				if i == m.cursor {
					cursor = "> "
					style = m.styles.ListItemFocus
				}

				name := result.Name
				year := result.Year
				if year == "" {
					year = "N/A"
				}

				typeIndicator := ""
				if result.Type == "boardgameexpansion" {
					typeIndicator = " [Expansion]"
				}

				if i == m.cursor && selType != "" && selType != "none" {
					name = renderSelectionAnim(name, selType, animFrame)
				} else {
					name = style.Render(name)
				}
				line := fmt.Sprintf("%s%s (%s)%s", cursor, name, year, typeIndicator)
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filtering {
			b.WriteString(m.styles.Help.Render("↑/↓: Navigate  Enter: Detail  Esc: Clear filter"))
		} else {
			b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Detail  /: Filter  s: New Search  ?: Help  b: Back  Esc: Menu"))
		}

		// Add image panel
		if m.imageEnabled && m.imgPlaceholder != "" {
			transmit = m.imgTransmit
			listContent := b.String()
			imgPanel := "\n" + m.imgPlaceholder + "\n"
			b.Reset()
			b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, listContent, "  ", imgPanel))
		} else if m.imageEnabled && m.imgLoading {
			listContent := b.String()
			imgPanel := "\n" + fixedSizeLoadingPanel(listImageCols, listImageRows) + "\n"
			b.Reset()
			b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, listContent, "  ", imgPanel))
		} else if m.imageEnabled && m.imgError {
			listContent := b.String()
			imgPanel := "\n" + fixedSizeNoImagePanel(listImageCols, listImageRows) + "\n"
			b.Reset()
			b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, listContent, "  ", imgPanel))
		}

	case searchStateError:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Retry  b: Back  Esc: Menu"))
	}

	content := b.String()
	return transmit + centerContent(content, width, height)
}
