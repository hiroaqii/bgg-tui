package bgg

import (
	"testing"
)

func TestExtractBoardGameRank(t *testing.T) {
	tests := []struct {
		name  string
		ranks []xmlRank
		want  int
	}{
		{
			name:  "ranked game",
			ranks: []xmlRank{{Name: "boardgame", Value: "42"}},
			want:  42,
		},
		{
			name:  "not ranked",
			ranks: []xmlRank{{Name: "boardgame", Value: "Not Ranked"}},
			want:  0,
		},
		{
			name:  "no boardgame rank",
			ranks: []xmlRank{{Name: "strategygames", Value: "10"}},
			want:  0,
		},
		{
			name:  "empty ranks",
			ranks: nil,
			want:  0,
		},
		{
			name:  "boardgame rank among others",
			ranks: []xmlRank{{Name: "strategygames", Value: "5"}, {Name: "boardgame", Value: "100"}},
			want:  100,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractBoardGameRank(tt.ranks)
			if got != tt.want {
				t.Errorf("extractBoardGameRank() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestDecodeHTML(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "HTML entities",
			input: "Hello &amp; World",
			want:  "Hello & World",
		},
		{
			name:  "numeric entity &#10; to newline",
			input: "Line1&#10;Line2",
			want:  "Line1\nLine2",
		},
		{
			name:  "angle bracket entities",
			input: "&lt;tag&gt;",
			want:  "<tag>",
		},
		{
			name:  "no entities",
			input: "plain text",
			want:  "plain text",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := decodeHTML(tt.input)
			if got != tt.want {
				t.Errorf("decodeHTML(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

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
