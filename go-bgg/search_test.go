package bgg

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

// createTestClient creates a Client that uses the test server.
func createTestClient(t *testing.T, server *httptest.Server) *Client {
	t.Helper()

	return &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 0,
		retryDelay: 100 * time.Millisecond,
		baseURL:    server.URL,
	}
}

func TestSearchGames(t *testing.T) {
	testData, err := os.ReadFile("testdata/search_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/search" {
			t.Errorf("expected path '/search', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		query := r.URL.Query().Get("query")
		if query != "catan" {
			t.Errorf("expected query 'catan', got '%s'", query)
		}

		typeParam := r.URL.Query().Get("type")
		if typeParam != "boardgame,boardgameexpansion" {
			t.Errorf("expected type 'boardgame,boardgameexpansion', got '%s'", typeParam)
		}

		// Verify authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-token" {
			t.Errorf("expected 'Bearer test-token', got '%s'", auth)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	results, err := client.SearchGames("catan")
	if err != nil {
		t.Fatalf("SearchGames failed: %v", err)
	}

	if len(results) != 3 {
		t.Errorf("expected 3 results, got %d", len(results))
	}

	// Verify first result
	if results[0].ID != 13 {
		t.Errorf("expected ID 13, got %d", results[0].ID)
	}
	if results[0].Name != "Catan" {
		t.Errorf("expected name 'Catan', got '%s'", results[0].Name)
	}
	if results[0].Year != "1995" {
		t.Errorf("expected year '1995', got '%s'", results[0].Year)
	}
	if results[0].Type != "boardgame" {
		t.Errorf("expected type 'boardgame', got '%s'", results[0].Type)
	}

	// Verify expansion type
	if results[1].Type != "boardgameexpansion" {
		t.Errorf("expected type 'boardgameexpansion', got '%s'", results[1].Type)
	}
}

func TestSearchGames_EmptyQuery(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.SearchGames("")
	if err == nil {
		t.Error("expected error for empty query")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestSearchGames_EmptyResults(t *testing.T) {
	emptyResponse := `<?xml version="1.0" encoding="utf-8"?><items total="0" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse"></items>`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(emptyResponse))
	}))
	defer server.Close()

	client := createTestClient(t, server)

	results, err := client.SearchGames("nonexistentgame123456")
	if err != nil {
		t.Fatalf("SearchGames failed: %v", err)
	}

	if len(results) != 0 {
		t.Errorf("expected 0 results, got %d", len(results))
	}
}

func TestSearchGamesJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/search_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.SearchGamesJSON("catan")
	if err != nil {
		t.Fatalf("SearchGamesJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var results []GameSearchResult
	if err := json.Unmarshal([]byte(jsonStr), &results); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if len(results) != 3 {
		t.Errorf("expected 3 results, got %d", len(results))
	}
}

func TestSearchGames_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err := client.SearchGames("catan")
	if err == nil {
		t.Error("expected error for unauthorized request")
	}

	var authErr *AuthError
	if !errors.As(err, &authErr) {
		t.Errorf("expected AuthError, got %T", err)
	}
}
