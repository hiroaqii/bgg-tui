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

type settingsModel struct {
	cursor            int
	styles            Styles
	keys              KeyMap
	config            *config.Config
	editing           bool
	editingField      int
	tokenInput        textinput.Model
	usernameInput     textinput.Model
	widthInput        textinput.Model
	heightInput       textinput.Model
	descWidthInput    textinput.Model
	wantsBack         bool
	wantsMenu         bool
	themeChanged      bool
	transitionChanged bool
	selectionChanged  bool
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

	hi := textinput.New()
	hi.Placeholder = "Enter height (5-100)"
	hi.CharLimit = 3
	hi.SetValue(fmt.Sprintf("%d", cfg.Display.ThreadHeight))

	dwi := textinput.New()
	dwi.Placeholder = "Enter width (20-200)"
	dwi.CharLimit = 3
	dwi.SetValue(fmt.Sprintf("%d", cfg.Display.DescriptionWidth))

	return settingsModel{
		cursor:         0,
		styles:         styles,
		keys:           keys,
		config:         cfg,
		tokenInput:     ti,
		usernameInput:  ui,
		widthInput:     wi,
		heightInput:    hi,
		descWidthInput: dwi,
	}
}

func (m settingsModel) itemCount() int {
	return 11 // Token, Username, ColorTheme, Transition, Selection, ListDensity, ShowImages, ShowOnlyOwned, ThreadWidth, ThreadHeight, DescriptionWidth
}

func (m settingsModel) Update(msg tea.Msg) (settingsModel, tea.Cmd) {
	var cmd tea.Cmd

	if m.editing {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				// Save the value
				switch m.editingField {
				case 0:
					val := strings.TrimSpace(m.tokenInput.Value())
					if val != "" {
						m.config.API.Token = val
					}
				case 1:
					m.config.Collection.DefaultUsername = strings.TrimSpace(m.usernameInput.Value())
				case 2:
					if v, err := strconv.Atoi(strings.TrimSpace(m.widthInput.Value())); err == nil && v >= 20 && v <= 200 {
						m.config.Display.ThreadWidth = v
					}
				case 3:
					if v, err := strconv.Atoi(strings.TrimSpace(m.heightInput.Value())); err == nil && v >= 5 && v <= 100 {
						m.config.Display.ThreadHeight = v
					}
				case 4:
					if v, err := strconv.Atoi(strings.TrimSpace(m.descWidthInput.Value())); err == nil && v >= 20 && v <= 200 {
						m.config.Display.DescriptionWidth = v
					}
				}
				m.editing = false
				m.tokenInput.Blur()
				m.usernameInput.Blur()
				m.widthInput.Blur()
				m.heightInput.Blur()
				m.descWidthInput.Blur()
				m.config.Save()
				return m, nil
			case key.Matches(msg, m.keys.Escape):
				m.editing = false
				m.tokenInput.Blur()
				m.usernameInput.Blur()
				m.widthInput.Blur()
				m.heightInput.Blur()
				m.descWidthInput.Blur()
				return m, nil
			}
		}

		switch m.editingField {
		case 0:
			m.tokenInput, cmd = m.tokenInput.Update(msg)
		case 1:
			m.usernameInput, cmd = m.usernameInput.Update(msg)
		case 2:
			m.widthInput, cmd = m.widthInput.Update(msg)
		case 3:
			m.heightInput, cmd = m.heightInput.Update(msg)
		case 4:
			m.descWidthInput, cmd = m.descWidthInput.Update(msg)
		}
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
			switch m.cursor {
			case 0: // Token
				m.editing = true
				m.editingField = 0
				m.tokenInput.SetValue("")
				m.tokenInput.Focus()
				return m, textinput.Blink
			case 1: // Username
				m.editing = true
				m.editingField = 1
				m.usernameInput.Focus()
				return m, textinput.Blink
			case 2: // Color Theme
				m.config.Interface.ColorTheme = cycleValue(m.config.Interface.ColorTheme, ThemeNames)
				m.config.Save()
				m.themeChanged = true
			case 3: // Transition
				m.config.Interface.Transition = cycleValue(m.config.Interface.Transition, TransitionNames)
				m.config.Save()
				m.transitionChanged = true
			case 4: // Selection
				m.config.Interface.Selection = cycleValue(m.config.Interface.Selection, SelectionNames)
				m.config.Save()
				m.selectionChanged = true
			case 5: // List Density
				m.config.Interface.ListDensity = cycleValue(m.config.Interface.ListDensity, ListDensityNames)
				m.config.Save()
			case 6: // Show Images
				m.config.Display.ShowImages = !m.config.Display.ShowImages
				m.config.Save()
			case 7: // Show Only Owned
				m.config.Collection.ShowOnlyOwned = !m.config.Collection.ShowOnlyOwned
				m.config.Save()
			case 8: // Thread Width
				m.editing = true
				m.editingField = 2
				m.widthInput.SetValue(fmt.Sprintf("%d", m.config.Display.ThreadWidth))
				m.widthInput.Focus()
				return m, textinput.Blink
			case 9: // Thread Height
				m.editing = true
				m.editingField = 3
				m.heightInput.SetValue(fmt.Sprintf("%d", m.config.Display.ThreadHeight))
				m.heightInput.Focus()
				return m, textinput.Blink
			case 10: // Description Width
				m.editing = true
				m.editingField = 4
				m.descWidthInput.SetValue(fmt.Sprintf("%d", m.config.Display.DescriptionWidth))
				m.descWidthInput.Focus()
				return m, textinput.Blink
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

	title := m.styles.Title.Render("Settings")
	b.WriteString(title)
	b.WriteString("\n\n")

	// API Section
	b.WriteString(m.styles.Subtitle.Render("API"))
	b.WriteString("\n")

	// Token
	cursor := "  "
	if m.cursor == 0 {
		cursor = "> "
	}
	tokenValue := "(not set)"
	if m.config.API.Token != "" {
		tokenValue = maskToken(m.config.API.Token)
	}
	if m.editing && m.editingField == 0 {
		b.WriteString(fmt.Sprintf("%sToken: %s\n", cursor, m.tokenInput.View()))
	} else {
		style := m.styles.MenuItem
		if m.cursor == 0 {
			style = m.styles.MenuItemFocus
		}
		b.WriteString(fmt.Sprintf("%s%s: %s\n", cursor, style.Render("Token"), tokenValue))
	}

	b.WriteString("\n")

	// Collection Section
	b.WriteString(m.styles.Subtitle.Render("Collection"))
	b.WriteString("\n")

	// Username
	cursor = "  "
	if m.cursor == 1 {
		cursor = "> "
	}
	usernameValue := "(not set)"
	if m.config.Collection.DefaultUsername != "" {
		usernameValue = m.config.Collection.DefaultUsername
	}
	if m.editing && m.editingField == 1 {
		b.WriteString(fmt.Sprintf("%sDefault Username: %s\n", cursor, m.usernameInput.View()))
	} else {
		style := m.styles.MenuItem
		if m.cursor == 1 {
			style = m.styles.MenuItemFocus
		}
		b.WriteString(fmt.Sprintf("%s%s: %s\n", cursor, style.Render("Default Username"), usernameValue))
	}

	b.WriteString("\n")

	// Interface Section
	b.WriteString(m.styles.Subtitle.Render("Interface"))
	b.WriteString("\n")

	// Color Theme
	cursor = "  "
	if m.cursor == 2 {
		cursor = "> "
	}
	style := m.styles.MenuItem
	if m.cursor == 2 {
		style = m.styles.MenuItemFocus
	}
	themeValue := m.config.Interface.ColorTheme
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Color Theme"), themeValue))

	// Transition
	cursor = "  "
	if m.cursor == 3 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 3 {
		style = m.styles.MenuItemFocus
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Transition"), m.config.Interface.Transition))

	// Selection
	cursor = "  "
	if m.cursor == 4 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 4 {
		style = m.styles.MenuItemFocus
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Selection"), m.config.Interface.Selection))

	// List Density
	cursor = "  "
	if m.cursor == 5 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 5 {
		style = m.styles.MenuItemFocus
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("List Density"), m.config.Interface.ListDensity))

	b.WriteString("\n")

	// Display Section
	b.WriteString(m.styles.Subtitle.Render("Display"))
	b.WriteString("\n")

	// Show Images
	cursor = "  "
	if m.cursor == 6 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 6 {
		style = m.styles.MenuItemFocus
	}
	imagesValue := "OFF"
	if m.config.Display.ShowImages {
		imagesValue = "ON"
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Show Images"), imagesValue))

	// Show Only Owned
	cursor = "  "
	if m.cursor == 7 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 7 {
		style = m.styles.MenuItemFocus
	}
	ownedValue := "OFF"
	if m.config.Collection.ShowOnlyOwned {
		ownedValue = "ON"
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Show Only Owned"), ownedValue))

	// Thread Width
	cursor = "  "
	if m.cursor == 8 {
		cursor = "> "
	}
	if m.editing && m.editingField == 2 {
		b.WriteString(fmt.Sprintf("%sThread Width: %s\n", cursor, m.widthInput.View()))
	} else {
		style = m.styles.MenuItem
		if m.cursor == 8 {
			style = m.styles.MenuItemFocus
		}
		b.WriteString(fmt.Sprintf("%s%s: %d\n", cursor, style.Render("Thread Width"), m.config.Display.ThreadWidth))
	}

	// Thread Height
	cursor = "  "
	if m.cursor == 9 {
		cursor = "> "
	}
	if m.editing && m.editingField == 3 {
		b.WriteString(fmt.Sprintf("%sThread Height: %s\n", cursor, m.heightInput.View()))
	} else {
		style = m.styles.MenuItem
		if m.cursor == 9 {
			style = m.styles.MenuItemFocus
		}
		b.WriteString(fmt.Sprintf("%s%s: %d\n", cursor, style.Render("Thread Height"), m.config.Display.ThreadHeight))
	}

	// Description Width
	cursor = "  "
	if m.cursor == 10 {
		cursor = "> "
	}
	if m.editing && m.editingField == 4 {
		b.WriteString(fmt.Sprintf("%sDescription Width: %s\n", cursor, m.descWidthInput.View()))
	} else {
		style = m.styles.MenuItem
		if m.cursor == 10 {
			style = m.styles.MenuItemFocus
		}
		b.WriteString(fmt.Sprintf("%s%s: %d\n", cursor, style.Render("Description Width"), m.config.Display.DescriptionWidth))
	}

	b.WriteString("\n")

	// Help
	if m.editing {
		b.WriteString(m.styles.Help.Render("Enter: Save  Esc: Cancel"))
	} else {
		b.WriteString(m.styles.Help.Render("j/k ↑↓: Navigate  Enter: Edit/Toggle  Esc: Menu"))
	}

	content := b.String()
	return centerContent(content, width, height)
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
