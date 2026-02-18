package tui

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	bgg "github.com/hiroaqii/go-bgg"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

type detailState int

const (
	detailStateLoading detailState = iota
	detailStateResults
	detailStateError
)

type detailModel struct {
	state      detailState
	styles     Styles
	keys       KeyMap
	config     *config.Config
	gameID     int
	game       *bgg.Game
	errMsg     string
	scroll       int
	maxScroll    int
	contentLines    []string // Pre-rendered full content lines
	descLines       []string // Pre-wrapped description lines
	maxContentWidth int      // max lipgloss.Width across all contentLines
	wantsBack    bool
	wantsMenu    bool
	wantsForum   bool // Navigate to forum view

	// Layout fields
	viewHeight int // terminal height from WindowSizeMsg

	// Image fields
	imageEnabled   bool
	imgTransmit    string // Kitty APC transmit sequence
	imgPlaceholder string // Unicode placeholder grid
	imgLoading     bool
	imgCols        int
	imgRows        int
	imgLineStart   int // first line index of image in contentLines (-1 = none)
	imgLineEnd     int // one past last line index of image in contentLines
	cache          *imageCache
}

// detailResultMsg is sent when game details are received.
type detailResultMsg struct {
	game *bgg.Game
	err  error
}

func newDetailModel(gameID int, styles Styles, keys KeyMap, imgEnabled bool, cache *imageCache, cfg *config.Config) detailModel {
	return detailModel{
		state:        detailStateLoading,
		styles:       styles,
		keys:         keys,
		config:       cfg,
		gameID:       gameID,
		imageEnabled: imgEnabled,
		imgCols:      detailImageCols,
		imgRows:      detailImageRows,
		cache:        cache,
	}
}

// visibleLines returns the number of content lines visible in the viewport.
func (m detailModel) visibleLines() int {
	v := m.viewHeight - overheadForDensity(m.config.Interface.ListDensity)
	if v < 1 {
		v = 1
	}
	return v
}

// buildContentLines pre-renders all content lines for full-screen scrolling.
func (m *detailModel) buildContentLines() {
	if m.game == nil {
		m.contentLines = nil
		m.maxScroll = 0
		return
	}

	var lines []string
	game := m.game

	// Title + blank
	lines = append(lines, m.styles.Title.Render(game.Name), "")

	// Image
	m.imgLineStart = -1
	m.imgLineEnd = -1
	if m.imgTransmit != "" {
		m.imgLineStart = len(lines)
		for _, pl := range strings.Split(m.imgPlaceholder, "\n") {
			lines = append(lines, pl)
		}
		m.imgLineEnd = len(lines)
	} else if m.imgLoading {
		lines = append(lines, m.styles.Loading.Render("Loading image..."), "")
	}

	// Year
	year := game.Year
	if year == "" {
		year = "N/A"
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Year"), year))

	// Rating (with StdDev)
	ratingStr := "N/A"
	if game.Rating > 0 {
		ratingStr = fmt.Sprintf("%.2f (%s votes", game.Rating, formatNumber(game.UsersRated))
		if game.StdDev > 0 {
			ratingStr += fmt.Sprintf(", σ %.2f", game.StdDev)
		}
		ratingStr += ")"
		if game.Median > 0 {
			ratingStr += fmt.Sprintf(" median %.2f", game.Median)
		}
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Rating"), m.styles.Rating.Render(ratingStr)))

	// Geek Rating (Bayes Average)
	if game.BayesAverage > 0 {
		geekStr := fmt.Sprintf("%.2f", game.BayesAverage)
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Geek Rating"), geekStr))
	}

	// Rank
	rankStr := "Not Ranked"
	if game.Rank > 0 {
		rankStr = fmt.Sprintf("#%d", game.Rank)
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Rank"), m.styles.Rank.Render(rankStr)))

	// Players
	playersStr := fmt.Sprintf("%d-%d", game.MinPlayers, game.MaxPlayers)
	if game.MinPlayers == game.MaxPlayers {
		playersStr = fmt.Sprintf("%d", game.MinPlayers)
	}
	if game.PlayerCountPoll != nil && game.PlayerCountPoll.RecWith != "" {
		playersStr += fmt.Sprintf("  (%s)", game.PlayerCountPoll.RecWith)
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Players"), m.styles.Players.Render(playersStr)))

	// Player count poll bar chart
	if game.PlayerCountPoll != nil && len(game.PlayerCountPoll.Results) > 0 {
		lines = append(lines, renderPlayerCountPoll(game.PlayerCountPoll)...)
	}

	// Playing time
	timeStr := fmt.Sprintf("%d min", game.PlayingTime)
	if game.MinPlayTime != game.MaxPlayTime {
		timeStr = fmt.Sprintf("%d-%d min", game.MinPlayTime, game.MaxPlayTime)
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Time"), m.styles.Time.Render(timeStr)))

	// Weight (with complexity label)
	weightStr := "N/A"
	if game.Weight > 0 {
		label := complexityLabel(game.Weight)
		weightStr = fmt.Sprintf("%.2f / 5 - %s", game.Weight, label)
		if game.NumWeights > 0 {
			weightStr += fmt.Sprintf(" (%s votes)", formatNumber(game.NumWeights))
		}
	}
	lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Weight"), weightStr))

	// Age
	if game.MinAge > 0 {
		lines = append(lines, fmt.Sprintf("%s %d+", m.styles.Label.Render("Age"), game.MinAge))
	}

	// Owned
	if game.Owned > 0 {
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Owned"), formatNumber(game.Owned)))
	}

	// Comments
	if game.NumComments > 0 {
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Comments"), formatNumber(game.NumComments)))
	}

	// Designers
	if len(game.Designers) > 0 {
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Designer"), strings.Join(game.Designers, ", ")))
	}

	// Artists
	if len(game.Artists) > 0 {
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Artist"), strings.Join(game.Artists, ", ")))
	}

	// Categories
	if len(game.Categories) > 0 {
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Categories"), strings.Join(game.Categories, ", ")))
	}

	// Mechanics
	if len(game.Mechanics) > 0 {
		lines = append(lines, m.styles.Label.Render("Mechanics"))
		for _, mech := range game.Mechanics {
			lines = append(lines, "  "+mech)
		}
	}

	// Description
	lines = append(lines, "", m.styles.Subtitle.Render("Description"))
	lines = append(lines, m.descLines...)

	m.contentLines = lines

	// Compute max width across all content lines for stable horizontal centering
	m.maxContentWidth = 0
	for _, line := range lines {
		if w := lipgloss.Width(line); w > m.maxContentWidth {
			m.maxContentWidth = w
		}
	}

	m.maxScroll = len(m.contentLines) - m.visibleLines()
	if m.maxScroll < 0 {
		m.maxScroll = 0
	}
	if m.scroll > m.maxScroll {
		m.scroll = m.maxScroll
	}
}

func (m detailModel) loadGame(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return detailResultMsg{err: fmt.Errorf(errNoToken)}
		}
		game, err := client.GetGame(m.gameID)
		return detailResultMsg{game: game, err: err}
	}
}

func (m detailModel) loadImage(url string) tea.Cmd {
	return func() tea.Msg {
		ri, err := renderKittyImage(m.cache, url, detailImageID, m.imgCols, m.imgRows, false)
		if err != nil {
			return imageLoadedMsg{url: url, err: err}
		}
		return imageLoadedMsg{url: url, imgTransmit: ri.transmit, imgPlaceholder: ri.placeholder, imgRows: ri.rows}
	}
}

func (m detailModel) Update(msg tea.Msg) (detailModel, tea.Cmd) {
	switch m.state {
	case detailStateLoading:
		switch msg := msg.(type) {
		case tea.WindowSizeMsg:
			m.viewHeight = msg.Height

		case detailResultMsg:
			if msg.err != nil {
				m.state = detailStateError
				m.errMsg = msg.err.Error()
				return m, nil
			}

			m.state = detailStateResults
			m.game = msg.game
			m.scroll = 0

			// Pre-calculate description lines
			desc := msg.game.Description
			if desc == "" {
				desc = "No description available."
			}
			m.descLines = wrapText(desc, m.config.Display.DescriptionWidth)
			m.buildContentLines()

			// Start image loading if enabled
			if m.imageEnabled && m.cache != nil && msg.game.Image != "" {
				m.imgLoading = true
				return m, m.loadImage(msg.game.Image)
			}
		}
		return m, nil

	case detailStateResults:
		switch msg := msg.(type) {
		case tea.WindowSizeMsg:
			m.viewHeight = msg.Height
			m.buildContentLines()

		case imageLoadedMsg:
			m.imgLoading = false
			if msg.err == nil {
				m.imgTransmit = msg.imgTransmit
				m.imgPlaceholder = msg.imgPlaceholder
				m.imgRows = msg.imgRows
			}
			m.buildContentLines()
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
				url := fmt.Sprintf("https://boardgamegeek.com/boardgame/%d", m.gameID)
				openBrowser(url)
			case key.Matches(msg, m.keys.Forum):
				m.wantsForum = true
			case key.Matches(msg, m.keys.Back):
				m.wantsBack = true
			case key.Matches(msg, m.keys.Escape):
				m.wantsMenu = true
			}
		}
		return m, nil

	case detailStateError:
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

func (m detailModel) View(width, height int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case detailStateLoading:
		writeLoadingView(&b, m.styles, "Game Details", "Loading...")

	case detailStateResults:
		start := m.scroll
		end := start + m.visibleLines()
		if end > len(m.contentLines) {
			end = len(m.contentLines)
		}

		// Only transmit image when placeholder lines are visible; delete when scrolled off
		if m.imgTransmit != "" {
			if m.imgLineStart >= 0 && m.imgLineStart < end && m.imgLineEnd > start {
				transmit = m.imgTransmit
			} else {
				transmit = fmt.Sprintf("\033_Ga=d,d=I,i=1\033\\")
			}
		}

		for i := start; i < end; i++ {
			b.WriteString(m.contentLines[i])
			b.WriteString("\n")
		}

		if m.maxScroll > 0 {
			b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("(%d/%d)", m.scroll+1, m.maxScroll+1)))
			b.WriteString("\n")
		}

		b.WriteString("\n")
		helpLine := m.styles.Help.Render("j/k ↑↓: Scroll  o: Open BGG  f: Forum  ?: Help  b: Back  Esc: Menu")
		if helpWidth := lipgloss.Width(helpLine); helpWidth < m.maxContentWidth {
			helpLine += strings.Repeat(" ", m.maxContentWidth-helpWidth)
		}
		b.WriteString(helpLine)

	case detailStateError:
		writeErrorView(&b, m.styles, "Game Details", m.errMsg, "b: Back  Esc: Menu")
	}

	content := b.String()
	return transmit + centerContent(content, width, height)
}

// wrapText wraps text to the specified width.
func wrapText(text string, width int) []string {
	var lines []string
	paragraphs := strings.Split(text, "\n")

	for _, para := range paragraphs {
		if para == "" {
			lines = append(lines, "")
			continue
		}

		// 引用プレフィックス（"│ " の繰り返し）を検出
		prefix := ""
		rest := para
		for strings.HasPrefix(rest, "│ ") {
			prefix += "│ "
			rest = rest[len("│ "):]
		}

		effectiveWidth := width - len(prefix)
		if effectiveWidth < 10 {
			effectiveWidth = 10
		}

		words := strings.Fields(rest)
		if len(words) == 0 {
			lines = append(lines, prefix)
			continue
		}

		currentLine := words[0]
		for _, word := range words[1:] {
			if len(currentLine)+1+len(word) <= effectiveWidth {
				currentLine += " " + word
			} else {
				lines = append(lines, prefix+currentLine)
				currentLine = word
			}
		}
		lines = append(lines, prefix+currentLine)
	}

	return lines
}

// complexityLabel returns a human-readable complexity label for the given weight.
func complexityLabel(weight float64) string {
	switch {
	case weight < 1.0:
		return "Light"
	case weight < 2.0:
		return "Medium Light"
	case weight < 3.0:
		return "Medium"
	case weight < 4.0:
		return "Medium Heavy"
	default:
		return "Heavy"
	}
}

// formatNumber formats an integer with comma separators (e.g. 123456 -> "123,456").
func formatNumber(n int) string {
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	var result []byte
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			result = append(result, ',')
		}
		result = append(result, byte(c))
	}
	return string(result)
}

// renderPlayerCountPoll renders a table showing votes for suggested number of players.
func renderPlayerCountPoll(poll *bgg.PlayerCountPoll) []string {
	if poll.TotalVotes == 0 {
		return nil
	}

	// Pre-compute formatted strings per row to determine column widths
	type rowData struct {
		numPlayers string
		bestStr    string
		recStr     string
		notRecStr  string
		icon       string
	}

	var rows []rowData
	for _, r := range poll.Results {
		total := r.Best + r.Recommended + r.NotRecommended
		if total == 0 {
			continue
		}

		bestPct := r.Best * 100 / total
		recPct := r.Recommended * 100 / total
		notRecPct := r.NotRecommended * 100 / total

		bestStr := fmt.Sprintf("%s (%d%%)", formatNumber(r.Best), bestPct)
		recStr := fmt.Sprintf("%s (%d%%)", formatNumber(r.Recommended), recPct)
		notRecStr := fmt.Sprintf("%s (%d%%)", formatNumber(r.NotRecommended), notRecPct)

		icon := "✗"
		if r.Best >= r.Recommended && r.Best >= r.NotRecommended && r.Best > 0 {
			icon = "★ Best"
		} else if r.Recommended >= r.NotRecommended && r.Recommended > 0 {
			icon = "★"
		}

		rows = append(rows, rowData{
			numPlayers: r.NumPlayers,
			bestStr:    bestStr,
			recStr:     recStr,
			notRecStr:  notRecStr,
			icon:       icon,
		})
	}

	if len(rows) == 0 {
		return nil
	}

	// Determine column widths (minimum = header length)
	npW, bW, rW, nrW := 2, 4, 3, 7 // "  ", "Best", "Rec", "Not Rec"
	for _, rd := range rows {
		if len(rd.numPlayers) > npW {
			npW = len(rd.numPlayers)
		}
		if len(rd.bestStr) > bW {
			bW = len(rd.bestStr)
		}
		if len(rd.recStr) > rW {
			rW = len(rd.recStr)
		}
		if len(rd.notRecStr) > nrW {
			nrW = len(rd.notRecStr)
		}
	}

	// Build table lines
	var lines []string

	// Top border
	top := fmt.Sprintf("  ┌%s┬%s┬%s┬%s┐",
		strings.Repeat("─", npW+2), strings.Repeat("─", bW+2),
		strings.Repeat("─", rW+2), strings.Repeat("─", nrW+2))
	lines = append(lines, top)

	// Header
	header := fmt.Sprintf("  │ %*s │ %*s │ %*s │ %*s │",
		npW, "", bW, "Best", rW, "Rec", nrW, "Not Rec")
	lines = append(lines, header)

	// Separator
	sep := fmt.Sprintf("  ├%s┼%s┼%s┼%s┤",
		strings.Repeat("─", npW+2), strings.Repeat("─", bW+2),
		strings.Repeat("─", rW+2), strings.Repeat("─", nrW+2))
	lines = append(lines, sep)

	// Data rows
	for _, rd := range rows {
		line := fmt.Sprintf("  │ %*s │ %*s │ %*s │ %*s │ %s",
			npW, rd.numPlayers, bW, rd.bestStr, rW, rd.recStr, nrW, rd.notRecStr, rd.icon)
		lines = append(lines, line)
	}

	// Bottom border
	bottom := fmt.Sprintf("  └%s┴%s┴%s┴%s┘",
		strings.Repeat("─", npW+2), strings.Repeat("─", bW+2),
		strings.Repeat("─", rW+2), strings.Repeat("─", nrW+2))
	lines = append(lines, bottom)

	return lines
}

// openBrowser opens the specified URL in the default browser.
func openBrowser(url string) {
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "linux":
		cmd = exec.Command("xdg-open", url)
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		return
	}

	cmd.Start()
}
