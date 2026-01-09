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

	fmt.Println("=== Testing Search API ===")
	fmt.Printf("Searching for '%s'...\n", query)
	url := fmt.Sprintf("%s/search?query=%s&type=boardgame,boardgameexpansion", bgg.BaseURL, query)
	fmt.Printf("URL: %s\n", url)
	fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", url)

	results, err := client.SearchGames(query)
	if err != nil {
		fmt.Printf("Error searching games: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Found %d results:\n\n", len(results))
	for i, game := range results {
		if i >= 10 {
			fmt.Printf("... and %d more results\n", len(results)-10)
			break
		}
		fmt.Printf("  [%d] %s (%s) - Type: %s\n", game.ID, game.Name, game.Year, game.Type)
	}

	fmt.Println("\n=== Test Complete ===")
}
