package tui

import bgg "github.com/hiroaqii/go-bgg"

// CollectionStatus represents a BGG collection status type.
type CollectionStatus int

const (
	StatusOwned CollectionStatus = iota
	StatusPrevOwned
	StatusForTrade
	StatusWant
	StatusWantToPlay
	StatusWantToBuy
	StatusWishlist
	StatusPreordered
	statusCount // sentinel
)

// allStatuses is the ordered list of all statuses shown in the picker.
var allStatuses = []CollectionStatus{
	StatusOwned,
	StatusPrevOwned,
	StatusForTrade,
	StatusWant,
	StatusWantToPlay,
	StatusWantToBuy,
	StatusWishlist,
	StatusPreordered,
}

// statusLabel returns the display label for a status.
func statusLabel(s CollectionStatus) string {
	switch s {
	case StatusOwned:
		return "Owned"
	case StatusPrevOwned:
		return "Prev Owned"
	case StatusForTrade:
		return "For Trade"
	case StatusWant:
		return "Want Trade"
	case StatusWantToPlay:
		return "Want Play"
	case StatusWantToBuy:
		return "Want Buy"
	case StatusWishlist:
		return "Wishlist"
	case StatusPreordered:
		return "Preordered"
	}
	return ""
}

// statusConfigKey returns the config key used in StatusFilter for a status.
func statusConfigKey(s CollectionStatus) string {
	switch s {
	case StatusOwned:
		return "owned"
	case StatusPrevOwned:
		return "prev_owned"
	case StatusForTrade:
		return "for_trade"
	case StatusWant:
		return "want"
	case StatusWantToPlay:
		return "want_to_play"
	case StatusWantToBuy:
		return "want_to_buy"
	case StatusWishlist:
		return "wishlist"
	case StatusPreordered:
		return "preordered"
	}
	return ""
}

// statusFromConfigKey converts a config key to a CollectionStatus.
// Returns -1 if not found.
func statusFromConfigKey(key string) CollectionStatus {
	for _, s := range allStatuses {
		if statusConfigKey(s) == key {
			return s
		}
	}
	return -1
}

// itemMatchesStatus returns true if the collection item has the given status.
func itemMatchesStatus(item bgg.CollectionItem, s CollectionStatus) bool {
	switch s {
	case StatusOwned:
		return item.Owned
	case StatusPrevOwned:
		return item.PrevOwned
	case StatusForTrade:
		return item.ForTrade
	case StatusWant:
		return item.Want
	case StatusWantToPlay:
		return item.WantToPlay
	case StatusWantToBuy:
		return item.WantToBuy
	case StatusWishlist:
		return item.Wishlist
	case StatusPreordered:
		return item.Preordered
	}
	return false
}
