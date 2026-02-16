package tui

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestUpdateFilter_CursorMovedBehavior(t *testing.T) {
	type item struct {
		name string
		id   int
	}

	keys := DefaultKeyMap()
	f := filterState[item]{
		items: []item{
			{name: "Alpha", id: 1},
			{name: "Beta", id: 2},
			{name: "Gamma", id: 3},
		},
		getName: func(i item) string { return i.name },
		getID:   func(i item) int { return i.id },
	}
	f.startFilter()

	// Simulate pressing down arrow - should move cursor
	downMsg := tea.KeyMsg{Type: tea.KeyDown}
	result, cursorMoved, _ := f.updateFilter(downMsg, keys)

	if result != filterNone {
		t.Errorf("expected filterNone, got %d", result)
	}
	if !cursorMoved {
		t.Error("expected cursorMoved=true for down key")
	}
	if f.cursor != 1 {
		t.Errorf("expected cursor=1, got %d", f.cursor)
	}

	// Simulate typing a character - cursor not moved
	charMsg := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}}
	result2, cursorMoved2, _ := f.updateFilter(charMsg, keys)

	if result2 != filterNone {
		t.Errorf("expected filterNone, got %d", result2)
	}
	if cursorMoved2 {
		t.Error("expected cursorMoved=false for character input")
	}
}
