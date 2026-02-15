package tui

import (
	"regexp"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Animation tick interval (~15 fps).
const animTickInterval = 66 * time.Millisecond

// animTickMsg is sent on every animation tick.
type animTickMsg time.Time

// animTickCmd returns a tea.Cmd that sends an animTickMsg after animTickInterval.
func animTickCmd() tea.Cmd {
	return tea.Tick(animTickInterval, func(t time.Time) tea.Msg {
		return animTickMsg(t)
	})
}

// Color palettes for animations.
var (
	waveColors = []lipgloss.Color{
		"#FF6B6B", "#FFE66D", "#4ECDC4", "#45B7D1", "#96CEB4",
	}

	rainbowColors = []lipgloss.Color{
		"#FF0000", "#FF7F00", "#FFFF00", "#00FF00", "#0000FF", "#4B0082", "#9400D3",
	}

	glitchChars = []rune("@#$%&*!?░▒▓█")
)

// TransitionNames lists all available transition types for cycling in settings.
var TransitionNames = []string{"none", "fade", "typing", "wave", "glitch", "rainbow", "blink"}

// SelectionNames lists all available selection animation types for cycling in settings.
var SelectionNames = []string{"none", "rainbow", "wave", "blink", "glitch"}

// stripAnsi removes ANSI escape sequences from a string.
func stripAnsi(str string) string {
	ansiRegex := regexp.MustCompile(`\x1b\[[0-9;]*m`)
	return ansiRegex.ReplaceAllString(str, "")
}

// transitionState holds the state of an active view transition.
type transitionState struct {
	active   bool
	name     string
	frame    int
	maxFrame int
	oldView  string // rendered content of the previous view
}

// startTransition creates a new transitionState for the given transition type.
func startTransition(name string, oldView string) transitionState {
	if name == "" || name == "none" {
		return transitionState{}
	}
	return transitionState{
		active:   true,
		name:     name,
		frame:    0,
		maxFrame: 15,
		oldView:  oldView,
	}
}

// renderTransition dispatches to the appropriate transition renderer.
// Returns the content as-is if the transition type is unknown.
func renderTransition(content string, t transitionState) string {
	switch t.name {
	case "fade":
		// T05
	case "typing":
		// T06
	case "wave":
		// T07
	case "glitch":
		// T08
	case "rainbow":
		// T09
	case "blink":
		// T10
	}
	return content
}

// renderSelectionAnim dispatches to the appropriate selection animation renderer.
// Returns the text as-is if the selection type is unknown or "none".
func renderSelectionAnim(text string, selType string, frame int) string {
	switch selType {
	case "rainbow":
		// T11
	case "wave":
		// T12
	case "blink":
		// T13
	case "glitch":
		// T14
	}
	return text
}
