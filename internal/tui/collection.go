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

type collectionState int

const (
	collectionStateInput collectionState = iota
	collectionStateLoading
	collectionStateResults
	collectionStateError
)

// statusPickerExtraLines is the extra vertical lines the picker occupies
// beyond the normal 1-line help text (title + 8 statuses + "Show All" + help - normal help = 10).
const statusPickerExtraLines = 10

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

	filter   filterState[bgg.CollectionItem]
	allItems []bgg.CollectionItem // unfiltered API results

	// Status picker
	statusPicker   bool
	statusCursor   int
	activeStatuses map[CollectionStatus]bool

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

	// Initialize active statuses from config
	active := make(map[CollectionStatus]bool)
	for _, key := range cfg.Collection.StatusFilter {
		if s := statusFromConfigKey(key); s >= 0 {
			active[s] = true
		}
	}

	return collectionModel{
		state:          collectionStateInput,
		styles:         styles,
		keys:           keys,
		config:         cfg,
		input:          ti,
		activeStatuses: active,
		img:            listImageState{enabled: imageEnabled, cache: cache},
		filter: filterState[bgg.CollectionItem]{
			getName: func(item bgg.CollectionItem) string { return item.Name },
			getID:   func(item bgg.CollectionItem) int { return item.ID },
		},
	}
}

func (m collectionModel) loadCollection(client *bgg.Client, username string) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return collectionResultMsg{err: fmt.Errorf(errNoToken)}
		}
		items, err := client.GetCollection(username, bgg.CollectionOptions{})
		return collectionResultMsg{items: items, err: err}
	}
}

// applyStatusFilter filters allItems by active statuses and updates filter.items.
func (m *collectionModel) applyStatusFilter() {
	if len(m.activeStatuses) == 0 {
		m.filter.items = m.allItems
	} else {
		filtered := make([]bgg.CollectionItem, 0, len(m.allItems))
		for _, item := range m.allItems {
			for s := range m.activeStatuses {
				if itemMatchesStatus(item, s) {
					filtered = append(filtered, item)
					break
				}
			}
		}
		m.filter.items = filtered
	}
	// Reset name filter if active
	if m.filter.active {
		m.filter.clearFilter()
	}
	m.filter.cursor = 0
}

// renderStatusFilterBar renders all statuses with active ones highlighted and inactive ones muted.
func (m collectionModel) renderStatusFilterBar() string {
	activeStyle := lipgloss.NewStyle().Foreground(ColorAccent).Italic(true)
	dimStyle := lipgloss.NewStyle().Foreground(ColorDim)
	var parts []string
	for _, s := range allStatuses {
		label := statusLabel(s)
		if m.activeStatuses[s] {
			parts = append(parts, activeStyle.Render(label))
		} else {
			parts = append(parts, dimStyle.Render(label))
		}
	}
	return "[" + strings.Join(parts, dimStyle.Render(", ")) + "]"
}

// saveStatusFilterToConfig persists the current active statuses to config.
func (m *collectionModel) saveStatusFilterToConfig() {
	var keys []string
	for _, s := range allStatuses {
		if m.activeStatuses[s] {
			keys = append(keys, statusConfigKey(s))
		}
	}
	m.config.Collection.StatusFilter = keys
	m.config.Save()
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
					return m, m.loadCollection(client, username)
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
				m.allItems = msg.items
				m.applyStatusFilter()
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

		// Status picker mode
		if m.statusPicker {
			return m.updateStatusPicker(msg)
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
			case key.Matches(msg, m.keys.StatusFilter):
				m.statusPicker = true
				m.statusCursor = 0
				return m, nil
			case key.Matches(msg, m.keys.User):
				// Change user - go back to input
				m.state = collectionStateInput
				m.input.Focus()
				m.filter.items = nil
				m.allItems = nil
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

		subtitle := fmt.Sprintf("%d/%d games  ♥ User Rating  ★ Rating  #Rank", min(m.filter.cursor+1, len(displayItems)), len(displayItems))
		b.WriteString(m.styles.Subtitle.Render(subtitle))
		b.WriteString("\n")
		b.WriteString(m.renderStatusFilterBar())
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
			if m.statusPicker {
				listHeight -= statusPickerExtraLines
			}
			listHeight--
			start, end := calcListRange(m.filter.cursor, len(displayItems), listHeight, m.config.Interface.ListDensity)

			// Calculate dynamic name width from ListWidth
			// overhead: prefix(2) + " (" + year(4) + ")" = 9
			hasBorder := HasBorder(m.config.Interface.BorderStyle)
			contentWidth := listContentWidth(m.config.Display.ListWidth, width, hasBorder)
			maxNameW := calcMaxNameWidth(contentWidth, 9)

			// First pass: find max name+year width for stats alignment
			maxNameYearLen := 0
			for i := start; i < end; i++ {
				item := displayItems[i]
				year := item.Year
				if year == "" {
					year = "N/A"
				}
				w := lipgloss.Width(truncateName(item.Name, maxNameW)) + len(year) + 3
				if w > maxNameYearLen {
					maxNameYearLen = w
				}
			}

			for i := start; i < end; i++ {
				item := displayItems[i]
				year := item.Year
				if year == "" {
					year = "N/A"
				}

				displayName := truncateName(item.Name, maxNameW)
				prefix, name := renderListItem(i, m.filter.cursor, displayName, m.styles, selType, animFrame)
				line := fmt.Sprintf("%s%s (%s)", prefix, name, year)

				hasStats := item.Rating > 0 || item.BGGRating > 0 || item.Rank > 0
				if hasStats {
					nameYearLen := lipgloss.Width(displayName) + len(year) + 3
					padding := maxNameYearLen - nameYearLen + 2
					line += strings.Repeat(" ", padding)
					line += renderStats([]statEntry{
						{"♥", item.Rating, "%5.2f", m.styles.Rating, 6},
						{"★", item.BGGRating, "%5.2f", m.styles.Rank, 6},
					})
					if rs := renderIntStat(item.Rank, " #%d", m.styles.Players); rs != "" {
						line += rs
					}
				}

				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		if m.statusPicker {
			b.WriteString(m.renderStatusPicker())
		} else if m.filter.active {
			b.WriteString(m.styles.Help.Render(helpFilterActive))
		} else {
			b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Detail  /: Filter  s: Status  u: Change User  ?: Help  b: Back  Esc: Menu"))
		}

		// Add image panel
		transmit = renderImagePanel(&b, m.img.enabled, m.img.placeholder, m.img.transmit, m.img.loading, m.img.hasError)

	case collectionStateError:
		writeErrorView(&b, m.styles, "User Collection", m.errMsg, "Enter: Retry  b: Back  Esc: Menu")
	}

	content := b.String()
	borderStyle := m.config.Interface.BorderStyle
	return transmit + renderView(content, m.styles, width, height, borderStyle)
}

// updateStatusPicker handles key input while the status picker is open.
func (m collectionModel) updateStatusPicker(msg tea.Msg) (collectionModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		pickerLen := len(allStatuses) + 1 // +1 for "Show All (clear)"
		switch {
		case key.Matches(msg, m.keys.Up):
			if m.statusCursor > 0 {
				m.statusCursor--
			}
		case key.Matches(msg, m.keys.Down):
			if m.statusCursor < pickerLen-1 {
				m.statusCursor++
			}
		case key.Matches(msg, m.keys.Enter):
			if m.statusCursor < len(allStatuses) {
				// Toggle status
				s := allStatuses[m.statusCursor]
				if m.activeStatuses[s] {
					delete(m.activeStatuses, s)
				} else {
					m.activeStatuses[s] = true
				}
			} else {
				// "Show All (clear)"
				m.activeStatuses = make(map[CollectionStatus]bool)
			}
			m.applyStatusFilter()
			m.saveStatusFilterToConfig()
			return m.maybeLoadThumb()
		case key.Matches(msg, m.keys.Escape):
			m.statusPicker = false
		}
	}
	return m, nil
}

// renderStatusPicker renders the inline status picker overlay.
func (m collectionModel) renderStatusPicker() string {
	var b strings.Builder
	b.WriteString(m.styles.Subtitle.Render("Status Filter"))
	b.WriteString("\n")
	for i, s := range allStatuses {
		check := "[ ]"
		if m.activeStatuses[s] {
			check = "[x]"
		}
		cursor := "  "
		if i == m.statusCursor {
			cursor = "> "
		}
		b.WriteString(fmt.Sprintf("%s%s %s\n", cursor, check, statusLabel(s)))
	}
	// "Show All (clear)" option
	cursor := "  "
	if m.statusCursor == len(allStatuses) {
		cursor = "> "
	}
	b.WriteString(fmt.Sprintf("%s    Show All (clear)\n", cursor))
	b.WriteString(m.styles.Help.Render("j/k: Move  Enter: Toggle  Esc: Close"))
	return b.String()
}
