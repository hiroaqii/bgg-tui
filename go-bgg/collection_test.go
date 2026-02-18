package bgg

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
)

func TestGetCollection(t *testing.T) {
	testData, err := os.ReadFile("testdata/collection_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/collection" {
			t.Errorf("expected path '/collection', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		username := r.URL.Query().Get("username")
		if username != "testuser" {
			t.Errorf("expected username 'testuser', got '%s'", username)
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

	items, err := client.GetCollection("testuser", CollectionOptions{})
	if err != nil {
		t.Fatalf("GetCollection failed: %v", err)
	}

	if len(items) != 3 {
		t.Errorf("expected 3 items, got %d", len(items))
	}

	// Verify first item
	if items[0].ID != 13 {
		t.Errorf("expected ID 13, got %d", items[0].ID)
	}
	if items[0].Name != "CATAN" {
		t.Errorf("expected name 'CATAN', got '%s'", items[0].Name)
	}
	if items[0].Year != "1995" {
		t.Errorf("expected year '1995', got '%s'", items[0].Year)
	}
	if items[0].NumPlays != 25 {
		t.Errorf("expected NumPlays 25, got %d", items[0].NumPlays)
	}
	if !items[0].Owned {
		t.Error("expected Owned to be true")
	}
	if !items[0].WantToPlay {
		t.Error("expected WantToPlay to be true")
	}
	if items[0].Rating != 8 {
		t.Errorf("expected Rating 8, got %f", items[0].Rating)
	}
	if items[0].BGGRating < 7.13 || items[0].BGGRating > 7.15 {
		t.Errorf("expected BGGRating ~7.14, got %f", items[0].BGGRating)
	}
	if items[0].Rank != 42 {
		t.Errorf("expected Rank 42, got %d", items[0].Rank)
	}

	// Verify wishlist item
	if !items[2].Wishlist {
		t.Error("expected third item to be on wishlist")
	}
	if items[2].Owned {
		t.Error("expected third item to not be owned")
	}
}

func TestGetCollection_OwnedOnly(t *testing.T) {
	testData, err := os.ReadFile("testdata/collection_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify own parameter is present
		own := r.URL.Query().Get("own")
		if own != "1" {
			t.Errorf("expected own '1', got '%s'", own)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err = client.GetCollection("testuser", CollectionOptions{OwnedOnly: true})
	if err != nil {
		t.Fatalf("GetCollection failed: %v", err)
	}
}

func TestGetCollection_EmptyUsername(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.GetCollection("", CollectionOptions{})
	if err == nil {
		t.Error("expected error for empty username")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestGetCollection_RetryOn202(t *testing.T) {
	testData, err := os.ReadFile("testdata/collection_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	var requestCount int32

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		count := atomic.AddInt32(&requestCount, 1)

		// Return 202 for first 2 requests, then 200
		if count <= 2 {
			w.WriteHeader(http.StatusAccepted)
			w.Write([]byte(""))
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	items, err := client.GetCollection("testuser", CollectionOptions{})
	if err != nil {
		t.Fatalf("GetCollection failed: %v", err)
	}

	if len(items) != 3 {
		t.Errorf("expected 3 items, got %d", len(items))
	}

	if requestCount != 3 {
		t.Errorf("expected 3 requests (2 retries), got %d", requestCount)
	}
}

func TestGetCollectionJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/collection_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetCollectionJSON("testuser", CollectionOptions{})
	if err != nil {
		t.Fatalf("GetCollectionJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var items []CollectionItem
	if err := json.Unmarshal([]byte(jsonStr), &items); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if len(items) != 3 {
		t.Errorf("expected 3 items, got %d", len(items))
	}
}

func TestGetCollection_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err := client.GetCollection("testuser", CollectionOptions{})
	if err == nil {
		t.Error("expected error for unauthorized request")
	}
}
