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
	"github.com/mattn/go-runewidth"
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
var TransitionNames = []string{"none", "fade", "typing", "glitch", "dissolve", "sweep", "lines", "lines-cross"}

// SelectionNames lists all available selection animation types for cycling in settings.
var SelectionNames = []string{"none", "wave", "blink", "glitch"}

var ansiRegex = regexp.MustCompile(`\x1b\[[0-9;]*m`)

// stripAnsi removes ANSI escape sequences from a string.
func stripAnsi(str string) string {
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
	case "dissolve":
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionDissolve(content, progress)
	case "sweep":
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionSweep(content, progress)
	case "lines":
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionLines(content, progress, false)
	case "lines-cross":
		progress := float64(t.frame) / float64(t.maxFrame)
		return renderTransitionLines(content, progress, true)
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

// easeOutQuad applies quadratic ease-out: fast start, slow finish.
func easeOutQuad(t float64) float64 {
	return 1 - (1-t)*(1-t)
}

// renderTransitionDissolve reveals characters from blank in a pseudo-random order.
// Each character has a deterministic threshold based on its position; once progress
// exceeds that threshold the real character appears, otherwise a space is shown.
func renderTransitionDissolve(content string, progress float64) string {
	lines := strings.Split(content, "\n")
	var resultLines []string
	for li, line := range lines {
		if hasKittyImage(line) {
			resultLines = append(resultLines, line)
			continue
		}
		plain := stripAnsi(line)
		var b strings.Builder
		for ci, ch := range []rune(plain) {
			threshold := float64((li*7919+ci*6271)%1000+1) / 1001.0
			if progress >= threshold {
				b.WriteRune(ch)
			} else {
				w := runewidth.RuneWidth(ch)
				for range w {
					b.WriteByte(' ')
				}
			}
		}
		resultLines = append(resultLines, b.String())
	}
	return strings.Join(resultLines, "\n")
}

// renderTransitionSweep reveals content column by column from left to right.
func renderTransitionSweep(content string, progress float64) string {
	lines := strings.Split(content, "\n")
	// Find the maximum display width across all lines.
	maxWidth := 0
	plainLines := make([]string, len(lines))
	for i, line := range lines {
		if hasKittyImage(line) {
			plainLines[i] = ""
			continue
		}
		plainLines[i] = stripAnsi(line)
		w := lipgloss.Width(plainLines[i])
		if w > maxWidth {
			maxWidth = w
		}
	}
	if maxWidth == 0 {
		return content
	}

	sweepCol := int(easeOutQuad(progress) * float64(maxWidth))
	edgeStyle := lipgloss.NewStyle().Foreground(ColorAccent)

	var resultLines []string
	for i, line := range lines {
		if hasKittyImage(line) {
			resultLines = append(resultLines, line)
			continue
		}
		plain := plainLines[i]
		runes := []rune(plain)
		var b strings.Builder
		col := 0
		for _, ch := range runes {
			w := runewidth.RuneWidth(ch)
			if col+w <= sweepCol {
				b.WriteRune(ch)
			} else if col == sweepCol && sweepCol > 0 {
				b.WriteString(edgeStyle.Render("▌"))
				for range w - 1 {
					b.WriteByte(' ')
				}
			} else {
				for range w {
					b.WriteByte(' ')
				}
			}
			col += w
		}
		// If sweepCol is beyond the line content, show the edge at the end.
		if col <= sweepCol && col < maxWidth && sweepCol > 0 {
			b.WriteString(edgeStyle.Render("▌"))
		}
		resultLines = append(resultLines, b.String())
	}
	return strings.Join(resultLines, "\n")
}

// renderTransitionLines reveals content line by line with staggered slide-in.
// If cross is true, odd lines slide from the left and even lines from the right.
func renderTransitionLines(content string, progress float64, cross bool) string {
	lines := strings.Split(content, "\n")
	totalLines := len(lines)
	if totalLines == 0 {
		return content
	}

	const stagger = 0.6

	var resultLines []string
	for i, line := range lines {
		if hasKittyImage(line) {
			resultLines = append(resultLines, line)
			continue
		}
		plain := stripAnsi(line)
		lineWidth := lipgloss.Width(plain)

		lineDelay := float64(i) / float64(totalLines) * stagger
		lp := (progress - lineDelay) / (1.0 - stagger)
		if lp < 0 {
			lp = 0
		} else if lp > 1 {
			lp = 1
		}
		lp = easeOutQuad(lp)

		if lp >= 1.0 {
			resultLines = append(resultLines, plain)
			continue
		}
		if lineWidth == 0 {
			resultLines = append(resultLines, "")
			continue
		}

		runes := []rune(plain)
		slideFromLeft := cross && i%2 == 1

		if slideFromLeft {
			// Slide from left: show the rightmost portion.
			visibleCols := int(float64(lineWidth) * lp)
			var b strings.Builder
			// Pad left with spaces.
			padWidth := lineWidth - visibleCols
			for range padWidth {
				b.WriteByte(' ')
			}
			// Show runes from the right.
			col := 0
			startCol := lineWidth - visibleCols
			for _, ch := range runes {
				w := runewidth.RuneWidth(ch)
				if col+w > startCol {
					b.WriteRune(ch)
				}
				col += w
			}
			resultLines = append(resultLines, b.String())
		} else {
			// Slide from right: show leftmost portion offset to the right.
			offset := int(float64(lineWidth) * (1.0 - lp))
			var b strings.Builder
			for range offset {
				b.WriteByte(' ')
			}
			// Show runes that fit within (lineWidth - offset) columns.
			visibleCols := lineWidth - offset
			col := 0
			for _, ch := range runes {
				w := runewidth.RuneWidth(ch)
				if col+w > visibleCols {
					break
				}
				b.WriteRune(ch)
				col += w
			}
			resultLines = append(resultLines, b.String())
		}
	}
	return strings.Join(resultLines, "\n")
}

// renderSelectionAnim dispatches to the appropriate selection animation renderer.
// Returns the text as-is if the selection type is empty, "none", or unknown.
func renderSelectionAnim(text string, selType string, frame int) string {
	if selType == "" || selType == "none" {
		return text
	}
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
