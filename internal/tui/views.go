package tui

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
