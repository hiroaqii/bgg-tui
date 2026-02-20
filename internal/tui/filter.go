package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// filterState provides generic filter-as-you-type functionality for list views.
type filterState[T any] struct {
	items    []T // full item list (set externally)
	filtered []T // nil when not filtering
	active   bool
	input    textinput.Model
	cursor   int
	getName  func(T) string // returns the filterable name for an item
	getID    func(T) int    // returns the selectable ID for an item
}

// filterResult is returned by updateFilter to signal actions to the caller.
type filterResult int

const (
	filterNone     filterResult = iota
	filterSelected              // user pressed Enter on a filtered item
	filterExited                // user pressed Escape to clear filter
)

// startFilter begins a new filter session, copying all items into filtered.
func (f *filterState[T]) startFilter() tea.Cmd {
	f.active = true
	f.input = newFilterInput()
	f.input.Focus()
	f.filtered = make([]T, len(f.items))
	copy(f.filtered, f.items)
	f.cursor = 0
	return textinput.Blink
}

// clearFilter exits filter mode and resets state.
func (f *filterState[T]) clearFilter() {
	f.active = false
	f.filtered = nil
	f.input.SetValue("")
	f.cursor = 0
}

// displayItems returns the filtered list if active, otherwise the full list.
func (f *filterState[T]) displayItems() []T {
	if f.active || f.filtered != nil {
		return f.filtered
	}
	return f.items
}

// selectedID returns the ID of the item at the current cursor position, or nil.
func (f *filterState[T]) selectedID() *int {
	items := f.displayItems()
	if f.cursor >= 0 && f.cursor < len(items) {
		id := f.getID(items[f.cursor])
		return &id
	}
	return nil
}

// moveCursorUp moves the cursor one position up, clamping at 0.
func (f *filterState[T]) moveCursorUp() {
	if f.cursor > 0 {
		f.cursor--
	}
}

// moveCursorDown moves the cursor one position down, clamping at the last item.
func (f *filterState[T]) moveCursorDown() {
	items := f.displayItems()
	if f.cursor < len(items)-1 {
		f.cursor++
	}
}

// updateFilter handles key input while filter mode is active.
// Returns the result type and any tea.Cmd.
// The caller is responsible for handling thumb loading after cursor changes.
func (f *filterState[T]) updateFilter(msg tea.Msg, keys KeyMap) (filterResult, bool, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			f.clearFilter()
			return filterExited, true, nil
		case key.Matches(msg, keys.Enter):
			return filterSelected, true, nil
		case msg.String() == "up":
			f.moveCursorUp()
			return filterNone, true, nil
		case msg.String() == "down":
			f.moveCursorDown()
			return filterNone, true, nil
		}
	}

	// Update text input and recompute filtered list
	var cmd tea.Cmd
	f.input, cmd = f.input.Update(msg)
	query := strings.ToLower(f.input.Value())
	f.filtered = nil
	for _, item := range f.items {
		if strings.Contains(strings.ToLower(f.getName(item)), query) {
			f.filtered = append(f.filtered, item)
		}
	}
	if f.cursor >= len(f.filtered) {
		f.cursor = max(0, len(f.filtered)-1)
	}
	return filterNone, false, cmd
}
