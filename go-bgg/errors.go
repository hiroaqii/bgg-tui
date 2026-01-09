package bgg

import (
	"fmt"
	"time"
)

// AuthError represents an authentication error (invalid token).
type AuthError struct {
	Message string
	Cause   error
}

func (e *AuthError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *AuthError) Unwrap() error {
	return e.Cause
}

// RateLimitError represents a rate limit error.
type RateLimitError struct {
	Message    string
	Cause      error
	RetryAfter time.Duration
}

func (e *RateLimitError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *RateLimitError) Unwrap() error {
	return e.Cause
}

// NotFoundError represents a resource not found error.
type NotFoundError struct {
	Message string
	Cause   error
	ID      int
}

func (e *NotFoundError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *NotFoundError) Unwrap() error {
	return e.Cause
}

// NetworkError represents a network or HTTP error.
type NetworkError struct {
	Message    string
	Cause      error
	StatusCode int
}

func (e *NetworkError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *NetworkError) Unwrap() error {
	return e.Cause
}

// ParseError represents an XML parsing error.
type ParseError struct {
	Message string
	Cause   error
}

func (e *ParseError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *ParseError) Unwrap() error {
	return e.Cause
}

// newAuthError creates a new AuthError.
func newAuthError(message string, cause error) *AuthError {
	return &AuthError{
		Message: message,
		Cause:   cause,
	}
}

// newRateLimitError creates a new RateLimitError.
func newRateLimitError(message string, retryAfter time.Duration) *RateLimitError {
	return &RateLimitError{
		Message:    message,
		RetryAfter: retryAfter,
	}
}

// newNotFoundError creates a new NotFoundError.
func newNotFoundError(id int) *NotFoundError {
	return &NotFoundError{
		Message: fmt.Sprintf("resource with ID %d not found", id),
		ID:      id,
	}
}

// newNetworkError creates a new NetworkError.
func newNetworkError(message string, statusCode int, cause error) *NetworkError {
	return &NetworkError{
		Message:    message,
		StatusCode: statusCode,
		Cause:      cause,
	}
}

// newParseError creates a new ParseError.
func newParseError(message string, cause error) *ParseError {
	return &ParseError{
		Message: message,
		Cause:   cause,
	}
}
