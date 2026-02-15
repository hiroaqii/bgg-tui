package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"

	bgg "github.com/hiroaqii/go-bgg"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

type threadState int

const (
	threadStateLoading threadState = iota
	threadStateResults
	threadStateError
)

type threadModel struct {
	state      threadState
	styles     Styles
	keys       KeyMap
	config     *config.Config
	threadID   int
	thread     *bgg.Thread
	scroll     int
	maxScroll  int
	viewLines  []string // Pre-rendered view lines
	viewHeight int      // Terminal height for dynamic layout
	errMsg     string
	wantsBack  bool
}

// threadResultMsg is sent when thread content is received.
type threadResultMsg struct {
	thread *bgg.Thread
	err    error
}

func newThreadModel(threadID int, styles Styles, keys KeyMap, cfg *config.Config, viewHeight int) threadModel {
	return threadModel{
		state:      threadStateLoading,
		styles:     styles,
		keys:       keys,
		config:     cfg,
		threadID:   threadID,
		viewHeight: viewHeight,
	}
}

// visibleLines returns the number of content lines that fit in the viewport.
// Overhead: title(1+marginBottom1) + subtitle(1) + blank(1) + scrollPos(2) + help(1+marginTop1) = 8
func (m threadModel) visibleLines() int {
	v := m.viewHeight - 8
	if v < 1 {
		v = 1
	}
	return v
}

func (m *threadModel) recalcScroll() {
	m.maxScroll = len(m.viewLines) - m.visibleLines()
	if m.maxScroll < 0 {
		m.maxScroll = 0
	}
	if m.scroll > m.maxScroll {
		m.scroll = m.maxScroll
	}
}

func (m threadModel) loadThread(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return threadResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		thread, err := client.GetThread(m.threadID)
		return threadResultMsg{thread: thread, err: err}
	}
}

func (m threadModel) Update(msg tea.Msg) (threadModel, tea.Cmd) {
	switch m.state {
	case threadStateLoading:
		switch msg := msg.(type) {
		case tea.WindowSizeMsg:
			m.viewHeight = msg.Height
		case threadResultMsg:
			if msg.err != nil {
				m.state = threadStateError
				m.errMsg = msg.err.Error()
			} else {
				m.state = threadStateResults
				m.thread = msg.thread
				m.scroll = 0

				// Pre-render view lines
				m.viewLines = m.renderArticles()
				m.recalcScroll()
			}
		}
		return m, nil

	case threadStateResults:
		switch msg := msg.(type) {
		case tea.WindowSizeMsg:
			m.viewHeight = msg.Height
			m.recalcScroll()
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Up):
				if m.scroll > 0 {
					m.scroll--
				}
			case key.Matches(msg, m.keys.Down):
				if m.scroll < m.maxScroll {
					m.scroll++
				}
			case key.Matches(msg, m.keys.Open):
				// Open in browser
				url := fmt.Sprintf("https://boardgamegeek.com/thread/%d", m.threadID)
				openBrowser(url)
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil

	case threadStateError:
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil
	}

	return m, nil
}

func (m threadModel) View(width, height int) string {
	var b strings.Builder

	switch m.state {
	case threadStateLoading:
		b.WriteString(m.styles.Title.Render("Thread"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading thread..."))

	case threadStateResults:
		// Title
		subject := m.thread.Subject
		if len(subject) > 60 {
			subject = subject[:57] + "..."
		}
		b.WriteString(m.styles.Title.Render(subject))
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d posts", len(m.thread.Articles))))
		b.WriteString("\n\n")

		// Show articles with scrolling
		start := m.scroll
		end := start + m.visibleLines()
		if end > len(m.viewLines) {
			end = len(m.viewLines)
		}

		for i := start; i < end; i++ {
			b.WriteString(m.viewLines[i])
			b.WriteString("\n")
		}

		if m.maxScroll > 0 {
			b.WriteString("\n")
			b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("(%d/%d)", m.scroll+1, m.maxScroll+1)))
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Scroll  o: Open BGG  b: Back"))

	case threadStateError:
		b.WriteString(m.styles.Title.Render("Thread"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("b: Back"))
	}

	content := b.String()
	return centerContent(content, width, height)
}

// renderArticles pre-renders all articles into lines for scrolling.
func (m threadModel) renderArticles() []string {
	var lines []string

	for i, article := range m.thread.Articles {
		// Header line
		header := fmt.Sprintf("--- %s · %s ---", article.Username, formatDate(article.PostDate))
		lines = append(lines, m.styles.Label.Width(0).Render(header))

		// Body lines (wrap text)
		bodyLines := htmlToText(article.Body, m.config.Display.ThreadWidth)
		lines = append(lines, bodyLines...)

		// Add separator between articles
		if i < len(m.thread.Articles)-1 {
			lines = append(lines, "")
		}
	}

	return lines
}
