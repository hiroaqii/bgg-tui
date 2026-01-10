package bgg

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestGetHotGames(t *testing.T) {
	testData, err := os.ReadFile("testdata/hot_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/hot" {
			t.Errorf("expected path '/hot', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		typeParam := r.URL.Query().Get("type")
		if typeParam != "boardgame" {
			t.Errorf("expected type 'boardgame', got '%s'", typeParam)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	games, err := client.GetHotGames()
	if err != nil {
		t.Fatalf("GetHotGames failed: %v", err)
	}

	if len(games) != 5 {
		t.Errorf("expected 5 games, got %d", len(games))
	}

	// Verify first game
	if games[0].ID != 224517 {
		t.Errorf("expected ID 224517, got %d", games[0].ID)
	}
	if games[0].Rank != 1 {
		t.Errorf("expected Rank 1, got %d", games[0].Rank)
	}
	if games[0].Name != "Brass: Birmingham" {
		t.Errorf("expected name 'Brass: Birmingham', got '%s'", games[0].Name)
	}
	if games[0].Year != "2018" {
		t.Errorf("expected year '2018', got '%s'", games[0].Year)
	}
	if games[0].Thumbnail == "" {
		t.Error("expected non-empty Thumbnail")
	}

	// Verify ranks are sequential
	for i, game := range games {
		expectedRank := i + 1
		if game.Rank != expectedRank {
			t.Errorf("expected rank %d, got %d", expectedRank, game.Rank)
		}
	}
}

func TestGetHotGamesJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/hot_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetHotGamesJSON()
	if err != nil {
		t.Fatalf("GetHotGamesJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var games []HotGame
	if err := json.Unmarshal([]byte(jsonStr), &games); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if len(games) != 5 {
		t.Errorf("expected 5 games, got %d", len(games))
	}
}

func TestGetHotGames_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err := client.GetHotGames()
	if err == nil {
		t.Error("expected error for unauthorized request")
	}
}
