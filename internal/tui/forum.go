package tui

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"

	"github.com/hiroaqii/bgg-tui/internal/config"
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
	config             *config.Config
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

func newForumModel(gameID int, gameName string, styles Styles, keys KeyMap, cfg *config.Config) forumModel {
	return forumModel{
		state:    forumStateLoadingForums,
		styles:   styles,
		keys:     keys,
		config:   cfg,
		gameID:   gameID,
		gameName: gameName,
		page:     1,
	}
}

func (m forumModel) loadForums(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return forumsResultMsg{err: fmt.Errorf(errNoToken)}
		}
		forums, err := client.GetForums(m.gameID)
		return forumsResultMsg{forums: forums, err: err}
	}
}

func (m forumModel) loadThreads(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return threadsResultMsg{err: fmt.Errorf(errNoToken)}
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
		writeLoadingView(&b, m.styles, fmt.Sprintf("%s - Forums", m.gameName), "Loading forums...")

	case forumStateForumList:
		b.WriteString(m.styles.Title.Render(fmt.Sprintf("%s - Forums", m.gameName)))
		b.WriteString("\n\n")

		if len(m.forums) == 0 {
			b.WriteString(m.styles.Subtitle.Render("No forums found."))
			b.WriteString("\n")
		} else {
			titles, metas := formatForumColumns(m.forums, m.config.Interface.DateFormat)
			for i := range m.forums {
				prefix, title := renderListItem(i, m.forumCursor, titles[i], m.styles, selType, animFrame)
				line := fmt.Sprintf("%s%s  %s", prefix, title, m.styles.Subtitle.Render(metas[i]))
				b.WriteString(line)
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Open  b: Back  Esc: Menu"))

	case forumStateLoadingThreads:
		writeLoadingView(&b, m.styles, m.selectedForumTitle, "Loading threads...")

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
			start, end := calcListRangeMultiLine(m.threadCursor, len(m.threads.Threads), height, "normal", 2)

			// Calculate dynamic subject width from ListWidth
			hasBorder := HasBorder(m.config.Interface.BorderStyle)
			contentWidth := listContentWidth(m.config.Display.ListWidth, width, hasBorder)
			// overhead: prefix(2)
			maxSubjectW := contentWidth - 2
			if maxSubjectW < 10 {
				maxSubjectW = 10
			}

			for i := start; i < end; i++ {
				thread := m.threads.Threads[i]

				subject := truncateName(thread.Subject, maxSubjectW)
				prefix, renderedSubject := renderListItem(i, m.threadCursor, subject, m.styles, selType, animFrame)
				line := fmt.Sprintf("%s%s", prefix, renderedSubject)
				b.WriteString(line)
				b.WriteString("\n")

				// Second line: author, date, replies
				meta := fmt.Sprintf("    %s · %s · %d replies",
					formatDate(thread.LastPostDate, m.config.Interface.DateFormat),
					thread.Author,
					thread.NumArticles-1)
				b.WriteString(m.styles.Subtitle.Render(meta))
				b.WriteString("\n")
			}
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Read  n/p: Page  b: Back  Esc: Menu"))

	case forumStateError:
		writeErrorView(&b, m.styles, "Forums", m.errMsg, "b: Back  Esc: Menu")
	}

	content := b.String()
	borderStyle := m.config.Interface.BorderStyle
	if m.state != forumStateForumList && m.state != forumStateThreadList {
		borderStyle = "none"
	}
	return renderView(content, m.styles, width, height, borderStyle)
}

// formatForumColumns formats forum titles and meta info with aligned columns.
func formatForumColumns(forums []bgg.Forum, dateFormat string) (titles []string, metas []string) {
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
		metas = append(metas, fmt.Sprintf("%*d threads · %s", maxDigits, f.NumThreads, formatDate(f.LastPostDate, dateFormat)))
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

// DateFormatNames lists the available date format options.
var DateFormatNames = []string{"YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY"}

// dateLayout returns the Go time layout string for the given format name.
func dateLayout(format string) string {
	switch format {
	case "MM/DD/YYYY":
		return "01/02/2006 15:04"
	case "DD/MM/YYYY":
		return "02/01/2006 15:04"
	default:
		return "2006-01-02 15:04"
	}
}

// formatDate formats a date string for display using the given format.
func formatDate(dateStr, format string) string {
	if dateStr == "" {
		return ""
	}
	t := parseDate(dateStr)
	if t.IsZero() {
		return dateStr
	}
	return t.Format(dateLayout(format))
}
