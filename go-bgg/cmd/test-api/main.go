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

	// Test Forum API (if we have a game ID)
	if firstGameID > 0 {
		fmt.Println("\n=== Testing Forum API ===")
		fmt.Printf("Getting forums for game ID %d...\n", firstGameID)
		forumListURL := fmt.Sprintf("%s/forumlist?type=thing&id=%d", bgg.BaseURL, firstGameID)
		fmt.Printf("URL: %s\n", forumListURL)
		fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", forumListURL)

		forums, err := client.GetForums(firstGameID)
		if err != nil {
			fmt.Printf("Error getting forums: %v\n", err)
		} else {
			fmt.Printf("Found %d forums:\n\n", len(forums))
			var firstForumID int
			for i, forum := range forums {
				if i >= 5 {
					fmt.Printf("... and %d more forums\n", len(forums)-5)
					break
				}
				fmt.Printf("  [%d] %s - Threads: %d, Posts: %d\n",
					forum.ID, forum.Title, forum.NumThreads, forum.NumPosts)
				if i == 0 && forum.NumThreads > 0 {
					firstForumID = forum.ID
				}
			}

			// Test Forum Threads API
			if firstForumID > 0 {
				fmt.Println("\n=== Testing Forum Threads API ===")
				fmt.Printf("Getting threads for forum ID %d...\n", firstForumID)
				forumURL := fmt.Sprintf("%s/forum?id=%d&page=1", bgg.BaseURL, firstForumID)
				fmt.Printf("URL: %s\n", forumURL)
				fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", forumURL)

				threadList, err := client.GetForumThreads(firstForumID, 1)
				if err != nil {
					fmt.Printf("Error getting forum threads: %v\n", err)
				} else {
					fmt.Printf("Found %d threads (page %d/%d):\n\n",
						len(threadList.Threads), threadList.Page, threadList.TotalPages)
					var firstThreadID int
					for i, thread := range threadList.Threads {
						if i >= 5 {
							fmt.Printf("... and %d more threads\n", len(threadList.Threads)-5)
							break
						}
						fmt.Printf("  [%d] %s by %s - Articles: %d\n",
							thread.ID, thread.Subject, thread.Author, thread.NumArticles)
						if i == 0 {
							firstThreadID = thread.ID
						}
					}

					// Test Thread API
					if firstThreadID > 0 {
						fmt.Println("\n=== Testing Thread API ===")
						fmt.Printf("Getting thread ID %d...\n", firstThreadID)
						threadURL := fmt.Sprintf("%s/thread?id=%d", bgg.BaseURL, firstThreadID)
						fmt.Printf("URL: %s\n", threadURL)
						fmt.Printf("curl: curl -s -H \"Authorization: Bearer $BGG_TOKEN\" \"%s\" | xmllint --format -\n\n", threadURL)

						thread, err := client.GetThread(firstThreadID)
						if err != nil {
							fmt.Printf("Error getting thread: %v\n", err)
						} else {
							fmt.Printf("Thread: %s\n", thread.Subject)
							fmt.Printf("Articles: %d\n\n", len(thread.Articles))
							for i, article := range thread.Articles {
								if i >= 3 {
									fmt.Printf("... and %d more articles\n", len(thread.Articles)-3)
									break
								}
								body := article.Body
								if len(body) > 100 {
									body = body[:100] + "..."
								}
								fmt.Printf("  [%s] %s\n", article.Username, body)
							}
						}
					}
				}
			}
		}
	}

	fmt.Println("\n=== Test Complete ===")
}
