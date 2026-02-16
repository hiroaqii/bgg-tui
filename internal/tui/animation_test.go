package tui

import "testing"

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
