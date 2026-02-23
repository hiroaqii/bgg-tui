package tui

import "github.com/charmbracelet/bubbles/key"

// KeyMap defines the key bindings for the application.
type KeyMap struct {
	Up       key.Binding
	Down     key.Binding
	Enter    key.Binding
	Back     key.Binding
	Escape   key.Binding
	Quit     key.Binding
	Help     key.Binding
	Search   key.Binding
	Hot      key.Binding
	Collect  key.Binding
	Settings key.Binding
	NextPage key.Binding
	PrevPage key.Binding
	Forum    key.Binding
	Open     key.Binding
	Refresh  key.Binding
	User     key.Binding
	Filter   key.Binding
	StatusFilter key.Binding
}

// DefaultKeyMap returns the default key bindings.
func DefaultKeyMap() KeyMap {
	return KeyMap{
		Up: key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("k/up", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("j/down", "down"),
		),
		Enter: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("enter", "select"),
		),
		Back: key.NewBinding(
			key.WithKeys("backspace", "b"),
			key.WithHelp("b", "back"),
		),
		Escape: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "menu"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		Search: key.NewBinding(
			key.WithKeys("2", "s"),
			key.WithHelp("2/s", "search"),
		),
		Hot: key.NewBinding(
			key.WithKeys("1"),
			key.WithHelp("1", "hot"),
		),
		Collect: key.NewBinding(
			key.WithKeys("3"),
			key.WithHelp("3", "collection"),
		),
		Settings: key.NewBinding(
			key.WithKeys("4"),
			key.WithHelp("4", "settings"),
		),
		NextPage: key.NewBinding(
			key.WithKeys("n"),
			key.WithHelp("n", "next page"),
		),
		PrevPage: key.NewBinding(
			key.WithKeys("p"),
			key.WithHelp("p", "prev page"),
		),
		Forum: key.NewBinding(
			key.WithKeys("f"),
			key.WithHelp("f", "forum"),
		),
		Open: key.NewBinding(
			key.WithKeys("o"),
			key.WithHelp("o", "open in browser"),
		),
		Refresh: key.NewBinding(
			key.WithKeys("r"),
			key.WithHelp("r", "refresh"),
		),
		User: key.NewBinding(
			key.WithKeys("u"),
			key.WithHelp("u", "change user"),
		),
		Filter: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "filter"),
		),
		StatusFilter: key.NewBinding(
			key.WithKeys("s"),
			key.WithHelp("s", "status filter"),
		),
	}
}

// ShortHelp returns the short help text for the key bindings.
func (k KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Enter, k.Back, k.Quit}
}

// FullHelp returns the full help text for the key bindings.
func (k KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Enter, k.Back},
		{k.Search, k.Hot, k.Collect, k.Settings},
		{k.NextPage, k.PrevPage, k.Forum, k.Open},
		{k.Refresh, k.Filter, k.StatusFilter, k.Help, k.Quit},
	}
}
