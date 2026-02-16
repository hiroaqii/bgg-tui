package bgg

import (
	"testing"
)

func TestParseXML(t *testing.T) {
	type simple struct {
		Name string `xml:"name"`
	}

	t.Run("valid XML", func(t *testing.T) {
		body := []byte(`<root><name>test</name></root>`)
		result, err := parseXML[simple](body, "parse failed")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if result.Name != "test" {
			t.Errorf("Name = %q, want %q", result.Name, "test")
		}
	})

	t.Run("invalid XML", func(t *testing.T) {
		body := []byte(`not xml`)
		_, err := parseXML[simple](body, "parse failed")
		if err == nil {
			t.Fatal("expected error for invalid XML, got nil")
		}
		pe, ok := err.(*ParseError)
		if !ok {
			t.Fatalf("expected *ParseError, got %T", err)
		}
		if pe.Message != "parse failed" {
			t.Errorf("Message = %q, want %q", pe.Message, "parse failed")
		}
	})
}
