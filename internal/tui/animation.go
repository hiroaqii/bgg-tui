package tui

import (
	"fmt"
	"math"
	"math/rand"
	"regexp"
	"strings"
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

	glitchChars = []rune("@#$%&*!?░▒▓█")
)

// TransitionNames lists all available transition types for cycling in settings.
var TransitionNames = []string{"none", "fade", "typing", "glitch"}

// SelectionNames lists all available selection animation types for cycling in settings.
var SelectionNames = []string{"none", "wave", "blink", "glitch"}

// stripAnsi removes ANSI escape sequences from a string.
func stripAnsi(str string) string {
	ansiRegex := regexp.MustCompile(`\x1b\[[0-9;]*m`)
	return ansiRegex.ReplaceAllString(str, "")
}

// hasKittyImage returns true if the line contains Kitty graphics protocol
// sequences (\x1b_G) or the Kitty placeholder character (U+10EEEE).
func hasKittyImage(line string) bool {
	return strings.Contains(line, "\x1b_G") || strings.ContainsRune(line, 0x10EEEE)
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
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionFade(content, progress)
	case "typing":
		return renderTransitionTyping(content, t.frame)
	case "glitch":
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionGlitch(content, progress)
	}
	return content
}

// renderTransitionFade applies a fade-in effect using ANSI256 grayscale.
// progress goes from 0.0 (dark) to 1.0 (fully visible).
func renderTransitionFade(content string, progress float64) string {
	// Map progress to ANSI256 grayscale: 232 (darkest) to 255 (lightest)
	grayIndex := 232 + int(progress*23)
	if grayIndex > 255 {
		grayIndex = 255
	}

	color := lipgloss.Color(fmt.Sprintf("%d", grayIndex))
	style := lipgloss.NewStyle().Foreground(color)

	lines := strings.Split(content, "\n")
	var result []string
	for _, line := range lines {
		if hasKittyImage(line) {
			result = append(result, line)
			continue
		}
		plain := stripAnsi(line)
		result = append(result, style.Render(plain))
	}
	return strings.Join(result, "\n")
}

// renderTransitionGlitch randomly replaces characters with glitch symbols.
// The replacement probability decreases as progress approaches 1.0.
func renderTransitionGlitch(content string, progress float64) string {
	lines := strings.Split(content, "\n")
	glitchProb := 0.4 * (1 - progress)
	glitchStyle := lipgloss.NewStyle().Foreground(ColorAccent)

	var resultLines []string
	for _, line := range lines {
		if hasKittyImage(line) {
			resultLines = append(resultLines, line)
			continue
		}
		plain := stripAnsi(line)
		var b strings.Builder
		for _, ch := range plain {
			if ch != ' ' && rand.Float64() < glitchProb {
				b.WriteString(glitchStyle.Render(string(glitchChars[rand.Intn(len(glitchChars))])))
			} else {
				b.WriteString(string(ch))
			}
		}
		resultLines = append(resultLines, b.String())
	}
	return strings.Join(resultLines, "\n")
}

// renderTransitionTyping reveals lines top-to-bottom with a cursor on the last visible line.
func renderTransitionTyping(content string, frame int) string {
	lines := strings.Split(content, "\n")
	totalLines := len(lines)
	if totalLines == 0 {
		return content
	}

	// Number of visible lines increases with each frame
	visibleLines := frame * totalLines / 30
	if visibleLines > totalLines {
		visibleLines = totalLines
	}

	var result []string
	for i := 0; i < totalLines; i++ {
		if hasKittyImage(lines[i]) {
			result = append(result, lines[i])
			continue
		}
		if i < visibleLines {
			result = append(result, lines[i])
		} else if i == visibleLines {
			// Current line: show cursor
			result = append(result, "▌")
		} else {
			result = append(result, "")
		}
	}
	return strings.Join(result, "\n")
}

// renderSelectionAnim dispatches to the appropriate selection animation renderer.
// Returns the text as-is if the selection type is unknown or "none".
func renderSelectionAnim(text string, selType string, frame int) string {
	switch selType {
	case "wave":
		return renderSelectionWave(text, frame)
	case "blink":
		return renderSelectionBlink(text, frame)
	case "glitch":
		return renderSelectionGlitch(text, frame)
	}
	return text
}

// renderSelectionWave applies sin-based 5-color wave per character with bold.
func renderSelectionWave(text string, frame int) string {
	var b strings.Builder
	for i, ch := range text {
		wave := math.Sin(float64(frame)*0.25 + float64(i)*0.3)
		colorIdx := int((wave+1)/2*float64(len(waveColors)-1)) % len(waveColors)
		style := lipgloss.NewStyle().Foreground(waveColors[colorIdx]).Bold(true)
		b.WriteString(style.Render(string(ch)))
	}
	return b.String()
}

// renderSelectionBlink toggles between bright and dim colors with bold.
func renderSelectionBlink(text string, frame int) string {
	var color lipgloss.Color
	if (frame/10)%2 == 0 {
		color = lipgloss.Color("#F8F8F2")
	} else {
		color = lipgloss.Color("#44475A")
	}
	style := lipgloss.NewStyle().Foreground(color).Bold(true)
	return style.Render(text)
}

// renderSelectionGlitch randomly replaces 8% of characters with glitch symbols.
func renderSelectionGlitch(text string, frame int) string {
	_ = frame // used implicitly via rand
	var b strings.Builder
	for _, ch := range text {
		if ch != ' ' && rand.Float64() < 0.08 {
			style := lipgloss.NewStyle().Foreground(ColorAccent).Bold(true)
			b.WriteString(style.Render(string(glitchChars[rand.Intn(len(glitchChars))])))
		} else {
			style := lipgloss.NewStyle().Bold(true)
			b.WriteString(style.Render(string(ch)))
		}
	}
	return b.String()
}
