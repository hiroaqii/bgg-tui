package tui

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

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
	sortNewest bool // true=newest first, false=oldest first (default)
	errMsg     string
	wantsBack  bool
	wantsMenu  bool
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

const threadExtraOverhead = 2

// visibleLines returns the number of content lines that fit in the viewport.
func (m threadModel) visibleLines() int {
	v := m.viewHeight - overheadForDensity(m.config.Interface.ListDensity) - threadExtraOverhead
	if HasBorder(m.config.Interface.BorderStyle) {
		v -= BorderHeightOverhead
	}
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
			return threadResultMsg{err: fmt.Errorf(errNoToken)}
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
			case key.Matches(msg, m.keys.Sort):
				m.sortNewest = !m.sortNewest
				sort.Slice(m.thread.Articles, func(i, j int) bool {
					ti := parseDate(m.thread.Articles[i].PostDate)
					tj := parseDate(m.thread.Articles[j].PostDate)
					if m.sortNewest {
						return ti.After(tj)
					}
					return ti.Before(tj)
				})
				m.viewLines = m.renderArticles()
				m.scroll = 0
				m.recalcScroll()
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case threadStateError:
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

func (m threadModel) View(width, height int) string {
	var b strings.Builder

	switch m.state {
	case threadStateLoading:
		writeLoadingView(&b, m.styles, "Thread", "Loading thread...")

	case threadStateResults:
		// Title
		hasBorder := HasBorder(m.config.Interface.BorderStyle)
		contentWidth := listContentWidth(m.config.Display.ListWidth, width, hasBorder)
		subject := truncateName(m.thread.Subject, calcMaxNameWidth(contentWidth, 0))
		b.WriteString(m.styles.Title.Render(subject))
		b.WriteString("\n")
		sortLabel := "↑Old"
		if m.sortNewest {
			sortLabel = "↓New"
		}
		b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("%d posts · %s", len(m.thread.Articles), sortLabel)))
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
		b.WriteString(m.styles.Help.Render("j/k ↑↓: Scroll  s: Sort  o: Open BGG  b: Back  Esc: Menu"))

	case threadStateError:
		writeErrorView(&b, m.styles, "Thread", m.errMsg, "b: Back  Esc: Menu")
	}

	content := b.String()
	borderStyle := m.config.Interface.BorderStyle
	if m.state != threadStateResults {
		borderStyle = "none"
	}
	return renderView(content, m.styles, width, height, borderStyle)
}

// renderArticles pre-renders all articles into lines for scrolling.
func (m threadModel) renderArticles() []string {
	var lines []string

	for i, article := range m.thread.Articles {
		// Header line
		nameStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
		dateStyle := lipgloss.NewStyle().Foreground(ColorMuted)
		header := fmt.Sprintf("%s  %s", nameStyle.Render("■ "+article.Username), dateStyle.Render(formatDate(article.PostDate, m.config.Interface.DateFormat)))
		lines = append(lines, header)

		// Body lines (wrap text)
		threadWidth := m.config.Display.ThreadWidth
		if HasBorder(m.config.Interface.BorderStyle) {
			threadWidth -= BorderWidthOverhead
		}
		bodyLines := linkifyLines(htmlToText(article.Body, threadWidth))
		quoteStyle := lipgloss.NewStyle().Foreground(ColorMuted)
		for i, line := range bodyLines {
			if strings.HasPrefix(line, "│") {
				bodyLines[i] = quoteStyle.Render(line)
			}
		}
		lines = append(lines, bodyLines...)

		// Add separator between articles
		if i < len(m.thread.Articles)-1 {
			separator := strings.Repeat("─", threadWidth)
			sepStyle := lipgloss.NewStyle().Foreground(ColorMuted)
			lines = append(lines, "")
			lines = append(lines, sepStyle.Render(separator))
			lines = append(lines, "")
		}
	}

	return lines
}
