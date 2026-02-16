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
	errMsg    string
	selected  *int // Selected game ID for detail view
	wantsBack bool
	wantsMenu bool

	filter filterState[bgg.CollectionItem]

	img listImageState
}

func (m *collectionModel) WantsMenu() bool  { return m.wantsMenu }
func (m *collectionModel) WantsBack() bool  { return m.wantsBack }
func (m *collectionModel) Selected() *int   { return m.selected }
func (m *collectionModel) ClearSignals()    { m.wantsMenu = false; m.wantsBack = false; m.selected = nil }

// collectionResultMsg is sent when collection results are received.
type collectionResultMsg struct {
	items []bgg.CollectionItem
	err   error
}

func newCollectionModel(cfg *config.Config, styles Styles, keys KeyMap, imageEnabled bool, cache *imageCache) collectionModel {
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
		img:    listImageState{enabled: imageEnabled, cache: cache},
		filter: filterState[bgg.CollectionItem]{
			getName: func(item bgg.CollectionItem) string { return item.Name },
			getID:   func(item bgg.CollectionItem) int { return item.ID },
		},
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

func (m collectionModel) currentThumbURL() string {
	items := m.filter.displayItems()
	if m.filter.cursor >= 0 && m.filter.cursor < len(items) {
		return items[m.filter.cursor].Thumbnail
	}
	return ""
}

func (m collectionModel) maybeLoadThumb() (collectionModel, tea.Cmd) {
	cmd := m.img.maybeLoad(m.currentThumbURL())
	return m, cmd
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
				m.wantsMenu = true
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
				m.filter.items = msg.items
				m.filter.cursor = 0
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			}
		}
		return m, nil

	case collectionStateResults:
		// Handle image loaded
		if msg, ok := msg.(listImageMsg); ok {
			m.img.handleLoaded(msg)
			return m, nil
		}

		if m.filter.active {
			result, cursorMoved, cmd := m.filter.updateFilter(msg, m.keys)
			switch result {
			case filterExited:
				m, thumbCmd := m.maybeLoadThumb()
				return m, thumbCmd
			case filterSelected:
				m.selected = m.filter.selectedID()
				return m, nil
			}
			if cursorMoved {
				m, thumbCmd := m.maybeLoadThumb()
				return m, tea.Batch(cmd, thumbCmd)
			}
			m, thumbCmd := m.maybeLoadThumb()
			return m, tea.Batch(cmd, thumbCmd)
		}

		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.filter.cursor > 0 {
					m.filter.cursor--
				}
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Down):
				if m.filter.cursor < len(m.filter.items)-1 {
					m.filter.cursor++
				}
				m, cmd := m.maybeLoadThumb()
				return m, cmd
			case key.Matches(msg, m.keys.Enter):
				if len(m.filter.items) > 0 {
					id := m.filter.items[m.filter.cursor].ID
					m.selected = &id
				}
			case key.Matches(msg, m.keys.Filter):
				filterCmd := m.filter.startFilter()
				m, thumbCmd := m.maybeLoadThumb()
				return m, tea.Batch(filterCmd, thumbCmd)
			case key.Matches(msg, m.keys.User):
				// Change user - go back to input
				m.state = collectionStateInput
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

func (m collectionModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case collectionStateInput:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString("Enter BGG username:\n")
		b.WriteString(m.input.View())
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Load Collection  Esc: Menu"))

	case collectionStateLoading:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading collection..."))
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render("(This may take a moment)"))

	case collectionStateResults:
		username := strings.TrimSpace(m.input.Value())
		b.WriteString(m.styles.Title.Render(fmt.Sprintf("%s's Collection", username)))
		if m.filter.active {
			b.WriteString("  Filter: ")
			b.WriteString(m.filter.input.View())
		}
		b.WriteString("\n")

		displayItems := m.filter.displayItems()

		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d/%d games", len(displayItems), len(m.filter.items))))
		b.WriteString("\n\n")

		if len(displayItems) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No games found."))
			b.WriteString("\n")
		} else {
			// Show results with scrolling
			start, end := calcListRange(m.filter.cursor, len(displayItems), height, m.config.Interface.ListDensity)

			for i := start; i < end; i++ {
				item := displayItems[i]
				cursor := "  "
				style := m.styles.ListItem
				if i == m.filter.cursor {
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

				name := style.Render(item.Name)
				if i == m.filter.cursor && selType != "" && selType != "none" {
					name = renderSelectionAnim(item.Name, selType, animFrame)
				}
				line := fmt.Sprintf("%s%s (%s)%s", cursor, name, year, m.styles.Rating.Render(ratingStr))
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.filter.active {
			b.WriteString(m.styles.Help.Render("↑/↓: Navigate  Enter: Detail  Esc: Clear filter"))
		} else {
			b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Detail  /: Filter  u: Change User  ?: Help  b: Back  Esc: Menu"))
		}

		// Add image panel
		transmit = renderImagePanel(&b, m.img.enabled, m.img.placeholder, m.img.transmit, m.img.loading, m.img.hasError)

	case collectionStateError:
		b.WriteString(m.styles.Title.Render("User Collection"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("Enter: Retry  b: Back  Esc: Menu"))
	}

	content := b.String()
	return transmit + centerContent(content, width, height)
}
