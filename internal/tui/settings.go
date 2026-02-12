package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

type settingsModel struct {
	cursor        int
	styles        Styles
	keys          KeyMap
	config        *config.Config
	editing       bool
	editingField  int
	tokenInput    textinput.Model
	usernameInput textinput.Model
	wantsBack     bool
}

func newSettingsModel(cfg *config.Config, styles Styles, keys KeyMap) settingsModel {
	ti := textinput.New()
	ti.Placeholder = "Enter API token"
	ti.CharLimit = 256

	ui := textinput.New()
	ui.Placeholder = "Enter BGG username"
	ui.CharLimit = 64
	ui.SetValue(cfg.Collection.DefaultUsername)

	return settingsModel{
		cursor:        0,
		styles:        styles,
		keys:          keys,
		config:        cfg,
		tokenInput:    ti,
		usernameInput: ui,
	}
}

func (m settingsModel) itemCount() int {
	return 4 // Token, Username, ShowImages, ShowOnlyOwned
}

func (m settingsModel) Update(msg tea.Msg) (settingsModel, tea.Cmd) {
	var cmd tea.Cmd

	if m.editing {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch {
			case key.Matches(msg, m.keys.Enter):
				// Save the value
				if m.editingField == 0 {
					val := strings.TrimSpace(m.tokenInput.Value())
					if val != "" {
						m.config.API.Token = val
					}
				} else if m.editingField == 1 {
					m.config.Collection.DefaultUsername = strings.TrimSpace(m.usernameInput.Value())
				}
				m.editing = false
				m.tokenInput.Blur()
				m.usernameInput.Blur()
				m.config.Save()
				return m, nil
			case key.Matches(msg, m.keys.Escape):
				m.editing = false
				m.tokenInput.Blur()
				m.usernameInput.Blur()
				return m, nil
			}
		}

		if m.editingField == 0 {
			m.tokenInput, cmd = m.tokenInput.Update(msg)
		} else {
			m.usernameInput, cmd = m.usernameInput.Update(msg)
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
			case 2: // Show Images
				m.config.Display.ShowImages = !m.config.Display.ShowImages
				m.config.Save()
			case 3: // Show Only Owned
				m.config.Collection.ShowOnlyOwned = !m.config.Collection.ShowOnlyOwned
				m.config.Save()
			}
		case key.Matches(msg, m.keys.Back), key.Matches(msg, m.keys.Escape):
			m.wantsBack = true
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

	// Display Section
	b.WriteString(m.styles.Subtitle.Render("Display"))
	b.WriteString("\n")

	// Show Images
	cursor = "  "
	if m.cursor == 2 {
		cursor = "> "
	}
	style := m.styles.MenuItem
	if m.cursor == 2 {
		style = m.styles.MenuItemFocus
	}
	imagesValue := "OFF"
	if m.config.Display.ShowImages {
		imagesValue = "ON"
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Show Images"), imagesValue))

	// Show Only Owned
	cursor = "  "
	if m.cursor == 3 {
		cursor = "> "
	}
	style = m.styles.MenuItem
	if m.cursor == 3 {
		style = m.styles.MenuItemFocus
	}
	ownedValue := "OFF"
	if m.config.Collection.ShowOnlyOwned {
		ownedValue = "ON"
	}
	b.WriteString(fmt.Sprintf("%s%s: [%s]\n", cursor, style.Render("Show Only Owned"), ownedValue))

	b.WriteString("\n")

	// Help
	if m.editing {
		b.WriteString(m.styles.Help.Render("Enter: Save  Esc: Cancel"))
	} else {
		b.WriteString(m.styles.Help.Render("j/k: Navigate  Enter: Edit/Toggle  b: Back"))
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
