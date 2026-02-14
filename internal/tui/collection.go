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

type collectionState int

const (
	collectionStateInput collectionState = iota
	collectionStateLoading
	collectionStateResults
	collectionStateError
)

type collectionModel struct {
	state     collectionState
	styles    Styles
	keys      KeyMap
	config    *config.Config
	input     textinput.Model
	items     []bgg.CollectionItem
	cursor    int
	errMsg    string
	selected  *int // Selected game ID for detail view
	wantsBack bool

	filtering     bool
	filterInput   textinput.Model
	filteredItems []bgg.CollectionItem
}

// collectionResultMsg is sent when collection results are received.
type collectionResultMsg struct {
	items []bgg.CollectionItem
	err   error
}

func newCollectionModel(cfg *config.Config, styles Styles, keys KeyMap) collectionModel {
	ti := textinput.New()
	ti.Placeholder = "Enter BGG username..."
	ti.CharLimit = 64
	ti.Width = 40
	ti.SetValue(cfg.Collection.DefaultUsername)
	ti.Focus()

	return collectionModel{
		state:  collectionStateInput,
		styles: styles,
		keys:   keys,
		config: cfg,
		input:  ti,
	}
}

func (m collectionModel) loadCollection(client *bgg.Client, username string, ownedOnly bool) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return collectionResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		opts := bgg.CollectionOptions{
			OwnedOnly: ownedOnly,
		}
		items, err := client.GetCollection(username, opts)
		return collectionResultMsg{items: items, err: err}
	}
}

func (m collectionModel) Update(msg tea.Msg, client *bgg.Client) (collectionModel, tea.Cmd) {
	var cmd tea.Cmd

	switch m.state {
	case collectionStateInput:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				username := strings.TrimSpace(m.input.Value())
				if username != "" {
					m.state = collectionStateLoading
					return m, m.loadCollection(client, username, m.config.Collection.ShowOnlyOwned)
				}
			case key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
				return m, nil
			}
		}
		m.input, cmd = m.input.Update(msg)
		return m, cmd

	case collectionStateLoading:
		switch msg := msg.(type) {
		case collectionResultMsg:
			if msg.err != nil {
				m.state = collectionStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = collectionStateResults
				m.items = msg.items
				m.cursor = 0
			}
		}
		return m, nil

	case collectionStateResults:
		if m.filtering {
			switch msg := msg.(type) {
			case tea.KeyMsg:
				switch {
				case key.Matches(msg, m.keys.Escape):
					m.filtering = false
					m.filteredItems = nil
					m.filterInput.SetValue("")
					m.cursor = 0
					return m, nil
				case key.Matches(msg, m.keys.Enter):
					if len(m.filteredItems) > 0 {
						id := m.filteredItems[m.cursor].ID
						m.selected = &id
					}
					return m, nil
				case msg.String() == "up":
					if m.cursor > 0 {
						m.cursor--
					}
					return m, nil
				case msg.String() == "down":
					if m.cursor < len(m.filteredItems)-1 {
						m.cursor++
					}
					return m, nil
				}
			}
			m.filterInput, cmd = m.filterInput.Update(msg)
			query := strings.ToLower(m.filterInput.Value())
			m.filteredItems = nil
			for _, item := range m.items {
				if strings.Contains(strings.ToLower(item.Name), query) {
					m.filteredItems = append(m.filteredItems, item)
				}
			}
			if m.cursor >= len(m.filteredItems) {
				m.cursor = max(0, len(m.filteredItems)-1)
			}
			return m, cmd
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.cursor > 0 {
					m.cursor--
				}
			case key.Matches(msg, m.keys.Down):
				if m.cursor < len(m.items)-1 {
					m.cursor++
				}
			case key.Matches(msg, m.keys.Enter):
				if len(m.items) > 0 {
					id := m.items[m.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Filter):
				m.filtering = true
				m.filterInput = newFilterInput()
				m.filterInput.Focus()
				m.filteredItems = make([]bgg.CollectionItem, len(m.items))
				copy(m.filteredItems, m.items)
				m.cursor = 0
				return m, textinput.Blink
			case key.Matches(msg, m.keys.User):
				// Change user - go back to input
				m.state = collectionStateInput
				m.input.Focus()
				m.items = nil
				m.cursor = 0
				return m, textinput.Blink
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil

	case collectionStateError:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				// Retry
				m.state = collectionStateInput
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

func (m collectionModel) View(width, height int) string {
	var b strings.Builder

	switch m.state {
	case collectionStateInput:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString("Enter BGG username:\n")
		b.WriteString(m.input.View())
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Load Collection  Esc: Back"))

	case collectionStateLoading:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading collection..."))
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render("(This may take a moment)"))

	case collectionStateResults:
		username := strings.TrimSpace(m.input.Value())
		b.WriteString(m.styles.Title.Render(fmt.Sprintf("%s's Collection", username)))
		if m.filtering {
			b.WriteString("  Filter: ")
			b.WriteString(m.filterInput.View())
		}
		b.WriteString("\n")

		displayItems := m.items
		if m.filtering || m.filteredItems != nil {
			displayItems = m.filteredItems
		}

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d games", len(displayItems), len(m.items))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
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
			if end > len(displayItems) {
				end = len(displayItems)
			}

			for i := start; i < end; i++ {
				item := displayItems[i]
				cursor := "  "
				style := m.styles.ListItem
				if i == m.cursor {
					cursor = "> "
					style = m.styles.ListItemFocus
				}

				year := item.Year
				if year == "" {
					year = "N/A"
				}

				// Show rating if available
				ratingStr := ""
				if item.Rating > 0 {
					ratingStr = fmt.Sprintf(" %.1f", item.Rating)
				}

				line := fmt.Sprintf("%s%s (%s)%s", cursor, style.Render(item.Name), year, m.styles.Rating.Render(ratingStr))
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filtering {
			b.WriteString(m.styles.Help.Render("↑/↓: Navigate  Enter: Detail  Esc: Clear filter"))
		} else {
			b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Detail  /: Filter  u: Change User  b: Back"))
		}

	case collectionStateError:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Retry  Esc: Back"))
	}

	content := b.String()
	return centerContent(content, width, height)
}
