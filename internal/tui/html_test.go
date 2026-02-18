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
			want:  []string{"│ quoted text"},
		},
		{
			name:  "gg-markup-quote basic",
			html:  "<gg-markup-quote>quoted reply</gg-markup-quote>",
			width: 80,
			want:  []string{"│ quoted reply"},
		},
		{
			name:  "gg-markup-quote nested",
			html:  "<gg-markup-quote>outer<gg-markup-quote>inner</gg-markup-quote></gg-markup-quote>",
			width: 80,
			want:  []string{"│ outer", "│ │ inner"},
		},
		{
			name:  "div class=quote (BGG format)",
			html:  `<div class='quote'><div class='quotetitle'><p><b>user wrote:</b></p></div><div class='quotebody'><i>quoted text</i></div></div>rest of message`,
			width: 80,
			want:  []string{"│ user wrote:", "", "│ quoted text", "rest of message"},
		},
		{
			name:  "div class=quote with surrounding text",
			html:  `Hello<div class='quote'><div class='quotebody'>inner quote</div></div>World`,
			width: 80,
			want:  []string{"Hello", "│ inner quote", "World"},
		},
		{
			name:  "BGG real quote format",
			html:  `&lt;font color=#2121A4&gt;&lt;div class='quote'&gt;&lt;div class='quotetitle'&gt;&lt;p&gt;&lt;b&gt;mrpoison wrote:&lt;/b&gt;&lt;/p&gt;&lt;/div&gt;&lt;div class='quotebody'&gt;&lt;i&gt;Yes, but that rule is under the &quot;Factory Selection&quot;.&lt;/i&gt;&lt;/div&gt;&lt;/div&gt;&lt;/font&gt;&lt;br/&gt;&lt;br/&gt;Seems logical to me.`,
			width: 80,
			want: []string{
				`│ mrpoison wrote:`,
				"",
				`│ Yes, but that rule is under the "Factory Selection".`,
				"",
				"",
				"Seems logical to me.",
			},
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
			name:  "blockquote wraps with prefix",
			html:  "<blockquote>The quick brown fox jumps over the lazy dog</blockquote>",
			width: 25,
			want:  []string{"│ The quick brown fox", "│ jumps over the lazy", "│ dog"},
		},
		{
			name:  "nested blockquote wraps with prefix",
			html:  "<blockquote><blockquote>The quick brown fox jumps over the lazy dog</blockquote></blockquote>",
			width: 30,
			want:  []string{"│ │ The quick brown fox", "│ │ jumps over the lazy", "│ │ dog"},
		},
		{
			name:  "empty string",
			html:  "",
			width: 80,
			want:  []string{""},
		},
		{
			name:  "a href where link text equals URL (no duplicate)",
			html:  `<a href="https://example.com">https://example.com</a>`,
			width: 80,
			want:  []string{"https://example.com"},
		},
		{
			name:  "a href where link text is truncated URL (no duplicate)",
			html:  `<a href="https://example.com/very/long/path">https://example.com/very/lon...</a>`,
			width: 80,
			want:  []string{"https://example.com/very/long/path"},
		},
		{
			name:  "a href where link text is truncated URL in blockquote (no duplicate)",
			html:  `<blockquote><a href="https://example.com/very/long/path">https://example.com/very/lon...</a></blockquote>`,
			width: 80,
			want:  []string{"│ https://example.com/very/long/path"},
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

func TestLinkifyLines(t *testing.T) {
	tests := []struct {
		name  string
		input []string
	}{
		{
			name:  "URL gets OSC 8 hyperlink",
			input: []string{"Visit https://example.com for info"},
		},
		{
			name:  "trailing punctuation excluded from link",
			input: []string{"See https://example.com."},
		},
		{
			name:  "no URL unchanged",
			input: []string{"No links here"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := linkifyLines(tt.input)
			switch tt.name {
			case "URL gets OSC 8 hyperlink":
				if !strings.Contains(got[0], "\x1b]8;") {
					t.Errorf("expected OSC 8 sequence, got: %q", got[0])
				}
				if !strings.Contains(got[0], "https://example.com") {
					t.Errorf("expected URL in output, got: %q", got[0])
				}
			case "trailing punctuation excluded from link":
				// The period should not be inside the OSC 8 link
				if !strings.HasSuffix(got[0], ".") {
					t.Errorf("expected trailing period, got: %q", got[0])
				}
				// OSC 8 closing sequence should come before the period
				osc8Close := "\x1b]8;;\x1b\\"
				idx := strings.LastIndex(got[0], osc8Close)
				if idx == -1 {
					t.Errorf("expected OSC 8 close sequence, got: %q", got[0])
				} else if got[0][idx+len(osc8Close):] != "." {
					t.Errorf("period should be after OSC 8 close, got suffix: %q", got[0][idx:])
				}
			case "no URL unchanged":
				if got[0] != tt.input[0] {
					t.Errorf("expected unchanged line, got: %q", got[0])
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
