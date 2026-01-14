package tui

import "github.com/charmbracelet/lipgloss"

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
