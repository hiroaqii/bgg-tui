package tui

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

// editField identifies which text input field is being edited.
type editField int

const (
	editFieldToken editField = iota
	editFieldUsername
	editFieldThreadWidth
	editFieldDetailWidth
)

// settingItemKind describes the interaction type for a settings item.
type settingItemKind int

const (
	settingText   settingItemKind = iota // Enter opens text input
	settingCycle                         // Enter cycles to next value
	settingToggle                        // Enter toggles boolean
	settingInfo                          // read-only display item
)

// settingItem describes a single settings menu entry.
type settingItem struct {
	label     string
	section   string          // section header (shown before this item if non-empty)
	kind      settingItemKind
	editField editField       // for settingText: which input to activate
	getValue  func() string   // current display value
	onEnter   func()          // for settingCycle/settingToggle
}

type settingsModel struct {
	cursor            int
	styles            Styles
	keys              KeyMap
	config            *config.Config
	editing           bool
	editingField      editField
	tokenInput        textinput.Model
	usernameInput     textinput.Model
	widthInput        textinput.Model
	detailWidthInput    textinput.Model
	wantsBack         bool
	wantsMenu         bool
	themeChanged      bool
	transitionChanged bool
	selectionChanged  bool
	items             []settingItem
}

func (m *settingsModel) blurAllInputs() {
	m.tokenInput.Blur()
	m.usernameInput.Blur()
	m.widthInput.Blur()
	m.detailWidthInput.Blur()
}

func newSettingsModel(cfg *config.Config, styles Styles, keys KeyMap) settingsModel {
	ti := textinput.New()
	ti.Placeholder = "Enter API token"
	ti.CharLimit = 256

	ui := textinput.New()
	ui.Placeholder = "Enter BGG username"
	ui.CharLimit = 64
	ui.SetValue(cfg.Collection.DefaultUsername)

	wi := textinput.New()
	wi.Placeholder = "Enter width (20-200)"
	wi.CharLimit = 3
	wi.SetValue(fmt.Sprintf("%d", cfg.Display.ThreadWidth))

	dwi := textinput.New()
	dwi.Placeholder = "Enter width (20-200)"
	dwi.CharLimit = 3
	dwi.SetValue(fmt.Sprintf("%d", cfg.Display.DetailWidth))

	m := settingsModel{
		cursor:         0,
		styles:         styles,
		keys:           keys,
		config:         cfg,
		tokenInput:     ti,
		usernameInput:  ui,
		widthInput:     wi,
		detailWidthInput: dwi,
	}
	m.items = m.buildItems()
	return m
}

func (m *settingsModel) buildItems() []settingItem {
	cfg := m.config
	return []settingItem{
		// Interface
		{
			label: "Color Theme", section: "Interface", kind: settingCycle,
			getValue: func() string { return cfg.Interface.ColorTheme },
			onEnter: func() {
				cfg.Interface.ColorTheme = cycleValue(cfg.Interface.ColorTheme, ThemeNames)
				cfg.Save()
			},
		},
		{
			label: "Transition", kind: settingCycle,
			getValue: func() string { return cfg.Interface.Transition },
			onEnter: func() {
				cfg.Interface.Transition = cycleValue(cfg.Interface.Transition, TransitionNames)
				cfg.Save()
			},
		},
		{
			label: "Selection", kind: settingCycle,
			getValue: func() string { return cfg.Interface.Selection },
			onEnter: func() {
				cfg.Interface.Selection = cycleValue(cfg.Interface.Selection, SelectionNames)
				cfg.Save()
			},
		},
		{
			label: "List Density", kind: settingCycle,
			getValue: func() string { return cfg.Interface.ListDensity },
			onEnter: func() {
				cfg.Interface.ListDensity = cycleValue(cfg.Interface.ListDensity, ListDensityNames)
				cfg.Save()
			},
		},
		{
			label: "Date Format", kind: settingCycle,
			getValue: func() string { return cfg.Interface.DateFormat },
			onEnter: func() {
				cfg.Interface.DateFormat = cycleValue(cfg.Interface.DateFormat, DateFormatNames)
				cfg.Save()
			},
		},
		{
			label: "Border Style", kind: settingCycle,
			getValue: func() string { return cfg.Interface.BorderStyle },
			onEnter: func() {
				cfg.Interface.BorderStyle = cycleValue(cfg.Interface.BorderStyle, BorderStyleNames)
				cfg.Save()
			},
		},
		// Display
		{
			label: "Show Images", section: "Display", kind: settingToggle,
			getValue: func() string {
				if cfg.Display.ShowImages {
					return "ON"
				}
				return "OFF"
			},
			onEnter: func() {
				cfg.Display.ShowImages = !cfg.Display.ShowImages
				cfg.Save()
			},
		},
		{
			label: "Thread Width", kind: settingText,
			editField: editFieldThreadWidth,
			getValue:  func() string { return fmt.Sprintf("%d", cfg.Display.ThreadWidth) },
		},
		{
			label: "Detail Width", kind: settingText,
			editField: editFieldDetailWidth,
			getValue:  func() string { return fmt.Sprintf("%d", cfg.Display.DetailWidth) },
		},
		// Collection
		{
			label: "Default Username", section: "Collection", kind: settingText,
			editField: editFieldUsername,
			getValue: func() string {
				if cfg.Collection.DefaultUsername != "" {
					return cfg.Collection.DefaultUsername
				}
				return "(not set)"
			},
		},
		{
			label: "Show Only Owned", kind: settingToggle,
			getValue: func() string {
				if cfg.Collection.ShowOnlyOwned {
					return "ON"
				}
				return "OFF"
			},
			onEnter: func() {
				cfg.Collection.ShowOnlyOwned = !cfg.Collection.ShowOnlyOwned
				cfg.Save()
			},
		},
		// API
		{
			label: "Token", section: "API", kind: settingText,
			editField: editFieldToken,
			getValue: func() string {
				if cfg.API.Token != "" {
					return maskToken(cfg.API.Token)
				}
				return "(not set)"
			},
		},
		{
			section: "Config File", kind: settingInfo,
			getValue: func() string {
				if p, err := config.ConfigPath(); err == nil {
					return p
				}
				return "(unknown)"
			},
		},
	}
}

func (m settingsModel) itemCount() int {
	return len(m.items)
}

// textInputForField returns a pointer to the text input model for the given editField.
func (m *settingsModel) textInputForField(field editField) *textinput.Model {
	switch field {
	case editFieldToken:
		return &m.tokenInput
	case editFieldUsername:
		return &m.usernameInput
	case editFieldThreadWidth:
		return &m.widthInput
	case editFieldDetailWidth:
		return &m.detailWidthInput
	}
	return nil
}

// saveEditField saves the current value of the active text input.
func (m *settingsModel) saveEditField() {
	switch m.editingField {
	case editFieldToken:
		val := strings.TrimSpace(m.tokenInput.Value())
		if val != "" {
			m.config.API.Token = val
		}
	case editFieldUsername:
		m.config.Collection.DefaultUsername = strings.TrimSpace(m.usernameInput.Value())
	case editFieldThreadWidth:
		if v, err := strconv.Atoi(strings.TrimSpace(m.widthInput.Value())); err == nil && v >= 20 && v <= 200 {
			m.config.Display.ThreadWidth = v
		}
	case editFieldDetailWidth:
		if v, err := strconv.Atoi(strings.TrimSpace(m.detailWidthInput.Value())); err == nil && v >= 20 && v <= 200 {
			m.config.Display.DetailWidth = v
		}
	}
	m.config.Save()
}

// startEditing activates text editing for the given field.
func (m *settingsModel) startEditing(field editField) tea.Cmd {
	m.editing = true
	m.editingField = field
	input := m.textInputForField(field)
	if field == editFieldToken {
		input.SetValue("")
	} else {
		// Pre-populate with current value from the item
		for _, item := range m.items {
			if item.kind == settingText && item.editField == field {
				input.SetValue(item.getValue())
				break
			}
		}
	}
	input.Focus()
	return textinput.Blink
}

func (m settingsModel) Update(msg tea.Msg) (settingsModel, tea.Cmd) {
	var cmd tea.Cmd

	if m.editing {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				m.saveEditField()
				m.editing = false
				m.blurAllInputs()
				return m, nil
			case key.Matches(msg, m.keys.Escape):
				m.editing = false
				m.blurAllInputs()
				return m, nil
			}
		}

		input := m.textInputForField(m.editingField)
		*input, cmd = input.Update(msg)
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keys.Up):
			if m.cursor > 0 {
				m.cursor--
			}
		case key.Matches(msg, m.keys.Down):
			if m.cursor < m.itemCount()-1 {
				m.cursor++
			}
		case key.Matches(msg, m.keys.Enter):
			item := m.items[m.cursor]
			switch item.kind {
			case settingText:
				return m, m.startEditing(item.editField)
			case settingCycle, settingToggle:
				oldTheme := m.config.Interface.ColorTheme
				oldTransition := m.config.Interface.Transition
				oldSelection := m.config.Interface.Selection
				item.onEnter()
				m.themeChanged = m.config.Interface.ColorTheme != oldTheme
				m.transitionChanged = m.config.Interface.Transition != oldTransition
				m.selectionChanged = m.config.Interface.Selection != oldSelection
			}
		case key.Matches(msg, m.keys.Back):
			m.wantsBack = true
		case key.Matches(msg, m.keys.Escape):
			m.wantsMenu = true
		}
	}

	return m, nil
}

func (m settingsModel) View(width, height int) string {
	var b strings.Builder

	b.WriteString(m.styles.Title.Render("Settings"))
	b.WriteString("\n\n")

	// セクションごとの最大ラベル幅を計算
	sectionMaxWidth := make(map[string]int)
	currentSection := ""
	for _, item := range m.items {
		if item.section != "" {
			currentSection = item.section
		}
		if len(item.label) > sectionMaxWidth[currentSection] {
			sectionMaxWidth[currentSection] = len(item.label)
		}
	}

	currentSection = ""
	for i, item := range m.items {
		// Section header
		if item.section != "" {
			currentSection = item.section
			if i > 0 {
				b.WriteString("\n")
			}
			b.WriteString(m.styles.Subtitle.Render(item.section))
			b.WriteString("\n")
		}

		cursor := "  "
		if i == m.cursor {
			cursor = "> "
		}

		maxWidth := sectionMaxWidth[currentSection]
		paddedLabel := fmt.Sprintf("%-*s", maxWidth, item.label)

		// Text input items can be in editing mode
		if item.kind == settingText && m.editing && m.editingField == item.editField {
			input := m.textInputForField(item.editField)
			b.WriteString(fmt.Sprintf("%s%s: %s\n", cursor, paddedLabel, input.View()))
			continue
		}

		style := m.styles.MenuItem
		if i == m.cursor {
			style = m.styles.MenuItemFocus
		}

		value := item.getValue()
		switch item.kind {
		case settingCycle, settingToggle:
			b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render(paddedLabel), value))
		default:
			if item.label == "" {
				b.WriteString(fmt.Sprintf("%s%s\n", cursor, style.Render(value)))
			} else {
				b.WriteString(fmt.Sprintf("%s%s: %s\n", cursor, style.Render(paddedLabel), value))
			}
		}
	}

	b.WriteString("\n")

	if m.editing {
		b.WriteString(m.styles.Help.Render("Enter: Save  Esc: Cancel"))
	} else {
		b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Edit/Toggle  Esc: Menu"))
	}

	content := b.String()
	return renderView(content, m.styles, width, height, m.config.Interface.BorderStyle)
}

func maskToken(token string) string {
	if len(token) <= 8 {
		return strings.Repeat("*", len(token))
	}
	return token[:4] + strings.Repeat("*", len(token)-8) + token[len(token)-4:]
}

// cycleValue returns the next value in names after current.
// If current is not found, it falls back to names[0].
func cycleValue(current string, names []string) string {
	for i, n := range names {
		if n == current {
			return names[(i+1)%len(names)]
		}
	}
	return names[0]
}
