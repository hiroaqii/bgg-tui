package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/lipgloss"
)

// ThemePalette defines the color palette for a theme.
type ThemePalette struct {
	Primary    lipgloss.Color
	Secondary  lipgloss.Color
	Accent     lipgloss.Color
	Error      lipgloss.Color
	Muted      lipgloss.Color
	Border     lipgloss.Color
	Foreground lipgloss.Color
}

var themes = map[string]ThemePalette{
	"default": {
		Primary:    lipgloss.Color("#CBA6F7"),
		Secondary:  lipgloss.Color("#89B4FA"),
		Accent:     lipgloss.Color("#FAB387"),
		Error:      lipgloss.Color("#F38BA8"),
		Muted:      lipgloss.Color("#6C7086"),
		Border:     lipgloss.Color("#313244"),
		Foreground: lipgloss.Color("#CDD6F4"),
	},
	"blue": {
		Primary:    lipgloss.Color("#88C0D0"),
		Secondary:  lipgloss.Color("#8FBCBB"),
		Accent:     lipgloss.Color("#81A1C1"),
		Error:      lipgloss.Color("#BF616A"),
		Muted:      lipgloss.Color("#5E81AC"),
		Border:     lipgloss.Color("#3B4252"),
		Foreground: lipgloss.Color("#D8DEE9"),
	},
	"orange": {
		Primary:    lipgloss.Color("#E0944A"),
		Secondary:  lipgloss.Color("#D4A84B"),
		Accent:     lipgloss.Color("#CC8B5E"),
		Error:      lipgloss.Color("#C96B6B"),
		Muted:      lipgloss.Color("#8C7A65"),
		Border:     lipgloss.Color("#4A3D32"),
		Foreground: lipgloss.Color("#E8DDD0"),
	},
	"green": {
		Primary:    lipgloss.Color("#33FF33"),
		Secondary:  lipgloss.Color("#20C020"),
		Accent:     lipgloss.Color("#66FF66"),
		Error:      lipgloss.Color("#FF4444"),
		Muted:      lipgloss.Color("#2E8B2E"),
		Border:     lipgloss.Color("#1A3A1A"),
		Foreground: lipgloss.Color("#B8FFB8"),
	},
}

// ThemeNames is the ordered list of theme names for cycling.
var ThemeNames = []string{"default", "blue", "orange", "green"}

// Colors for the application.
var (
	ColorPrimary   = lipgloss.Color("#7C3AED")
	ColorSecondary = lipgloss.Color("#10B981")
	ColorAccent    = lipgloss.Color("#F59E0B")
	ColorError     = lipgloss.Color("#EF4444")
	ColorMuted     = lipgloss.Color("#6B7280")
	ColorBorder    = lipgloss.Color("#374151")
)

// ApplyTheme updates the package-level color variables based on the theme.
func ApplyTheme(theme string) {
	palette, ok := themes[theme]
	if !ok {
		palette = themes["default"]
	}
	ColorPrimary = palette.Primary
	ColorSecondary = palette.Secondary
	ColorAccent = palette.Accent
	ColorError = palette.Error
	ColorMuted = palette.Muted
	ColorBorder = palette.Border
}

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
	Rating        lipgloss.Style
	Rank          lipgloss.Style
	Players       lipgloss.Style
	Time          lipgloss.Style
	Label         lipgloss.Style
}

// NewStyles returns styles for the application based on the given theme.
func NewStyles(theme string) Styles {
	ApplyTheme(theme)

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
			Padding(1, 3),

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
	}
}

func newFilterInput() textinput.Model {
	ti := textinput.New()
	ti.Placeholder = "type to filter..."
	ti.CharLimit = 50
	ti.Width = 30
	return ti
}

// BorderStyleNames lists all available border styles for cycling in settings.
var BorderStyleNames = []string{"none", "rounded", "thick", "double", "block"}

// renderView wraps content in a border (if borderStyle is not "none") and centers it.
func renderView(content string, styles Styles, width, height int, borderStyle string) string {
	if border, ok := borderForStyle(borderStyle); ok {
		content = lipgloss.NewStyle().
			Border(border).
			BorderForeground(ColorMuted).
			Padding(1, 3).
			Render(content)
	}
	return centerContent(content, width, height)
}

// borderForStyle returns the lipgloss.Border for the given style name.
func borderForStyle(name string) (lipgloss.Border, bool) {
	switch name {
	case "rounded":
		return lipgloss.RoundedBorder(), true
	case "thick":
		return lipgloss.ThickBorder(), true
	case "double":
		return lipgloss.DoubleBorder(), true
	case "block":
		return lipgloss.BlockBorder(), true
	}
	return lipgloss.Border{}, false
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

	// Ensure output is exactly `height` lines (truncate excess, pad shortfall)
	resultLines := strings.Split(result, "\n")
	if len(resultLines) > height {
		resultLines = resultLines[:height]
	}
	for len(resultLines) < height {
		resultLines = append(resultLines, "")
	}
	// Pad each line to full width to clear previous screen content
	for i, line := range resultLines {
		if w := lipgloss.Width(line); w < width {
			resultLines[i] = line + strings.Repeat(" ", width-w)
		}
	}
	return strings.Join(resultLines, "\n")
}
