package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"
)

type hotState int

const (
	hotStateLoading hotState = iota
	hotStateResults
	hotStateError
)

type hotModel struct {
	state     hotState
	styles    Styles
	keys      KeyMap
	games     []bgg.HotGame
	cursor    int
	errMsg    string
	selected  *int // Selected game ID for detail view
	wantsBack bool
}

// hotResultMsg is sent when hot games are received.
type hotResultMsg struct {
	games []bgg.HotGame
	err   error
}

func newHotModel(styles Styles, keys KeyMap) hotModel {
	return hotModel{
		state:  hotStateLoading,
		styles: styles,
		keys:   keys,
	}
}

func (m hotModel) loadHotGames(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		games, err := client.GetHotGames()
		return hotResultMsg{games: games, err: err}
	}
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
			}
		}
		return m, nil

	case hotStateResults:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.cursor > 0 {
					m.cursor--
				}
			case key.Matches(msg, m.keys.Down):
				if m.cursor < len(m.games)-1 {
					m.cursor++
				}
			case key.Matches(msg, m.keys.Enter):
				if len(m.games) > 0 {
					id := m.games[m.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Refresh):
				m.state = hotStateLoading
				m.games = nil
				m.cursor = 0
				return m, m.loadHotGames(client)
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
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
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil
	}

	return m, nil
}

func (m hotModel) View(width, height int) string {
	var b strings.Builder

	switch m.state {
	case hotStateLoading:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading..."))

	case hotStateResults:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render("Top 50 trending games on BGG"))
		b.WriteString("\n\n")

		if len(m.games) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No games found."))
			b.WriteString("\n")
		} else {
			// Show up to 15 results with scrolling
			start := 0
			visible := 15
			if m.cursor >= visible {
				start = m.cursor - visible + 1
			}
			end := start + visible
			if end > len(m.games) {
				end = len(m.games)
			}

			for i := start; i < end; i++ {
				game := m.games[i]
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
				line := fmt.Sprintf("%s%s %s (%s)", cursor, m.styles.Rank.Render(rankStr), style.Render(game.Name), year)
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Detail  r: Refresh  b: Back"))

	case hotStateError:
		b.WriteString(m.styles.Title.Render("Hot Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter/r: Retry  b: Back"))
	}

	content := b.String()
	return centerContent(content, width, height)
}
