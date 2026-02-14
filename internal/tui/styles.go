package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/lipgloss"
)

// Colors for the application.
var (
	ColorPrimary   = lipgloss.Color("#7C3AED") // Purple
	ColorSecondary = lipgloss.Color("#10B981") // Green
	ColorAccent    = lipgloss.Color("#F59E0B") // Amber
	ColorError     = lipgloss.Color("#EF4444") // Red
	ColorMuted     = lipgloss.Color("#6B7280") // Gray
	ColorBorder    = lipgloss.Color("#374151") // Dark gray
)

// Styles contains all the styles used in the application.
type Styles struct {
	Title         lipgloss.Style
	Subtitle      lipgloss.Style
	MenuItem      lipgloss.Style
	MenuItemFocus lipgloss.Style
	ListItem      lipgloss.Style
	ListItemFocus lipgloss.Style
	Help          lipgloss.Style
	Error         lipgloss.Style
	Loading       lipgloss.Style
	Border        lipgloss.Style
	Badge         lipgloss.Style
	Rating        lipgloss.Style
	Rank          lipgloss.Style
	Players       lipgloss.Style
	Time          lipgloss.Style
	Label         lipgloss.Style
	Value         lipgloss.Style
}

// DefaultStyles returns the default styles for the application.
func DefaultStyles() Styles {
	return Styles{
		Title: lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorPrimary).
			MarginBottom(1),

		Subtitle: lipgloss.NewStyle().
			Foreground(ColorMuted).
			Italic(true),

		MenuItem: lipgloss.NewStyle().
			PaddingLeft(2),

		MenuItemFocus: lipgloss.NewStyle().
			PaddingLeft(2).
			Foreground(ColorPrimary).
			Bold(true),

		ListItem: lipgloss.NewStyle().
			PaddingLeft(2),

		ListItemFocus: lipgloss.NewStyle().
			PaddingLeft(2).
			Foreground(ColorSecondary).
			Bold(true),

		Help: lipgloss.NewStyle().
			Foreground(ColorMuted).
			MarginTop(1),

		Error: lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true),

		Loading: lipgloss.NewStyle().
			Foreground(ColorAccent).
			Italic(true),

		Border: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorBorder).
			Padding(1),

		Badge: lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")).
			Background(ColorPrimary).
			Padding(0, 1),

		Rating: lipgloss.NewStyle().
			Foreground(ColorAccent),

		Rank: lipgloss.NewStyle().
			Foreground(ColorSecondary),

		Players: lipgloss.NewStyle().
			Foreground(ColorPrimary),

		Time: lipgloss.NewStyle().
			Foreground(ColorMuted),

		Label: lipgloss.NewStyle().
			Foreground(ColorMuted).
			Width(12),

		Value: lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")),
	}
}

func newFilterInput() textinput.Model {
	ti := textinput.New()
	ti.Placeholder = "type to filter..."
	ti.CharLimit = 50
	ti.Width = 30
	return ti
}

// centerContent centers the content both horizontally and vertically within the given dimensions.
func centerContent(content string, width, height int) string {
	contentHeight := strings.Count(content, "\n") + 1

	// Vertical padding (1/3 from top)
	topPadding := (height - contentHeight) / 3
	if topPadding < 0 {
		topPadding = 0
	}

	// Find max width of content
	lines := strings.Split(content, "\n")
	maxWidth := 0
	for _, line := range lines {
		if w := lipgloss.Width(line); w > maxWidth {
			maxWidth = w
		}
	}

	// Horizontal centering
	leftPadding := (width - maxWidth) / 2
	if leftPadding < 0 {
		leftPadding = 0
	}

	// Apply padding to all lines
	var centered []string
	for _, line := range lines {
		centered = append(centered, strings.Repeat(" ", leftPadding)+line)
	}

	result := strings.Repeat("\n", topPadding) + strings.Join(centered, "\n")
	return lipgloss.NewStyle().Width(width).Height(height).Render(result)
}
