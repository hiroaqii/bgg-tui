package tui

import (
	"math"
	"strings"
	"testing"
)

func TestStripAnsi(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"no ansi", "hello world", "hello world"},
		{"with color", "\x1b[31mred\x1b[0m", "red"},
		{"multiple sequences", "\x1b[1;32mbold green\x1b[0m normal", "bold green normal"},
		{"empty string", "", ""},
		{"only ansi", "\x1b[0m", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := stripAnsi(tt.input)
			if got != tt.want {
				t.Errorf("stripAnsi(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestRenderSelectionAnim_Guard(t *testing.T) {
	text := "Hello World"

	tests := []struct {
		name    string
		selType string
		want    string
	}{
		{"empty string returns text as-is", "", text},
		{"none returns text as-is", "none", text},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := renderSelectionAnim(text, tt.selType, 0)
			if got != tt.want {
				t.Errorf("renderSelectionAnim(%q, %q, 0) = %q, want %q", text, tt.selType, got, tt.want)
			}
		})
	}

	// "wave" should return non-empty output containing the original text
	t.Run("wave returns non-empty", func(t *testing.T) {
		got := renderSelectionAnim(text, "wave", 0)
		stripped := stripAnsi(got)
		if stripped != text {
			t.Errorf("stripped wave output = %q, want original text %q", stripped, text)
		}
	})
}

func TestEaseOutQuad(t *testing.T) {
	tests := []struct {
		input, want float64
	}{
		{0.0, 0.0},
		{1.0, 1.0},
		{0.5, 0.75},
	}
	for _, tt := range tests {
		got := easeOutQuad(tt.input)
		if math.Abs(got-tt.want) > 1e-9 {
			t.Errorf("easeOutQuad(%v) = %v, want %v", tt.input, got, tt.want)
		}
	}
}

func TestRenderTransitionDissolve(t *testing.T) {
	content := "Hello World\nSecond Line"

	t.Run("progress 1.0 shows full content", func(t *testing.T) {
		got := renderTransitionDissolve(content, 1.0)
		if got != content {
			t.Errorf("at progress 1.0, got %q, want %q", got, content)
		}
	})

	t.Run("progress 0.0 shows only spaces", func(t *testing.T) {
		got := renderTransitionDissolve(content, 0.0)
		for _, line := range strings.Split(got, "\n") {
			if strings.TrimSpace(line) != "" {
				t.Errorf("at progress 0.0, expected blank lines, got %q", line)
			}
		}
	})

	t.Run("kitty image lines pass through", func(t *testing.T) {
		input := "Normal line\n\x1b_Gimage data\nAnother line"
		got := renderTransitionDissolve(input, 0.5)
		lines := strings.Split(got, "\n")
		if lines[1] != "\x1b_Gimage data" {
			t.Errorf("kitty image line was modified: %q", lines[1])
		}
	})
}

func TestRenderTransitionSweep(t *testing.T) {
	content := "Hello\nWorld"

	t.Run("progress 1.0 shows full content", func(t *testing.T) {
		got := renderTransitionSweep(content, 1.0)
		if stripAnsi(got) != content {
			t.Errorf("at progress 1.0, got %q, want %q", stripAnsi(got), content)
		}
	})

	t.Run("progress 0.0 shows mostly blank", func(t *testing.T) {
		got := renderTransitionSweep(content, 0.0)
		for _, line := range strings.Split(got, "\n") {
			plain := stripAnsi(line)
			trimmed := strings.TrimSpace(plain)
			// At progress 0.0, only an edge character or empty
			if len(trimmed) > 1 {
				t.Errorf("at progress 0.0, expected near-blank, got %q", plain)
			}
		}
	})

	t.Run("kitty image lines pass through", func(t *testing.T) {
		input := "Normal\n\x1b_Gimage\nEnd"
		got := renderTransitionSweep(input, 0.5)
		lines := strings.Split(got, "\n")
		if lines[1] != "\x1b_Gimage" {
			t.Errorf("kitty image line was modified: %q", lines[1])
		}
	})
}

func TestRenderTransitionLines(t *testing.T) {
	content := "Line one\nLine two\nLine three"

	t.Run("progress 1.0 shows full content", func(t *testing.T) {
		got := renderTransitionLines(content, 1.0, false)
		if got != content {
			t.Errorf("at progress 1.0, got %q, want %q", got, content)
		}
	})

	t.Run("progress 0.0 shows blank/offset lines", func(t *testing.T) {
		got := renderTransitionLines(content, 0.0, false)
		for _, line := range strings.Split(got, "\n") {
			if strings.TrimSpace(line) != "" {
				t.Errorf("at progress 0.0, expected blank lines, got %q", line)
			}
		}
	})

	t.Run("cross mode progress 1.0 shows full content", func(t *testing.T) {
		got := renderTransitionLines(content, 1.0, true)
		if got != content {
			t.Errorf("cross at progress 1.0, got %q, want %q", got, content)
		}
	})

	t.Run("kitty image lines pass through", func(t *testing.T) {
		input := "Normal\n\x1b_Gimage\nEnd"
		got := renderTransitionLines(input, 0.5, false)
		lines := strings.Split(got, "\n")
		if lines[1] != "\x1b_Gimage" {
			t.Errorf("kitty image line was modified: %q", lines[1])
		}
	})
}
