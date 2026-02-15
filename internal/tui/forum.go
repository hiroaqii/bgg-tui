package tui

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"
)

type forumState int

const (
	forumStateLoadingForums forumState = iota
	forumStateForumList
	forumStateLoadingThreads
	forumStateThreadList
	forumStateError
)

type forumModel struct {
	state              forumState
	styles             Styles
	keys               KeyMap
	gameID             int
	gameName           string
	forums             []bgg.Forum
	forumCursor        int
	selectedForumID    int
	selectedForumTitle string
	threads            *bgg.ThreadList
	threadCursor       int
	page               int
	errMsg             string
	wantsBack          bool
	wantsMenu          bool
	wantsThread        *int // Selected thread ID
}

// forumsResultMsg is sent when forums are received.
type forumsResultMsg struct {
	forums []bgg.Forum
	err    error
}

// threadsResultMsg is sent when threads are received.
type threadsResultMsg struct {
	threads *bgg.ThreadList
	err     error
}

func newForumModel(gameID int, gameName string, styles Styles, keys KeyMap) forumModel {
	return forumModel{
		state:    forumStateLoadingForums,
		styles:   styles,
		keys:     keys,
		gameID:   gameID,
		gameName: gameName,
		page:     1,
	}
}

func (m forumModel) loadForums(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return forumsResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		forums, err := client.GetForums(m.gameID)
		return forumsResultMsg{forums: forums, err: err}
	}
}

func (m forumModel) loadThreads(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return threadsResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		threads, err := client.GetForumThreads(m.selectedForumID, m.page)
		return threadsResultMsg{threads: threads, err: err}
	}
}

func (m forumModel) Update(msg tea.Msg, client *bgg.Client) (forumModel, tea.Cmd) {
	switch m.state {
	case forumStateLoadingForums:
		switch msg := msg.(type) {
		case forumsResultMsg:
			if msg.err != nil {
				m.state = forumStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = forumStateForumList
				m.forums = msg.forums
				// Sort by last post date (descending)
				sort.Slice(m.forums, func(i, j int) bool {
					return parseDate(m.forums[i].LastPostDate).After(parseDate(m.forums[j].LastPostDate))
				})
				m.forumCursor = 0
			}
		}
		return m, nil

	case forumStateForumList:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.forumCursor > 0 {
					m.forumCursor--
				}
			case key.Matches(msg, m.keys.Down):
				if m.forumCursor < len(m.forums)-1 {
					m.forumCursor++
				}
			case key.Matches(msg, m.keys.Enter):
				if len(m.forums) > 0 {
					forum := m.forums[m.forumCursor]
					m.selectedForumID = forum.ID
					m.selectedForumTitle = forum.Title
					m.page = 1
					m.threadCursor = 0
					m.state = forumStateLoadingThreads
					return m, m.loadThreads(client)
				}
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case forumStateLoadingThreads:
		switch msg := msg.(type) {
		case threadsResultMsg:
			if msg.err != nil {
				m.state = forumStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = forumStateThreadList
				m.threads = msg.threads
				m.threadCursor = 0
			}
		}
		return m, nil

	case forumStateThreadList:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.threadCursor > 0 {
					m.threadCursor--
				}
			case key.Matches(msg, m.keys.Down):
				if m.threads != nil && m.threadCursor < len(m.threads.Threads)-1 {
					m.threadCursor++
				}
			case key.Matches(msg, m.keys.Enter):
				if m.threads != nil && len(m.threads.Threads) > 0 {
					threadID := m.threads.Threads[m.threadCursor].ID
					m.wantsThread = &threadID
				}
			case key.Matches(msg, m.keys.NextPage):
				if m.threads != nil && m.page < m.threads.TotalPages {
					m.page++
					m.threadCursor = 0
					m.state = forumStateLoadingThreads
					return m, m.loadThreads(client)
				}
			case key.Matches(msg, m.keys.PrevPage):
				if m.page > 1 {
					m.page--
					m.threadCursor = 0
					m.state = forumStateLoadingThreads
					return m, m.loadThreads(client)
				}
			case key.Matches(msg, m.keys.Back):
				// Go back to forum list
				m.state = forumStateForumList
				m.threads = nil
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case forumStateError:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
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

func (m forumModel) View(width, height int, selType string, animFrame int) string {
	var b strings.Builder

	switch m.state {
	case forumStateLoadingForums:
		b.WriteString(m.styles.Title.Render(fmt.Sprintf("%s - Forums", m.gameName)))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading forums..."))

	case forumStateForumList:
		b.WriteString(m.styles.Title.Render(fmt.Sprintf("%s - Forums", m.gameName)))
		b.WriteString("\n\n")

		if len(m.forums) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No forums found."))
			b.WriteString("\n")
		} else {
			titles, metas := formatForumColumns(m.forums)
			for i := range m.forums {
				cursor := "  "
				style := m.styles.ListItem
				if i == m.forumCursor {
					cursor = "> "
					style = m.styles.ListItemFocus
				}

				title := style.Render(titles[i])
				if i == m.forumCursor && selType != "" && selType != "none" {
					title = renderSelectionAnim(titles[i], selType, animFrame)
				}
				line := fmt.Sprintf("%s%s  %s", cursor, title, m.styles.Subtitle.Render(metas[i]))
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Open  b: Back  Esc: Menu"))

	case forumStateLoadingThreads:
		b.WriteString(m.styles.Title.Render(m.selectedForumTitle))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading threads..."))

	case forumStateThreadList:
		b.WriteString(m.styles.Title.Render(m.selectedForumTitle))
		b.WriteString("\n")
		if m.threads != nil {
			b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("Page %d / %d", m.page, m.threads.TotalPages)))
		}
		b.WriteString("\n\n")

		if m.threads == nil || len(m.threads.Threads) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No threads found."))
			b.WriteString("\n")
		} else {
			// Show up to 10 threads with scrolling
			start := 0
			visible := 10
			if m.threadCursor >= visible {
				start = m.threadCursor - visible + 1
			}
			end := start + visible
			if end > len(m.threads.Threads) {
				end = len(m.threads.Threads)
			}

			for i := start; i < end; i++ {
				thread := m.threads.Threads[i]
				cursor := "  "
				style := m.styles.ListItem
				if i == m.threadCursor {
					cursor = "> "
					style = m.styles.ListItemFocus
				}

				// Truncate subject if too long
				subject := thread.Subject
				if len(subject) > 50 {
					subject = subject[:47] + "..."
				}

				renderedSubject := style.Render(subject)
			if i == m.threadCursor && selType != "" && selType != "none" {
				renderedSubject = renderSelectionAnim(subject, selType, animFrame)
			}
			line := fmt.Sprintf("%s%s", cursor, renderedSubject)
				b.WriteString(line)
				b.WriteString("\n")

				// Second line: author, date, replies
				meta := fmt.Sprintf("    %s · %s · %d replies",
					formatDate(thread.LastPostDate),
					thread.Author,
					thread.NumArticles-1)
				b.WriteString(m.styles.Subtitle.Render(meta))
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Read  n/p: Page  b: Back  Esc: Menu"))

	case forumStateError:
		b.WriteString(m.styles.Title.Render("Forums"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("b: Back  Esc: Menu"))
	}

	content := b.String()
	return centerContent(content, width, height)
}

// formatForumColumns formats forum titles and meta info with aligned columns.
func formatForumColumns(forums []bgg.Forum) (titles []string, metas []string) {
	maxTitleWidth := 0
	maxThreads := 0
	for _, f := range forums {
		if w := len(f.Title); w > maxTitleWidth {
			maxTitleWidth = w
		}
		if f.NumThreads > maxThreads {
			maxThreads = f.NumThreads
		}
	}
	maxDigits := len(fmt.Sprintf("%d", maxThreads))
	if maxDigits == 0 {
		maxDigits = 1
	}

	for _, f := range forums {
		titles = append(titles, fmt.Sprintf("%-*s", maxTitleWidth, f.Title))
		metas = append(metas, fmt.Sprintf("%*d threads · %s", maxDigits, f.NumThreads, formatDate(f.LastPostDate)))
	}
	return
}

// parseDate parses a date string into time.Time.
// Returns zero time if parsing fails.
func parseDate(dateStr string) time.Time {
	formats := []string{
		time.RFC1123Z, // "Mon, 02 Jan 2006 15:04:05 -0700"
		time.RFC1123,  // "Mon, 02 Jan 2006 15:04:05 MST"
		time.RFC3339,  // "2006-01-02T15:04:05Z07:00"
	}
	for _, layout := range formats {
		if t, err := time.Parse(layout, dateStr); err == nil {
			return t
		}
	}
	return time.Time{}
}

// formatDate formats a date string for display.
// Output format: "2006-01-02 15:04"
func formatDate(dateStr string) string {
	if dateStr == "" {
		return ""
	}
	t := parseDate(dateStr)
	if t.IsZero() {
		return dateStr
	}
	return t.Format("2006-01-02 15:04")
}
