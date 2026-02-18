package bgg

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestGetGame(t *testing.T) {
	testData, err := os.ReadFile("testdata/thing_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/thing" {
			t.Errorf("expected path '/thing', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		id := r.URL.Query().Get("id")
		if id != "13" {
			t.Errorf("expected id '13', got '%s'", id)
		}

		stats := r.URL.Query().Get("stats")
		if stats != "1" {
			t.Errorf("expected stats '1', got '%s'", stats)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	game, err := client.GetGame(13)
	if err != nil {
		t.Fatalf("GetGame failed: %v", err)
	}

	// Verify basic fields
	if game.ID != 13 {
		t.Errorf("expected ID 13, got %d", game.ID)
	}
	if game.Name != "CATAN" {
		t.Errorf("expected name 'CATAN', got '%s'", game.Name)
	}
	if game.Year != "1995" {
		t.Errorf("expected year '1995', got '%s'", game.Year)
	}

	// Verify player count
	if game.MinPlayers != 3 {
		t.Errorf("expected MinPlayers 3, got %d", game.MinPlayers)
	}
	if game.MaxPlayers != 4 {
		t.Errorf("expected MaxPlayers 4, got %d", game.MaxPlayers)
	}

	// Verify time
	if game.PlayingTime != 120 {
		t.Errorf("expected PlayingTime 120, got %d", game.PlayingTime)
	}
	if game.MinPlayTime != 60 {
		t.Errorf("expected MinPlayTime 60, got %d", game.MinPlayTime)
	}
	if game.MaxPlayTime != 120 {
		t.Errorf("expected MaxPlayTime 120, got %d", game.MaxPlayTime)
	}

	// Verify age
	if game.MinAge != 10 {
		t.Errorf("expected MinAge 10, got %d", game.MinAge)
	}

	// Verify statistics
	if game.Rating < 7.14 || game.Rating > 7.15 {
		t.Errorf("expected Rating ~7.14, got %f", game.Rating)
	}
	if game.UsersRated != 98765 {
		t.Errorf("expected UsersRated 98765, got %d", game.UsersRated)
	}
	if game.Rank != 389 {
		t.Errorf("expected Rank 389, got %d", game.Rank)
	}
	if game.Weight < 2.31 || game.Weight > 2.33 {
		t.Errorf("expected Weight ~2.32, got %f", game.Weight)
	}
	if game.BayesAverage < 7.01 || game.BayesAverage > 7.02 {
		t.Errorf("expected BayesAverage ~7.01234, got %f", game.BayesAverage)
	}
	if game.StdDev < 1.54 || game.StdDev > 1.55 {
		t.Errorf("expected StdDev ~1.54321, got %f", game.StdDev)
	}
	if game.Median != 0 {
		t.Errorf("expected Median 0, got %f", game.Median)
	}
	if game.Owned != 123456 {
		t.Errorf("expected Owned 123456, got %d", game.Owned)
	}
	if game.NumComments != 23456 {
		t.Errorf("expected NumComments 23456, got %d", game.NumComments)
	}
	if game.NumWeights != 7890 {
		t.Errorf("expected NumWeights 7890, got %d", game.NumWeights)
	}

	// Verify designers
	if len(game.Designers) != 1 || game.Designers[0] != "Klaus Teuber" {
		t.Errorf("expected designer 'Klaus Teuber', got %v", game.Designers)
	}

	// Verify artists
	if len(game.Artists) != 2 {
		t.Errorf("expected 2 artists, got %d", len(game.Artists))
	} else {
		if game.Artists[0] != "Volkan Baga" {
			t.Errorf("expected first artist 'Volkan Baga', got '%s'", game.Artists[0])
		}
		if game.Artists[1] != "Tanja Donner" {
			t.Errorf("expected second artist 'Tanja Donner', got '%s'", game.Artists[1])
		}
	}

	// Verify categories
	if len(game.Categories) != 2 {
		t.Errorf("expected 2 categories, got %d", len(game.Categories))
	}

	// Verify mechanics
	if len(game.Mechanics) != 4 {
		t.Errorf("expected 4 mechanics, got %d", len(game.Mechanics))
	}

	// Verify images
	if game.Thumbnail == "" {
		t.Error("expected non-empty Thumbnail")
	}
	if game.Image == "" {
		t.Error("expected non-empty Image")
	}

	// Verify PlayerCountPoll
	if game.PlayerCountPoll == nil {
		t.Fatal("expected PlayerCountPoll to be non-nil")
	}
	pcp := game.PlayerCountPoll
	if pcp.TotalVotes != 2551 {
		t.Errorf("expected TotalVotes 2551, got %d", pcp.TotalVotes)
	}
	if len(pcp.Results) != 5 {
		t.Fatalf("expected 5 player count results, got %d", len(pcp.Results))
	}
	// Check 4-player votes
	r4 := pcp.Results[3]
	if r4.NumPlayers != "4" {
		t.Errorf("expected NumPlayers '4', got '%s'", r4.NumPlayers)
	}
	if r4.Best != 1838 {
		t.Errorf("expected Best 1838, got %d", r4.Best)
	}
	if r4.Recommended != 525 {
		t.Errorf("expected Recommended 525, got %d", r4.Recommended)
	}
	if r4.NotRecommended != 52 {
		t.Errorf("expected NotRecommended 52, got %d", r4.NotRecommended)
	}
	// Check poll-summary
	if pcp.BestWith != "Best with 4 players" {
		t.Errorf("expected BestWith 'Best with 4 players', got '%s'", pcp.BestWith)
	}
	if pcp.RecWith != "Recommended with 3-4 players" {
		t.Errorf("expected RecWith 'Recommended with 3-4 players', got '%s'", pcp.RecWith)
	}
}

func TestGetGame_InvalidID(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.GetGame(0)
	if err == nil {
		t.Error("expected error for invalid ID")
	}

	var notFoundErr *NotFoundError
	if !errors.As(err, &notFoundErr) {
		t.Errorf("expected NotFoundError, got %T", err)
	}
}

func TestGetGame_NotFound(t *testing.T) {
	emptyResponse := `<?xml version="1.0" encoding="utf-8"?><items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse"></items>`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(emptyResponse))
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err := client.GetGame(999999)
	if err == nil {
		t.Error("expected error for non-existent game")
	}

	var notFoundErr *NotFoundError
	if !errors.As(err, &notFoundErr) {
		t.Errorf("expected NotFoundError, got %T", err)
	}
}

func TestGetGameJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/thing_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetGameJSON(13)
	if err != nil {
		t.Fatalf("GetGameJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var game Game
	if err := json.Unmarshal([]byte(jsonStr), &game); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if game.ID != 13 {
		t.Errorf("expected ID 13, got %d", game.ID)
	}
}

func TestGetGames(t *testing.T) {
	testData, err := os.ReadFile("testdata/thing_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify comma-separated IDs
		id := r.URL.Query().Get("id")
		if id != "13,278" {
			t.Errorf("expected id '13,278', got '%s'", id)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	games, err := client.GetGames([]int{13, 278})
	if err != nil {
		t.Fatalf("GetGames failed: %v", err)
	}

	if len(games) == 0 {
		t.Error("expected at least one game")
	}
}

func TestGetGames_Empty(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	games, err := client.GetGames([]int{})
	if err != nil {
		t.Fatalf("GetGames failed: %v", err)
	}

	if len(games) != 0 {
		t.Errorf("expected 0 games, got %d", len(games))
	}
}

func TestGetGames_TooMany(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	ids := make([]int, 21)
	for i := range ids {
		ids[i] = i + 1
	}

	_, err := client.GetGames(ids)
	if err == nil {
		t.Error("expected error for too many IDs")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestDecodeDescription(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{
			input:    "Hello &amp; World",
			expected: "Hello & World",
		},
		{
			input:    "Line1&#10;Line2",
			expected: "Line1\nLine2",
		},
		{
			input:    "&lt;tag&gt;",
			expected: "<tag>",
		},
	}

	for _, tt := range tests {
		result := decodeDescription(tt.input)
		if result != tt.expected {
			t.Errorf("decodeDescription(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}
