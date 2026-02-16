package tui

import "testing"

func TestDetailVisibleLines(t *testing.T) {
	tests := []struct {
		name       string
		viewHeight int
		want       int
	}{
		{"normal height", 30, 24},
		{"small height", 10, 4},
		{"very small height", 5, 1},
		{"zero height", 0, 1},
		{"negative result clamped", 3, 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m := detailModel{viewHeight: tt.viewHeight}
			got := m.visibleLines()
			if got != tt.want {
				t.Errorf("visibleLines() with viewHeight=%d = %d, want %d", tt.viewHeight, got, tt.want)
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
