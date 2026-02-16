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

	// Stats fields (fetched via /thing endpoint)
	stats       map[int]bgg.Game // game ID → Game (stats info)
	statsLoaded bool

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

// hotStatsMsg is sent when game stats are received from /thing endpoint.
type hotStatsMsg struct {
	games []bgg.Game
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

func loadHotStats(client *bgg.Client, ids []int) tea.Cmd {
	return func() tea.Msg {
		var allGames []bgg.Game
		// Split into batches of 20 (API limit)
		for i := 0; i < len(ids); i += 20 {
			end := i + 20
			if end > len(ids) {
				end = len(ids)
			}
			games, err := client.GetGames(ids[i:end])
			if err != nil {
				return hotStatsMsg{err: err}
			}
			allGames = append(allGames, games...)
		}
		return hotStatsMsg{games: allGames}
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
				m.stats = nil
				m.statsLoaded = false
				m, thumbCmd := m.maybeLoadThumb()
				// Collect game IDs for stats fetch
				ids := make([]int, len(msg.games))
				for i, g := range msg.games {
					ids[i] = g.ID
				}
				statsCmd := loadHotStats(client, ids)
				return m, tea.Batch(thumbCmd, statsCmd)
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

		// Handle stats loaded
		if msg, ok := msg.(hotStatsMsg); ok {
			if msg.err == nil {
				m.stats = make(map[int]bgg.Game, len(msg.games))
				for _, g := range msg.games {
					m.stats[g.ID] = g
				}
			}
			m.statsLoaded = true
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
				m.stats = nil
				m.statsLoaded = false
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

const maxNameLen = 45

func truncateName(s string, maxWidth int) string {
	if lipgloss.Width(s) <= maxWidth {
		return s
	}
	runes := []rune(s)
	for i := len(runes) - 1; i >= 0; i-- {
		if lipgloss.Width(string(runes[:i])+"...") <= maxWidth {
			return string(runes[:i]) + "..."
		}
	}
	return "..."
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
			visible := calcListVisible(height, m.config.Interface.ListDensity)
			if m.cursor >= visible {
				start = m.cursor - visible + 1
			}
			end := start + visible
			if end > len(displayItems) {
				end = len(displayItems)
			}

			// First pass: find max name+year width for stats alignment
			maxNameYearLen := 0
			for i := start; i < end; i++ {
				game := displayItems[i]
				year := game.Year
				if year == "" {
					year = "N/A"
				}
				w := lipgloss.Width(truncateName(game.Name, maxNameLen)) + len(year) + 3 // " (" + year + ")"
				if w > maxNameYearLen {
					maxNameYearLen = w
				}
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
				displayName := truncateName(game.Name, maxNameLen)
				name := style.Render(displayName)
				if i == m.cursor && selType != "" && selType != "none" {
					name = renderSelectionAnim(displayName, selType, animFrame)
				}
				line := fmt.Sprintf("%s%s %s (%s)", cursor, m.styles.Rank.Render(rankStr), name, year)

				// Append stats if available, aligned to a fixed column
				if s, ok := m.stats[game.ID]; ok {
					var parts []string
					if s.Rating > 0 {
						parts = append(parts, fmt.Sprintf("★%.2f", s.Rating))
					}
					if s.Weight > 0 {
						parts = append(parts, fmt.Sprintf("W%.2f", s.Weight))
					}
					if s.Rank > 0 {
						parts = append(parts, fmt.Sprintf("#%d", s.Rank))
					} else {
						parts = append(parts, "-")
					}
					if len(parts) > 0 {
						nameYearLen := lipgloss.Width(displayName) + len(year) + 3
						padding := maxNameYearLen - nameYearLen + 2
						line += strings.Repeat(" ", padding) + m.styles.Subtitle.Render(strings.Join(parts, " "))
					}
				}

				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filtering {
			b.WriteString(m.styles.Help.Render("↑/↓: Navigate  Enter: Detail  Esc: Clear filter"))
		} else {
			b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Detail  /: Filter  r: Refresh  ?: Help  Esc: Menu"))
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
