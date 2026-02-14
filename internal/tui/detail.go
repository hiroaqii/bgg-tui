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
	gameID     int
	game       *bgg.Game
	errMsg     string
	scroll     int
	maxScroll  int
	descLines  []string // Pre-wrapped description lines
	wantsBack  bool
	wantsForum bool // Navigate to forum view

	// Image fields
	imageEnabled   bool
	imgTransmit    string // Kitty APC transmit sequence
	imgPlaceholder string // Unicode placeholder grid
	imgLoading     bool
	imgCols        int
	imgRows        int
	cache          *imageCache
}

// detailResultMsg is sent when game details are received.
type detailResultMsg struct {
	game *bgg.Game
	err  error
}

func newDetailModel(gameID int, styles Styles, keys KeyMap, imgEnabled bool, cache *imageCache) detailModel {
	return detailModel{
		state:        detailStateLoading,
		styles:       styles,
		keys:         keys,
		gameID:       gameID,
		imageEnabled: imgEnabled,
		imgCols:      20,
		imgRows:      10,
		cache:        cache,
	}
}

func (m detailModel) loadGame(client *bgg.Client) tea.Cmd {
	return func() tea.Msg {
		if client == nil {
			return detailResultMsg{err: fmt.Errorf("API token not configured. Please set your token in Settings.")}
		}
		game, err := client.GetGame(m.gameID)
		return detailResultMsg{game: game, err: err}
	}
}

func (m detailModel) loadImage(url string) tea.Cmd {
	return func() tea.Msg {
		path, err := m.cache.Download(url)
		if err != nil {
			return imageLoadedMsg{url: url, err: err}
		}

		cellW, cellH := termCellSize()
		pixW := m.imgCols * cellW
		pixH := m.imgRows * cellH

		img, err := loadAndResize(path, pixW, pixH)
		if err != nil {
			return imageLoadedMsg{url: url, err: err}
		}

		// Compute actual placeholder size from resized image bounds
		bounds := img.Bounds()
		actualCols := (bounds.Dx() + cellW - 1) / cellW
		actualRows := (bounds.Dy() + cellH - 1) / cellH
		if actualCols < 1 {
			actualCols = 1
		}
		if actualRows < 1 {
			actualRows = 1
		}

		const imageID uint32 = 1
		transmit, err := kittyTransmitString(img, imageID)
		if err != nil {
			return imageLoadedMsg{url: url, err: err}
		}

		placeholder := kittyPlaceholder(imageID, actualRows, actualCols)

		return imageLoadedMsg{url: url, imgTransmit: transmit, imgPlaceholder: placeholder}
	}
}

func (m detailModel) Update(msg tea.Msg) (detailModel, tea.Cmd) {
	switch m.state {
	case detailStateLoading:
		switch msg := msg.(type) {
		case detailResultMsg:
			if msg.err != nil {
				m.state = detailStateError
				m.errMsg = msg.err.Error()
				return m, nil
			}

			m.state = detailStateResults
			m.game = msg.game
			m.scroll = 0

			// Pre-calculate description lines and max scroll
			desc := msg.game.Description
			if desc == "" {
				desc = "No description available."
			}
			m.descLines = wrapText(desc, 60)
			visibleLines := 8
			m.maxScroll = len(m.descLines) - visibleLines
			if m.maxScroll < 0 {
				m.maxScroll = 0
			}

			// Start image loading if enabled
			if m.imageEnabled && m.cache != nil && msg.game.Image != "" {
				m.imgLoading = true
				return m, m.loadImage(msg.game.Image)
			}
		}
		return m, nil

	case detailStateResults:
		switch msg := msg.(type) {
		case imageLoadedMsg:
			m.imgLoading = false
			if msg.err == nil {
				m.imgTransmit = msg.imgTransmit
				m.imgPlaceholder = msg.imgPlaceholder
			}
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
			case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
				m.wantsBack = true
			}
		}
		return m, nil

	case detailStateError:
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

func (m detailModel) View(width, height int) string {
	var b strings.Builder
	var transmit string

	switch m.state {
	case detailStateLoading:
		b.WriteString(m.styles.Title.Render("Game Details"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Loading.Render("Loading..."))

	case detailStateResults:
		game := m.game

		// Title
		b.WriteString(m.styles.Title.Render(game.Name))
		b.WriteString("\n\n")

		// Image
		if m.imgTransmit != "" {
			transmit = m.imgTransmit
			b.WriteString(m.imgPlaceholder)
			b.WriteString("\n")
		} else if m.imgLoading {
			b.WriteString(m.styles.Loading.Render("Loading image..."))
			b.WriteString("\n\n")
		}

		// Basic info
		lines := []string{}

		// Year
		year := game.Year
		if year == "" {
			year = "N/A"
		}
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Year"), year))

		// Rating
		ratingStr := "N/A"
		if game.Rating > 0 {
			ratingStr = fmt.Sprintf("%.2f (%d votes)", game.Rating, game.UsersRated)
		}
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Rating"), m.styles.Rating.Render(ratingStr)))

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
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Players"), m.styles.Players.Render(playersStr)))

		// Playing time
		timeStr := fmt.Sprintf("%d min", game.PlayingTime)
		if game.MinPlayTime != game.MaxPlayTime {
			timeStr = fmt.Sprintf("%d-%d min", game.MinPlayTime, game.MaxPlayTime)
		}
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Time"), m.styles.Time.Render(timeStr)))

		// Weight
		weightStr := "N/A"
		if game.Weight > 0 {
			weightStr = fmt.Sprintf("%.2f / 5", game.Weight)
		}
		lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Weight"), weightStr))

		// Designers
		if len(game.Designers) > 0 {
			lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Designer"), strings.Join(game.Designers, ", ")))
		}

		// Categories
		if len(game.Categories) > 0 {
			lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Categories"), strings.Join(game.Categories, ", ")))
		}

		// Mechanics
		if len(game.Mechanics) > 0 {
			lines = append(lines, fmt.Sprintf("%s %s", m.styles.Label.Render("Mechanics"), strings.Join(game.Mechanics, ", ")))
		}

		for _, line := range lines {
			b.WriteString(line)
			b.WriteString("\n")
		}

		// Description
		b.WriteString("\n")
		b.WriteString(m.styles.Subtitle.Render("Description"))
		b.WriteString("\n")

		// Use pre-calculated description lines
		visibleLines := 8
		start := m.scroll
		end := start + visibleLines
		if end > len(m.descLines) {
			end = len(m.descLines)
		}

		for i := start; i < end; i++ {
			b.WriteString(m.descLines[i])
			b.WriteString("\n")
		}

		if m.maxScroll > 0 {
			b.WriteString(m.styles.Subtitle.Render(fmt.Sprintf("(%d/%d)", m.scroll+1, m.maxScroll+1)))
			b.WriteString("\n")
		}

		b.WriteString("\n")
		b.WriteString(m.styles.Help.Render("j/k: Scroll  o: Open BGG  f: Forum  b: Back"))

	case detailStateError:
		b.WriteString(m.styles.Title.Render("Game Details"))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Error.Render("Error: " + m.errMsg))
		b.WriteString("\n\n")
		b.WriteString(m.styles.Help.Render("b: Back"))
	}

	content := b.String()
	return transmit + lipgloss.NewStyle().Width(width).Height(height).Padding(2, 4).Render(content)
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

		words := strings.Fields(para)
		if len(words) == 0 {
			lines = append(lines, "")
			continue
		}

		currentLine := words[0]
		for _, word := range words[1:] {
			if len(currentLine)+1+len(word) <= width {
				currentLine += " " + word
			} else {
				lines = append(lines, currentLine)
				currentLine = word
			}
		}
		lines = append(lines, currentLine)
	}

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
