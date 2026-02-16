package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ListDensityNames lists all available list density options for cycling in settings.
var ListDensityNames = []string{"compact", "normal", "relaxed"}

// listOverheadForDensity returns the list view overhead for the given density.
func listOverheadForDensity(density string) int {
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
	v := height - listOverheadForDensity(density)
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
