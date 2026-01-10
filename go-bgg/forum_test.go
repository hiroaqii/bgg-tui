package bgg

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestGetForums(t *testing.T) {
	testData, err := os.ReadFile("testdata/forumlist_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/forumlist" {
			t.Errorf("expected path '/forumlist', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		typeParam := r.URL.Query().Get("type")
		if typeParam != "thing" {
			t.Errorf("expected type 'thing', got '%s'", typeParam)
		}

		idParam := r.URL.Query().Get("id")
		if idParam != "13" {
			t.Errorf("expected id '13', got '%s'", idParam)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	forums, err := client.GetForums(13)
	if err != nil {
		t.Fatalf("GetForums failed: %v", err)
	}

	if len(forums) != 3 {
		t.Errorf("expected 3 forums, got %d", len(forums))
	}

	// Verify first forum
	if forums[0].ID != 19 {
		t.Errorf("expected ID 19, got %d", forums[0].ID)
	}
	if forums[0].Title != "Reviews" {
		t.Errorf("expected title 'Reviews', got '%s'", forums[0].Title)
	}
	if forums[0].NumThreads != 150 {
		t.Errorf("expected NumThreads 150, got %d", forums[0].NumThreads)
	}
	if forums[0].NumPosts != 450 {
		t.Errorf("expected NumPosts 450, got %d", forums[0].NumPosts)
	}

	// Verify third forum (General)
	if forums[2].Title != "General" {
		t.Errorf("expected title 'General', got '%s'", forums[2].Title)
	}
	if forums[2].NumThreads != 500 {
		t.Errorf("expected NumThreads 500, got %d", forums[2].NumThreads)
	}
}

func TestGetForums_InvalidID(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.GetForums(0)
	if err == nil {
		t.Error("expected error for invalid ID")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestGetForumsJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/forumlist_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetForumsJSON(13)
	if err != nil {
		t.Fatalf("GetForumsJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var forums []Forum
	if err := json.Unmarshal([]byte(jsonStr), &forums); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if len(forums) != 3 {
		t.Errorf("expected 3 forums, got %d", len(forums))
	}
}

func TestGetForumThreads(t *testing.T) {
	testData, err := os.ReadFile("testdata/forum_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/forum" {
			t.Errorf("expected path '/forum', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		idParam := r.URL.Query().Get("id")
		if idParam != "21" {
			t.Errorf("expected id '21', got '%s'", idParam)
		}

		pageParam := r.URL.Query().Get("page")
		if pageParam != "1" {
			t.Errorf("expected page '1', got '%s'", pageParam)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	threadList, err := client.GetForumThreads(21, 1)
	if err != nil {
		t.Fatalf("GetForumThreads failed: %v", err)
	}

	if len(threadList.Threads) != 3 {
		t.Errorf("expected 3 threads, got %d", len(threadList.Threads))
	}

	// Verify first thread
	if threadList.Threads[0].ID != 1001 {
		t.Errorf("expected ID 1001, got %d", threadList.Threads[0].ID)
	}
	if threadList.Threads[0].Subject != "Best strategy for beginners?" {
		t.Errorf("expected subject 'Best strategy for beginners?', got '%s'", threadList.Threads[0].Subject)
	}
	if threadList.Threads[0].Author != "player1" {
		t.Errorf("expected author 'player1', got '%s'", threadList.Threads[0].Author)
	}
	if threadList.Threads[0].NumArticles != 15 {
		t.Errorf("expected NumArticles 15, got %d", threadList.Threads[0].NumArticles)
	}

	// Verify pagination
	if threadList.Page != 1 {
		t.Errorf("expected Page 1, got %d", threadList.Page)
	}
	// 120 threads / 50 per page = 3 pages
	if threadList.TotalPages != 3 {
		t.Errorf("expected TotalPages 3, got %d", threadList.TotalPages)
	}
}

func TestGetForumThreads_InvalidID(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.GetForumThreads(0, 1)
	if err == nil {
		t.Error("expected error for invalid ID")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestGetForumThreads_DefaultPage(t *testing.T) {
	testData, err := os.ReadFile("testdata/forum_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify page defaults to 1
		pageParam := r.URL.Query().Get("page")
		if pageParam != "1" {
			t.Errorf("expected page '1', got '%s'", pageParam)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	// Pass 0 for page, should default to 1
	_, err = client.GetForumThreads(21, 0)
	if err != nil {
		t.Fatalf("GetForumThreads failed: %v", err)
	}
}

func TestGetForumThreadsJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/forum_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetForumThreadsJSON(21, 1)
	if err != nil {
		t.Fatalf("GetForumThreadsJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var threadList ThreadList
	if err := json.Unmarshal([]byte(jsonStr), &threadList); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if len(threadList.Threads) != 3 {
		t.Errorf("expected 3 threads, got %d", len(threadList.Threads))
	}
}

func TestGetThread(t *testing.T) {
	testData, err := os.ReadFile("testdata/thread_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify request path
		if r.URL.Path != "/thread" {
			t.Errorf("expected path '/thread', got '%s'", r.URL.Path)
		}

		// Verify query parameters
		idParam := r.URL.Query().Get("id")
		if idParam != "1001" {
			t.Errorf("expected id '1001', got '%s'", idParam)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	thread, err := client.GetThread(1001)
	if err != nil {
		t.Fatalf("GetThread failed: %v", err)
	}

	if thread.ID != 1001 {
		t.Errorf("expected ID 1001, got %d", thread.ID)
	}
	if thread.Subject != "Best strategy for beginners?" {
		t.Errorf("expected subject 'Best strategy for beginners?', got '%s'", thread.Subject)
	}

	if len(thread.Articles) != 3 {
		t.Errorf("expected 3 articles, got %d", len(thread.Articles))
	}

	// Verify first article
	if thread.Articles[0].ID != 5001 {
		t.Errorf("expected article ID 5001, got %d", thread.Articles[0].ID)
	}
	if thread.Articles[0].Username != "player1" {
		t.Errorf("expected username 'player1', got '%s'", thread.Articles[0].Username)
	}

	// Verify HTML entity decoding in second article
	if thread.Articles[1].Body == "" {
		t.Error("expected non-empty body")
	}
	// Check that &apos; was decoded to '
	if thread.Articles[1].Body[len(thread.Articles[1].Body)-1] != '!' {
		t.Error("expected body to end with '!'")
	}
}

func TestGetThread_InvalidID(t *testing.T) {
	client, _ := NewClient(Config{Token: "test-token"})

	_, err := client.GetThread(0)
	if err == nil {
		t.Error("expected error for invalid ID")
	}

	var parseErr *ParseError
	if !errors.As(err, &parseErr) {
		t.Errorf("expected ParseError, got %T", err)
	}
}

func TestGetThreadJSON(t *testing.T) {
	testData, err := os.ReadFile("testdata/thread_response.xml")
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(testData)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	jsonStr, err := client.GetThreadJSON(1001)
	if err != nil {
		t.Fatalf("GetThreadJSON failed: %v", err)
	}

	// Verify it's valid JSON
	var thread Thread
	if err := json.Unmarshal([]byte(jsonStr), &thread); err != nil {
		t.Fatalf("failed to parse JSON output: %v", err)
	}

	if thread.ID != 1001 {
		t.Errorf("expected ID 1001, got %d", thread.ID)
	}
	if len(thread.Articles) != 3 {
		t.Errorf("expected 3 articles, got %d", len(thread.Articles))
	}
}

func TestGetForums_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := createTestClient(t, server)

	_, err := client.GetForums(13)
	if err == nil {
		t.Error("expected error for unauthorized request")
	}
}
