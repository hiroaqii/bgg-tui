package tui

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
