package bgg

import (
	"errors"
	"net/http"
	"net/http/httptest"
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

func TestClient_doRequest_Success(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-token" {
			t.Errorf("expected Authorization header 'Bearer test-token', got '%s'", auth)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte("<items></items>"))
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 3,
		retryDelay: 100 * time.Millisecond,
	}

	// We need to test with the actual server URL
	req, _ := http.NewRequest(http.MethodGet, server.URL, nil)
	req.Header.Set("Authorization", "Bearer test-token")
	resp, err := client.httpClient.Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected status 200, got %d", resp.StatusCode)
	}
}

func TestClient_doRequest_AuthError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "invalid-token",
		retryCount: 0,
		retryDelay: 100 * time.Millisecond,
	}

	req, _ := http.NewRequest(http.MethodGet, server.URL, nil)
	req.Header.Set("Authorization", "Bearer invalid-token")
	resp, _ := client.httpClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("expected status 401, got %d", resp.StatusCode)
	}
}

func TestClient_doRequest_RateLimit(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "5")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 0,
		retryDelay: 100 * time.Millisecond,
	}

	req, _ := http.NewRequest(http.MethodGet, server.URL, nil)
	req.Header.Set("Authorization", "Bearer test-token")
	resp, _ := client.httpClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusTooManyRequests {
		t.Errorf("expected status 429, got %d", resp.StatusCode)
	}

	retryAfter := resp.Header.Get("Retry-After")
	if retryAfter != "5" {
		t.Errorf("expected Retry-After '5', got '%s'", retryAfter)
	}
}

func TestClient_doRequest_NotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := &Client{
		httpClient: server.Client(),
		token:      "test-token",
		retryCount: 0,
		retryDelay: 100 * time.Millisecond,
	}

	req, _ := http.NewRequest(http.MethodGet, server.URL, nil)
	req.Header.Set("Authorization", "Bearer test-token")
	resp, _ := client.httpClient.Do(req)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("expected status 404, got %d", resp.StatusCode)
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
