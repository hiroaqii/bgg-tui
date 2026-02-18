package bgg

import "encoding/xml"

// XML structures for parsing BGG API responses.
// These are internal types used for XML parsing.

// xmlItems is the root element for search results.
type xmlItems struct {
	XMLName xml.Name  `xml:"items"`
	Items   []xmlItem `xml:"item"`
}

// xmlItem represents an item in search results.
type xmlItem struct {
	Type      string      `xml:"type,attr"`
	ID        int         `xml:"id,attr"`
	Name      xmlNameElem `xml:"name"`
	YearValue xmlValue    `xml:"yearpublished"`
}

// xmlNameElem represents a name element with type and value attributes.
type xmlNameElem struct {
	Type  string `xml:"type,attr"`
	Value string `xml:"value,attr"`
}

// xmlValue represents an element with a value attribute.
type xmlValue struct {
	Value string `xml:"value,attr"`
}

// xmlIntValue represents an element with an integer value attribute.
type xmlIntValue struct {
	Value int `xml:"value,attr"`
}

// xmlThing is the root element for thing (game detail) responses.
type xmlThing struct {
	XMLName xml.Name      `xml:"items"`
	Items   []xmlThingItem `xml:"item"`
}

// xmlThingItem represents a detailed game item.
type xmlThingItem struct {
	Type        string           `xml:"type,attr"`
	ID          int              `xml:"id,attr"`
	Thumbnail   string           `xml:"thumbnail"`
	Image       string           `xml:"image"`
	Names       []xmlNameElem    `xml:"name"`
	Description string           `xml:"description"`
	YearValue   xmlValue         `xml:"yearpublished"`
	MinPlayers  xmlIntValue      `xml:"minplayers"`
	MaxPlayers  xmlIntValue      `xml:"maxplayers"`
	PlayingTime xmlIntValue      `xml:"playingtime"`
	MinPlayTime xmlIntValue      `xml:"minplaytime"`
	MaxPlayTime xmlIntValue      `xml:"maxplaytime"`
	MinAge      xmlIntValue      `xml:"minage"`
	Links         []xmlLink        `xml:"link"`
	Polls         []xmlPoll        `xml:"poll"`
	PollSummaries []xmlPollSummary `xml:"poll-summary"`
	Statistics    xmlStatistics    `xml:"statistics"`
}

// xmlLink represents a link element (designer, category, mechanic, etc.).
type xmlLink struct {
	Type  string `xml:"type,attr"`
	ID    int    `xml:"id,attr"`
	Value string `xml:"value,attr"`
}

// xmlStatistics contains game statistics.
type xmlStatistics struct {
	Ratings xmlRatings `xml:"ratings"`
}

// xmlRatings contains rating information.
type xmlRatings struct {
	UsersRated    xmlIntValue   `xml:"usersrated"`
	Average       xmlFloatValue `xml:"average"`
	BayesAverage  xmlFloatValue `xml:"bayesaverage"`
	Ranks         xmlRanks      `xml:"ranks"`
	StdDev        xmlFloatValue `xml:"stddev"`
	Median        xmlFloatValue `xml:"median"`
	Owned         xmlIntValue   `xml:"owned"`
	NumComments   xmlIntValue   `xml:"numcomments"`
	NumWeights    xmlIntValue   `xml:"numweights"`
	AverageWeight xmlFloatValue `xml:"averageweight"`
}

// xmlFloatValue represents an element with a float value attribute.
type xmlFloatValue struct {
	Value float64 `xml:"value,attr"`
}

// xmlRanks contains rank information.
type xmlRanks struct {
	Ranks []xmlRank `xml:"rank"`
}

// xmlRank represents a single rank entry.
type xmlRank struct {
	Type       string `xml:"type,attr"`
	ID         int    `xml:"id,attr"`
	Name       string `xml:"name,attr"`
	FriendlyName string `xml:"friendlyname,attr"`
	Value      string `xml:"value,attr"`
}

// xmlPoll represents a poll element.
type xmlPoll struct {
	Name       string           `xml:"name,attr"`
	Title      string           `xml:"title,attr"`
	TotalVotes int              `xml:"totalvotes,attr"`
	Results    []xmlPollResults `xml:"results"`
}

// xmlPollResults represents results for a specific option (e.g. player count).
type xmlPollResults struct {
	NumPlayers string          `xml:"numplayers,attr"`
	Results    []xmlPollResult `xml:"result"`
}

// xmlPollResult represents a single result entry in a poll.
type xmlPollResult struct {
	Value    string `xml:"value,attr"`
	NumVotes int    `xml:"numvotes,attr"`
}

// xmlPollSummary represents a poll-summary element.
type xmlPollSummary struct {
	Name    string                 `xml:"name,attr"`
	Results []xmlPollSummaryResult `xml:"result"`
}

// xmlPollSummaryResult represents a result in a poll summary.
type xmlPollSummaryResult struct {
	Name  string `xml:"name,attr"`
	Value string `xml:"value,attr"`
}

// xmlHot is the root element for hot list responses.
type xmlHot struct {
	XMLName xml.Name     `xml:"items"`
	Items   []xmlHotItem `xml:"item"`
}

// xmlHotItem represents an item in the hot list.
type xmlHotItem struct {
	ID        int       `xml:"id,attr"`
	Rank      int       `xml:"rank,attr"`
	Thumbnail xmlValue  `xml:"thumbnail"`
	Name      xmlValue  `xml:"name"`
	YearValue xmlValue  `xml:"yearpublished"`
}

// xmlCollection is the root element for collection responses.
type xmlCollection struct {
	XMLName xml.Name            `xml:"items"`
	Items   []xmlCollectionItem `xml:"item"`
}

// xmlCollectionItem represents an item in a user's collection.
type xmlCollectionItem struct {
	ObjectType string               `xml:"objecttype,attr"`
	ObjectID   int                  `xml:"objectid,attr"`
	Subtype    string               `xml:"subtype,attr"`
	CollID     int                  `xml:"collid,attr"`
	Name       xmlCollectionName    `xml:"name"`
	YearValue  string               `xml:"yearpublished"`
	Image      string               `xml:"image"`
	Thumbnail  string               `xml:"thumbnail"`
	Status     xmlCollectionStatus  `xml:"status"`
	NumPlays   int                  `xml:"numplays"`
	Stats      xmlCollectionStats   `xml:"stats"`
}

// xmlCollectionName represents the name element in collection.
type xmlCollectionName struct {
	SortIndex int    `xml:"sortindex,attr"`
	Value     string `xml:",chardata"`
}

// xmlCollectionStatus represents the status flags in collection.
type xmlCollectionStatus struct {
	Own          string `xml:"own,attr"`
	PrevOwned    string `xml:"prevowned,attr"`
	ForTrade     string `xml:"fortrade,attr"`
	Want         string `xml:"want,attr"`
	WantToPlay   string `xml:"wanttoplay,attr"`
	WantToBuy    string `xml:"wanttobuy,attr"`
	Wishlist     string `xml:"wishlist,attr"`
	Preordered   string `xml:"preordered,attr"`
	LastModified string `xml:"lastmodified,attr"`
}

// xmlCollectionStats contains collection item statistics.
type xmlCollectionStats struct {
	MinPlayers  int                   `xml:"minplayers,attr"`
	MaxPlayers  int                   `xml:"maxplayers,attr"`
	MinPlayTime int                   `xml:"minplaytime,attr"`
	MaxPlayTime int                   `xml:"maxplaytime,attr"`
	PlayingTime int                   `xml:"playingtime,attr"`
	NumOwned    int                   `xml:"numowned,attr"`
	Rating      xmlCollectionRating   `xml:"rating"`
}

// xmlCollectionRating contains rating info for collection items.
type xmlCollectionRating struct {
	Value        string        `xml:"value,attr"`
	UsersRated   xmlIntValue   `xml:"usersrated"`
	Average      xmlFloatValue `xml:"average"`
	BayesAverage xmlFloatValue `xml:"bayesaverage"`
}

// xmlForumList is the root element for forum list responses.
type xmlForumList struct {
	XMLName xml.Name   `xml:"forums"`
	Type    string     `xml:"type,attr"`
	ID      int        `xml:"id,attr"`
	Forums  []xmlForum `xml:"forum"`
}

// xmlForum represents a forum in the forum list.
type xmlForum struct {
	ID           int    `xml:"id,attr"`
	GroupID      int    `xml:"groupid,attr"`
	Title        string `xml:"title,attr"`
	NoPosting    int    `xml:"noposting,attr"`
	Description  string `xml:"description,attr"`
	NumThreads   int    `xml:"numthreads,attr"`
	NumPosts     int    `xml:"numposts,attr"`
	LastPostDate string `xml:"lastpostdate,attr"`
}

// xmlForumPage is the root element for forum page responses.
type xmlForumPage struct {
	XMLName      xml.Name    `xml:"forum"`
	ID           int         `xml:"id,attr"`
	Title        string      `xml:"title,attr"`
	NumThreads   int         `xml:"numthreads,attr"`
	NumPosts     int         `xml:"numposts,attr"`
	LastPostDate string      `xml:"lastpostdate,attr"`
	NoPosting    int         `xml:"noposting,attr"`
	Threads      xmlThreads  `xml:"threads"`
}

// xmlThreads contains a list of threads.
type xmlThreads struct {
	Threads []xmlThreadSummary `xml:"thread"`
}

// xmlThreadSummary represents a thread in forum listing.
type xmlThreadSummary struct {
	ID           int    `xml:"id,attr"`
	Subject      string `xml:"subject,attr"`
	Author       string `xml:"author,attr"`
	NumArticles  int    `xml:"numarticles,attr"`
	PostDate     string `xml:"postdate,attr"`
	LastPostDate string `xml:"lastpostdate,attr"`
}

// xmlThread is the root element for thread responses.
type xmlThread struct {
	XMLName   xml.Name      `xml:"thread"`
	ID        int           `xml:"id,attr"`
	NumArticles int         `xml:"numarticles,attr"`
	Link      string        `xml:"link,attr"`
	Subject   string        `xml:"subject"`
	Articles  []xmlArticle  `xml:"articles>article"`
}

// xmlArticle represents an article (post) in a thread.
type xmlArticle struct {
	ID       int    `xml:"id,attr"`
	Username string `xml:"username,attr"`
	Link     string `xml:"link,attr"`
	PostDate string `xml:"postdate,attr"`
	EditDate string `xml:"editdate,attr"`
	NumEdits int    `xml:"numedits,attr"`
	Body     string `xml:"body"`
}
