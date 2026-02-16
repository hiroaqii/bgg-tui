package tui

import (
	"strings"
	"testing"
)

func TestErrNoToken(t *testing.T) {
	if errNoToken != "API token not configured. Please set your token in Settings." {
		t.Errorf("errNoToken = %q, unexpected value", errNoToken)
	}
}

func TestTruncateName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		maxWidth int
		want     string
	}{
		{"short ASCII", "Hello", 10, "Hello"},
		{"exact fit", "Hello", 5, "Hello"},
		{"truncated ASCII", "Hello World Test", 10, "Hello W..."},
		{"empty string", "", 10, ""},
		{"Japanese text under limit", "カタン", 10, "カタン"},
		{"Japanese text over limit", "カタンの開拓者たち", 10, "カタン..."},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := truncateName(tt.input, tt.maxWidth)
			if got != tt.want {
				t.Errorf("truncateName(%q, %d) = %q, want %q", tt.input, tt.maxWidth, got, tt.want)
			}
		})
	}
}

func TestCalcListRange(t *testing.T) {
	tests := []struct {
		name       string
		cursor     int
		totalItems int
		height     int
		density    string
		wantStart  int
		wantEnd    int
	}{
		{"beginning of list", 0, 50, 30, "normal", 0, 18},
		{"middle scroll", 20, 50, 30, "normal", 3, 21},
		{"short list", 2, 5, 30, "normal", 0, 5},
		{"compact density", 0, 50, 20, "compact", 0, 12},
		{"relaxed density", 0, 50, 30, "relaxed", 0, 14},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			start, end := calcListRange(tt.cursor, tt.totalItems, tt.height, tt.density)
			if start != tt.wantStart || end != tt.wantEnd {
				t.Errorf("calcListRange(%d, %d, %d, %q) = (%d, %d), want (%d, %d)",
					tt.cursor, tt.totalItems, tt.height, tt.density, start, end, tt.wantStart, tt.wantEnd)
			}
		})
	}
}

func TestCalcListRangeMultiLine(t *testing.T) {
	tests := []struct {
		name         string
		cursor       int
		totalItems   int
		height       int
		density      string
		linesPerItem int
		wantStart    int
		wantEnd      int
	}{
		{"2-line items beginning", 0, 48, 30, "normal", 2, 0, 9},
		{"2-line items middle scroll", 15, 48, 30, "normal", 2, 7, 16},
		{"2-line items short list", 2, 5, 30, "normal", 2, 0, 5},
		{"2-line items small height", 0, 48, 10, "normal", 2, 0, 1},
		{"1-line matches calcListRange", 0, 50, 30, "normal", 1, 0, 18},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			start, end := calcListRangeMultiLine(tt.cursor, tt.totalItems, tt.height, tt.density, tt.linesPerItem)
			if start != tt.wantStart || end != tt.wantEnd {
				t.Errorf("calcListRangeMultiLine(%d, %d, %d, %q, %d) = (%d, %d), want (%d, %d)",
					tt.cursor, tt.totalItems, tt.height, tt.density, tt.linesPerItem, start, end, tt.wantStart, tt.wantEnd)
			}
		})
	}
}

func TestRenderListItem(t *testing.T) {
	styles := NewStyles("default")

	t.Run("selected item", func(t *testing.T) {
		prefix, _ := renderListItem(3, 3, "Game Name", styles, "none", 0)
		if prefix != "> " {
			t.Errorf("prefix = %q, want %q", prefix, "> ")
		}
	})

	t.Run("non-selected item", func(t *testing.T) {
		prefix, rendered := renderListItem(1, 3, "Game Name", styles, "none", 0)
		if prefix != "  " {
			t.Errorf("prefix = %q, want %q", prefix, "  ")
		}
		if !strings.Contains(rendered, "Game Name") {
			t.Errorf("rendered = %q, should contain %q", rendered, "Game Name")
		}
	})
}

func TestWriteLoadingView(t *testing.T) {
	styles := NewStyles("default")
	var b strings.Builder
	writeLoadingView(&b, styles, "Test Title", "Loading...")
	output := b.String()

	if !strings.Contains(output, "Test Title") {
		t.Error("writeLoadingView output should contain the title")
	}
	if !strings.Contains(output, "Loading...") {
		t.Error("writeLoadingView output should contain the message")
	}
}

func TestWriteErrorView(t *testing.T) {
	styles := NewStyles("default")
	var b strings.Builder
	writeErrorView(&b, styles, "Test Title", "something failed", "Retry")
	output := b.String()

	if !strings.Contains(output, "Test Title") {
		t.Error("writeErrorView output should contain the title")
	}
	if !strings.Contains(output, "something failed") {
		t.Error("writeErrorView output should contain the error message")
	}
	if !strings.Contains(output, "Retry") {
		t.Error("writeErrorView output should contain the help text")
	}
}
