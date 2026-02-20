package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
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
	errMsg    string
	selected  *int // Selected game ID for detail view
	wantsBack bool
	wantsMenu bool

	filter filterState[bgg.HotGame]

	// Stats fields (fetched via /thing endpoint)
	stats       map[int]bgg.Game // game ID → Game (stats info)
	statsLoaded bool

	img listImageState
}

func (m *hotModel) WantsMenu() bool  { return m.wantsMenu }
func (m *hotModel) WantsBack() bool  { return m.wantsBack }
func (m *hotModel) Selected() *int   { return m.selected }
func (m *hotModel) ClearSignals()    { m.wantsMenu = false; m.wantsBack = false; m.selected = nil }

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
		state:  hotStateLoading,
		config: cfg,
		styles: styles,
		keys:   keys,
		img:    listImageState{enabled: imageEnabled, cache: cache},
		filter: filterState[bgg.HotGame]{
			getName: func(g bgg.HotGame) string { return g.Name },
			getID:   func(g bgg.HotGame) int { return g.ID },
		},
	}
}

func (m hotModel) loadHotGames(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return hotResultMsg{err: fmt.Errorf(errNoToken)}
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
	items := m.filter.displayItems()
	if m.filter.cursor >= 0 && m.filter.cursor < len(items) {
		return items[m.filter.cursor].Thumbnail
	}
	return ""
}

func (m hotModel) maybeLoadThumb() (hotModel, tea.Cmd) {
	cmd := m.img.maybeLoad(m.currentThumbURL())
	return m, cmd
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
				m.filter.items = msg.games
				m.filter.cursor = 0
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
			m.img.handleLoaded(msg)
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

		if m.filter.active {
			result, _, cmd := m.filter.updateFilter(msg, m.keys)
			switch result {
			case filterExited:
				m, thumbCmd := m.maybeLoadThumb()
				return m, thumbCmd
			case filterSelected:
				m.selected = m.filter.selectedID()
				return m, nil
			}
			m, thumbCmd := m.maybeLoadThumb()
			return m, tea.Batch(cmd, thumbCmd)
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				m.filter.moveCursorUp()
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Down):
				m.filter.moveCursorDown()
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Enter):
				m.selected = m.filter.selectedID()
			case key.Matches(msg, m.keys.Filter):
				filterCmd := m.filter.startFilter()
				m, thumbCmd := m.maybeLoadThumb()
				return m, tea.Batch(filterCmd, thumbCmd)
			case key.Matches(msg, m.keys.Refresh):
				m.state = hotStateLoading
				m.filter.items = nil
				m.filter.cursor = 0
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


func (m hotModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case hotStateLoading:
		writeLoadingView(&b, m.styles, "Hot Games", "Loading...")

	case hotStateResults:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		if m.filter.active {
			b.WriteString("  Filter: ")
			b.WriteString(m.filter.input.View())
		}
		b.WriteString("\n")

		displayItems := m.filter.displayItems()

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d trending games  ★Rating ⚖Weight #Rank", min(m.filter.cursor+1, len(displayItems)), len(displayItems))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No games found."))
			b.WriteString("\n")
		} else {
			// Show results with scrolling
			listHeight := height
			if HasBorder(m.config.Interface.BorderStyle) {
				listHeight -= BorderHeightOverhead
			}
			start, end := calcListRange(m.filter.cursor, len(displayItems), listHeight, m.config.Interface.ListDensity)

			// Calculate dynamic name width from ListWidth
			// overhead: prefix(2) + rank("#NNN "=5) + " (" + year(4) + ")" = 14
			hasBorder := HasBorder(m.config.Interface.BorderStyle)
			contentWidth := listContentWidth(m.config.Display.ListWidth, width, hasBorder)
			maxNameW := calcMaxNameWidth(contentWidth, 14)

			// First pass: find max name+year width for stats alignment
			maxNameYearLen := 0
			for i := start; i < end; i++ {
				game := displayItems[i]
				year := game.Year
				if year == "" {
					year = "N/A"
				}
				w := lipgloss.Width(truncateName(game.Name, maxNameW)) + len(year) + 3 // " (" + year + ")"
				if w > maxNameYearLen {
					maxNameYearLen = w
				}
			}

			for i := start; i < end; i++ {
				game := displayItems[i]

				year := game.Year
				if year == "" {
					year = "N/A"
				}

				rankStr := fmt.Sprintf("#%-3d", game.Rank)
				displayName := truncateName(game.Name, maxNameW)
				prefix, name := renderListItem(i, m.filter.cursor, displayName, m.styles, selType, animFrame)
				line := fmt.Sprintf("%s%s %s (%s)", prefix, m.styles.Rank.Render(rankStr), name, year)

				// Append stats if available, aligned to a fixed column
				if s, ok := m.stats[game.ID]; ok {
					var parts []string
					if s.Rating > 0 {
						parts = append(parts, m.styles.Rank.Render(fmt.Sprintf("★%.2f", s.Rating)))
					}
					if s.Weight > 0 {
						parts = append(parts, m.styles.Players.Render(fmt.Sprintf("⚖%.2f", s.Weight)))
					}
					if s.Rank > 0 {
						parts = append(parts, m.styles.Subtitle.Render(fmt.Sprintf("#%d", s.Rank)))
					}
					if len(parts) > 0 {
						nameYearLen := lipgloss.Width(displayName) + len(year) + 3
						padding := maxNameYearLen - nameYearLen + 2
						line += strings.Repeat(" ", padding) + strings.Join(parts, " ")
					}
				}

				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filter.active {
			b.WriteString(m.styles.Help.Render(helpFilterActive))
		} else {
			b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Detail  /: Filter  r: Refresh  ?: Help  Esc: Menu"))
		}

		// Add image panel
		transmit = renderImagePanel(&b, m.img.enabled, m.img.placeholder, m.img.transmit, m.img.loading, m.img.hasError)

	case hotStateError:
		writeErrorView(&b, m.styles, "Hot Games", m.errMsg, "Enter/r: Retry  Esc: Menu")
	}

	content := b.String()
	return transmit + renderView(content, m.styles, width, height, m.config.Interface.BorderStyle)
}
