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

type hotState int

const (
	hotStateLoading hotState = iota
	hotStateResults
	hotStateError
)

type hotModel struct {
	state     hotState
	config    *config.Config
	styles    Styles
	keys      KeyMap
	games     []bgg.HotGame
	cursor    int
	errMsg    string
	selected  *int // Selected game ID for detail view
	wantsBack bool
	wantsMenu bool

	filtering     bool
	filterInput   textinput.Model
	filteredGames []bgg.HotGame

	// Image fields
	imageEnabled   bool
	cache          *imageCache
	imgTransmit    string
	imgPlaceholder string
	imgLoading     bool
	imgError       bool
	lastThumbURL   string
}

// hotResultMsg is sent when hot games are received.
type hotResultMsg struct {
	games []bgg.HotGame
	err   error
}

func newHotModel(cfg *config.Config, styles Styles, keys KeyMap, imageEnabled bool, cache *imageCache) hotModel {
	return hotModel{
		state:        hotStateLoading,
		config:       cfg,
		styles:       styles,
		keys:         keys,
		imageEnabled: imageEnabled,
		cache:        cache,
	}
}

func (m hotModel) loadHotGames(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return hotResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		games, err := client.GetHotGames()
		return hotResultMsg{games: games, err: err}
	}
}

func (m hotModel) currentThumbURL() string {
	items := m.games
	if m.filtering || m.filteredGames != nil {
		items = m.filteredGames
	}
	if m.cursor >= 0 && m.cursor < len(items) {
		return items[m.cursor].Thumbnail
	}
	return ""
}

func (m hotModel) maybeLoadThumb() (hotModel, tea.Cmd) {
	if !m.imageEnabled || m.cache == nil {
		return m, nil
	}
	url := m.currentThumbURL()
	if url == "" || url == m.lastThumbURL {
		return m, nil
	}
	m.lastThumbURL = url
	m.imgLoading = true
	m.imgError = false
	m.imgTransmit = ""
	m.imgPlaceholder = ""
	return m, loadListImage(m.cache, url)
}

func (m hotModel) Update(msg tea.Msg, client *bgg.Client) (hotModel, tea.Cmd) {
	switch m.state {
	case hotStateLoading:
		switch msg := msg.(type) {
		case hotResultMsg:
			if msg.err != nil {
				m.state = hotStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = hotStateResults
				m.games = msg.games
				m.cursor = 0
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			}
		}
		return m, nil

	case hotStateResults:
		// Handle image loaded
		if msg, ok := msg.(listImageMsg); ok {
			if msg.url == m.lastThumbURL {
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
					m.filteredGames = nil
					m.filterInput.SetValue("")
					m.cursor = 0
					m, cmd := m.maybeLoadThumb()
					return m, cmd
				case key.Matches(msg, m.keys.Enter):
					if len(m.filteredGames) > 0 {
						id := m.filteredGames[m.cursor].ID
						m.selected = &id
					}
					return m, nil
				case msg.String() == "up":
					if m.cursor > 0 {
						m.cursor--
					}
					m, cmd := m.maybeLoadThumb()
					return m, cmd
				case msg.String() == "down":
					if m.cursor < len(m.filteredGames)-1 {
						m.cursor++
					}
					m, cmd := m.maybeLoadThumb()
					return m, cmd
				}
			}
			var cmd tea.Cmd
			m.filterInput, cmd = m.filterInput.Update(msg)
			query := strings.ToLower(m.filterInput.Value())
			m.filteredGames = nil
			for _, g := range m.games {
				if strings.Contains(strings.ToLower(g.Name), query) {
					m.filteredGames = append(m.filteredGames, g)
				}
			}
			if m.cursor >= len(m.filteredGames) {
				m.cursor = max(0, len(m.filteredGames)-1)
			}
			m2, cmd2 := m.maybeLoadThumb()
			return m2, tea.Batch(cmd, cmd2)
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.cursor > 0 {
					m.cursor--
				}
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Down):
				if m.cursor < len(m.games)-1 {
					m.cursor++
				}
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Enter):
				if len(m.games) > 0 {
					id := m.games[m.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Filter):
				m.filtering = true
				m.filterInput = newFilterInput()
				m.filterInput.Focus()
				m.filteredGames = make([]bgg.HotGame, len(m.games))
				copy(m.filteredGames, m.games)
				m.cursor = 0
				m, cmd := m.maybeLoadThumb()
				return m, tea.Batch(textinput.Blink, cmd)
			case key.Matches(msg, m.keys.Refresh):
				m.state = hotStateLoading
				m.games = nil
				m.cursor = 0
				return m, m.loadHotGames(client)
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case hotStateError:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter), key.Matches(msg, m.keys.Refresh):
				m.state = hotStateLoading
				m.errMsg = ""
				return m, m.loadHotGames(client)
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

func (m hotModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case hotStateLoading:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading..."))

	case hotStateResults:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		if m.filtering {
			b.WriteString("  Filter: ")
			b.WriteString(m.filterInput.View())
		}
		b.WriteString("\n")

		displayItems := m.games
		if m.filtering || m.filteredGames != nil {
			displayItems = m.filteredGames
		}

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d trending games", len(displayItems), len(m.games))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No games found."))
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
				game := displayItems[i]
				cursor := "  "
				style := m.styles.ListItem
				if i == m.cursor {
					cursor = "> "
					style = m.styles.ListItemFocus
				}

				year := game.Year
				if year == "" {
					year = "N/A"
				}

				rankStr := fmt.Sprintf("#%-3d", game.Rank)
				name := style.Render(game.Name)
				if i == m.cursor && selType != "" && selType != "none" {
					name = renderSelectionAnim(game.Name, selType, animFrame)
				}
				line := fmt.Sprintf("%s%s %s (%s)", cursor, m.styles.Rank.Render(rankStr), name, year)
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filtering {
			b.WriteString(m.styles.Help.Render("↑/↓: Navigate  Enter: Detail  Esc: Clear filter"))
		} else {
			b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Detail  /: Filter  r: Refresh  ?: Help  Esc: Menu"))
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

	case hotStateError:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter/r: Retry  Esc: Menu"))
	}

	content := b.String()
	return transmit + centerContent(content, width, height)
}
