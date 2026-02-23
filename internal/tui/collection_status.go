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
)

// statusDef holds the metadata for a single collection status.
type statusDef struct {
	label     string
	configKey string
	match     func(bgg.CollectionItem) bool
}

// statusDefs maps each CollectionStatus to its metadata.
var statusDefs = [...]statusDef{
	StatusOwned:      {"Owned", "owned", func(i bgg.CollectionItem) bool { return i.Owned }},
	StatusPrevOwned:  {"Prev Owned", "prev_owned", func(i bgg.CollectionItem) bool { return i.PrevOwned }},
	StatusForTrade:   {"For Trade", "for_trade", func(i bgg.CollectionItem) bool { return i.ForTrade }},
	StatusWant:       {"Want Trade", "want", func(i bgg.CollectionItem) bool { return i.Want }},
	StatusWantToPlay: {"Want Play", "want_to_play", func(i bgg.CollectionItem) bool { return i.WantToPlay }},
	StatusWantToBuy:  {"Want Buy", "want_to_buy", func(i bgg.CollectionItem) bool { return i.WantToBuy }},
	StatusWishlist:   {"Wishlist", "wishlist", func(i bgg.CollectionItem) bool { return i.Wishlist }},
	StatusPreordered: {"Preordered", "preordered", func(i bgg.CollectionItem) bool { return i.Preordered }},
}

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
func statusLabel(s CollectionStatus) string { return statusDefs[s].label }

// statusConfigKey returns the config key used in StatusFilter for a status.
func statusConfigKey(s CollectionStatus) string { return statusDefs[s].configKey }

// statusFromConfigKey converts a config key to a CollectionStatus.
// Returns -1 if not found.
func statusFromConfigKey(key string) CollectionStatus {
	for _, s := range allStatuses {
		if statusDefs[s].configKey == key {
			return s
		}
	}
	return -1
}

// itemMatchesStatus returns true if the collection item has the given status.
func itemMatchesStatus(item bgg.CollectionItem, s CollectionStatus) bool {
	return statusDefs[s].match(item)
}
