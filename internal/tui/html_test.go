package tui

import (
	"strings"
	"testing"
)

func TestHtmlToText(t *testing.T) {
	tests := []struct {
		name  string
		html  string
		width int
		want  []string
	}{
		{
			name:  "plain text without tags",
			html:  "Hello World",
			width: 80,
			want:  []string{"Hello World"},
		},
		{
			name:  "br line break",
			html:  "Line1<br>Line2",
			width: 80,
			want:  []string{"Line1", "Line2"},
		},
		{
			name:  "p paragraphs",
			html:  "<p>Para1</p><p>Para2</p>",
			width: 80,
			want:  []string{"Para1", "", "Para2"},
		},
		{
			name:  "inline tags stripped",
			html:  "<b>bold</b> and <i>italic</i>",
			width: 80,
			want:  []string{"bold and italic"},
		},
		{
			name:  "a href link",
			html:  `<a href="https://example.com">click</a>`,
			width: 80,
			want:  []string{"click (https://example.com)"},
		},
		{
			name:  "blockquote",
			html:  "<blockquote>quoted text</blockquote>",
			width: 80,
			want:  []string{"> quoted text"},
		},
		{
			name:  "ul li unordered list",
			html:  "<ul><li>A</li><li>B</li></ul>",
			width: 80,
			want:  []string{"- A", "- B"},
		},
		{
			name:  "ol li ordered list",
			html:  "<ol><li>A</li><li>B</li></ol>",
			width: 80,
			want:  []string{"1. A", "2. B"},
		},
		{
			name:  "html entities",
			html:  "&amp; &lt; &gt;",
			width: 80,
			want:  []string{"& < >"},
		},
		{
			name:  "word wrap",
			html:  "The quick brown fox jumps over the lazy dog",
			width: 20,
			want:  []string{"The quick brown fox", "jumps over the lazy", "dog"},
		},
		{
			name:  "empty string",
			html:  "",
			width: 80,
			want:  []string{""},
		},
		{
			name:  "complex html",
			html:  `<p>Welcome to <b>BoardGameGeek</b>!</p><p>Check out:</p><ul><li>Strategy games</li><li>Party games</li></ul><p>Visit <a href="https://bgg.cc">BGG</a> for more.</p>`,
			width: 80,
			want: []string{
				"Welcome to BoardGameGeek!",
				"",
				"Check out:",
				"",
				"- Strategy games",
				"- Party games",
				"",
				"Visit BGG (https://bgg.cc) for more.",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := htmlToText(tt.html, tt.width)

			// Trim trailing empty strings for comparison since paragraph
			// closing tags may produce trailing blank lines.
			got = trimTrailingEmpty(got)
			want := trimTrailingEmpty(tt.want)

			if len(got) != len(want) {
				t.Errorf("line count mismatch:\n  got  (%d): %q\n  want (%d): %q", len(got), got, len(want), want)
				return
			}
			for i := range want {
				if got[i] != want[i] {
					t.Errorf("line %d mismatch:\n  got:  %q\n  want: %q", i, got[i], want[i])
				}
			}
		})
	}
}

// trimTrailingEmpty removes trailing empty strings from a slice.
func trimTrailingEmpty(lines []string) []string {
	for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}
