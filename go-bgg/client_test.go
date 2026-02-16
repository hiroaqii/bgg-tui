package bgg

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestNewClient(t *testing.T) {
	tests := []struct {
		name    string
		cfg     Config
		wantErr bool
	}{
		{
			name: "valid config with token",
			cfg: Config{
				Token: "test-token",
			},
			wantErr: false,
		},
		{
			name:    "missing token",
			cfg:     Config{},
			wantErr: true,
		},
		{
			name: "custom timeout",
			cfg: Config{
				Token:   "test-token",
				Timeout: 60 * time.Second,
			},
			wantErr: false,
		},
		{
			name: "custom retry settings",
			cfg: Config{
				Token:      "test-token",
				RetryCount: 5,
				RetryDelay: 1 * time.Second,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := NewClient(tt.cfg)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewClient() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && client == nil {
				t.Error("NewClient() returned nil client")
			}
		})
	}
}

func TestDoRequest_Success(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-token" {
			t.Errorf("expected Authorization 'Bearer test-token', got %q", auth)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("<items></items>"))
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 3,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	body, err := client.doRequest("/hot")
	if err != nil {
		t.Fatalf("doRequest() error = %v", err)
	}
	if string(body) != "<items></items>" {
		t.Errorf("body = %q, want %q", string(body), "<items></items>")
	}
}

func TestDoRequest_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "invalid-token",
		retryCount: 0,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	_, err := client.doRequest("/hot")
	if err == nil {
		t.Fatal("expected error for 401 response")
	}

	var authErr *AuthError
	if !errors.As(err, &authErr) {
		t.Errorf("expected AuthError, got %T: %v", err, err)
	}
}

func TestDoRequest_NotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 0,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	_, err := client.doRequest("/thing?id=999999")
	if err == nil {
		t.Fatal("expected error for 404 response")
	}

	var notFoundErr *NotFoundError
	if !errors.As(err, &notFoundErr) {
		t.Errorf("expected NotFoundError, got %T: %v", err, err)
	}
}

func TestDoRequest_RetryOn202(t *testing.T) {
	var attempts int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&attempts, 1)
		if n < 3 {
			w.WriteHeader(http.StatusAccepted)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("<ok/>"))
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 5,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	body, err := client.doRequest("/collection")
	if err != nil {
		t.Fatalf("doRequest() error = %v", err)
	}
	if string(body) != "<ok/>" {
		t.Errorf("body = %q, want %q", string(body), "<ok/>")
	}
	if atomic.LoadInt32(&attempts) != 3 {
		t.Errorf("expected 3 attempts, got %d", atomic.LoadInt32(&attempts))
	}
}

func TestDoRequest_429WithRetry(t *testing.T) {
	var attempts int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&attempts, 1)
		if n == 1 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("<ok/>"))
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 3,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	body, err := client.doRequest("/hot")
	if err != nil {
		t.Fatalf("doRequest() error = %v", err)
	}
	if string(body) != "<ok/>" {
		t.Errorf("body = %q, want %q", string(body), "<ok/>")
	}
}

func TestDoRequestWithRetryOn202_429ReturnsError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "5")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 3,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	_, err := client.doRequestWithRetryOn202("/collection", 1)
	if err == nil {
		t.Fatal("expected error for 429 in doRequestWithRetryOn202")
	}

	var rateLimitErr *RateLimitError
	if !errors.As(err, &rateLimitErr) {
		t.Errorf("expected RateLimitError, got %T: %v", err, err)
	}
}

func TestDoRequest_503Retry(t *testing.T) {
	var attempts int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&attempts, 1)
		if n == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("<ok/>"))
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 3,
		retryDelay: 10 * time.Millisecond,
		baseURL:    server.URL,
	}

	body, err := client.doRequest("/hot")
	if err != nil {
		t.Fatalf("doRequest() error = %v", err)
	}
	if string(body) != "<ok/>" {
		t.Errorf("body = %q, want %q", string(body), "<ok/>")
	}
}

func TestErrorTypes(t *testing.T) {
	t.Run("AuthError", func(t *testing.T) {
		err := newAuthError("invalid token", nil)
		if err.Error() != "invalid token" {
			t.Errorf("expected 'invalid token', got '%s'", err.Error())
		}

		var authErr *AuthError
		if !errors.As(err, &authErr) {
			t.Error("expected error to be AuthError")
		}
	})

	t.Run("AuthError with cause", func(t *testing.T) {
		cause := errors.New("underlying error")
		err := newAuthError("invalid token", cause)
		if err.Error() != "invalid token: underlying error" {
			t.Errorf("expected 'invalid token: underlying error', got '%s'", err.Error())
		}
	})

	t.Run("RateLimitError", func(t *testing.T) {
		err := newRateLimitError("rate limited", 5*time.Second)
		if err.Error() != "rate limited" {
			t.Errorf("expected 'rate limited', got '%s'", err.Error())
		}
		if err.RetryAfter != 5*time.Second {
			t.Errorf("expected RetryAfter 5s, got %v", err.RetryAfter)
		}

		var rateLimitErr *RateLimitError
		if !errors.As(err, &rateLimitErr) {
			t.Error("expected error to be RateLimitError")
		}
	})

	t.Run("NotFoundError", func(t *testing.T) {
		err := newNotFoundError(123)
		if err.ID != 123 {
			t.Errorf("expected ID 123, got %d", err.ID)
		}

		var notFoundErr *NotFoundError
		if !errors.As(err, &notFoundErr) {
			t.Error("expected error to be NotFoundError")
		}
	})

	t.Run("NetworkError", func(t *testing.T) {
		err := newNetworkError("connection failed", 500, nil)
		if err.StatusCode != 500 {
			t.Errorf("expected StatusCode 500, got %d", err.StatusCode)
		}

		var networkErr *NetworkError
		if !errors.As(err, &networkErr) {
			t.Error("expected error to be NetworkError")
		}
	})

	t.Run("ParseError", func(t *testing.T) {
		cause := errors.New("xml syntax error")
		err := newParseError("failed to parse XML", cause)
		if err.Error() != "failed to parse XML: xml syntax error" {
			t.Errorf("unexpected error message: %s", err.Error())
		}

		var parseErr *ParseError
		if !errors.As(err, &parseErr) {
			t.Error("expected error to be ParseError")
		}
	})
}

func TestError_Unwrap(t *testing.T) {
	cause := errors.New("root cause")
	err := &AuthError{
		Message: "wrapper",
		Cause:   cause,
	}

	unwrapped := err.Unwrap()
	if unwrapped != cause {
		t.Errorf("expected unwrapped error to be root cause")
	}
}

func TestToJSON(t *testing.T) {
	type sample struct {
		Name string `json:"name"`
		Age  int    `json:"age"`
	}

	result, err := toJSON(sample{Name: "test", Age: 42})
	if err != nil {
		t.Fatalf("toJSON() error = %v", err)
	}
	if result == "" {
		t.Error("toJSON() returned empty string")
	}
	if !contains(result, `"name": "test"`) {
		t.Errorf("toJSON() result missing name field: %s", result)
	}
	if !contains(result, `"age": 42`) {
		t.Errorf("toJSON() result missing age field: %s", result)
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
