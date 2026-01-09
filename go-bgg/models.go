// Package bgg provides a client for the BoardGameGeek XML API.
package bgg

// GameSearchResult represents a game in search results.
type GameSearchResult struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	Year string `json:"year"`
	Type string `json:"type"` // "boardgame" or "boardgameexpansion"
}

// Game represents detailed information about a board game.
type Game struct {
	ID          int      `json:"id"`
	Name        string   `json:"name"`
	Year        string   `json:"year"`
	Description string   `json:"description"`
	Thumbnail   string   `json:"thumbnail"`
	Image       string   `json:"image"`
	MinPlayers  int      `json:"min_players"`
	MaxPlayers  int      `json:"max_players"`
	PlayingTime int      `json:"playing_time"`
	MinPlayTime int      `json:"min_play_time"`
	MaxPlayTime int      `json:"max_play_time"`
	MinAge      int      `json:"min_age"`
	Rating      float64  `json:"rating"`
	UsersRated  int      `json:"users_rated"`
	Rank        int      `json:"rank"` // 0 = Not Ranked
	Weight      float64  `json:"weight"`
	Designers   []string `json:"designers"`
	Artists     []string `json:"artists"`
	Publishers  []string `json:"publishers"`
	Categories  []string `json:"categories"`
	Mechanics   []string `json:"mechanics"`
}

// HotGame represents a game in the hot list.
type HotGame struct {
	ID        int    `json:"id"`
	Rank      int    `json:"rank"`
	Name      string `json:"name"`
	Year      string `json:"year"`
	Thumbnail string `json:"thumbnail"`
}

// CollectionOptions specifies options for fetching a user's collection.
type CollectionOptions struct {
	OwnedOnly bool // true: own=1
}

// CollectionItem represents a game in a user's collection.
type CollectionItem struct {
	ID         int     `json:"id"`
	Name       string  `json:"name"`
	Year       string  `json:"year"`
	Thumbnail  string  `json:"thumbnail"`
	Image      string  `json:"image"`
	NumPlays   int     `json:"num_plays"`
	Rating     float64 `json:"rating"`     // User's rating
	BGGRating  float64 `json:"bgg_rating"` // BGG average rating
	Owned      bool    `json:"owned"`
	WantToPlay bool    `json:"want_to_play"`
	Wishlist   bool    `json:"wishlist"`
}

// Forum represents a forum category for a game.
type Forum struct {
	ID           int    `json:"id"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	NumThreads   int    `json:"num_threads"`
	NumPosts     int    `json:"num_posts"`
	LastPostDate string `json:"last_post_date"`
}

// ThreadList represents a paginated list of threads.
type ThreadList struct {
	Threads    []ThreadSummary `json:"threads"`
	Page       int             `json:"page"`
	TotalPages int             `json:"total_pages"`
}

// ThreadSummary represents a thread in a forum listing.
type ThreadSummary struct {
	ID           int    `json:"id"`
	Subject      string `json:"subject"`
	Author       string `json:"author"`
	NumArticles  int    `json:"num_articles"`
	PostDate     string `json:"post_date"`
	LastPostDate string `json:"last_post_date"`
}

// Thread represents a thread with its articles.
type Thread struct {
	ID         int       `json:"id"`
	Subject    string    `json:"subject"`
	Articles   []Article `json:"articles"`
	Page       int       `json:"page"`
	TotalPages int       `json:"total_pages"`
}

// Article represents a post in a thread.
type Article struct {
	ID       int    `json:"id"`
	Username string `json:"username"`
	PostDate string `json:"post_date"`
	Body     string `json:"body"`
}
