// Test program to verify BGG API connectivity
package main

import (
	"fmt"
	"os"

	bgg "github.com/hiroaqii/go-bgg"
)

func main() {
	token := os.Getenv("BGG_TOKEN")
	if token == "" {
		fmt.Println("Error: BGG_TOKEN environment variable is not set")
		fmt.Println("Usage: BGG_TOKEN=your-token go run . <search-query>")
		os.Exit(1)
	}

	if len(os.Args) < 2 {
		fmt.Println("Error: search query is required")
		fmt.Println("Usage: BGG_TOKEN=your-token go run . <search-query> [username]")
		os.Exit(1)
	}

	query := os.Args[1]
	var username string
	if len(os.Args) >= 3 {
		username = os.Args[2]
	}

	client, err := bgg.NewClient(bgg.Config{
		Token: token,
	})
	if err != nil {
		fmt.Printf("Error creating client: %v\n", err)
		os.Exit(1)
	}

	// Test Search API
	fmt.Println("=== Testing Search API ===")
	fmt.Printf("Searching for '%s'...\n", query)
	searchURL := fmt.Sprintf("%s/search?query=%s&type=boardgame,boardgameexpansion", bgg.BaseURL, query)
	fmt.Printf("URL: %s\n", searchURL)
	fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", searchURL)

	results, err := client.SearchGames(query)
	if err != nil {
		fmt.Printf("Error searching games: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Found %d results:\n\n", len(results))
	var firstGameID int
	for i, game := range results {
		if i >= 10 {
			fmt.Printf("... and %d more results\n", len(results)-10)
			break
		}
		fmt.Printf("  [%d] %s (%s) - Type: %s\n", game.ID, game.Name, game.Year, game.Type)
		if i == 0 {
			firstGameID = game.ID
		}
	}

	// Test Thing API with first result
	if firstGameID > 0 {
		fmt.Println("\n=== Testing Thing API ===")
		fmt.Printf("Getting details for game ID %d...\n", firstGameID)
		thingURL := fmt.Sprintf("%s/thing?id=%d&stats=1", bgg.BaseURL, firstGameID)
		fmt.Printf("URL: %s\n", thingURL)
		fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", thingURL)

		game, err := client.GetGame(firstGameID)
		if err != nil {
			fmt.Printf("Error getting game: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Game Details:\n")
		fmt.Printf("  Name:        %s\n", game.Name)
		fmt.Printf("  Year:        %s\n", game.Year)
		fmt.Printf("  Players:     %d-%d\n", game.MinPlayers, game.MaxPlayers)
		fmt.Printf("  Time:        %d-%d min\n", game.MinPlayTime, game.MaxPlayTime)
		fmt.Printf("  Age:         %d+\n", game.MinAge)
		fmt.Printf("  Rating:      %.2f (%d votes)\n", game.Rating, game.UsersRated)
		fmt.Printf("  Rank:        #%d\n", game.Rank)
		fmt.Printf("  Weight:      %.2f/5\n", game.Weight)
		fmt.Printf("  Designers:   %v\n", game.Designers)
		fmt.Printf("  Categories:  %v\n", game.Categories)
		fmt.Printf("  Mechanics:   %v\n", game.Mechanics)
	}

	// Test Hot API
	fmt.Println("\n=== Testing Hot API ===")
	hotURL := fmt.Sprintf("%s/hot?type=boardgame", bgg.BaseURL)
	fmt.Printf("URL: %s\n", hotURL)
	fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", hotURL)

	hotGames, err := client.GetHotGames()
	if err != nil {
		fmt.Printf("Error getting hot games: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Top 10 Hot Games:\n\n")
	for i, game := range hotGames {
		if i >= 10 {
			break
		}
		fmt.Printf("  #%d [%d] %s (%s)\n", game.Rank, game.ID, game.Name, game.Year)
	}

	// Test Collection API (if username provided)
	if username != "" {
		fmt.Println("\n=== Testing Collection API ===")
		fmt.Printf("Getting collection for user '%s'...\n", username)
		collectionURL := fmt.Sprintf("%s/collection?username=%s&stats=1", bgg.BaseURL, username)
		fmt.Printf("URL: %s\n", collectionURL)
		fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", collectionURL)

		items, err := client.GetCollection(username, bgg.CollectionOptions{})
		if err != nil {
			fmt.Printf("Error getting collection: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Found %d items in collection:\n\n", len(items))
		for i, item := range items {
			if i >= 10 {
				fmt.Printf("... and %d more items\n", len(items)-10)
				break
			}
			status := ""
			if item.Owned {
				status += "[Owned]"
			}
			if item.Wishlist {
				status += "[Wishlist]"
			}
			if item.WantToPlay {
				status += "[WantToPlay]"
			}
			fmt.Printf("  [%d] %s (%s) - Plays: %d, Rating: %.1f %s\n",
				item.ID, item.Name, item.Year, item.NumPlays, item.Rating, status)
		}
	} else {
		fmt.Println("\n=== Skipping Collection API ===")
		fmt.Println("Provide a username as second argument to test Collection API")
		fmt.Println("Usage: BGG_TOKEN=your-token go run . <search-query> <username>")
	}

	fmt.Println("\n=== Test Complete ===")
}
