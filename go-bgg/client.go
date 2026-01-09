package bgg

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	// BaseURL is the base URL for the BGG XML API.
	BaseURL = "https://boardgamegeek.com/xmlapi2"

	// DefaultTimeout is the default HTTP request timeout.
	DefaultTimeout = 30 * time.Second

	// DefaultRetryCount is the default number of retry attempts.
	DefaultRetryCount = 3

	// DefaultRetryDelay is the default delay between retries.
	DefaultRetryDelay = 2 * time.Second
)

// Config holds the configuration for the BGG API client.
type Config struct {
	Token      string        // Required: BGG API Bearer Token
	Timeout    time.Duration // Optional: HTTP request timeout (default: 30s)
	RetryCount int           // Optional: Number of retry attempts (default: 3)
	RetryDelay time.Duration // Optional: Delay between retries (default: 2s)
}

// Client is the BGG API client.
type Client struct {
	httpClient *http.Client
	token      string
	retryCount int
	retryDelay time.Duration
}

// NewClient creates a new BGG API client.
func NewClient(cfg Config) (*Client, error) {
	if cfg.Token == "" {
		return nil, newAuthError("token is required", nil)
	}

	timeout := cfg.Timeout
	if timeout == 0 {
		timeout = DefaultTimeout
	}

	retryCount := cfg.RetryCount
	if retryCount == 0 {
		retryCount = DefaultRetryCount
	}

	retryDelay := cfg.RetryDelay
	if retryDelay == 0 {
		retryDelay = DefaultRetryDelay
	}

	return &Client{
		httpClient: &http.Client{
			Timeout: timeout,
		},
		token:      cfg.Token,
		retryCount: retryCount,
		retryDelay: retryDelay,
	}, nil
}

// doRequest performs an HTTP GET request with authentication and retry logic.
func (c *Client) doRequest(endpoint string) ([]byte, error) {
	url := BaseURL + endpoint

	var lastErr error
	for attempt := 0; attempt <= c.retryCount; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryDelay * time.Duration(attempt)) // Exponential backoff
		}

		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			return nil, newNetworkError("failed to create request", 0, err)
		}

		req.Header.Set("Authorization", "Bearer "+c.token)
		req.Header.Set("Accept", "application/xml")

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = newNetworkError("request failed", 0, err)
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			lastErr = newNetworkError("failed to read response body", resp.StatusCode, err)
			continue
		}

		switch resp.StatusCode {
		case http.StatusOK:
			return body, nil

		case http.StatusAccepted:
			// 202 Accepted - BGG is processing the request, retry needed
			lastErr = newNetworkError("request accepted but not ready, retry needed", resp.StatusCode, nil)
			continue

		case http.StatusUnauthorized:
			return nil, newAuthError("invalid or expired token", nil)

		case http.StatusNotFound:
			return nil, newNotFoundError(0)

		case http.StatusTooManyRequests:
			retryAfter := 5 * time.Second // Default retry after
			if ra := resp.Header.Get("Retry-After"); ra != "" {
				if d, err := time.ParseDuration(ra + "s"); err == nil {
					retryAfter = d
				}
			}
			lastErr = newRateLimitError("rate limit exceeded", retryAfter)
			time.Sleep(retryAfter)
			continue

		case http.StatusServiceUnavailable:
			lastErr = newNetworkError("service unavailable", resp.StatusCode, nil)
			continue

		default:
			return nil, newNetworkError(fmt.Sprintf("unexpected status code: %d", resp.StatusCode), resp.StatusCode, nil)
		}
	}

	if lastErr != nil {
		return nil, lastErr
	}
	return nil, newNetworkError("max retries exceeded", 0, nil)
}

// doRequestWithRetryOn202 performs a request with special handling for 202 responses.
// This is used for Collection API which returns 202 when data is being prepared.
func (c *Client) doRequestWithRetryOn202(endpoint string, maxRetries int) ([]byte, error) {
	url := BaseURL + endpoint

	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryDelay)
		}

		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			return nil, newNetworkError("failed to create request", 0, err)
		}

		req.Header.Set("Authorization", "Bearer "+c.token)
		req.Header.Set("Accept", "application/xml")

		resp, err := c.httpClient.Do(req)
		if err != nil {
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			continue
		}

		switch resp.StatusCode {
		case http.StatusOK:
			return body, nil

		case http.StatusAccepted:
			// 202 - Collection is being prepared, retry
			continue

		case http.StatusUnauthorized:
			return nil, newAuthError("invalid or expired token", nil)

		case http.StatusNotFound:
			return nil, newNotFoundError(0)

		case http.StatusTooManyRequests:
			retryAfter := 5 * time.Second
			if ra := resp.Header.Get("Retry-After"); ra != "" {
				if d, err := time.ParseDuration(ra + "s"); err == nil {
					retryAfter = d
				}
			}
			return nil, newRateLimitError("rate limit exceeded", retryAfter)

		default:
			return nil, newNetworkError(fmt.Sprintf("unexpected status code: %d", resp.StatusCode), resp.StatusCode, nil)
		}
	}

	return nil, newNetworkError("collection not ready after max retries", http.StatusAccepted, nil)
}
