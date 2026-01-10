# go-bgg

Go client library for the BoardGameGeek (BGG) XML API.

## Installation

```bash
go get github.com/hiroaqii/go-bgg
```

## Usage

```go
package main

import (
    "fmt"
    "log"
    "time"

    "github.com/hiroaqii/go-bgg"
)

func main() {
    // Create a new client
    client, err := bgg.NewClient(bgg.Config{
        Token:      "your-bearer-token",
        Timeout:    30 * time.Second,
        RetryCount: 3,
        RetryDelay: 2 * time.Second,
    })
    if err != nil {
        log.Fatal(err)
    }

    // Search for games
    results, err := client.SearchGames("catan")
    if err != nil {
        log.Fatal(err)
    }
    for _, game := range results {
        fmt.Printf("%s (%s)\n", game.Name, game.Year)
    }

    // Get game details
    game, err := client.GetGame(13)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("%s - Rating: %.2f\n", game.Name, game.Rating)

    // Get hot games
    hotGames, err := client.GetHotGames()
    if err != nil {
        log.Fatal(err)
    }
    for _, hg := range hotGames {
        fmt.Printf("#%d: %s\n", hg.Rank, hg.Name)
    }

    // Get user collection
    collection, err := client.GetCollection("username", bgg.CollectionOptions{
        OwnedOnly: true,
    })
    if err != nil {
        log.Fatal(err)
    }
    for _, item := range collection {
        fmt.Printf("%s - Plays: %d\n", item.Name, item.NumPlays)
    }

    // Get forum list for a game
    forums, err := client.GetForums(13)
    if err != nil {
        log.Fatal(err)
    }
    for _, forum := range forums {
        fmt.Printf("%s (%d threads)\n", forum.Title, forum.NumThreads)
    }

    // Get threads in a forum
    threadList, err := client.GetForumThreads(forumID, 1)
    if err != nil {
        log.Fatal(err)
    }
    for _, t := range threadList.Threads {
        fmt.Printf("%s by %s\n", t.Subject, t.Author)
    }

    // Get thread content
    thread, err := client.GetThread(threadID)
    if err != nil {
        log.Fatal(err)
    }
    for _, article := range thread.Articles {
        fmt.Printf("%s: %s\n", article.Username, article.Body)
    }
}
```

## API Methods

### Search

- `SearchGames(query string) ([]GameSearchResult, error)` - Search for games
- `SearchGamesJSON(query string) (string, error)` - Search for games (JSON response)

### Thing (Game Details)

- `GetGame(id int) (*Game, error)` - Get game details
- `GetGameJSON(id int) (string, error)` - Get game details (JSON response)
- `GetGames(ids []int) ([]Game, error)` - Get multiple games (max 20)

### Hot Games

- `GetHotGames() ([]HotGame, error)` - Get hot games list
- `GetHotGamesJSON() (string, error)` - Get hot games list (JSON response)

### User Collection

- `GetCollection(username string, opts CollectionOptions) ([]CollectionItem, error)` - Get user collection
- `GetCollectionJSON(username string, opts CollectionOptions) (string, error)` - Get user collection (JSON response)

### Forums

- `GetForums(gameID int) ([]Forum, error)` - Get forum list for a game
- `GetForumsJSON(gameID int) (string, error)` - Get forum list (JSON response)
- `GetForumThreads(forumID int, page int) (*ThreadList, error)` - Get threads in a forum
- `GetForumThreadsJSON(forumID int, page int) (string, error)` - Get threads (JSON response)
- `GetThread(threadID int) (*Thread, error)` - Get thread content
- `GetThreadJSON(threadID int) (string, error)` - Get thread content (JSON response)

## Error Handling

The library provides custom error types for different error conditions:

- `AuthError` - Authentication error (invalid token)
- `RateLimitError` - Rate limit exceeded
- `NotFoundError` - Resource not found
- `NetworkError` - Network/HTTP error
- `ParseError` - XML parsing error

```go
game, err := client.GetGame(999999)
if err != nil {
    var notFound *bgg.NotFoundError
    if errors.As(err, &notFound) {
        fmt.Printf("Game %d not found\n", notFound.ID)
    }
}
```

## License

MIT License
