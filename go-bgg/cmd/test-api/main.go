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
		fmt.Println("Usage: BGG_TOKEN=your-token go run . <search-query>")
		os.Exit(1)
	}

	query := os.Args[1]

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

	fmt.Println("\n=== Test Complete ===")
}
