package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// errNoToken is the common error message when the API token is not configured.
const errNoToken = "API token not configured. Please set your token in Settings."

const maxNameLen = 45

const helpFilterActive = "↑/↓: Navigate  Enter: Detail  Esc: Clear filter"

// truncateName truncates a string to maxWidth based on display width (not byte count).
func truncateName(s string, maxWidth int) string {
	if lipgloss.Width(s) <= maxWidth {
		return s
	}
	runes := []rune(s)
	for i := len(runes) - 1; i >= 0; i-- {
		if lipgloss.Width(string(runes[:i])+"...") <= maxWidth {
			return string(runes[:i]) + "..."
		}
	}
	return "..."
}

// writeLoadingView writes a standard loading view with title and message.
func writeLoadingView(b *strings.Builder, styles Styles, title, message string) {
	b.WriteString(styles.Title.Render(title))
	b.WriteString("\n\n")
	b.WriteString(styles.Loading.Render(message))
}

// writeErrorView writes a standard error view with title, error message, and help text.
func writeErrorView(b *strings.Builder, styles Styles, title, errMsg, helpText string) {
	b.WriteString(styles.Title.Render(title))
	b.WriteString("\n\n")
	b.WriteString(styles.Error.Render("Error: " + errMsg))
	b.WriteString("\n\n")
	b.WriteString(styles.Help.Render(helpText))
}

// ListDensityNames lists all available list density options for cycling in settings.
var ListDensityNames = []string{"compact", "normal", "relaxed"}

// overheadForDensity returns the view overhead for the given density.
func overheadForDensity(density string) int {
	switch density {
	case "compact":
		return 8
	case "relaxed":
		return 16
	default:
		return 12
	}
}

// calcListVisible returns the number of list items that fit in the given terminal height.
func calcListVisible(height int, density string) int {
	v := height - overheadForDensity(density)
	if v < 1 {
		v = 1
	}
	return v
}

// calcListRange computes the start and end indices for a scrollable list view.
func calcListRange(cursor, totalItems, height int, density string) (start, end int) {
	visible := calcListVisible(height, density)
	if cursor >= visible {
		start = cursor - visible + 1
	}
	end = start + visible
	if end > totalItems {
		end = totalItems
	}
	return start, end
}

// calcListRangeMultiLine computes the start and end indices for a scrollable list
// where each item occupies multiple lines (e.g., forum thread list with 2-line items).
func calcListRangeMultiLine(cursor, totalItems, height int, density string, linesPerItem int) (start, end int) {
	visible := calcListVisible(height, density) / linesPerItem
	if visible < 1 {
		visible = 1
	}
	if cursor >= visible {
		start = cursor - visible + 1
	}
	end = start + visible
	if end > totalItems {
		end = totalItems
	}
	return start, end
}

// renderImagePanel joins the list content with an image panel side-by-side.
// It returns the combined string and the Kitty transmit sequence (empty if no image).
func renderImagePanel(b *strings.Builder, imageEnabled bool, placeholder, transmit string, loading, hasError bool) string {
	if !imageEnabled {
		return ""
	}
	var imgPanel string
	var tx string
	if placeholder != "" {
		tx = transmit
		imgPanel = "\n" + placeholder + "\n"
	} else if loading {
		imgPanel = "\n" + fixedSizeLoadingPanel(listImageCols, listImageRows) + "\n"
	} else if hasError {
		imgPanel = "\n" + fixedSizeNoImagePanel(listImageCols, listImageRows) + "\n"
	} else {
		return ""
	}
	listContent := b.String()
	b.Reset()
	b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, listContent, "  ", imgPanel))
	return tx
}

// renderListItem returns the cursor prefix and styled text for a list item.
// If the item is at the cursor position, it uses "> " prefix and selection animation;
// otherwise it uses "  " prefix and the normal ListItem style.
func renderListItem(index, cursor int, text string, styles Styles, selType string, animFrame int) (string, string) {
	if index == cursor {
		return "> ", renderSelectionAnim(text, selType, animFrame)
	}
	return "  ", styles.ListItem.Render(text)
}

// listNavigator provides navigation signals from list sub-models.
type listNavigator interface {
	WantsMenu() bool
	WantsBack() bool
	Selected() *int
	ClearSignals()
}

// handleListNav processes common navigation signals (menu, back, detail selection).
// Returns true and a tea.Cmd if a navigation was handled.
func (m *Model) handleListNav(nav listNavigator, backView View) (bool, tea.Cmd) {
	if nav.WantsMenu() {
		nav.ClearSignals()
		m.setView(ViewMenu)
		if m.imageEnabled {
			m.needsClearImages = true
		}
		return true, nil
	}

	if nav.WantsBack() {
		nav.ClearSignals()
		m.setView(ViewMenu)
		if m.imageEnabled {
			m.needsClearImages = true
		}
		return true, nil
	}

	if sel := nav.Selected(); sel != nil {
		nav.ClearSignals()
		m.previousView = backView
		m.detail = newDetailModel(*sel, m.styles, m.keys, m.imageEnabled, m.imageCache, m.config)
		m.detail.viewHeight = m.height
		m.setView(ViewDetail)
		if m.imageEnabled {
			m.needsClearImages = true
		}
		return true, m.detail.loadGame(m.bggClient)
	}

	return false, nil
}

// View represents the current view state of the application.
type View int

const (
	ViewMenu View = iota
	ViewSearchInput
	ViewSearchResults
	ViewHot
	ViewCollectionInput
	ViewCollectionList
	ViewDetail
	ViewForumList
	ViewThreadList
	ViewThreadView
	ViewSettings
	ViewSetupToken
)

// String returns the string representation of a View.
func (v View) String() string {
	switch v {
	case ViewMenu:
		return "Menu"
	case ViewSearchInput:
		return "SearchInput"
	case ViewSearchResults:
		return "SearchResults"
	case ViewHot:
		return "Hot"
	case ViewCollectionInput:
		return "CollectionInput"
	case ViewCollectionList:
		return "CollectionList"
	case ViewDetail:
		return "Detail"
	case ViewForumList:
		return "ForumList"
	case ViewThreadList:
		return "ThreadList"
	case ViewThreadView:
		return "ThreadView"
	case ViewSettings:
		return "Settings"
	case ViewSetupToken:
		return "SetupToken"
	default:
		return "Unknown"
	}
}
