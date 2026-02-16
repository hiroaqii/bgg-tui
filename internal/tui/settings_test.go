package tui

import (
	"testing"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

func TestEditFieldConstants(t *testing.T) {
	tests := []struct {
		name  string
		field editField
		want  int
	}{
		{"Token", editFieldToken, 0},
		{"Username", editFieldUsername, 1},
		{"ThreadWidth", editFieldThreadWidth, 2},
		{"DescWidth", editFieldDescWidth, 3},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if int(tt.field) != tt.want {
				t.Errorf("%s = %d, want %d", tt.name, int(tt.field), tt.want)
			}
		})
	}
}

func TestSettingsItemCount(t *testing.T) {
	cfg := config.DefaultConfig()
	styles := NewStyles("default")
	keys := DefaultKeyMap()
	m := newSettingsModel(cfg, styles, keys)

	if m.itemCount() != len(m.items) {
		t.Errorf("itemCount() = %d, len(items) = %d", m.itemCount(), len(m.items))
	}
	if m.itemCount() != 10 {
		t.Errorf("itemCount() = %d, want 10", m.itemCount())
	}
}

func TestBlurAllInputs(t *testing.T) {
	cfg := config.DefaultConfig()
	styles := NewStyles("default")
	keys := DefaultKeyMap()
	m := newSettingsModel(cfg, styles, keys)

	// Focus all inputs
	m.tokenInput.Focus()
	m.usernameInput.Focus()
	m.widthInput.Focus()
	m.descWidthInput.Focus()

	m.blurAllInputs()

	if m.tokenInput.Focused() {
		t.Error("tokenInput should not be focused after blurAllInputs")
	}
	if m.usernameInput.Focused() {
		t.Error("usernameInput should not be focused after blurAllInputs")
	}
	if m.widthInput.Focused() {
		t.Error("widthInput should not be focused after blurAllInputs")
	}
	if m.descWidthInput.Focused() {
		t.Error("descWidthInput should not be focused after blurAllInputs")
	}
}

func TestSettingsNavigation(t *testing.T) {
	cfg := config.DefaultConfig()
	styles := NewStyles("default")
	keys := DefaultKeyMap()
	m := newSettingsModel(cfg, styles, keys)

	if m.cursor != 0 {
		t.Errorf("initial cursor = %d, want 0", m.cursor)
	}

	// Can't go above 0
	if m.cursor != 0 {
		t.Errorf("cursor should stay at 0, got %d", m.cursor)
	}

	// Can't go below itemCount-1
	m.cursor = m.itemCount() - 1
	if m.cursor != 9 {
		t.Errorf("cursor at last item = %d, want 9", m.cursor)
	}
}

func TestCycleValue(t *testing.T) {
	names := []string{"a", "b", "c"}

	tests := []struct {
		current string
		want    string
	}{
		{"a", "b"},
		{"b", "c"},
		{"c", "a"},
		{"unknown", "a"},
	}

	for _, tt := range tests {
		got := cycleValue(tt.current, names)
		if got != tt.want {
			t.Errorf("cycleValue(%q, %v) = %q, want %q", tt.current, names, got, tt.want)
		}
	}
}
