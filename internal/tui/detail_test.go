package tui

import (
	"testing"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

func TestDetailVisibleLines(t *testing.T) {
	tests := []struct {
		name       string
		viewHeight int
		density    string
		want       int
	}{
		{"compact density", 30, "compact", 22},
		{"normal density", 30, "normal", 18},
		{"relaxed density", 30, "relaxed", 14},
		{"small height normal", 10, "normal", 1},
		{"very small height", 5, "normal", 1},
		{"zero height", 0, "normal", 1},
		{"negative result clamped", 3, "normal", 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := config.DefaultConfig()
			cfg.Interface.ListDensity = tt.density
			m := detailModel{viewHeight: tt.viewHeight, config: cfg}
			got := m.visibleLines()
			if got != tt.want {
				t.Errorf("visibleLines() with viewHeight=%d density=%s = %d, want %d", tt.viewHeight, tt.density, got, tt.want)
			}
		})
	}
}

func TestWrapTextQuotePrefix(t *testing.T) {
	tests := []struct {
		name  string
		text  string
		width int
		want  []string
	}{
		{
			name:  "no prefix wraps normally",
			text:  "The quick brown fox jumps over the lazy dog",
			width: 20,
			want:  []string{"The quick brown fox", "jumps over the lazy", "dog"},
		},
		{
			name:  "single quote prefix preserved on wrap",
			text:  "│ The quick brown fox jumps over the lazy dog",
			width: 25,
			want:  []string{"│ The quick brown fox", "│ jumps over the lazy", "│ dog"},
		},
		{
			name:  "nested quote prefix preserved on wrap",
			text:  "│ │ The quick brown fox jumps over the lazy dog",
			width: 30,
			want:  []string{"│ │ The quick brown fox", "│ │ jumps over the lazy", "│ │ dog"},
		},
		{
			name:  "short quoted line no wrap needed",
			text:  "│ short",
			width: 80,
			want:  []string{"│ short"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := wrapText(tt.text, tt.width)
			if len(got) != len(tt.want) {
				t.Errorf("line count mismatch:\n  got  (%d): %q\n  want (%d): %q", len(got), got, len(tt.want), tt.want)
				return
			}
			for i := range tt.want {
				if got[i] != tt.want[i] {
					t.Errorf("line %d mismatch:\n  got:  %q\n  want: %q", i, got[i], tt.want[i])
				}
			}
		})
	}
}

func TestDetailImageConstants(t *testing.T) {
	if detailImageID != 1 {
		t.Errorf("detailImageID = %d, want 1", detailImageID)
	}
	if detailImageCols != 20 {
		t.Errorf("detailImageCols = %d, want 20", detailImageCols)
	}
	if detailImageRows != 10 {
		t.Errorf("detailImageRows = %d, want 10", detailImageRows)
	}
}
