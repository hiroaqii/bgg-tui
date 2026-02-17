package tui

import (
	"testing"

	bgg "github.com/hiroaqii/go-bgg"
)

func TestParseDate(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		wantZero bool
		wantYear int
	}{
		{"RFC 2822 format", "Tue, 10 Feb 2025 14:30:00 +0000", false, 2025},
		{"RFC 2822 with offset", "Fri, 20 Dec 2024 08:32:00 -0600", false, 2024},
		{"RFC 1123 with MST", "Mon, 02 Jan 2006 15:04:05 MST", false, 2006},
		{"RFC 3339 format", "2024-12-20T08:32:00-06:00", false, 2024},
		{"RFC 3339 UTC", "2025-01-15T00:00:00Z", false, 2025},
		{"empty string", "", true, 0},
		{"unparseable", "unknown", true, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseDate(tt.input)
			if tt.wantZero {
				if !got.IsZero() {
					t.Errorf("parseDate(%q) = %v, want zero time", tt.input, got)
				}
			} else {
				if got.IsZero() {
					t.Errorf("parseDate(%q) returned zero time, want year %d", tt.input, tt.wantYear)
				}
				if got.Year() != tt.wantYear {
					t.Errorf("parseDate(%q).Year() = %d, want %d", tt.input, got.Year(), tt.wantYear)
				}
			}
		})
	}

	t.Run("correct ordering", func(t *testing.T) {
		older := parseDate("Fri, 20 Dec 2024 08:32:00 +0000")
		newer := parseDate("Tue, 10 Feb 2025 14:30:00 +0000")
		if !newer.After(older) {
			t.Errorf("expected %v to be after %v", newer, older)
		}
	})

}

func TestFormatDate(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		format string
		want   string
	}{
		{"YYYY-MM-DD default", "Tue, 10 Feb 2025 14:30:00 +0000", "YYYY-MM-DD", "2025-02-10 14:30"},
		{"YYYY-MM-DD with offset", "Fri, 20 Dec 2024 08:32:00 -0600", "YYYY-MM-DD", "2024-12-20 08:32"},
		{"YYYY-MM-DD RFC 3339", "2024-12-20T08:32:00-06:00", "YYYY-MM-DD", "2024-12-20 08:32"},
		{"YYYY-MM-DD RFC 3339 UTC", "2025-01-15T00:00:00Z", "YYYY-MM-DD", "2025-01-15 00:00"},
		{"MM/DD/YYYY format", "Tue, 10 Feb 2025 14:30:00 +0000", "MM/DD/YYYY", "02/10/2025 14:30"},
		{"DD/MM/YYYY format", "Tue, 10 Feb 2025 14:30:00 +0000", "DD/MM/YYYY", "10/02/2025 14:30"},
		{"empty string", "", "YYYY-MM-DD", ""},
		{"unparseable fallback", "unknown", "YYYY-MM-DD", "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := formatDate(tt.input, tt.format)
			if got != tt.want {
				t.Errorf("formatDate(%q, %q) = %q, want %q", tt.input, tt.format, got, tt.want)
			}
		})
	}
}

func TestFormatForumColumns(t *testing.T) {
	t.Run("aligns titles and thread counts", func(t *testing.T) {
		forums := []bgg.Forum{
			{Title: "Play By Forum", NumThreads: 2, LastPostDate: "2025-01-15T00:00:00Z"},
			{Title: "News", NumThreads: 11, LastPostDate: "2025-01-15T00:00:00Z"},
			{Title: "Find Players", NumThreads: 6, LastPostDate: "2025-01-15T00:00:00Z"},
		}

		titles, metas := formatForumColumns(forums, "YYYY-MM-DD")

		// All titles should have the same width (padded to "Play By Forum" = 13 chars)
		for i, title := range titles {
			if len(title) != 13 {
				t.Errorf("titles[%d] = %q (len %d), want len 13", i, title, len(title))
			}
		}

		// Thread counts should be right-aligned (2 digits)
		if metas[0] != " 2 threads · 2025-01-15 00:00" {
			t.Errorf("metas[0] = %q, want %q", metas[0], " 2 threads · 2025-01-15 00:00")
		}
		if metas[1] != "11 threads · 2025-01-15 00:00" {
			t.Errorf("metas[1] = %q, want %q", metas[1], "11 threads · 2025-01-15 00:00")
		}
	})

	t.Run("single forum", func(t *testing.T) {
		forums := []bgg.Forum{
			{Title: "General", NumThreads: 5, LastPostDate: "2025-01-15T00:00:00Z"},
		}

		titles, metas := formatForumColumns(forums, "YYYY-MM-DD")

		if len(titles) != 1 || titles[0] != "General" {
			t.Errorf("titles = %v, want [\"General\"]", titles)
		}
		if len(metas) != 1 || metas[0] != "5 threads · 2025-01-15 00:00" {
			t.Errorf("metas = %v, want [\"5 threads · 2025-01-15 00:00\"]", metas)
		}
	})

	t.Run("empty slice", func(t *testing.T) {
		titles, metas := formatForumColumns(nil, "YYYY-MM-DD")

		if titles != nil || metas != nil {
			t.Errorf("expected nil slices, got titles=%v, metas=%v", titles, metas)
		}
	})
}
