package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"
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
	styles   Styles
	keys     KeyMap
	input    textinput.Model
	results  []bgg.GameSearchResult
	cursor   int
	errMsg   string
	selected *int // Selected game ID for detail view

	wantsBack bool
}

// searchResultMsg is sent when search results are received.
type searchResultMsg struct {
	results []bgg.GameSearchResult
	err     error
}

func newSearchModel(styles Styles, keys KeyMap) searchModel {
	ti := textinput.New()
	ti.Placeholder = "Enter game name..."
	ti.CharLimit = 100
	ti.Width = 40
	ti.Focus()

	return searchModel{
		state:  searchStateInput,
		styles: styles,
		keys:   keys,
		input:  ti,
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
				m.wantsBack = true
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
			}
		}
		return m, nil

	case searchStateResults:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.cursor > 0 {
					m.cursor--
				}
			case key.Matches(msg, m.keys.Down):
				if m.cursor < len(m.results)-1 {
					m.cursor++
				}
			case key.Matches(msg, m.keys.Enter):
				if len(m.results) > 0 {
					id := m.results[m.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Search):
				// New search
				m.state = searchStateInput
				m.input.SetValue("")
				m.input.Focus()
				m.results = nil
				m.cursor = 0
				return m, textinput.Blink
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
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
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil
	}

	return m, nil
}

func (m searchModel) View(width, height int) string {
	var b strings.Builder

	switch m.state {
	case searchStateInput:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString("Enter game name:\n")
		b.WriteString(m.input.View())
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Search  Esc: Back"))

	case searchStateLoading:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Searching..."))

	case searchStateResults:
		b.WriteString(m.styles.Title.Render("Search Results"))
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d games found", len(m.results))))
		b.WriteString("\n\n")

		if len(m.results) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No results found."))
			b.WriteString("\n")
		} else {
			// Show up to 15 results with scrolling
			start := 0
			visible := 15
			if m.cursor >= visible {
				start = m.cursor - visible + 1
			}
			end := start + visible
			if end > len(m.results) {
				end = len(m.results)
			}

			for i := start; i < end; i++ {
				result := m.results[i]
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

				line := fmt.Sprintf("%s%s (%s)%s", cursor, style.Render(name), year, typeIndicator)
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Detail  s: New Search  b: Back"))

	case searchStateError:
		b.WriteString(m.styles.Title.Render("Search Games"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Retry  Esc: Back"))
	}

	content := b.String()
	return centerContent(content, width, height)
}
